extends Area2D
class_name LaserDrop

@export var spin_speed := 2.5
@export var rot_degrees := 12.0

var _t := 0.0
var visual: Node2D

func _ready() -> void:
	visual = get_node("Visual") as Node2D

	# connect overlap signal
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

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
