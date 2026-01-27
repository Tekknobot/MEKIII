extends Unit
class_name M1

# -------------------------
# Visual / identity
# -------------------------
@export var portrait_tex: Texture2D = preload("res://sprites/Portraits/dog_port.png")
@export var display_name := "M1 Sunderer"
@export var thumbnail: Texture2D

# Optional: if your unit scene has an AnimationPlayer with an animation named "attack"
@export var attack_anim_name: StringName = &"attack"

# Optional: if you prefer spawning an FX scene instead of AnimationPlayer
@export var attack_fx_scene: PackedScene = null

# -------------------------
# Base stats
# -------------------------
@export var base_move_range := 5
@export var base_attack_range := 1
@export var base_max_hp := 6

# -------------------------
# ONLY SPECIAL: SUNDER
# - hits target tile, then continues "behind it" (same line) one by one
# - spawns explosion per tile
# - damages enemies on each tile
# - stops when out of bounds or blocked by structure_blocked
# -------------------------
@export var sunder_range := 5
@export var sunder_damage := 2
@export var sunder_cooldown := 3
@export var sunder_step_delay := 0.08

func _ready() -> void:
	set_meta("portrait_tex", portrait_tex)
	set_meta("display_name", display_name)

	footprint_size = Vector2i(1, 1)
	move_range = base_move_range
	attack_range = base_attack_range

	max_hp = max(max_hp, base_max_hp)
	hp = clamp(hp, 0, max_hp)

	print("M1 thumbnail = ", thumbnail, "  type=", typeof(thumbnail))

	super._ready()

# -------------------------
# Specials list (for UI)
# -------------------------
func get_available_specials() -> Array[String]:
	return ["Sunder"]

func can_use_special(id: String) -> bool:
	id = id.to_lower()
	if id != "sunder":
		return false
	if special_cd.has(id) and int(special_cd[id]) > 0:
		return false
	return true

func get_special_range(id: String) -> int:
	id = id.to_lower()
	if id == "sunder":
		return sunder_range
	return 0

# -------------------------------------------------------
# Special: SUNDER (line sweep behind target)
# -------------------------------------------------------
func perform_sunder(M: MapController, target_cell: Vector2i) -> void:
	if not can_use_special("sunder"):
		return
	if M == null:
		return

	# Must be in straight line (no diagonals)
	var dx := target_cell.x - cell.x
	var dy := target_cell.y - cell.y
	if dx != 0 and dy != 0:
		return

	var dist = abs(dx) + abs(dy)
	if dist <= 0 or dist > sunder_range:
		return

	if not _cell_in_bounds(M, target_cell):
		return

	# Direction from attacker -> target
	var dir := Vector2i.ZERO
	if dx != 0:
		dir.x = 1 if dx > 0 else -1
	else:
		dir.y = 1 if dy > 0 else -1

	_face_toward_cell(target_cell)
	_play_attack_fx(M, target_cell)

	# Optional: stop the sweep if it hits structure-blocked tiles
	var structure_blocked := _get_structure_blocked(M)

	# Start at target tile, then keep going "behind it"
	var c := target_cell
	while _cell_in_bounds(M, c) and not _cell_blocked(structure_blocked, c):

		# ✅ face the direction of THIS strike (cell -> world)
		if M != null and M.terrain != null:
			var local_pos: Vector2 = M.terrain.map_to_local(c)
			var world_pos: Vector2 = M.terrain.to_global(local_pos)
			M._face_unit_toward_world(self, world_pos)

		_play_attack_anim_once()
		_spawn_explosion(M, c)
		_damage_enemy_on_cell(M, c)

		await _wait_attack_anim()

		if sunder_step_delay > 0.0:
			await get_tree().create_timer(sunder_step_delay).timeout

		c += dir

	# ✅ go back to idle
	var spr := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if spr == null:
		spr = get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D
	if spr != null:
		spr.play("idle")
		
	mark_special_used("sunder", sunder_cooldown)

# -------------------------
# Helpers
# -------------------------

func _cell_in_bounds(M: MapController, c: Vector2i) -> bool:
	if M.grid != null and M.grid.has_method("in_bounds"):
		return bool(M.grid.in_bounds(c))
	if M.grid != null and ("w" in M.grid) and ("h" in M.grid):
		return c.x >= 0 and c.y >= 0 and c.x < int(M.grid.w) and c.y < int(M.grid.h)
	return true

func _get_structure_blocked(M: MapController) -> Dictionary:
	if M.game_ref != null and ("structure_blocked" in M.game_ref):
		return M.game_ref.structure_blocked
	return {}

func _cell_blocked(structure_blocked: Dictionary, c: Vector2i) -> bool:
	return structure_blocked.has(c) and bool(structure_blocked[c]) == true

func _spawn_explosion(M: MapController, c: Vector2i) -> void:
	# Prefer your existing explosion spawner if you have one
	if M.has_method("spawn_explosion_at_cell"):
		M.call("spawn_explosion_at_cell", c)
		return
	if M.has_method("_spawn_explosion_at_cell"):
		M.call("_spawn_explosion_at_cell", c)
		return

	# Fallback: just play a sound at that tile (optional)
	if M.has_method("_sfx"):
		var p = M.grid.cell_to_world(c)
		M.call("_sfx", &"explosion_small", 1.0, randf_range(0.95, 1.05), p)

func _damage_enemy_on_cell(M: MapController, c: Vector2i) -> void:
	var u := M.unit_at_cell(c)
	if u != null and u.team != team:
		_apply_damage_safely(u, sunder_damage)

func _apply_damage_safely(tgt: Object, dmg: int) -> void:
	if tgt == null:
		return

	# --- take_damage path ---
	if tgt.has_method("take_damage"):
		var m := tgt.get_method_list().filter(func(x): return x.name == "take_damage")
		if m.size() > 0 and m[0].args.size() >= 2:
			# method expects (damage, source)
			tgt.call("take_damage", dmg, self)
		else:
			# method expects (damage) only
			tgt.call("take_damage", dmg)
		return

	# --- apply_damage path ---
	if tgt.has_method("apply_damage"):
		var m2 := tgt.get_method_list().filter(func(x): return x.name == "apply_damage")
		if m2.size() > 0 and m2[0].args.size() >= 2:
			tgt.call("apply_damage", dmg, self)
		else:
			tgt.call("apply_damage", dmg)
		return

	# --- fallback raw hp ---
	if "hp" in tgt:
		tgt.hp -= dmg
		if tgt.hp <= 0:
			if tgt.has_method("die"):
				tgt.call("die")
			else:
				tgt.queue_free()

func _play_attack_fx(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
		return

	# --------- cell -> global position (via TileMap) ----------
	var global_pos := Vector2.ZERO
	if M.terrain != null:
		# TileMap local position for that cell (center-ish depending on tileset)
		var map_local := M.terrain.map_to_local(target_cell)
		# Convert to global so FX is correct no matter where the TileMap is
		global_pos = M.terrain.to_global(map_local)
	else:
		# fallback (won't crash)
		global_pos = Vector2(target_cell.x * 32, target_cell.y * 32)

	# SFX hook (optional)
	if M.has_method("_sfx"):
		M.call("_sfx", &"sunder", 1.0, randf_range(0.95, 1.05), global_pos)

	# Try AnimationPlayer first
	var ap := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		ap = get_node_or_null("Anim") as AnimationPlayer

	if ap != null and ap.has_animation(String(attack_anim_name)):
		ap.play(String(attack_anim_name))
		return

	# Otherwise spawn an FX scene
	if attack_fx_scene != null:
		var fx := attack_fx_scene.instantiate()
		var parent: Node = M
		parent.add_child(fx)

		if fx is Node2D:
			(fx as Node2D).global_position = global_pos

func _face_toward_cell(target_cell: Vector2i) -> void:
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	if spr == null:
		spr = get_node_or_null("Visual/Sprite2D") as Sprite2D
	if spr == null:
		return
	if target_cell.x < cell.x:
		spr.flip_h = true
	elif target_cell.x > cell.x:
		spr.flip_h = false

func _play_attack_anim_once() -> void:
	var spr := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if spr == null:
		spr = get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D
	if spr == null:
		return

	var anim := String(attack_anim_name)
	if spr.sprite_frames == null:
		return
	if not spr.sprite_frames.has_animation(anim):
		return

	spr.stop()
	spr.play(anim)


func _wait_attack_anim() -> void:
	var spr := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if spr == null:
		spr = get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D
	if spr == null:
		return

	var anim := String(attack_anim_name)
	if spr.sprite_frames == null:
		return
	if not spr.sprite_frames.has_animation(anim):
		return

	# Wait until this specific animation finishes
	await spr.animation_finished
