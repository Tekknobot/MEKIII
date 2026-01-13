extends Area2D
class_name MedkitDrop

@export var spin_speed := 2.5
@export var rot_degrees := 12.0

@export_range(1, 10, 1) var heal_amount := 2
@export var also_flash := true

var _t := 0.0
var visual: Node2D

func _ready() -> void:
	visual = get_node_or_null("Visual") as Node2D

	# connect overlap signals
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
	# Only Units can collect
	if not (obj is Unit):
		return

	var u := obj as Unit
	if u == null or not is_instance_valid(u):
		return

	# find the Map node (same pattern as LaserDrop)
	var map := get_tree().get_first_node_in_group("GameMap")
	if map == null:
		return

	# prevent double trigger
	set_deferred("monitoring", false)

	# ✅ heal (works with your Unit.hp / Unit.max_hp)
	var before := u.hp
	u.hp = min(u.max_hp, u.hp + heal_amount)

	# optional flash via Map's existing helper (if present)
	if also_flash and u.hp > before:
		if map.has_method("_flash_unit"):
			await map._flash_unit(u)

	# small vanish
	queue_free()
