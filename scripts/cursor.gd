extends Sprite2D
class_name GridCursor

@export var tilemap: TileMap
@export var map_controller: Node

@export var highlight_texture: Texture2D
@export var mouse_offset := Vector2(0, 0)
@export var cursor_offset := Vector2(0, 0)

# Depth sorting by grid coordinate sum
@export var cursor_z_base := 0
@export var cursor_z_per_cell := 1

var hovered_cell: Vector2i = Vector2i(-1, -1)

func _ready() -> void:
	top_level = true
	z_as_relative = false
	show_behind_parent = false
	texture = highlight_texture
	z_index = cursor_z_base

func _process(_delta: float) -> void:
	if tilemap == null or map_controller == null:
		return
	if map_controller.grid == null:
		return

	var mouse_global := get_viewport().get_mouse_position()
	mouse_global = get_viewport().get_canvas_transform().affine_inverse() * mouse_global
	mouse_global += mouse_offset

	var local := tilemap.to_local(mouse_global)
	var cell := tilemap.local_to_map(local)

	if not map_controller.grid.in_bounds(cell):
		visible = false
		hovered_cell = Vector2i(-1, -1)
		return

	visible = true
	hovered_cell = cell

	# Position cursor on hovered cell
	global_position = tilemap.to_global(tilemap.map_to_local(cell)) + cursor_offset

	# ✅ Proper x+y sum layering
	z_index = cursor_z_base + ((cell.x + cell.y) * cursor_z_per_cell)
