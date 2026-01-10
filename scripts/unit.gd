extends Node2D
class_name Unit

@export var footprint_size := Vector2i(1, 1)
@export var move_range := 3
@export var attack_range := 1
@export var attack_repeats := 1
@export var attack_anim: StringName = "attack"

@export var max_hp := 3   # NEW
var hp := 3               # NEW

@export var death_offset := Vector2.ZERO
var _sprite_base_pos := Vector2.ZERO

var grid_pos := Vector2i.ZERO
const Z_UNITS := 2000

func _ready():
	hp = max_hp
	var spr := _unit_sprite()
	if spr != null:
		_sprite_base_pos = spr.position

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


# =========================
# Damage / Death API
# =========================

func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		await die() # wait so the animation can play

func die() -> void:
	# Prevent double-death if hit multiple times quickly
	if is_queued_for_deletion():
		return

	# Try play death animation
	var spr := _unit_sprite()
	var played := false

	if spr != null and spr.sprite_frames != null:
		if spr.sprite_frames.has_animation("explode"):
			self.scale = Vector2(1,1)
			
			# Apply per-unit death offset
			spr.position = _sprite_base_pos + death_offset
			
			spr.play("explode")
			played = true

		elif spr.sprite_frames.has_animation("death"):
			
			spr.play("death")
			played = true

	# Tell the map to clear occupancy / selection immediately
	# (so dead units stop blocking tiles right away)
	var map := _get_map_controller()
	if map != null and map.has_method("_on_unit_died"):
		map._on_unit_died(self)

	# If we played a death anim, wait for it to finish
	if played:
		await spr.animation_finished
	else:
		# tiny fallback pause so it doesn't feel instant
		await get_tree().create_timer(0.05).timeout

	queue_free()


# ---- helpers (Unit-local) ----
func _unit_sprite() -> AnimatedSprite2D:
	if has_node("AnimatedSprite2D"):
		return $AnimatedSprite2D as AnimatedSprite2D
	return null

func _get_map_controller() -> Node:
	# UnitsRoot is a child of the main map node in your setup
	# Unit -> Units (Node2D) -> Map (Node2D)
	if get_parent() != null and get_parent().get_parent() != null:
		return get_parent().get_parent()
	return null
