extends Camera2D

@export var map_width := 16
@export var map_height := 16

@onready var terrain := $"../Terrain"

# --- Middle-mouse drag pan ---
@export var drag_button: MouseButton = MOUSE_BUTTON_MIDDLE
@export var drag_sensitivity := 1.0

var _dragging := false
var _last_mouse_pos := Vector2.ZERO

@export var zoom_levels := [1.0, 2.0, 3.0]
@export var default_zoom_index := 1   # 0=1x, 1=2x, 2=3x

var _zoom_index := 1

@export var zoom_tween_time := 0.12
var _zoom_tw: Tween = null

func _ready() -> void:
	_zoom_index = clamp(default_zoom_index, 0, zoom_levels.size()-1)
	zoom = Vector2.ONE * zoom_levels[_zoom_index]

	await get_tree().process_frame
	center_on_map()

func center_on_map() -> void:
	# Get the world position of top-left and bottom-right tiles
	var top_left = terrain.map_to_local(Vector2i(0, 0))
	var bottom_right = terrain.map_to_local(Vector2i(map_width, map_height))

	# Convert to global
	top_left = terrain.to_global(top_left)
	bottom_right = terrain.to_global(bottom_right)

	# Center point
	var center = (top_left + bottom_right) * 0.5
	global_position = center

func _input(event: InputEvent) -> void:
	# Start/stop dragging with mouse wheel button (middle mouse)
	if event is InputEventMouseButton and event.button_index == drag_button:
		if event.pressed:
			_dragging = true
			_last_mouse_pos = event.position
		else:
			_dragging = false
		get_viewport().set_input_as_handled()

	# While dragging, move camera opposite to mouse movement
	if _dragging and event is InputEventMouseMotion:
		var delta = event.position - _last_mouse_pos
		_last_mouse_pos = event.position

		# Dragging should "grab" the world: move camera opposite the mouse
		global_position -= delta * drag_sensitivity / zoom

		get_viewport().set_input_as_handled()

	# Mouse wheel zoom
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom_index(_zoom_index + 1)
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom_index(_zoom_index - 1)
			get_viewport().set_input_as_handled()
			return

func _set_zoom_index(i: int) -> void:
	_zoom_index = clamp(i, 0, zoom_levels.size() - 1)

	var target := Vector2.ONE * float(zoom_levels[_zoom_index])

	# kill previous zoom tween if it's still running
	if _zoom_tw != null and is_instance_valid(_zoom_tw):
		_zoom_tw.kill()
	_zoom_tw = null

	# smooth zoom
	_zoom_tw = create_tween()
	_zoom_tw.set_trans(Tween.TRANS_SINE)
	_zoom_tw.set_ease(Tween.EASE_OUT)
	_zoom_tw.tween_property(self, "zoom", target, max(0.01, zoom_tween_time))
