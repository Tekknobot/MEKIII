extends Node2D
class_name StructureShot

signal finished

# ✅ Every shot takes the same amount of time (no fast “short shots”)
@export var shot_time_sec: float = 2.00

# Curve look controls
@export var arc_height_px: float = 140.0          # base arc height
@export var arc_height_per_px: float = 0.10       # extra height per pixel of distance
@export var segments: int = 128                   # curve smoothness

@onready var line: Line2D = $Line2D

var _start_world: Vector2
var _end_world: Vector2
var _t := 0.0
var _dur := 0.45
var _end_local: Vector2
var _ctrl_local: Vector2
var _pts: PackedVector2Array

func fire(start_world: Vector2, end_world: Vector2) -> void:
	_start_world = start_world

	# ✅ 16px destination offset (screen up)
	_end_world = end_world + Vector2(0, -16)

	# Root sits at start, so local points are relative to start
	global_position = _start_world
	_end_local = to_local(_end_world)

	# ✅ Fixed duration for all shots
	_dur = max(shot_time_sec, 0.05)
	_t = 0.0

	# Still use distance for arc height so long shots arc higher
	var dist := _start_world.distance_to(_end_world)
	var mid := _end_local * 0.5
	var h := arc_height_px + dist * arc_height_per_px

	# Screen "up" is negative Y (works well for most 2D/iso)
	_ctrl_local = mid + Vector2(0, -h)

	_pts = _build_bezier_points(Vector2.ZERO, _ctrl_local, _end_local, max(segments, 6))

	line.width = 1.0
	line.clear_points()
	line.add_point(_pts[0]) # start visible

	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	var a = clamp(_t / _dur, 0.0, 1.0)

	# ✅ Smooth reveal: continuous “tip” interpolation (no stepping)
	var n := _pts.size() - 1
	if n <= 0:
		set_process(false)
		emit_signal("finished")
		return

	var prog = a * float(n)
	var whole := int(floor(prog))
	var frac = prog - float(whole)

	line.clear_points()

	# add fully revealed points
	for i in range(whole + 1):
		line.add_point(_pts[i])

	# add a smoothly moving tip point between points
	if whole < n:
		var p0 := _pts[whole]
		var p1 := _pts[whole + 1]
		line.add_point(p0.lerp(p1, frac))

	if a >= 1.0:
		set_process(false)
		emit_signal("finished")

func _build_bezier_points(p0: Vector2, p1: Vector2, p2: Vector2, segs: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(segs + 1)

	for i in range(segs + 1):
		var t := float(i) / float(segs)
		var u := 1.0 - t
		# quadratic bezier: (1-t)^2 p0 + 2(1-t)t p1 + t^2 p2
		out[i] = (u*u)*p0 + (2.0*u*t)*p1 + (t*t)*p2

	return out
