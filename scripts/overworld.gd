extends Node2D

@export var game_scene: PackedScene

@onready var radar: OverworldRadar = $OverworldRadar

func _ready() -> void:
	if radar != null:
		radar.mission_requested.connect(_on_mission_requested)

func _on_mission_requested(node_id: int, node_type: int, difficulty: float) -> void:
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
		get_tree().change_scene_to_packed(game_scene)
	else:
		get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _type_to_key(t: int) -> StringName:
	match t:
		OverworldRadar.NodeType.START:  return &"start"
		OverworldRadar.NodeType.COMBAT: return &"combat"
		OverworldRadar.NodeType.SUPPLY: return &"supply"
		OverworldRadar.NodeType.EVENT:  return &"event"
		OverworldRadar.NodeType.ELITE:  return &"elite"
		OverworldRadar.NodeType.BOSS:   return &"boss"
	return &"combat"
