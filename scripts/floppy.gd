extends Node2D
class_name Floppy

@export var spin_speed := 2.5
@export var rot_degrees := 12.0

# keeps pickups above terrain/roads/structures but still x+y sorted
@export var z_base := 1

var _t := 0.0
var visual: Node2D

func _ready() -> void:
	# Prefer a child named Visual
	visual = get_node_or_null("Visual") as Node2D

	# Fallback: if you didn't name it Visual, try first Node2D child
	if visual == null:
		for ch in get_children():
			if ch is Node2D:
				visual = ch
				break

	if visual == null:
		push_warning("Floppy: No Node2D child found to rotate. Add a child named 'Visual' (Sprite2D).")
	else:
		# Make sure we’re actually ticking
		set_process(true)

	_apply_xy_sum_layering()

func _process(delta: float) -> void:
	if visual == null:
		return

	_t += delta
	var r := sin(_t * spin_speed * TAU) * deg_to_rad(rot_degrees)
	visual.rotation = r

func _apply_xy_sum_layering() -> void:
	# If spawner already gave us the authoritative grid cell, use it.
	if has_meta("pickup_cell"):
		var cell: Vector2i = get_meta("pickup_cell")
		z_as_relative = false
		z_index = int(z_base + cell.x + cell.y)
		return

	# ---- Fallback only if no cell meta ----
	var map := get_tree().get_first_node_in_group("GameMap")
	if map == null:
		return
	if not map.has_node("Terrain"):
		return

	var terrain := map.get_node("Terrain") as TileMap
	if terrain == null or not is_instance_valid(terrain):
		return

	# Convert world → terrain local → map cell
	var local_px := terrain.to_local(global_position)
	var cell := terrain.local_to_map(local_px)

	z_as_relative = false
	z_index = int(z_base + cell.x + cell.y)
