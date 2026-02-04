extends Node2D

@export var float_time := 0.45
@export var fade_time := 0.20

# If you want zero drift, set drift_px = 0
@export var drift_px := 6.0
@export var drift_speed := 10.0

@onready var p := $CPUParticles2D as CPUParticles2D

var _t := 0.0
var _base_pos := Vector2.ZERO

func _ready() -> void:
	if p == null:
		queue_free()
		return

	_base_pos = position

	# fire the one-shot burst
	p.restart()

	# let it float for a bit
	await get_tree().create_timer(max(0.01, float_time)).timeout

	# fade out and cleanup
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, max(0.01, fade_time))
	await tw.finished
	queue_free()

func _process(dt: float) -> void:
	if drift_px <= 0.0:
		return
	_t += dt * drift_speed
	position = _base_pos + Vector2(sin(_t), cos(_t * 0.9)) * drift_px
