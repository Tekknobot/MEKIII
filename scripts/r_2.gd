extends Unit
class_name R2
# Heavy-cannon ranged mech
# Base: ranged attack
# Special: CANNON BARRAGE — fires a few heavy shells at enemies in range (closest first),
# each shell splashes in an area (bigger than R1 by default).

# -------------------------
# Visual / identity
# -------------------------
@export var portrait_tex: Texture2D = preload("res://sprites/Portraits/dog_port.png")
@export var thumbnail: Texture2D
@export var special: String = "CANNON"
@export var special_desc: String = "Three powerful slow moving projectiles that cause extensive splash damage."

@export var attack_anim_name: StringName = &"attack"

# -------------------------
# Base stats
# -------------------------
@export var base_move_range := 4
@export var base_attack_range := 7   # heavy cannon = long range
@export var base_max_hp := 8

# -------------------------
# Basic ranged tuning
# -------------------------
@export var basic_ranged_damage := 2

# -------------------------
# Special: CANNON BARRAGE
# - auto-targets all enemies in range (closest first)
# - fires up to cannon_shots shells
# - each shell deals cannon_damage at center + splash
# -------------------------
@export var cannon_range := 7
@export var cannon_damage := 3
@export var cannon_cooldown := 5
@export var cannon_shots := 3

@export var projectile_scene: PackedScene                 # assign: res://fx/R2Shell.tscn (Node2D recommended)
@export var projectile_travel_time := 0.28                # heavier = slightly slower than R1
@export var projectile_stagger := 0.10                    # chunky cadence
@export var impact_sfx_id: StringName = &"cannon_hit"
@export var fire_sfx_id: StringName = &"cannon_fire"

@export var skip_structure_blocked_tiles := false

@export var explosion_fx_scene: PackedScene = null
@export var splash_radius := 2                       # bigger boom than R1
@export var splash_damage_falloff := true            # center full, ring reduced
@export var splash_ring_damage := 1
@export var hit_structures_too := true               # cannon can smash buildings (toggle off if you want)

func _ready() -> void:
	set_meta("portrait_tex", portrait_tex)
	set_meta("display_name", display_name)

	footprint_size = Vector2i(1, 1)
	move_range = base_move_range
	attack_range = base_attack_range

	max_hp = max(max_hp, base_max_hp)
	hp = clamp(hp, 0, max_hp)

	super._ready()

# -------------------------
# Specials list (for UI)
# -------------------------
func get_available_specials() -> Array[String]:
	return ["Cannon"]

func can_use_special(id: String) -> bool:
	id = id.to_lower()
	if id != "cannon":
		return false
	# normalize key used in special_cd
	return int(special_cd.get("cannon", 0)) <= 0

func get_special_range(id: String) -> int:
	id = id.to_lower()
	if id == "cannon":
		return cannon_range
	return 0

# -------------------------------------------------------
# Basic ranged attack (optional)
# -------------------------------------------------------
func perform_basic_attack(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
		return
	if abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y) > attack_range:
		return
	var tgt := M.unit_at_cell(target_cell)
	if tgt == null:
		return
	_face_toward_cell(target_cell)
	_play_attack_anim_once()
	_apply_damage_safely(tgt, basic_ranged_damage)

# -------------------------------------------------------
# Special: CANNON BARRAGE (AUTO)
# - Fires heavy shells at up to cannon_shots enemies in range (closest first)
# -------------------------------------------------------
func perform_cannon(M: MapController, _target_cell: Vector2i) -> void:
	var id_key := "cannon"
	if int(special_cd.get(id_key, 0)) > 0:
		return
	if M == null:
		return
	if cannon_range <= 0 or cannon_shots <= 0:
		return

	var structure_blocked := _get_structure_blocked(M)

	var target_cells: Array[Vector2i] = _get_enemy_cells_in_range(M, cannon_range)

	if skip_structure_blocked_tiles and structure_blocked.size() > 0:
		var filtered: Array[Vector2i] = []
		for c in target_cells:
			if not _cell_blocked(structure_blocked, c):
				filtered.append(c)
		target_cells = filtered

	if target_cells.is_empty():
		return

	if target_cells.size() > cannon_shots:
		target_cells.resize(cannon_shots)

	_sfx_at_cell(M, fire_sfx_id, cell)

	for c in target_cells:
		if not _alive():
			return
		if M == null or not is_instance_valid(M):
			return

		if not _cell_in_bounds(M, c):
			continue

		_face_unit_toward_cell_world(M, c)

		if projectile_stagger > 0.0:
			await get_tree().create_timer(projectile_stagger).timeout
			if not _alive():
				return

		await _fire_projectile_to_cell_with_explosion(M, c)
		if not _alive():
			return


	# back to idle
	var spr := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if spr == null:
		spr = get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D
	if spr != null:
		spr.play("idle")

	if not _alive():
		return

	# cooldown once at end
	special_cd[id_key] = cannon_cooldown

# Collect enemy cells within Manhattan range, sorted closest-first
func _get_enemy_cells_in_range(M: MapController, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []

	for k in M.units_by_cell.keys():
		var c := k as Vector2i
		var u := M.unit_at_cell(c)
		if u == null or not is_instance_valid(u):
			continue
		if u.team == team:
			continue

		var d = abs(c.x - cell.x) + abs(c.y - cell.y)
		if d > 0 and d <= r:
			out.append(c)

	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da = abs(a.x - cell.x) + abs(a.y - cell.y)
		var db = abs(b.x - cell.x) + abs(b.y - cell.y)
		if da == db:
			if a.x == b.x:
				return a.y < b.y
			return a.x < b.x
		return da < db
	)

	return out

# -------------------------------------------------------
# Projectile firing
# -------------------------------------------------------
func _fire_projectile_to_cell_with_explosion(M: MapController, dest_cell: Vector2i) -> void:
	if M == null or not _alive():
		return
			
	var start_pos := _cell_to_global(M, cell)
	var end_pos := _cell_to_global(M, dest_cell)

	start_pos.y -= 16
	end_pos.y -= 16

	_play_attack_anim_once()

	var proj: Node = null
	if projectile_scene != null:
		proj = projectile_scene.instantiate()
		var parent: Node = M
		parent.add_child(proj)

		if proj is Node2D:
			(proj as Node2D).global_position = start_pos

		if proj.has_method("set_owner"):
			proj.call("set_owner", self)
		if proj.has_method("set_target_cell"):
			proj.call("set_target_cell", dest_cell)

	if proj != null and proj is Node2D:
		var tw := create_tween()
		tw.tween_property(proj, "global_position", end_pos, max(projectile_travel_time, 0.01))
		await tw.finished
	else:
		await get_tree().create_timer(max(projectile_travel_time, 0.01)).timeout

	if not _alive():
		if proj != null and is_instance_valid(proj):
			proj.queue_free()
		return

	if proj != null and is_instance_valid(proj):
		proj.queue_free()

	_sfx_at_cell(M, impact_sfx_id, dest_cell)

	if not _alive():
		return

	_spawn_explosion_fx(M, dest_cell)
	_apply_splash_damage(M, dest_cell)

func _apply_splash_damage(M: MapController, center_cell: Vector2i) -> void:
	# Center hit always uses cannon_damage
	_damage_enemy_on_cell(M, center_cell, cannon_damage)
	_damage_structure_on_cell_if_enabled(M, center_cell, cannon_damage)

	if splash_radius <= 0:
		return

	for ox in range(-splash_radius, splash_radius + 1):
		for oy in range(-splash_radius, splash_radius + 1):
			if ox == 0 and oy == 0:
				continue
			var c := center_cell + Vector2i(ox, oy)
			if not _cell_in_bounds(M, c):
				continue

			var dmg := cannon_damage
			if splash_damage_falloff:
				dmg = splash_ring_damage

			if dmg <= 0:
				continue

			_damage_enemy_on_cell(M, c, dmg)
			_damage_structure_on_cell_if_enabled(M, c, dmg)

func _damage_enemy_on_cell(M: MapController, c: Vector2i, dmg: int) -> void:
	if M == null:
		return
	var u := M.unit_at_cell(c)
	if u != null and is_instance_valid(u) and u.team != team:
		_apply_damage_safely(u, dmg)

func _damage_structure_on_cell_if_enabled(M: MapController, c: Vector2i, dmg: int) -> void:
	if not hit_structures_too:
		return
	if M == null or M.game_ref == null:
		return

	if M.game_ref.has_method("damage_structure_at"):
		M.game_ref.call("damage_structure_at", c, dmg, self)
	elif M.game_ref.has_method("apply_structure_damage_at"):
		M.game_ref.call("apply_structure_damage_at", c, dmg, self)

func _spawn_explosion_fx(M: MapController, c: Vector2i) -> void:
	if M != null:
		if M.has_method("spawn_explosion_at_cell"):
			M.call("spawn_explosion_at_cell", c)
			return
		if M.has_method("_spawn_explosion_at_cell"):
			M.call("_spawn_explosion_at_cell", c)
			return

	if explosion_fx_scene != null and M != null:
		var fx := explosion_fx_scene.instantiate()
		M.add_child(fx)
		if fx is Node2D:
			(fx as Node2D).global_position = _cell_to_global(M, c)

func _face_unit_toward_cell_world(M: MapController, c: Vector2i) -> void:
	if M != null and M.has_method("_face_unit_toward_world") and M.terrain != null:
		var local_pos := M.terrain.map_to_local(c)
		var world_pos := M.terrain.to_global(local_pos)
		M.call("_face_unit_toward_world", self, world_pos)
		return
	_face_toward_cell(c)

# -------------------------
# Helpers (copied pattern from R1)
# -------------------------
func _cell_to_global(M: MapController, c: Vector2i) -> Vector2:
	if M != null and M.terrain != null:
		var map_local := M.terrain.map_to_local(c)
		return M.terrain.to_global(map_local)
	return Vector2(c.x * 32, c.y * 32)

func _sfx_at_cell(M: MapController, sfx_id: StringName, c: Vector2i) -> void:
	if M == null:
		return
	if sfx_id == &"":
		return
	if M.has_method("_sfx"):
		M.call("_sfx", sfx_id, 1.0, randf_range(0.97, 1.03), _cell_to_global(M, c))

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

func _apply_damage_safely(tgt: Object, dmg: int) -> void:
	if tgt == null:
		return

	if tgt.has_method("take_damage"):
		var m := tgt.get_method_list().filter(func(x): return x.name == "take_damage")
		if m.size() > 0 and m[0].args.size() >= 2:
			tgt.call("take_damage", dmg, self)
		else:
			tgt.call("take_damage", dmg)
		return

	if tgt.has_method("apply_damage"):
		var m2 := tgt.get_method_list().filter(func(x): return x.name == "apply_damage")
		if m2.size() > 0 and m2[0].args.size() >= 2:
			tgt.call("apply_damage", dmg, self)
		else:
			tgt.call("apply_damage", dmg)
		return

	if "hp" in tgt:
		tgt.hp -= dmg
		if tgt.hp <= 0:
			if tgt.has_method("die"):
				tgt.call("die")
			else:
				tgt.queue_free()

func _face_toward_cell(target_cell: Vector2i) -> void:
	var spr2 := get_node_or_null("Sprite2D") as Sprite2D
	if spr2 == null:
		spr2 = get_node_or_null("Visual/Sprite2D") as Sprite2D
	if spr2 == null:
		return
	if target_cell.x < cell.x:
		spr2.flip_h = true
	elif target_cell.x > cell.x:
		spr2.flip_h = false

func _play_attack_anim_once() -> void:
	var sprA := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprA == null:
		sprA = get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D
	if sprA == null:
		return

	var anim := String(attack_anim_name)
	if sprA.sprite_frames == null:
		return
	if not sprA.sprite_frames.has_animation(anim):
		return

	sprA.stop()
	sprA.play(anim)

func _alive() -> bool:
	return is_instance_valid(self) and hp > 0 and (not ("_dying" in self and self._dying))
