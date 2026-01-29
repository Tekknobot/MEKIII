extends Camera2D
class_name OverworldCamera

@export var radar_path: NodePath        # drag your OverworldRadar node here in Inspector
@export var smooth_follow := true
@export var follow_speed := 6.0         # higher = snappier

@export var fixed_zoom := Vector2(1.0, 1.0)

var radar: Node2D

func _ready() -> void:
	radar = get_node_or_null(radar_path)
	zoom = fixed_zoom

	# If radar exists, snap instantly on start
	if radar != null:
		global_position = radar.global_position

func _process(delta: float) -> void:
	if radar == null:
		return

	if smooth_follow:
		global_position = global_position.lerp(radar.global_position, follow_speed * delta)
	else:
		global_position = radar.global_position
