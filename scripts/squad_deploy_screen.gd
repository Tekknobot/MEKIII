# res://scripts/squad_deploy_screen.gd
extends Control

@export var game_scene: PackedScene
@export var title_scene_path: String = "res://scenes/title_screen.tscn"

# -------------------------------------------------------
# Badge UI styling
# -------------------------------------------------------
@export var achievements_float_font: Font
@export var achievements_float_font_size: int = 16

# Folder containing ONLY ally unit scenes (and subfolders).
@export var units_folder: String = "res://scenes/units/allies"

@export var unit_card_scene: PackedScene = preload("res://scenes/unit_card.tscn")
@export var squad_size: int = 3

@export var roster_columns: int = 3

@onready var roster_grid: GridContainer = $UI/RosterPanel/ScrollContainer/RosterGrid
@onready var squad_grid: GridContainer = $UI/SquadPanel/SquadGrid
@onready var start_button: Button = $UI/SquadPanel/StartButton
@onready var back_button: Button = $UI/SquadPanel/BackButton

# Achievements UI (optional panel)
@onready var achievements_grid: GridContainer = $UI/AchievementsPanel/ScrollContainer/AchievementsGrid

@onready var info_panel: Panel = $InfoPanel
@onready var info_name: Label = $InfoPanel/VBox/HBoxContainer/InfoName
@onready var info_stats: Label = $InfoPanel/VBox/HBoxContainer/InfoStats
@onready var info_thumbnail: TextureRect = $InfoPanel/VBox/HBoxContainer/Thumbnail

@export var overworld_scene: PackedScene

# ✅ Fade settings
@export var background_starfield: Node2D  # Assign in the inspector
@export var fade_duration: float = 1.0
@export var UI: Control  # Main UI panel to fade
@export var InfoPanel: Control  # Info panel to fade
@export var BackgroundColorRect: ColorRect  # CanvasLayer child ColorRect to fade

# roster entries: {path,name,portrait,hp,move,range,damage}
var _roster: Array[Dictionary] = []
var _selected: Array[String] = []  # ordered roster unit IDs

var _probe_root: Node

var _roster_cards: Dictionary = {} # id:String -> UnitCard

const ROSTER_SLOTS := 16
const LOCKED_LABEL := "LOCKED"

var _roster_lookup: Dictionary = {}   # uid -> data

func _ready() -> void:
	start_button.pressed.connect(_on_start)
	back_button.pressed.connect(_on_back)

	# ✅ Safety: exported PackedScene can be overridden to null in inspector
	if unit_card_scene == null:
		unit_card_scene = preload("res://scenes/unit_card.tscn")
		
	# ✅ Start with everything visible (alpha = 1)
	_set_fade_targets_alpha(1.0)

	# ✅ Fade BackgroundColorRect out on ready (and anything else you want)
	_fade_on_ready()

	_probe_root = Node.new()
	_probe_root.name = "_ProbeRoot"
	add_child(_probe_root)

	# Grid settings
	if roster_grid.columns <= 0:
		roster_grid.columns = roster_columns
	squad_grid.columns = squad_size

	# Build roster
	await _build_roster_async()
	_refresh_all()
	_refresh_achievements_ui()

	info_panel.visible = false

func _on_start() -> void:
	if _selected.size() != squad_size:
		return

	await _fade_out_all()

	var rs := _rs()
	if rs != null:
		var paths: Array[String] = []
		var owned_ids: Array[String] = []
		var defs: Array[Dictionary] = []

		for ui_id in _selected:
			var d := _find_roster_data(ui_id)
			if d.is_empty():
				continue

			var p := str(d.get("path", ""))
			if p != "" and ResourceLoader.exists(p):
				paths.append(p)

			# ✅ always use the REAL owned id, never the UI id with "#1"
			var owned_id := str(d.get("owned_id", ""))

			# ultra-safe fallback: strip "#N" if owned_id wasn't stored
			if owned_id == "":
				owned_id = ui_id
				var hash := owned_id.rfind("#")
				if hash != -1:
					owned_id = owned_id.substr(0, hash)

			owned_ids.append(owned_id)

			defs.append({
				"id": owned_id,
				"path": p,
				"quirks": d.get("quirks", []).duplicate(true),
			})

		# ✅ Primary: store owned ids so RunState can recover quirks reliably
		if rs.has_method("set_squad_units"):
			rs.call("set_squad_units", owned_ids)
		else:
			if "squad_unit_ids" in rs:
				rs.set("squad_unit_ids", owned_ids)
			rs.set_meta(&"squad_unit_ids", owned_ids)

		# ✅ ALSO store explicit per-slot entries (path + quirks) so spawn can't "guess wrong"
		if rs.has_method("set_squad_entries"):
			rs.call("set_squad_entries", defs)
		else:
			# fallback: save it as meta if older RunState
			rs.set_meta(&"squad_entries", defs)

		# Keep legacy paths in sync (for old code/UI)
		if "squad_scene_paths" in rs:
			rs.set("squad_scene_paths", paths)
		rs.set_meta(&"squad_scene_paths", paths)

		# Optional debug defs
		if "squad_defs" in rs:
			rs.set("squad_defs", defs)
		rs.set_meta(&"squad_defs", defs)

		if rs.has_method("save_to_disk"):
			rs.call("save_to_disk")

	# go to overworld
	if overworld_scene != null:
		get_tree().change_scene_to_packed(overworld_scene)
	else:
		get_tree().change_scene_to_file("res://scenes/overworld.tscn")

func _fade_on_ready() -> void:
	# optional: one frame delay so Control layout/modulate is initialized
	await get_tree().process_frame

	var tween := create_tween()
	tween.set_parallel(true)

	# ✅ Fade BackgroundColorRect
	if BackgroundColorRect != null and is_instance_valid(BackgroundColorRect):
		tween.tween_property(BackgroundColorRect, "modulate:a", 0.0, fade_duration)

	# (Optional) also fade starfield/UI/info on ready if you want:
	# if background_starfield != null and is_instance_valid(background_starfield):
	# 	tween.tween_property(background_starfield, "modulate:a", 0.0, fade_duration)
	# if UI != null and is_instance_valid(UI):
	# 	tween.tween_property(UI, "modulate:a", 0.0, fade_duration)
	# if InfoPanel != null and is_instance_valid(InfoPanel):
	# 	tween.tween_property(InfoPanel, "modulate:a", 0.0, fade_duration)


func _set_fade_targets_alpha(a: float) -> void:
	# keep this simple + safe
	if BackgroundColorRect != null and is_instance_valid(BackgroundColorRect):
		var m := BackgroundColorRect.modulate
		m.a = a
		BackgroundColorRect.modulate = m

	if background_starfield != null and is_instance_valid(background_starfield):
		var m2 := background_starfield.modulate
		m2.a = a
		background_starfield.modulate = m2

	if UI != null and is_instance_valid(UI):
		var m3 := UI.modulate
		m3.a = a
		UI.modulate = m3

	if InfoPanel != null and is_instance_valid(InfoPanel):
		var m4 := InfoPanel.modulate
		m4.a = a
		InfoPanel.modulate = m4

# -----------------------
# RunState getter (autoload)
# -----------------------
func _rs() -> Node:
	var r := get_tree().root
	var rs := r.get_node_or_null("RunStateNode")
	if rs != null: return rs
	rs = r.get_node_or_null("RunState")
	if rs != null: return rs
	return null

# -----------------------
# UI refresh
# -----------------------
func _refresh_all() -> void:
	_rebuild_roster_ui()   # now updates selection without deleting
	_rebuild_squad_ui()    # this one can still rebuild, that's fine
	start_button.disabled = (_selected.size() != squad_size)

func _refresh_achievements_ui() -> void:
	if achievements_grid == null or not is_instance_valid(achievements_grid):
		return
	# Clear existing
	for c in achievements_grid.get_children():
		c.queue_free()

	var rs := _rs()
	if rs == null or not is_instance_valid(rs):
		return
	if not rs.has_method("get_all_achievement_defs"):
		return
	var defs: Array = rs.call("get_all_achievement_defs")
	const LIMIT := 10
	defs = defs.slice(0, min(LIMIT, defs.size()))

	for d in defs:
		if not (d is Dictionary):
			continue
		var id := str(d.get("id", ""))
		var title := str(d.get("title", ""))
		var desc := str(d.get("desc", ""))
		var icon_path := str(d.get("icon", ""))
		var unlocked := false
		if rs.has_method("is_achievement_unlocked"):
			unlocked = bool(rs.call("is_achievement_unlocked", id)) # ✅ RunState uses String keys

		# Container so we can show icon + text
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(72, 44)
		box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var tr := TextureRect.new()

		tr.custom_minimum_size = Vector2(44, 44)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Use custom hover panel instead of OS tooltip (so we can control font)
		tr.tooltip_text = ""

		var show_title := title
		var show_desc := desc

		if not unlocked:
			# Silhouette/locked look
			tr.modulate = Color(0.25, 0.25, 0.25, 0.9)

			# Hide the real title, but give a hint
			show_title = "???"

			var hint := _badge_hint(id)

			# If stat-based, show BOTH hint + progress
			if d.has("stat") and rs.has_method("get_stat"):
				var stat_key := str(d.get("stat", ""))
				var req := int(d.get("min", 0))
				var cur := int(rs.call("get_stat", stat_key))
				show_desc = "Hint: %s\nProgress: %d / %d" % [hint, cur, req]
			else:
				show_desc = "Hint: %s" % hint

		if icon_path != "" and ResourceLoader.exists(icon_path):
			var t = load(icon_path)
			if t is Texture2D:
				tr.texture = t
	
		# Custom hover (uses chosen font)
		var hover_title := show_title
		var hover_desc := show_desc

		tr.mouse_entered.connect(func():
			_show_badge_hover(hover_title, hover_desc)
		)
		tr.mouse_exited.connect(func():
			_hide_badge_hover()
		)
				
		# Optional label (uses your chosen "floating font")
		var lbl := Label.new()
		lbl.text = show_title
		
		lbl.custom_minimum_size = Vector2(60, 0) # a bit wider than the 44px icon
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_constant_override("margin_left", 4)
		lbl.add_theme_constant_override("margin_right", 4)
		
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lbl.clip_text = false

		if achievements_float_font != null:
			lbl.add_theme_font_override("font", achievements_float_font)
			lbl.add_theme_font_size_override("font_size", achievements_float_font_size)

		# Build
		box.add_child(tr)
		box.add_child(lbl)
		achievements_grid.add_child(box)


	# Optional: listen for new unlocks while this screen is open
	if rs.has_signal("achievement_unlocked"):
		var cb := Callable(self, "_on_rs_achievement_unlocked")
		if not rs.achievement_unlocked.is_connected(cb):
			rs.achievement_unlocked.connect(cb)

func _badge_hint(id: String) -> String:
	match id:
		"first_blood":
			return "Kill any zombie."
		"body_count_25":
			return "Total kills add up across runs."
		"body_count_100":
			return "Keep thinning the horde."
		"beacon_online":
			return "Fully power the beacon."
		"first_floppy":
			return "Pick up a floppy disk."
		"overwatch":
			return "Use an Overwatch special."
		"mine_trigger":
			return "Lure an enemy onto a mine."
		"demolition":
			return "Reduce a structure to 0 HP."
		"weakpoint":
			return "Destroy a boss weakpoint."
		"ice_cold":
			return "Get Chilled."
		_:
			return "Keep playing."

func _show_badge_hover(title: String, desc: String) -> void:
	if info_panel == null or not is_instance_valid(info_panel):
		return

	info_panel.visible = true
	info_name.text = title
	info_stats.text = desc

	# ✅ apply chosen font to hover text
	if achievements_float_font != null:
		info_name.add_theme_font_override("font", achievements_float_font)
		info_name.add_theme_font_size_override("font_size", achievements_float_font_size)

		info_stats.add_theme_font_override("font", achievements_float_font)
		info_stats.add_theme_font_size_override("font_size", achievements_float_font_size)

func _hide_badge_hover() -> void:
	if info_panel != null and is_instance_valid(info_panel):
		info_panel.visible = false

func _on_rs_achievement_unlocked(_id: String, _def: Dictionary) -> void:
	# Refresh visuals live
	_refresh_achievements_ui()

   # now updates selection without deleting
	_rebuild_squad_ui()    # this one can still rebuild, that's fine
	start_button.disabled = (_selected.size() != squad_size)

func _rebuild_roster_ui() -> void:
	if roster_grid == null or not is_instance_valid(roster_grid):
		return

	if roster_grid.columns <= 0:
		roster_grid.columns = roster_columns

	if unit_card_scene == null:
		push_warning("SquadDeploy: unit_card_scene is null (check inspector override).")
		return

	# ✅ Always clear UI to prevent duplicates
	for ch in roster_grid.get_children():
		ch.queue_free()

	_roster_cards.clear()

	# ✅ Rebuild from current _roster data
	for data in _roster:
		var card := unit_card_scene.instantiate()
		roster_grid.add_child(card)

		if card.has_method("set_data"):
			card.call("set_data", data)

		var locked := bool(data.get("locked", false))
		var ui_id := str(data.get("id", ""))

		# Store by UI id
		_roster_cards[ui_id] = card

		# Locked: disable and skip hooks
		if locked or ui_id == "" or str(data.get("path","")) == "":
			if card is BaseButton:
				(card as BaseButton).disabled = true
			if card.has_method("set_selected"):
				card.call("set_selected", false)
			continue

		# Unlocked: click to toggle
		if card is BaseButton:
			(card as BaseButton).pressed.connect(Callable(self, "_on_roster_card_pressed").bind(ui_id))

		if card.has_signal("hovered"):
			card.hovered.connect(_on_card_hovered)
		if card.has_signal("unhovered"):
			card.unhovered.connect(_on_card_unhovered)

	# ✅ Apply selection highlight
	for id_key in _roster_cards.keys():
		var c = _roster_cards[id_key]
		if c != null and is_instance_valid(c) and c.has_method("set_selected"):
			var d := _find_roster_data(str(id_key))
			var locked2 := bool(d.get("locked", false))
			c.call("set_selected", (not locked2) and _selected.has(str(id_key)))

func _on_card_hovered(data: Dictionary) -> void:
	info_panel.visible = true
	info_name.text = str(data.get("name", ""))

	var hp := int(data.get("hp", 0))
	var mv := int(data.get("move", 0))
	var rng := int(data.get("range", 0))
	var dmg := int(data.get("damage", 0))

	# --- Special(s) ---
	var special_text := ""
	if data.has("special"):
		var sp = data.get("special")
		if sp is Array:
			# ["Pounce","Overwatch"] -> "Pounce, Overwatch"
			special_text = ", ".join(sp)
		else:
			special_text = str(sp)

	var special_desc := str(data.get("special_desc", ""))

	var lines: Array[String] = []

	# Left column padded to 6 characters
	lines.append("%-6s %d" % ["HP", hp])
	lines.append("%-6s %d" % ["MOVE", mv])
	lines.append("%-6s %d" % ["RANGE", rng])
	lines.append("%-6s %d" % ["DMG", dmg])

	if special_text != "":
		lines.append("")
		lines.append("SPECIAL:")
		lines.append(special_text)
		if special_desc != "":
			lines.append(special_desc)

	var quirks_text := str(data.get("quirks_text", "")).strip_edges()
	if quirks_text != "":
		lines.append("")
		lines.append("QUIRKS:")
		lines.append(quirks_text)

	info_stats.text = "\n".join(lines)

	# ✅ thumbnail
	if info_thumbnail:
		var t: Texture2D = data.get("thumb", null)
		info_thumbnail.texture = t
		info_thumbnail.visible = (t != null)


func _on_card_unhovered() -> void:
	info_panel.visible = false
	if info_thumbnail:
		info_thumbnail.texture = null

func _rebuild_squad_ui() -> void:
	for c in squad_grid.get_children():
		c.queue_free()

	squad_grid.columns = squad_size

	for i in range(squad_size):
		if i < _selected.size():
			var uid := _selected[i]
			var d := _find_roster_data(uid)

			var card := unit_card_scene.instantiate()
			squad_grid.add_child(card)

			if card.has_method("set_data"):
				card.call("set_data", d)
			if card.has_method("set_selected"):
				card.call("set_selected", true)

			if card is BaseButton:
				var b := card as BaseButton
				# ✅ capture-safe: stores i at connect-time
				b.pressed.connect(Callable(self, "_on_squad_slot_pressed").bind(i))
		else:
			var empty := unit_card_scene.instantiate()
			squad_grid.add_child(empty)
			if empty.has_method("set_empty"):
				empty.call("set_empty", "EMPTY")

func _toggle_pick(uid: String) -> void:
	var idx := _selected.find(uid)
	if idx != -1:
		_selected.remove_at(idx)
	else:
		if _selected.size() < squad_size:
			_selected.append(uid)
		else:
			# replace last slot
			_selected[squad_size - 1] = uid
	_refresh_all()

func _find_roster_data(uid: String) -> Dictionary:
	# direct hit
	if _roster_lookup.has(uid):
		return _roster_lookup[uid]

	# strip "#N" suffix (duplicate instances)
	var hash_idx := uid.rfind("#")
	if hash_idx != -1:
		var base_uid := uid.substr(0, hash_idx)
		if _roster_lookup.has(base_uid):
			return _roster_lookup[base_uid]

	# last resort: scan _roster array (shouldn't be needed once lookup is built)
	for d in _roster:
		if str(d.get("id", "")) == uid:
			return d

	return {}

# -----------------------
# Roster discovery
# -----------------------
func _build_roster_async() -> void:
	_roster.clear()
	_roster_lookup.clear()

	var rs := _rs()
	var entries: Array = []

	# Prefer NEW roster_units (owned individual units)
	if rs != null and ("roster_units" in rs) and (rs.roster_units is Array) and not rs.roster_units.is_empty():
		entries = rs.roster_units.duplicate(true)
	elif rs != null and rs.has_method("get_roster_units"):
		entries = rs.call("get_roster_units")
	else:
		# Fallback (older saves): show unlocked unit TYPES
		var paths: Array[String] = []
		if rs != null and "roster_scene_paths" in rs and not rs.roster_scene_paths.is_empty():
			paths = rs.roster_scene_paths.duplicate()
		else:
			paths = UnitRegistry.ALLY_PATHS.duplicate()
		paths = paths.filter(func(p): return ResourceLoader.exists(p))
		paths.sort()
		for p in paths:
			entries.append({"id": p, "path": p, "quirks": []})

	print("SquadDeploy: roster entries = ", entries.size())

	# ✅ enforce unique ids (so selection works even if save has dup/missing ids)
	var seen: Dictionary = {}  # uid:String -> true
	var make_uid := func(base: String) -> String:
		var u := base
		var n := 1
		while seen.has(u):
			u = "%s#%d" % [base, n]
			n += 1
		seen[u] = true
		return u

	for e in entries:
		if not (e is Dictionary):
			continue

		var p := str(e.get("path", ""))
		if p == "" or not ResourceLoader.exists(p):
			continue

		# ✅ This is the REAL owned unit id from RunState.roster_units
		var owned_id := str(e.get("id", e.get("uid", "")))
		if owned_id == "":
			owned_id = p  # fallback only for legacy path-only entries

		# ✅ UI id must be unique (so the grid can display duplicates safely)
		var ui_id = make_uid.call(owned_id)

		var data := await _extract_unit_card_data(p)
		if data.is_empty():
			continue

		data["locked"] = false
		data["id"] = ui_id                 # ✅ UI id (may include #1/#2)
		data["owned_id"] = owned_id        # ✅ REAL RunState roster_units id
		data["path"] = p
		data["quirks"] = e.get("quirks", [])

		_apply_quirks_to_card_data(data)

		_roster.append(data)
		_roster_lookup[ui_id] = data # ✅ so hover/selection always finds the right one

	# Sort unlocked mechs by name (your existing behavior)
	_roster.sort_custom(func(a, b): return str(a.get("name","")) < str(b.get("name","")))

	# Append locked placeholder slots to reach a fixed grid size
	var missing := ROSTER_SLOTS - _roster.size()
	if missing > 0:
		for i in range(missing):
			_roster.append({
				"id": "LOCKED_%02d" % i, # ✅ unique, never collides
				"locked": true,
				"name": "LOCKED",
				"desc": "Unlock more mechs by clearing sectors.",
				"portrait": null,
				"thumb": null,
				"path": ""
			})

func _scan_tscn_recursive(folder: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(folder)
	if dir == null:
		push_warning("SquadDeploy: cannot open folder: " + folder)
		return out

	dir.list_dir_begin()
	while true:
		var f := dir.get_next()
		if f == "":
			break

		if dir.current_is_dir():
			if f.begins_with("."):
				continue
			out.append_array(_scan_tscn_recursive(folder.path_join(f)))
		else:
			if f.ends_with(".tscn"):
				out.append(folder.path_join(f))

	dir.list_dir_end()
	return out

# -----------------------
# Unit extraction (root OR nested)
# -----------------------
func _find_unit_in_tree(n: Node) -> Node:
	# Don't rely on class_name being visible everywhere; use method sniffing too.
	if n != null:
		# Best case: it *is* your Unit class
		if n.get_class() == "Node2D" and n.has_method("get_display_name") and n.has_method("get_portrait_texture"):
			return n
		if n.has_method("take_damage") and ("hp" in n) and ("max_hp" in n):
			return n

	for ch in n.get_children():
		var u := _find_unit_in_tree(ch)
		if u != null:
			return u
	return null

func _extract_unit_card_data(scene_path: String) -> Dictionary:
	var res := load(scene_path)
	if not (res is PackedScene):
		push_warning("SquadDeploy: not a PackedScene: " + scene_path)
		return {}

	var inst := (res as PackedScene).instantiate()
	if inst == null:
		push_warning("SquadDeploy: failed to instantiate: " + scene_path)
		return {}

	_probe_root.add_child(inst)
	await get_tree().process_frame

	var u := _find_unit_in_tree(inst)
	if u == null:
		# Not a unit scene
		inst.queue_free()
		return {}

	# ---- gather fields robustly ----
	var name := _unit_get_name(u, inst, scene_path)
	var portrait := _unit_get_portrait(u)
	var hp := _unit_get_int(u, "max_hp", ["max_hp"], 0)
	var mv := _unit_get_int(u, "move_range", ["move_range"], 0)
	var rng := _unit_get_int(u, "attack_range", ["attack_range"], 0)
	var dmg := _unit_get_int(u, "attack_damage", ["attack_damage"], 0)

	var thumb = null
	if u.has_method("get_thumbnail_texture"):
		thumb = u.call("get_thumbnail_texture")

	# If your Unit has the fancy getters, prefer them
	if u.has_method("get_move_range"):
		mv = int(u.call("get_move_range"))
	if u.has_method("get_attack_damage"):
		dmg = int(u.call("get_attack_damage"))
	if u.has_method("get_display_name"):
		name = str(u.call("get_display_name"))
	if u.has_method("get_portrait_texture"):
		portrait = u.call("get_portrait_texture")

	# --- Specials (supports either: special:String OR specials:Array[String]) ---
	var special_value = ""          # can be String or Array[String]
	var special_desc := ""

	# Prefer "specials" array if present
	var sp_arr := _unit_get_string_array(u, "specials")
	if not sp_arr.is_empty():
		special_value = sp_arr
	else:
		# Otherwise fall back to single string "special"
		special_value = _unit_get_string(u, "special", "")
	
	special_desc = _unit_get_string(u, "special_desc", "")

	var data := {
		"path": scene_path,
		"name": name,
		"portrait": portrait,
		"thumb": thumb,

		# ✅ what your hover UI expects
		"special": special_value,
		"special_desc": special_desc,

		"hp": hp,
		"move": mv,
		"range": rng,
		"damage": dmg,
	}


	inst.queue_free()
	return data


func _apply_quirks_to_card_data(data: Dictionary) -> void:
	# Apply quirk stat deltas to the UI card data so the player sees the variant.
	if data.is_empty() or not data.has("quirks"):
		return
	var quirks: Array = data.get("quirks", [])
	if quirks.is_empty():
		data["quirks_text"] = ""
		return

	var d_hp := 0
	var d_mv := 0
	var d_rng := 0
	var d_dmg := 0

	for q in quirks:
		var def := QuirkDB.get_def(StringName(str(q)))
		if def.is_empty():
			continue
		var fx: Dictionary = def.get("effects", {})
		d_hp += int(fx.get("max_hp", 0))
		d_mv += int(fx.get("move_range", 0))
		d_rng += int(fx.get("attack_range", 0))
		d_dmg += int(fx.get("attack_damage", 0))

	data["hp"] = max(1, int(data.get("hp", 1)) + d_hp)
	data["move"] = max(1, int(data.get("move", 1)) + d_mv)
	data["range"] = max(0, int(data.get("range", 0)) + d_rng)
	data["damage"] = max(0, int(data.get("damage", 0)) + d_dmg)
	data["quirks_text"] = QuirkDB.describe_list(quirks)

# -----------------------
# Robust unit getters
# -----------------------
func _unit_get_name(u: Node, inst: Node, scene_path: String) -> String:
	# exported property "display_name"
	if "display_name" in u:
		var v = u.get("display_name")
		if v != null and str(v) != "":
			return str(v)

	# meta
	if u.has_meta("display_name"):
		var m = u.get_meta("display_name")
		if m != null and str(m) != "":
			return str(m)

	# fallback
	return scene_path.get_file().get_basename()

func _unit_get_portrait(u: Node) -> Texture2D:
	if "portrait_tex" in u:
		var v = u.get("portrait_tex")
		if v is Texture2D:
			return v

	if u.has_meta("portrait_tex"):
		var m = u.get_meta("portrait_tex")
		if m is Texture2D:
			return m

	return null


func _unit_get_int(u: Node, primary_key: String, fallback_keys: Array[String], default_val: int) -> int:
	if primary_key in u:
		var v = u.get(primary_key)
		if v != null:
			return int(v)
	for k in fallback_keys:
		if k in u:
			var vv = u.get(k)
			if vv != null:
				return int(vv)
	if u.has_meta(primary_key):
		return int(u.get_meta(primary_key))
	return default_val

# -----------------------
# Fade out all elements
# -----------------------
func _fade_out_all() -> void:
	var tween := create_tween()
	tween.set_parallel(true)

	if background_starfield != null and is_instance_valid(background_starfield):
		tween.tween_property(background_starfield, "modulate:a", 0.0, fade_duration)

	if UI != null and is_instance_valid(UI):
		tween.tween_property(UI, "modulate:a", 0.0, fade_duration)

	if InfoPanel != null and is_instance_valid(InfoPanel):
		tween.tween_property(InfoPanel, "modulate:a", 0.0, fade_duration)

	# ✅ include it here too
	if BackgroundColorRect != null and is_instance_valid(BackgroundColorRect):
		tween.tween_property(BackgroundColorRect, "modulate:a", 1.0, fade_duration)

	await tween.finished


# -----------------------
# Start / Back
# -----------------------
func _unit_get_string(u: Node, key: String, default_val := "") -> String:
	if key in u:
		var v = u.get(key)
		if v != null:
			return str(v)
	if u.has_meta(key):
		return str(u.get_meta(key))
	return default_val

func _unit_get_string_array(u: Node, key: String) -> Array[String]:
	var out: Array[String] = []
	if key in u:
		var v = u.get(key)
		if v is Array:
			for item in v:
				out.append(str(item))
			return out
	if u.has_meta(key):
		var m = u.get_meta(key)
		if m is Array:
			for item in m:
				out.append(str(item))
			return out
	return out

func _on_back() -> void:
	get_tree().change_scene_to_file(title_scene_path)

func _on_roster_card_pressed(uid: String) -> void:
	_toggle_pick(uid)

func _on_squad_slot_pressed(slot_i: int) -> void:
	if slot_i < 0 or slot_i >= _selected.size():
		return
	_selected.remove_at(slot_i)
	_refresh_all()
