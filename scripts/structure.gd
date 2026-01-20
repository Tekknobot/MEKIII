extends Node2D
class_name Structure

@export var footprint_size := Vector2i(1, 1)
var origin_cell: Vector2i = Vector2i.ZERO
var _terrain: TileMap = null

# Depth baseline (bump this up if needed vs other things)
@export var z_base := 1
@export var z_per_cell := 1

# HP / damage
@export var max_hp := 6
var hp: int = 6

# Animation hooks
@export var demolished_anim := "demolished" # AnimatedSprite2D animation name
@export var hurt_flash_time := 0.80

signal destroyed(structure: Structure)

var _base_modulate: Color = Color(1, 1, 1, 1)
var _flash_tween: Tween = null

func _ready() -> void:
	hp = max_hp
	add_to_group("Structures")

	var ci := _find_first_canvas_item()
	if ci != null:
		_base_modulate = ci.modulate

	update_layering()


func set_origin(cell: Vector2i, terrain: TileMap) -> void:
	origin_cell = cell
	set_meta("cell", origin_cell)
	_terrain = terrain
	if _terrain != null and is_instance_valid(_terrain):
		global_position = _terrain.to_global(_terrain.map_to_local(cell))
	update_layering()

func update_layering() -> void:
	# Depth sorting uses the x+y sum of the bottom-right "feet" cell.
	var feet := origin_cell + Vector2i(footprint_size.x - 1, footprint_size.y - 1)
	z_as_relative = false
	z_index = z_base + (feet.x + feet.y) * z_per_cell

# ----------------------------------------------------
# Damage API (call this from TNT / splash / mines, etc.)
# ----------------------------------------------------
func apply_damage(amount: int) -> void:
	if amount <= 0:
		return
	if hp <= 0:
		return

	hp -= amount
	_flash_white(hurt_flash_time)

	if hp <= 0:
		hp = 0
		_set_demolished()
		emit_signal("destroyed", self)

func is_destroyed() -> bool:
	return hp <= 0

func _set_demolished() -> void:
	# Prefer a structure-defined method if you override this in child scenes
	if has_method("on_demolished"):
		call("on_demolished")
		return

	# AnimatedSprite2D path
	var a := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if a != null and a.sprite_frames != null:
		if a.sprite_frames.has_animation(demolished_anim):
			a.play(demolished_anim)
			return

	# AnimationPlayer path
	var ap := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap != null:
		if ap.has_animation(demolished_anim):
			ap.play(demolished_anim)
			return

	# Fallback: dim it so you can tell it died
	var ci := _find_first_canvas_item()
	if ci != null:
		ci.modulate = Color(0.5, 0.5, 0.5, 1.0)
		_base_modulate = ci.modulate
	else:
		modulate = Color(0.5, 0.5, 0.5, 1.0)


# -----------------------
# Simple white flash
# -----------------------
func _flash_white(t: float) -> void:
	var ci := _find_first_canvas_item()
	if ci == null:
		return

	# If base not initialized yet, set it now
	if _base_modulate == null:
		_base_modulate = ci.modulate

	# ✅ Kill any previous flash tween so overlaps can't leave you stuck
	if _flash_tween != null and is_instance_valid(_flash_tween):
		_flash_tween.kill()
	_flash_tween = null

	# Always flash from the CURRENT color, but return to BASE color
	var start := ci.modulate
	var peak := Color(
		min(start.r * 2.0, 2.0),
		min(start.g * 2.0, 2.0),
		min(start.b * 2.0, 2.0),
		start.a
	)

	_flash_tween = create_tween()
	_flash_tween.set_trans(Tween.TRANS_SINE)
	_flash_tween.set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(ci, "modulate", peak, max(0.01, t * 0.35))
	_flash_tween.set_ease(Tween.EASE_IN)
	_flash_tween.tween_property(ci, "modulate", _base_modulate, max(0.01, t * 0.65))

	# Safety: force exact base at end (prevents tiny drift)
	_flash_tween.finished.connect(func():
		if ci != null and is_instance_valid(ci):
			ci.modulate = _base_modulate
		_flash_tween = null
	)

func _find_first_canvas_item() -> CanvasItem:
	# Prefer obvious render nodes
	var s := get_node_or_null("Sprite2D") as Sprite2D
	if s != null:
		return s

	var a := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if a != null:
		return a

	# Otherwise first CanvasItem child
	for ch in get_children():
		if ch is CanvasItem:
			return ch as CanvasItem

	# As last resort, Structure itself is a CanvasItem? (Node2D isn't)
	return null

# -----------------------
# Helper: footprint cells
# -----------------------
func get_footprint_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in range(footprint_size.x):
		for dy in range(footprint_size.y):
			out.append(origin_cell + Vector2i(dx, dy))
	return out

func get_cell() -> Vector2i:
	return origin_cell

func occupies_cell(c: Vector2i) -> bool:
	return (c.x >= origin_cell.x and c.y >= origin_cell.y
		and c.x < origin_cell.x + footprint_size.x
		and c.y < origin_cell.y + footprint_size.y)
