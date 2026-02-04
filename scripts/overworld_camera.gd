extends Camera2D
class_name OverworldCamera

@export var radar_path: NodePath

@export var smooth_follow := true
@export var follow_speed := 6.0
@export var fixed_zoom := Vector2(1.0, 1.0)

@export var launch_zoom := Vector2(2.2, 2.2)
@export var launch_time := 0.35
@export var launch_hold := 0.08

var radar: OverworldRadar
var _cinematic_active := false
var _tw: Tween

signal launch_cinematic_finished


func _ready() -> void:
	radar = get_node_or_null(radar_path) as OverworldRadar
	if radar == null:
		push_error("OverworldCamera: radar_path not set or invalid.")
		return

	zoom = fixed_zoom
	global_position = radar.get_center_world()

func _process(delta: float) -> void:
	if radar == null or _cinematic_active:
		return

	var target := radar.get_center_world()
	global_position = global_position.lerp(target, follow_speed * delta) \
		if smooth_follow else target

func play_launch_cinematic(target_world_pos: Vector2) -> void:
	if _tw != null and is_instance_valid(_tw):
		_tw.kill()

	_cinematic_active = true

	_tw = create_tween()
	_tw.set_trans(Tween.TRANS_SINE)
	_tw.set_ease(Tween.EASE_IN_OUT)
	_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	_tw.tween_property(self, "global_position", target_world_pos, launch_time)
	_tw.parallel().tween_property(self, "zoom", launch_zoom, launch_time)

	await _tw.finished
	
	if launch_hold > 0.0:
		await get_tree().create_timer(launch_hold).timeout
