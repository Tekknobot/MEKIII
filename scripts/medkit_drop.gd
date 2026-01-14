extends Area2D
class_name MedkitDrop

@export var spin_speed := 2.5
@export var rot_degrees := 12.0

@export_range(1, 10, 1) var heal_amount := 2
@export var also_flash := true

# keeps pickups above terrain/roads/structures but still x+y sorted
@export var z_base := 2

var _t := 0.0
var visual: Node2D

@export var pickup_sfx: AudioStream
@export var pickup_vol_db := -6.0
@export var pickup_pitch_min := 0.95
@export var pickup_pitch_max := 1.05

func _ready() -> void:
	visual = get_node_or_null("Visual") as Node2D

	# connect overlap signals
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

	# ✅ heal
	var before := int(u.hp)
	u.hp = min(int(u.max_hp), int(u.hp) + int(heal_amount))

	# ✅ play pickup sfx only if it actually healed
	if int(u.hp) > before and pickup_sfx != null:
		if map.has_method("play_sfx_poly"):
			map.play_sfx_poly(pickup_sfx, u.global_position, pickup_vol_db, pickup_pitch_min, pickup_pitch_max)
		else:
			var p := AudioStreamPlayer2D.new()
			p.stream = pickup_sfx
			p.global_position = u.global_position
			p.volume_db = pickup_vol_db
			p.pitch_scale = randf_range(pickup_pitch_min, pickup_pitch_max)
			get_tree().current_scene.add_child(p)
			p.play()
			p.finished.connect(func(): if is_instance_valid(p): p.queue_free())

	# optional flash
	if also_flash and int(u.hp) > before:
		if map.has_method("_flash_unit"):
			await map._flash_unit(u)

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

	var local_in_terrain := terrain.to_local(global_position)
	var cell := terrain.local_to_map(local_in_terrain)

	# ✅ x+y sum layering
	z_as_relative = false
	z_index = int(z_base + cell.x + cell.y)
