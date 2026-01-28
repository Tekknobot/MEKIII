extends Camera2D

@export var map_width := 16
@export var map_height := 16
@onready var terrain := $"../Terrain"

# --- Middle-mouse drag pan ---
@export var drag_button: MouseButton = MOUSE_BUTTON_MIDDLE
@export var drag_sensitivity := 1.0

var _dragging := false
var _last_mouse_pos := Vector2.ZERO

# --- Zoom ---
@export var zoom_levels := [1.0, 2.0, 3.0]
@export var default_zoom_index := 1
var _zoom_index := 1
@export var zoom_tween_time := 0.12
var _zoom_tw: Tween = null

# ----------------------------------------------------
# Optional smooth follow using GROUP
# ----------------------------------------------------
@export var follow_enabled := false
@export var follow_group := "Bomber"     # group name to search
@export var follow_smoothness := 8.0
@export var disable_follow_while_dragging := true
@export var snap_on_enable_follow := true

# Follow gating: only follow when target is moving DOWN (+Y)
@export var follow_only_when_moving_down := true
@export var down_deadzone_px := 0.25 # ignore tiny jitter

# When target starts moving UP, smoothly return to map center
@export var recenter_on_up := true
@export var recenter_smoothness := 6.0
@export var up_deadzone_px := 0.25  # ignore tiny jitter
@export var recenter_latch := true  # if true, keep recentering until close to center
@export var recenter_stop_dist := 2.0

var _follow_target: Node2D = null
var _follow_prev_target_y: float = INF

var _recentering := false
var _map_center: Vector2 = Vector2.ZERO


func _ready() -> void:
	_zoom_index = clamp(default_zoom_index, 0, zoom_levels.size() - 1)
	zoom = Vector2.ONE * float(zoom_levels[_zoom_index])

	await get_tree().process_frame
	_map_center = _compute_map_center()
	global_position = _map_center

	# Find initial follow target if enabled
	if follow_enabled:
		_find_follow_target()
		if snap_on_enable_follow and _follow_target != null:
			global_position = _follow_target.global_position
		if _follow_target != null:
			_follow_prev_target_y = _follow_target.global_position.y


func _process(delta: float) -> void:
	# If follow target lost (eg. bomber died), try to reacquire
	if follow_enabled and (_follow_target == null or not is_instance_valid(_follow_target)):
		_find_follow_target()

	# If user is dragging, don't auto-move camera
	if disable_follow_while_dragging and _dragging:
		return

	# Update cached map center (in case map size changes or tilemap shifts)
	_map_center = _compute_map_center()

	# If we're recentering, do that first (latched)
	if _recentering:
		var t2 := 1.0 - exp(-recenter_smoothness * delta)
		global_position = global_position.lerp(_map_center, t2)

		var done := false

		if not recenter_latch:
			done = true
		else:
			if global_position.distance_to(_map_center) <= recenter_stop_dist:
				done = true

		if done:
			_recentering = false
			follow_enabled = false   # ✅ TURN OFF FOLLOW AFTER CENTERING

		return

	# No follow? nothing else
	if not follow_enabled:
		return
	if _follow_target == null:
		return

	# --- Movement detection ---
	var y := _follow_target.global_position.y
	if _follow_prev_target_y == INF:
		_follow_prev_target_y = y
		return

	var dy := y - _follow_prev_target_y
	_follow_prev_target_y = y

	# If target starts moving UP (dy < 0), begin recentering
	if recenter_on_up and dy < -up_deadzone_px:
		_recentering = true
		return

	# Only follow when moving DOWN (+Y)
	if follow_only_when_moving_down:
		if dy <= down_deadzone_px:
			return

	# Smooth exponential follow
	var t := 1.0 - exp(-follow_smoothness * delta)
	global_position = global_position.lerp(_follow_target.global_position, t)


func _find_follow_target() -> void:
	var arr := get_tree().get_nodes_in_group(follow_group)
	if arr.size() > 0:
		_follow_target = arr[0] as Node2D
		if _follow_target != null:
			_follow_prev_target_y = _follow_target.global_position.y
		else:
			_follow_prev_target_y = INF
	else:
		_follow_target = null
		_follow_prev_target_y = INF


func set_follow_enabled(on: bool) -> void:
	follow_enabled = on
	_recentering = false

	if follow_enabled:
		_find_follow_target()
		if snap_on_enable_follow and _follow_target != null:
			global_position = _follow_target.global_position
		if _follow_target != null:
			_follow_prev_target_y = _follow_target.global_position.y
	else:
		_follow_prev_target_y = INF


func _compute_map_center() -> Vector2:
	# Get the world position of top-left and bottom-right tiles
	var top_left = terrain.map_to_local(Vector2i(0, 0))
	var bottom_right = terrain.map_to_local(Vector2i(map_width, map_height))

	# Convert to global
	top_left = terrain.to_global(top_left)
	bottom_right = terrain.to_global(bottom_right)

	return (top_left + bottom_right) * 0.5


func center_on_map() -> void:
	_map_center = _compute_map_center()
	global_position = _map_center


func _input(event: InputEvent) -> void:
	# Drag start/stop
	if event is InputEventMouseButton and event.button_index == drag_button:
		if event.pressed:
			_dragging = true
			_last_mouse_pos = event.position
		else:
			_dragging = false
		get_viewport().set_input_as_handled()

	# Drag motion
	if _dragging and event is InputEventMouseMotion:
		var delta = event.position - _last_mouse_pos
		_last_mouse_pos = event.position
		global_position -= delta * drag_sensitivity / zoom
		get_viewport().set_input_as_handled()

	# Wheel zoom
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom_index(_zoom_index + 1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom_index(_zoom_index - 1)
			get_viewport().set_input_as_handled()


func _set_zoom_index(i: int) -> void:
	_zoom_index = clamp(i, 0, zoom_levels.size() - 1)
	var target := Vector2.ONE * float(zoom_levels[_zoom_index])

	if _zoom_tw != null and is_instance_valid(_zoom_tw):
		_zoom_tw.kill()

	_zoom_tw = create_tween()
	_zoom_tw.set_trans(Tween.TRANS_SINE)
	_zoom_tw.set_ease(Tween.EASE_OUT)
	_zoom_tw.tween_property(self, "zoom", target, max(0.01, zoom_tween_time))
