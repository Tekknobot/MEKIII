# res://scripts/squad_deploy_screen.gd
extends Control

@export var game_scene: PackedScene
@export var title_scene_path: String = "res://scenes/title_screen.tscn"

# Folder containing ONLY ally unit scenes (and subfolders).
@export var units_folder: String = "res://scenes/units/allies"

@export var unit_card_scene: PackedScene = preload("res://scenes/unit_card.tscn")
@export var squad_size: int = 3

@export var roster_columns: int = 3

@onready var roster_grid: GridContainer = $UI/RosterPanel/ScrollContainer/RosterGrid
@onready var squad_grid: GridContainer = $UI/SquadPanel/SquadGrid
@onready var start_button: Button = $UI/SquadPanel/StartButton
@onready var back_button: Button = $UI/SquadPanel/BackButton

@onready var info_panel: Panel = $InfoPanel
@onready var info_name: Label = $InfoPanel/VBox/InfoName
@onready var info_stats: Label = $InfoPanel/VBox/InfoStats
@onready var info_thumbnail: TextureRect = $InfoPanel/VBox/Thumbnail

# roster entries: {path,name,portrait,hp,move,range,damage}
var _roster: Array[Dictionary] = []
var _selected: Array[String] = []  # ordered scene paths

var _probe_root: Node

func _ready() -> void:
	start_button.pressed.connect(_on_start)
	back_button.pressed.connect(_on_back)

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

	info_panel.visible = false

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
	_rebuild_roster_ui()
	_rebuild_squad_ui()
	start_button.disabled = (_selected.size() != squad_size)

func _rebuild_roster_ui() -> void:
	for c in roster_grid.get_children():
		c.queue_free()

	if roster_grid.columns <= 0:
		roster_grid.columns = roster_columns

	for data in _roster:
		var card := unit_card_scene.instantiate()
		roster_grid.add_child(card)

		# If scene script is missing / wrong, don’t hard-crash
		if card.has_method("set_data"):
			card.call("set_data", data)
		if card.has_method("set_selected"):
			card.call("set_selected", _selected.has(str(data.get("path",""))))

		var p := str(data.get("path",""))
		if card is BaseButton:
			(card as BaseButton).pressed.connect(func():
				_toggle_pick(p)
			)

		if card.has_signal("hovered"):
			card.hovered.connect(_on_card_hovered)
		if card.has_signal("unhovered"):
			card.unhovered.connect(_on_card_unhovered)

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

	if not DirAccess.dir_exists_absolute(units_folder):
		# DirAccess.dir_exists_absolute expects absolute; res:// is “virtual”.
		# So we check by attempting open.
		var test := DirAccess.open(units_folder)
		if test == null:
			push_error("SquadDeploy: units_folder not found or cannot open: " + units_folder)
			return

	var paths := _scan_tscn_recursive(units_folder)
	paths.sort()

	print("SquadDeploy: Found .tscn count = ", paths.size(), " in ", units_folder)

	for p in paths:
		var data := await _extract_unit_card_data(p)
		if data.is_empty():
			continue
		_roster.append(data)

	# sort by display name
	_roster.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name","")) < str(b.get("name",""))
	)

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
	# Don’t rely on class_name being visible everywhere; use method sniffing too.
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
# Start / Back
# -----------------------
func _on_start() -> void:
	if _selected.size() != squad_size:
		return

	var rs := _rs()
	if rs != null:
		# ✅ store squad
		if rs.has_method("set_squad"):
			rs.call("set_squad", _selected)

		# ✅ store full roster paths (all recruitable allies)
		var all_paths: Array[String] = []
		for d in _roster:
			all_paths.append(str(d.get("path","")))

		if rs.has_method("set_roster"):
			rs.call("set_roster", all_paths)

		# ✅ build recruit pool = roster - squad
		if rs.has_method("rebuild_recruit_pool"):
			rs.call("rebuild_recruit_pool")

	if game_scene != null:
		get_tree().change_scene_to_packed(game_scene)
	else:
		push_error("SquadDeploy: game_scene is not assigned.")

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
