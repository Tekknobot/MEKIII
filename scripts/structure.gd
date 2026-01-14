extends Node2D
class_name Structure

@export var footprint_size := Vector2i(2, 2)
var origin_cell: Vector2i = Vector2i.ZERO

const Z_STRUCTURES := 0

func set_origin(cell: Vector2i, terrain: TileMap) -> void:
	origin_cell = cell
	if terrain != null and is_instance_valid(terrain):
		global_position = terrain.to_global(terrain.map_to_local(cell))
	update_layering()

func update_layering() -> void:
	# Depth sorting uses the x+y sum of the bottom-right "feet" cell.
	var feet := origin_cell + Vector2i(footprint_size.x - 1, footprint_size.y - 1)
	z_as_relative = false
	z_index = Z_STRUCTURES + feet.x + feet.y
