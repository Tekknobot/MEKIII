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
@onready var info_name: Label = $InfoPanel/VBox/InfoName
@onready var info_stats: Label = $InfoPanel/VBox/InfoStats
@onready var info_thumbnail: TextureRect = $InfoPanel/VBox/Thumbnail

@export var overworld_scene: PackedScene

# ✅ Fade settings
@export var background_starfield: Node2D  # Assign in the inspector
@export var fade_duration: float = 1.0
@export var UI: Control  # Main UI panel to fade
@export var InfoPanel: Control  # Info panel to fade
@export var BackgroundColorRect: ColorRect  # CanvasLayer child ColorRect to fade

# roster entries: {path,name,portrait,hp,move,range,damage}
var _roster: Array[Dictionary] = []
var _selected: Array[String] = []  # ordered scene paths

var _probe_root: Node

var _roster_cards: Dictionary = {} # path:String -> UnitCard

const ROSTER_SLOTS := 16
const LOCKED_LABEL := "LOCKED"

func _ready() -> void:
	start_button.pressed.connect(_on_start)
	back_button.pressed.connect(_on_back)

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
		var sid := StringName(id) # ✅ convert to StringName (matches RunState keys)
		if rs.has_method("is_achievement_unlocked"):
			unlocked = bool(rs.call("is_achievement_unlocked", sid))

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

			# If this badge is stat-based, show progress without revealing too much
			if d.has("stat") and rs.has_method("get_stat"):
				var stat_key := str(d.get("stat", ""))
				var req := int(d.get("min", 0))
				var cur := int(rs.call("get_stat", stat_key))
				show_desc = "Progress: %d / %d" % [cur, req]
			else:
				# Non-stat: give a vague hint
				show_desc = "Hint: " + _badge_hint(id)

		if icon_path != "" and ResourceLoader.exists(icon_path):
			var t = load(icon_path)
			if t is Texture2D:
				tr.texture = t
	
		# Custom hover (uses chosen font)
		tr.mouse_entered.connect(func():
			_show_badge_hover(show_title, show_desc)
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
		"beacon_online":
			return "Complete the beacon."
		"weakpoint":
			return "Something big has weak spots."
		"mine_trigger":
			return "Let the enemy step wrong."
		"demolition":
			return "Buildings can fall."
		"overwatch":
			return "Watch the lanes."
		"ice_cold":
			return "Cold status effects matter."
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
	if roster_grid.columns <= 0:
		roster_grid.columns = roster_columns

	# Build ONCE
	if roster_grid.get_child_count() == 0:
		_roster_cards.clear()

		for data in _roster:
			var card := unit_card_scene.instantiate()
			roster_grid.add_child(card)

			if card.has_method("set_data"):
				card.call("set_data", data)

			var p := str(data.get("path",""))
			_roster_cards[p] = card

			if card is BaseButton:
				(card as BaseButton).pressed.connect(func():
					_toggle_pick(p)
				)

			if card.has_signal("hovered"):
				card.hovered.connect(_on_card_hovered)
			if card.has_signal("unhovered"):
				card.unhovered.connect(_on_card_unhovered)

	# Update selection state ONLY (no rebuilding)
	for p in _roster_cards.keys():
		var c = _roster_cards[p]
		if c != null and is_instance_valid(c) and c.has_method("set_selected"):
			c.call("set_selected", _selected.has(str(p)))


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
			var p := _selected[i]
			var d := _find_roster_data(p)

			var card := unit_card_scene.instantiate()
			squad_grid.add_child(card)

			if card.has_method("set_data"):
				card.call("set_data", d)
			if card.has_method("set_selected"):
				card.call("set_selected", true)

			if card is BaseButton:
				(card as BaseButton).pressed.connect(func():
					if i < _selected.size():
						_selected.remove_at(i)
						_refresh_all()
				)
		else:
			var empty := unit_card_scene.instantiate()
			squad_grid.add_child(empty)
			if empty.has_method("set_empty"):
				empty.call("set_empty", "EMPTY")

func _toggle_pick(path: String) -> void:
	var idx := _selected.find(path)
	if idx != -1:
		_selected.remove_at(idx)
	else:
		if _selected.size() < squad_size:
			_selected.append(path)
		else:
			# replace last slot
			_selected[squad_size - 1] = path
	_refresh_all()

func _find_roster_data(path: String) -> Dictionary:
	for d in _roster:
		if str(d.get("path","")) == path:
			return d
	return {"path": path, "name": path.get_file().get_basename(), "portrait": null, "hp": 0, "move": 0, "range": 0, "damage": 0}

# -----------------------
# Roster discovery
# -----------------------
func _build_roster_async() -> void:
	_roster.clear()

	var rs := _rs()
	var paths: Array[String] = []

	# Prefer the runstate roster (this is your "unlocked" list)
	if rs != null and "roster_scene_paths" in rs and not rs.roster_scene_paths.is_empty():
		paths = rs.roster_scene_paths.duplicate()
	else:
		# Fallback: if you want the UI to show "locked" slots meaningfully,
		# you should seed rs.roster_scene_paths at run start.
		# This fallback will make everything available (no locked slots).
		paths = UnitRegistry.ALLY_PATHS.duplicate()

	paths = paths.filter(func(p): return ResourceLoader.exists(p))
	paths.sort()

	print("SquadDeploy: roster paths = ", paths.size())

	# Build unlocked roster entries
	for p in paths:
		var data := await _extract_unit_card_data(p)
		if data.is_empty():
			continue
		data["locked"] = false
		data["scene_path"] = p
		_roster.append(data)

	# Sort unlocked mechs by name (your existing behavior)
	_roster.sort_custom(func(a, b): return str(a.get("name","")) < str(b.get("name","")))

	# Append locked placeholder slots to reach a fixed grid size
	const ROSTER_SLOTS := 16
	var missing := ROSTER_SLOTS - _roster.size()
	if missing > 0:
		for i in range(missing):
			_roster.append({
				"locked": true,
				"name": "LOCKED",
				"desc": "Unlock more mechs by clearing sectors.",
				"portrait": null,      # your UI builder should handle null portrait
				"scene_path": ""       # no scene
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
func _on_start() -> void:
	if _selected.size() != squad_size:
		return

	# ✅ Fade out everything first
	await _fade_out_all()

	var rs := _rs()

	print("[EXPORT CHECK] rs=", rs)
	print("[EXPORT CHECK] squad_scene_paths=", rs.squad_scene_paths if rs != null and "squad_scene_paths" in rs else "NONE")

	print("exists units=", DirAccess.dir_exists_absolute("res://scenes/units"))
	print("exists allies=", DirAccess.dir_exists_absolute("res://scenes/units/allies"))
	
	if rs != null:
		# ✅ store squad
		if rs.has_method("set_squad"):
			rs.call("set_squad", _selected)

		# ✅ store squad
		if rs.has_method("set_squad"):
			rs.call("set_squad", _selected)

		# ✅ rebuild recruit pool from existing unlocked roster
		if rs.has_method("rebuild_recruit_pool"):
			rs.call("rebuild_recruit_pool")


	if overworld_scene != null:
		get_tree().change_scene_to_packed(overworld_scene)
	else:
		get_tree().change_scene_to_file("res://scenes/overworld.tscn")


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
