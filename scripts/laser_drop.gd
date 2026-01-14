extends Area2D
class_name LaserDrop

@export var spin_speed := 2.5
@export var rot_degrees := 12.0

# keeps pickups above terrain/roads/structures but still x+y sorted
@export var z_base := 1

var _t := 0.0
var visual: Node2D

func _ready() -> void:
	visual = get_node_or_null("Visual") as Node2D

	# connect overlap signal
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# ✅ depth sort once at spawn
	_apply_xy_sum_layering()

func _process(delta: float) -> void:
	if visual == null:
		return

	_t += delta
	var r := sin(_t * spin_speed * TAU) * deg_to_rad(rot_degrees)
	visual.rotation = r

func _on_body_entered(body: Node) -> void:
	_try_collect(body)

func _on_area_entered(area: Area2D) -> void:
	_try_collect(area)

func _try_collect(obj: Node) -> void:
	# we only care about Units
	if not (obj is Unit):
		return

	# find the Map node (parent of Units root)
	var map := get_tree().get_first_node_in_group("GameMap")
	if map == null:
		return

	# prevent double trigger
	set_deferred("monitoring", false)

	# call orbital strike
	map._orbital_laser_strike()

	# small vanish
	queue_free()

func _apply_xy_sum_layering() -> void:
	var map := get_tree().get_first_node_in_group("GameMap")
	if map == null:
		return
	if not map.has_node("Terrain"):
		return

	var terrain := map.get_node("Terrain") as TileMap
	if terrain == null or not is_instance_valid(terrain):
		return

	# world -> terrain local -> map cell
	var local_in_terrain := terrain.to_local(global_position)
	var cell := terrain.local_to_map(local_in_terrain)

	# ✅ x+y sum layering
	z_as_relative = false
	z_index = int(z_base + cell.x + cell.y)
