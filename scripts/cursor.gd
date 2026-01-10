extends Sprite2D
class_name GridCursor

@export var tilemap: TileMap
@export var map_controller: Node
@export var highlight_texture_1x1: Texture2D
@export var highlight_texture_2x2: Texture2D
@export var mouse_offset := Vector2(0, 0)

# Cursor art-specific offsets (tweak in inspector)
@export var cursor_offset_1x1 := Vector2(0, 0)
@export var cursor_offset_2x2 := Vector2(0, 16)

var hovered_cell: Vector2i = Vector2i(-1, -1)

func _ready() -> void:
	top_level = true

func _process(_delta: float) -> void:
	if tilemap == null or map_controller == null:
		return

	var mouse_global := get_viewport().get_mouse_position()
	mouse_global = get_viewport().get_canvas_transform().affine_inverse() * mouse_global
	mouse_global += mouse_offset

	var local := tilemap.to_local(mouse_global)
	var cell := tilemap.local_to_map(local)

	if not map_controller.grid.in_bounds(cell):
		visible = false
		map_controller.set_hovered_unit(null)
		return

	visible = true
	hovered_cell = cell

	var u: Unit = map_controller.unit_at_cell(cell)

	var anchor_cell := cell
	if u != null:
		anchor_cell = map_controller.get_unit_origin(u)

	# Decide footprint + texture
	var is_big := false
	if u != null:
		var fp := u.footprint_cells(anchor_cell)
		is_big = fp.size() > 1

	texture = (highlight_texture_2x2 if is_big else highlight_texture_1x1)

	# Base position at anchor cell
	var base_world := tilemap.to_global(tilemap.map_to_local(anchor_cell))

	# Apply pixel offset based on footprint
	global_position = base_world + (cursor_offset_2x2 if is_big else cursor_offset_1x1)

	map_controller.set_hovered_unit(u)
