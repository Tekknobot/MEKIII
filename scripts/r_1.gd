extends Unit
class_name R1
# Evangelion-style ranged mech
# Base: ranged attack
# Special: NINEFOLD VOLLEY — fires 9 projectiles into a 3x3 area centered on a target cell

# -------------------------
# Visual / identity
# -------------------------
@export var portrait_tex: Texture2D = preload("res://sprites/Portraits/dog_port.png") # swap to EVA/mecha portrait
@export var display_name := "R1 Evangelion"
@export var thumbnail: Texture2D
@export var special: String = "VOLLEY"
@export var special_desc: String = "Fires projectiles causing splash damage within range."


@export var attack_anim_name: StringName = &"attack"

# -------------------------
# Base stats
# -------------------------
@export var base_move_range := 5
@export var base_attack_range := 6   # ranged basic
@export var base_max_hp := 7

# -------------------------
# Basic ranged tuning (optional)
# -------------------------
@export var basic_ranged_damage := 2

# -------------------------
# Special: NINEFOLD VOLLEY
# - pick a target destination cell within volley_range (Manhattan)
# - fires 9 projectiles (3x3) centered on that cell
# - each projectile travels from shooter -> its tile and deals damage on arrival
# -------------------------
@export var volley_range := 6
@export var volley_damage := 2
@export var volley_cooldown := 4

@export var projectile_scene: PackedScene                 # <-- assign: res://fx/R1Projectile.tscn (Node2D recommended)
@export var projectile_travel_time := 0.22                # seconds per shot
@export var projectile_stagger := 0.04                    # delay between each of the 9 shots
@export var impact_sfx_id: StringName = &"volley_hit"      # if MapController has _sfx(...)
@export var fire_sfx_id: StringName = &"volley_fire"

# If true: skip tiles that are structure-blocked (so you don’t waste shots into buildings)
@export var skip_structure_blocked_tiles := false

@export var explosion_fx_scene: PackedScene = null   # optional: assign an explosion scene if you want
@export var splash_radius := 1                       # 1 = 3x3 splash around impact
@export var splash_damage_falloff := false           # if true: center full, ring reduced
@export var splash_ring_damage := 1                  # used only if falloff=true
@export var hit_structures_too := false              # if you want structures to be damaged by splash

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
	return ["Volley"]

func can_use_special(id: String) -> bool:
	id = id.to_lower()
	if id != "volley":
		return false
	return int(special_cd.get(id, 0)) <= 0

func get_special_range(id: String) -> int:
	id = id.to_lower()
	if id == "volley":
		return volley_range
	return 0

# -------------------------------------------------------
# Basic ranged attack hook (optional; call from your Unit attack flow)
# If your base Unit already handles attack/damage, you can ignore this.
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
# Special: NINEFOLD VOLLEY (AUTO)
# - Fires at all enemy targets in range (closest first)
# - Caps at 9 shots by default (keeps "Ninefold" meaning)
# -------------------------------------------------------
func perform_volley(M: MapController, _target_cell: Vector2i) -> void:
	var id_key := "volley"
	if not can_use_special(id_key):
		return
	if M == null:
		return
	if volley_range <= 0:
		return

	# Optional: structure blocked lookup
	var structure_blocked := _get_structure_blocked(M)

	# Build list of enemy target cells within range
	var target_cells: Array[Vector2i] = _get_enemy_cells_in_range(M, volley_range)

	# Optionally skip structure-blocked destinations
	if skip_structure_blocked_tiles and structure_blocked.size() > 0:
		var filtered: Array[Vector2i] = []
		for c in target_cells:
			if not _cell_blocked(structure_blocked, c):
				filtered.append(c)
		target_cells = filtered

	# Nothing to shoot -> don't consume cooldown
	if target_cells.is_empty():
		return

	# Keep the "Ninefold" identity: max 9 shots
	var max_shots := 9
	if target_cells.size() > max_shots:
		target_cells.resize(max_shots)

	# SFX at start
	_sfx_at_cell(M, fire_sfx_id, cell)

	# Fire at each target cell (closest first)
	for c in target_cells:
		if not _cell_in_bounds(M, c):
			continue

		# Face shot destination
		_face_unit_toward_cell_world(M, c)

		# Stagger for burst feel
		if projectile_stagger > 0.0:
			await get_tree().create_timer(projectile_stagger).timeout

		await _fire_projectile_to_cell_with_explosion(M, c)

	# ✅ go back to idle after volley finishes
	var spr := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if spr == null:
		spr = get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D
	if spr != null:
		spr.play("idle") # change if your idle anim name differs
		
	# Cooldown once at end
	mark_special_used(id_key, volley_cooldown)


# Collect enemy cells within Manhattan range, sorted closest-first
func _get_enemy_cells_in_range(M: MapController, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []

	# Fast path if you already store units by cell
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

	# Sort closest first
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da = abs(a.x - cell.x) + abs(a.y - cell.y)
		var db = abs(b.x - cell.x) + abs(b.y - cell.y)
		if da == db:
			# stable-ish tie-breaker so it doesn't feel random
			if a.x == b.x:
				return a.y < b.y
			return a.x < b.x
		return da < db
	)

	return out

# -------------------------------------------------------
# Projectile firing
# - Spawns projectile_scene (Node2D recommended) and tweens it to the cell.
# - On impact, damages unit there and (optionally) a structure if your Game has a method.
# -------------------------------------------------------
func _fire_projectile_to_cell_with_explosion(M: MapController, dest_cell: Vector2i) -> void:
	# compute world positions
	var start_pos := _cell_to_global(M, cell)
	var end_pos := _cell_to_global(M, dest_cell)
	
	start_pos.y -= 16
	end_pos.y -= 16
	
	# play an attack anim per shot (optional)
	_play_attack_anim_once()

	# spawn projectile
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

	# travel (tween fallback)
	if proj != null and proj is Node2D:
		var tw := create_tween()
		tw.tween_property(proj, "global_position", end_pos, max(projectile_travel_time, 0.01))
		await tw.finished
	else:
		await get_tree().create_timer(max(projectile_travel_time, 0.01)).timeout

	# cleanup projectile
	if proj != null and is_instance_valid(proj):
		proj.queue_free()

	# impact sfx
	_sfx_at_cell(M, impact_sfx_id, dest_cell)

	# ✅ explosion FX at impact
	_spawn_explosion_fx(M, dest_cell)

	# ✅ splash damage at impact
	_apply_splash_damage(M, dest_cell)


func _apply_splash_damage(M: MapController, center_cell: Vector2i) -> void:
	if splash_radius <= 0:
		# treat as single-tile
		_damage_enemy_on_cell(M, center_cell, volley_damage)
		_damage_structure_on_cell_if_enabled(M, center_cell, volley_damage)
		return

	# square splash (radius 1 => 3x3)
	for ox in range(-splash_radius, splash_radius + 1):
		for oy in range(-splash_radius, splash_radius + 1):
			var c := center_cell + Vector2i(ox, oy)
			if not _cell_in_bounds(M, c):
				continue

			var dmg := volley_damage
			if splash_damage_falloff:
				if ox != 0 or oy != 0:
					dmg = splash_ring_damage

			if dmg <= 0:
				continue

			_damage_enemy_on_cell(M, c, dmg)
			_damage_structure_on_cell_if_enabled(M, c, dmg)


func _damage_enemy_on_cell(M: MapController, c: Vector2i, dmg: int) -> void:
	var u := M.unit_at_cell(c)
	if u != null and is_instance_valid(u) and u.team != team:
		_apply_damage_safely(u, dmg)


func _damage_structure_on_cell_if_enabled(M: MapController, c: Vector2i, dmg: int) -> void:
	if not hit_structures_too:
		return
	if M == null or M.game_ref == null:
		return

	# you already support these optional structure hooks
	if M.game_ref.has_method("damage_structure_at"):
		M.game_ref.call("damage_structure_at", c, dmg, self)
	elif M.game_ref.has_method("apply_structure_damage_at"):
		M.game_ref.call("apply_structure_damage_at", c, dmg, self)


func _spawn_explosion_fx(M: MapController, c: Vector2i) -> void:
	# Prefer your existing spawner if you have one (like your M1)
	if M != null:
		if M.has_method("spawn_explosion_at_cell"):
			M.call("spawn_explosion_at_cell", c)
			return
		if M.has_method("_spawn_explosion_at_cell"):
			M.call("_spawn_explosion_at_cell", c)
			return

	# Otherwise, use an assigned explosion scene (optional)
	if explosion_fx_scene != null and M != null:
		var fx := explosion_fx_scene.instantiate()
		M.add_child(fx)
		if fx is Node2D:
			(fx as Node2D).global_position = _cell_to_global(M, c)


func _face_unit_toward_cell_world(M: MapController, c: Vector2i) -> void:
	# If your MapController has the nicer world-facing helper, use it.
	if M != null and M.has_method("_face_unit_toward_world") and M.terrain != null:
		var local_pos := M.terrain.map_to_local(c)
		var world_pos := M.terrain.to_global(local_pos)
		M.call("_face_unit_toward_world", self, world_pos)
		return

	# Fallback to your usual left/right flip (still works)
	_face_toward_cell(c)

# -------------------------
# Helpers
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
