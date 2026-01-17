extends Camera2D

@export var map_width := 16
@export var map_height := 16

@onready var terrain := $"../Terrain"

# --- Middle-mouse drag pan ---
@export var drag_button: MouseButton = MOUSE_BUTTON_MIDDLE
@export var drag_sensitivity := 1.0

var _dragging := false
var _last_mouse_pos := Vector2.ZERO

func _ready() -> void:
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
