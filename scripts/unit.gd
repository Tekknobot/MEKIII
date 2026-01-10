extends Node2D
class_name Unit

@export var footprint_size := Vector2i(1, 1)
@export var move_range := 3
@export var attack_range := 1
@export var attack_repeats := 1
@export var attack_anim: StringName = "attack"

var grid_pos := Vector2i.ZERO

const Z_UNITS := 2000

func footprint_cells(origin: Vector2i = grid_pos) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx in range(footprint_size.x):
		for dy in range(footprint_size.y):
			cells.append(origin + Vector2i(dx, dy))
	return cells

func feet_cell() -> Vector2i:
	return grid_pos + Vector2i(footprint_size.x - 1, footprint_size.y - 1)

func update_layering() -> void:
	var key := feet_cell().x + feet_cell().y
	z_index = Z_UNITS + key
