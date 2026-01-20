extends Node2D
class_name Unit

enum Team { ALLY, ENEMY }
# --- Specials base plumbing ---
var special_cd: Dictionary = {} # String -> int turns remaining

@export var team: Team = Team.ALLY
@export var footprint_size: Vector2i = Vector2i(1, 1)

@export var move_range: int = 3
@export var attack_range: int = 3
@export var attack_damage: int = 1

@export var tnt_throw_range: int = 0

@export var max_hp: int = 3
@export var hp: int = 3

var cell: Vector2i = Vector2i.ZERO

@export var z_base: int = 1
@export var z_per_cell: int = 1

@export var sprite_path: NodePath = NodePath("Sprite2D")
@onready var spr: Sprite2D = get_node_or_null(sprite_path) as Sprite2D

var _dying := false

func _ready() -> void:
	hp = clamp(hp, 0, max_hp)
	_update_depth()

func set_cell(c: Vector2i, terrain: TileMap) -> void:
	cell = c
	if terrain and is_instance_valid(terrain):
		global_position = terrain.to_global(terrain.map_to_local(c))
	_update_depth()

func _update_depth() -> void:
	z_as_relative = false
	z_index = 1 + (cell.x + cell.y) * z_per_cell

func set_selected(on: bool) -> void:
	if spr:
		spr.modulate = (Color(1, 1, 1) if not on else Color(1.25, 1.25, 1.25))

func take_damage(dmg: int) -> void:
	if _dying:
		return

	hp = max(hp - dmg, 0)

	if hp <= 0:
		_die()

func can_use_special(id: String) -> bool:
	return int(special_cd.get(id, 0)) <= 0


func mark_special_used(id: String, cd_turns: int = 1) -> void:
	special_cd[id] = max(0, cd_turns)


func tick_special_cooldowns() -> void:
	for k in special_cd.keys():
		special_cd[k] = max(0, int(special_cd[k]) - 1)

func await_die() -> void:
	# If already dying, just wait until freed (best-effort)
	if _dying:
		var t := 0.0
		while is_instance_valid(self) and t < 2.0:
			await get_tree().process_frame
			t += get_process_delta_time()
		return

	# If not dying yet, force death (plays anim) then wait for free
	hp = 0
	_die()

	var tt := 0.0
	while is_instance_valid(self) and tt < 2.0:
		await get_tree().process_frame
		tt += get_process_delta_time()

func _die() -> void:
	if _dying:
		return
	_dying = true

	# Prefer unit-specific death behavior if you add it later.
	# IMPORTANT: your custom play_death_anim should NOT queue_free immediately,
	# it should play, then queue_free at the end (or emit a signal).
	if has_method("play_death_anim"):
		call("play_death_anim")
		return

	var a := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if a != null and a.sprite_frames != null and a.sprite_frames.has_animation("death"):
		# ✅ make sure it won't loop (looping death never "finishes")
		a.sprite_frames.set_animation_loop("death", false)

		# (optional) stop whatever was playing
		a.stop()

		# ✅ play + await finish
		a.play("death")
		await a.animation_finished

		queue_free()
		return

	# Last resort: fade + shrink
	await _play_death_anim_fallback()
	queue_free()

func _play_death_anim_fallback() -> void:
	var ci: CanvasItem = null

	if spr != null:
		ci = spr
	else:
		# grab any CanvasItem child (Sprite2D, AnimatedSprite2D, etc.)
		for ch in get_children():
			if ch is CanvasItem:
				ci = ch as CanvasItem
				break

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD)
	tw.set_ease(Tween.EASE_OUT)

	# Fade (if we found a CanvasItem)
	if ci != null:
		var m := ci.modulate
		tw.tween_property(ci, "modulate", Color(m.r, m.g, m.b, 0.0), 0.18)

	# Shrink the node slightly
	tw.parallel().tween_property(self, "scale", scale * 0.85, 0.18)

	await tw.finished

func get_special_range(id: String) -> int:
	return 0
