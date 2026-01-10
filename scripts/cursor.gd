extends Sprite2D
class_name GridCursor

@export var tilemap: TileMap
@export var map_controller: Node # drag your map Node2D here in inspector
@export var highlight_texture_1x1: Texture2D
@export var highlight_texture_2x2: Texture2D
@export var mouse_offset := Vector2(8, 16)

var hovered_cell: Vector2i = Vector2i(-1, -1)

func _ready() -> void:
	top_level = true

func _process(_delta: float) -> void:
	if tilemap == null or map_controller == null:
		return

	var mouse_global := get_viewport().get_mouse_position()
	mouse_global = get_viewport().get_canvas_transform().affine_inverse() * mouse_global
	mouse_global += mouse_offset

	# Convert mouse world -> tile cell
	var local := tilemap.to_local(mouse_global)
	var cell := tilemap.local_to_map(local)

	# If out of bounds, hide cursor + clear hover
	if not map_controller.grid.in_bounds(cell):
		visible = false
		map_controller.set_hovered_unit(null)
		return

	visible = true
	hovered_cell = cell

	# Find unit under this cell (works for 2x2 because all cells are occupied)
	var u: Unit = map_controller.unit_at_cell(cell)

	# Decide what cell to anchor the cursor to:
	# - If hovering a unit, anchor to the unit's ORIGIN (top-left of footprint)
	# - Otherwise anchor to hovered cell
	var anchor_cell := cell
	if u != null:
		anchor_cell = map_controller.get_unit_origin(u)

	# Position cursor exactly on that anchor cell
	global_position = tilemap.to_global(tilemap.map_to_local(anchor_cell))

	# Swap cursor texture based on footprint size
	if u != null:
		var fp := u.footprint_cells(anchor_cell)
		texture = (highlight_texture_2x2 if fp.size() > 1 else highlight_texture_1x1)
	else:
		texture = highlight_texture_1x1

	# Tell map to highlight hover footprint
	map_controller.set_hovered_unit(u)
