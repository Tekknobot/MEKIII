extends Node2D

@export var game_scene: PackedScene

@onready var radar: OverworldRadar = $OverworldRadar

# Supply reward panel (spawned on-demand)
var _supply_panel: EndGamePanelRuntime = null
var _pending_supply_node_id: int = -1

@export var upgrade_title_font: Font
@export var upgrade_body_font: Font
@export var upgrade_button_font: Font

@export var upgrade_title_font_size := 32
@export var upgrade_body_font_size := 16
@export var upgrade_button_font_size := 16

@export var radar_path: NodePath
@export var camera_path: NodePath

@onready var cam := get_node_or_null(camera_path) as OverworldCamera

@export var fade_rect: ColorRect
@export var fade_duration: float = 1.0

func _ready() -> void:
	_fade_from_black_on_ready()
	
	if radar != null:
		radar.mission_requested.connect(_on_mission_requested)

func _on_mission_requested(node_id: int, node_type: int, difficulty: float) -> void:
	# ✅ SUPPLY = rewards only (no map)
	if node_type == OverworldRadar.NodeType.SUPPLY:
		_handle_supply_clicked(node_id, difficulty)
		return

	# --- normal mission launch (combat/elite/event/boss/start) ---
	var rs := get_node_or_null("/root/RunStateNode")
	if rs != null:
		# persist overworld position
		rs.overworld_current_node_id = node_id

		# mission payload (fine to keep)
		rs.mission_node_id = node_id
		rs.mission_difficulty = difficulty
		rs.mission_node_type = _type_to_key(node_type)

		# ✅ boss latch (consume in TurnManager)
		rs.boss_mode_enabled_next_mission = (node_type == OverworldRadar.NodeType.BOSS)

		# ✅ event latch (consume in TurnManager)
		if node_type == OverworldRadar.NodeType.EVENT:
			rs.event_mode_enabled_next_mission = true
			rs.event_id_next_mission = &"titan_overwatch"
		else:
			rs.event_mode_enabled_next_mission = false
			rs.event_id_next_mission = &""

		# seed: stable per node
		var base_seed := int(rs.overworld_seed) if ("overworld_seed" in rs) else 0
		if base_seed == 0:
			base_seed = randi()
		rs.overworld_seed = base_seed
		rs.mission_seed = int(hash(str(base_seed) + ":" + str(node_id)))

	# go to game
	if game_scene != null:
		var target_pos = radar.get_node_world_pos(node_id)
		cam.play_launch_cinematic(target_pos)
		
		# ✅ cover screen while the cinematic finishes / scene switches
		await _fade_to_black()
				
		await get_tree().create_timer(2).timeout
		get_tree().change_scene_to_packed(game_scene)
	else:
		get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _handle_supply_clicked(node_id: int, difficulty: float) -> void:
	_pending_supply_node_id = node_id

	if _supply_panel == null or not is_instance_valid(_supply_panel):
		_supply_panel = EndGamePanelRuntime.new()

		# ✅ set exports BEFORE _ready/_build_ui happens
		_apply_supply_fonts(_supply_panel)

		add_child(_supply_panel)
		_supply_panel.continue_pressed.connect(_on_supply_continue)
	else:
		# panel already exists; force-apply to live controls too (see below)
		_apply_supply_fonts_live(_supply_panel)

	var upgrades := _roll_supply_upgrades()
	_supply_panel.show_win(0, upgrades)
	_supply_panel.title_label.text = "SUPPLY CACHE"
	_supply_panel.body_label.text = "You crack open an abandoned cache.\n\nGrab what you can before the dead catch up."

func _apply_supply_fonts(panel: EndGamePanelRuntime) -> void:
	if upgrade_title_font != null:
		panel.title_font = upgrade_title_font
	panel.title_font_size = upgrade_title_font_size

	if upgrade_body_font != null:
		panel.body_font = upgrade_body_font
	panel.body_font_size = upgrade_body_font_size

	if upgrade_button_font != null:
		panel.button_font = upgrade_button_font
	panel.button_font_size = upgrade_button_font_size

func _apply_supply_fonts_live(panel: EndGamePanelRuntime) -> void:
	# Update the existing UI nodes (if already built)

	# Title label
	var title := panel.get_node_or_null("Root/TitleLabel") as Label
	if title and upgrade_title_font:
		title.add_theme_font_override("font", upgrade_title_font)
	title.add_theme_font_size_override("font_size", upgrade_title_font_size)

	# Body (RichTextLabel)
	var body := panel.get_node_or_null("Root/BodyLabel") as RichTextLabel
	if body and upgrade_body_font:
		body.add_theme_font_override("font", upgrade_body_font)
	body.add_theme_font_size_override("font_size", upgrade_body_font_size)

	# Buttons (upgrade choices + continue/restart)
	# If you named buttons in build_ui, hit them directly; otherwise just brute-force all Buttons under panel.
	for b in panel.find_children("", "Button", true, false):
		var btn := b as Button
		if btn == null:
			continue
		if upgrade_button_font:
			btn.add_theme_font_override("font", upgrade_button_font)
		btn.add_theme_font_size_override("font_size", upgrade_button_font_size)

func _on_supply_continue() -> void:
	if _pending_supply_node_id < 0:
		return

	var id := _pending_supply_node_id
	_pending_supply_node_id = -1

	# Mark cleared in radar data
	if radar != null and id >= 0 and id < radar.nodes.size():
		radar.nodes[id].cleared = true

	# Persist cleared in RunState
	var rs := get_node_or_null("/root/RunStateNode")
	if rs != null and ("overworld_cleared" in rs):
		rs.overworld_cleared[str(id)] = true
		if rs.has_method("save_to_disk"):
			rs.call("save_to_disk")

	# Update visuals
	if radar != null:
		radar.queue_redraw()

func _roll_supply_upgrades() -> Array:
	# Simple, guaranteed-working pool: global upgrades (these always apply)
	return [
		{"id": &"all_hp_plus_1",   "title": "ARMOR PLATING", "desc": "+1 Max HP to all allies."},
		{"id": &"all_move_plus_1", "title": "FIELD DRILLS",  "desc": "+1 Move to all allies."},
		{"id": &"all_dmg_plus_1",  "title": "HOT LOADS",     "desc": "+1 Attack Damage to all allies."},
	]

func _type_to_key(t: int) -> StringName:
	match t:
		OverworldRadar.NodeType.START:  return &"start"
		OverworldRadar.NodeType.COMBAT: return &"combat"
		OverworldRadar.NodeType.SUPPLY: return &"supply"
		OverworldRadar.NodeType.EVENT:  return &"event"
		OverworldRadar.NodeType.ELITE:  return &"elite"
		OverworldRadar.NodeType.BOSS:   return &"boss"
	return &"combat"

func _set_fade_alpha(a: float) -> void:
	if fade_rect == null or not is_instance_valid(fade_rect):
		return
	var m := fade_rect.modulate
	m.a = a
	fade_rect.modulate = m

func _fade_from_black_on_ready() -> void:
	# starts black (1), fades to clear (0)
	_set_fade_alpha(1.0)
	call_deferred("_do_fade_from_black")

func _do_fade_from_black() -> void:
	if fade_rect == null or not is_instance_valid(fade_rect):
		return
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, fade_duration)

func _fade_to_black() -> void:
	if fade_rect == null or not is_instance_valid(fade_rect):
		# fallback if not assigned
		await get_tree().create_timer(0.25).timeout
		return

	# ensure it’s not already black
	_set_fade_alpha(clamp(fade_rect.modulate.a, 0.0, 1.0))

	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, fade_duration)
	await tw.finished
