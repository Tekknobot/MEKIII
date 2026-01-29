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

		# mission payload
		rs.mission_node_id = node_id
		rs.mission_difficulty = difficulty
		rs.mission_node_type = _type_to_key(node_type)

		# seed: stable per node (so re-entering same node is repeatable)
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
