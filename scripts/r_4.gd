extends Unit
class_name R4
# ED-209 Heavy Enforcement Mech
# Special 1: MALFUNCTION - Spiraling explosion pattern radiating outward (unstable!)
# Special 2: SUPPRESS - Fire projectiles at multiple targets with explosive impacts

# -------------------------
# Visual / identity
# -------------------------
@export var portrait_tex: Texture2D = preload("res://sprites/Portraits/dog_port.png") # swap to ED-209 portrait
@export var thumbnail: Texture2D
@export var specials: Array[String] = ["MALFUNCTION", "STORM"]
@export var special_desc: String = "Unleash chaotic spiral explosions, or rain down explosive ordinance."

@export var attack_anim_name: StringName = &"attack"
@export var idle_anim_name: StringName = &"idle"

# -------------------------
# Base stats
# -------------------------
@export var base_move_range := 3
@export var base_attack_range := 6
@export var base_max_hp := 10
@export var basic_ranged_damage := 3

# -------------------------
# Special 1: MALFUNCTION tuning
# -------------------------
@export var malfunction_max_radius := 4
@export var malfunction_damage := 2
@export var malfunction_cooldown := 7
@export var malfunction_min_safe_dist := 2
@export var malfunction_self_damage := 1  # ED-209 hurts itself during malfunction!

# Spiral timing
@export var malfunction_ring_delay := 0.12  # delay between each ring
@export var malfunction_explosion_stagger := 0.04  # delay between explosions in same ring
@export var malfunction_warning_time := 0.5  # warning before explosions start

# VFX / SFX
@export var malfunction_warning_sfx_id: StringName = &"malfunction_warning"
@export var malfunction_explosion_sfx_id: StringName = &"explosion_small"

# -------------------------
# Special 2: STORM tuning
# -------------------------
@export var storm_range := 8
@export var storm_max_targets := 6
@export var storm_damage := 2
@export var storm_splash_radius := 1
@export var storm_cooldown := 5
@export var storm_min_safe_dist := 2

# Projectile properties
@export var storm_projectile_speed := 400.0
@export var storm_fire_stagger := 0.08  # delay between shots
@export var storm_muzzle_flash_duration := 0.1

# Safety settings
@export var storm_avoid_allies := true

# VFX / SFX
@export var storm_fire_sfx_id: StringName = &"autocannon_fire"
@export var storm_impact_sfx_id: StringName = &"explosion_small"

# Projectile scene
@export var projectile_scene: PackedScene
@export var iso_feet_offset_y := 16.0

signal storm_complete

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
	return specials

func can_use_special(id: String) -> bool:
	id = id.to_lower()
	if id == "malfunction":
		return int(special_cd.get("malfunction", 0)) <= 0
	elif id == "storm":
		return int(special_cd.get("storm", 0)) <= 0
	return false

func get_special_range(id: String) -> int:
	id = id.to_lower()
	if id == "malfunction":
		return malfunction_max_radius
	elif id == "storm":
		return storm_range
	return 0

func get_special_min_distance(id: String) -> int:
	id = id.to_lower()
	if id == "malfunction":
		return malfunction_min_safe_dist
	elif id == "storm":
		return storm_min_safe_dist
	return 0

# -------------------------------------------------------
# Basic attack (heavy autocannon)
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

	# Fire projectile if scene is available
	if projectile_scene != null:
		await _fire_projectile(M, cell, target_cell)
	else:
		# Fallback to instant hit
		await get_tree().create_timer(0.3).timeout

	if is_instance_valid(tgt):
		_apply_damage_safely(tgt, basic_ranged_damage)
		M.spawn_explosion_at_cell(target_cell)
		_sfx_at_cell(M, &"explosion_small", target_cell)

	_play_idle_anim()

# -------------------------------------------------------
# Special 1: MALFUNCTION
# Spiraling explosion pattern radiating outward
# -------------------------------------------------------
func perform_malfunction(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
		return
	if not _alive():
		return

	var id_key := "malfunction"
	if int(special_cd.get(id_key, 0)) > 0:
		return

	# Target cell must be within range from the mech
	var d = abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y)
	if d > malfunction_max_radius:
		return

	_play_attack_anim_once()

	# Warning sound and brief delay (ED-209 style malfunction warning)
	_sfx_at_cell(M, malfunction_warning_sfx_id, cell)
	await get_tree().create_timer(malfunction_warning_time).timeout

	if not _alive():
		return

	# Build spiral pattern centered on the mech itself
	var spiral_cells := _get_spiral_pattern(M, cell, malfunction_max_radius)

	# Execute spiral explosion pattern
	for ring_cells in spiral_cells:
		if not _alive():
			break

		# Shuffle cells in this ring for chaotic effect
		ring_cells.shuffle()

		for c in ring_cells:
			if not _alive():
				break

			# Skip cells too close (minimum safe distance from ANY ally)
			if not _malfunction_cell_is_safe(M, c):
				continue

			# Spawn explosion
			M.spawn_explosion_at_cell(c)
			_sfx_at_cell(M, malfunction_explosion_sfx_id, c)

			# Apply damage to units at this cell
			var tgt := M.unit_at_cell(c)
			if tgt != null and is_instance_valid(tgt):
				if "team" in tgt and tgt.team != team:
					if M.has_method("_flash_unit_white"):
						M.call("_flash_unit_white", tgt, 0.10)
					_apply_damage_safely(tgt, malfunction_damage + attack_damage)

			# Stagger explosions within ring
			if malfunction_explosion_stagger > 0.0:
				await get_tree().create_timer(malfunction_explosion_stagger).timeout

		# Delay before next ring
		if malfunction_ring_delay > 0.0:
			await get_tree().create_timer(malfunction_ring_delay).timeout

	# ED-209 takes self-damage from malfunction
	if malfunction_self_damage > 0 and _alive():
		_apply_damage_safely(self, malfunction_self_damage)
		if M.has_method("_flash_unit_white"):
			M.call("_flash_unit_white", self, 0.15)

	_play_idle_anim()
	special_cd[id_key] = malfunction_cooldown

func _get_spiral_pattern(M: MapController, center: Vector2i, max_radius: int) -> Array:
	var rings := []
	
	# Build rings from radius 1 to max_radius
	for r in range(1, max_radius + 1):
		var ring_cells: Array[Vector2i] = []
		
		# Get all cells at exactly distance r (Manhattan distance)
		for ox in range(-r, r + 1):
			for oy in range(-r, r + 1):
				var dist = abs(ox) + abs(oy)
				if dist != r:
					continue
				
				var c := center + Vector2i(ox, oy)
				if _cell_in_bounds(M, c):
					ring_cells.append(c)
		
		if not ring_cells.is_empty():
			rings.append(ring_cells)
	
	return rings

func _malfunction_cell_is_safe(M: MapController, target_cell: Vector2i) -> bool:
	# Check minimum safe distance from ALL allies (including self)
	for u in M.get_all_units():
		if u == null or not is_instance_valid(u):
			continue
		if u.team != Unit.Team.ALLY:
			continue

		var d = abs(target_cell.x - u.cell.x) + abs(target_cell.y - u.cell.y)
		if d < malfunction_min_safe_dist:
			return false

	return true

# -------------------------------------------------------
# Special 2: STORM
# Rain down explosive projectiles on multiple targets
# -------------------------------------------------------
func perform_storm(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
		return
	if not _alive():
		return

	var id_key := "storm"
	if int(special_cd.get(id_key, 0)) > 0:
		return

	var d = abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y)
	if d < storm_min_safe_dist or d > storm_range:
		return

	_face_toward_cell(target_cell)

	# Find all valid targets
	var targets := _find_storm_targets(M)
	if targets.is_empty():
		_play_idle_anim()
		return

	var shots = min(storm_max_targets, targets.size())
	var pending_impacts := 0

	# Fire at each target
	for i in range(shots):
		if not _alive():
			break

		var impact_cell: Vector2i = targets[i].cell

		_play_attack_anim_once()
		_sfx_at_cell(M, storm_fire_sfx_id, cell)

		# Fire projectile
		if projectile_scene != null:
			pending_impacts += 1
			_fire_storm_projectile(M, cell, impact_cell, pending_impacts)
		else:
			# Fallback: instant impact
			await get_tree().create_timer(0.3).timeout
			_on_storm_impact(M, impact_cell)

		# Stagger shots
		if i < shots - 1 and storm_fire_stagger > 0.0:
			await get_tree().create_timer(storm_fire_stagger).timeout

	# Wait for all projectiles to impact (if using projectiles)
	if pending_impacts > 0:
		await storm_complete

	_play_idle_anim()
	special_cd[id_key] = storm_cooldown

func _fire_storm_projectile(M: MapController, from_cell: Vector2i, to_cell: Vector2i, impact_id: int) -> void:
	var proj := projectile_scene.instantiate()
	if proj == null:
		_on_storm_impact(M, to_cell)
		return

	var from_pos := _cell_to_global(M, from_cell)
	from_pos.y -= iso_feet_offset_y

	var to_pos := _cell_to_global(M, to_cell)
	to_pos.y -= iso_feet_offset_y

	if proj is Node2D:
		proj.global_position = from_pos
		proj.z_index = 999

	M.add_child(proj)

	# Animate projectile to target
	var distance := from_pos.distance_to(to_pos)
	var duration := distance / storm_projectile_speed

	var tween := create_tween()
	tween.tween_property(proj, "global_position", to_pos, duration)
	tween.finished.connect(func():
		if is_instance_valid(proj):
			proj.queue_free()
		_on_storm_impact(M, to_cell)
	)

func _on_storm_impact(M: MapController, impact_cell: Vector2i) -> void:
	if M == null or not is_instance_valid(M):
		return

	# Explosion and sound
	M.spawn_explosion_at_cell(impact_cell)
	_sfx_at_cell(M, storm_impact_sfx_id, impact_cell)

	# Splash damage
	await M._apply_splash_damage(
		impact_cell,
		storm_splash_radius,
		storm_damage + attack_damage
	)

	# Structure damage
	if M.has_method("_apply_structure_splash_damage"):
		M.call("_apply_structure_splash_damage", impact_cell, storm_splash_radius, 1)

	emit_signal("storm_complete")

func _find_storm_targets(M: MapController) -> Array[Unit]:
	var out: Array[Unit] = []
	var enemies := M.get_all_enemies()
	if enemies.is_empty():
		return out

	for e in enemies:
		if e == null or not is_instance_valid(e) or e.hp <= 0:
			continue

		var d = abs(e.cell.x - cell.x) + abs(e.cell.y - cell.y)
		if d > storm_range or d < storm_min_safe_dist:
			continue

		# Safety check: don't hit allies with splash
		if storm_avoid_allies and not _storm_target_is_safe(M, e.cell):
			continue

		out.append(e)

	# Sort by distance (closest first)
	out.sort_custom(func(a: Unit, b: Unit) -> bool:
		var da = abs(a.cell.x - cell.x) + abs(a.cell.y - cell.y)
		var db = abs(b.cell.x - cell.x) + abs(b.cell.y - cell.y)
		return da < db
	)

	return out

func _storm_target_is_safe(M: MapController, target_cell: Vector2i) -> bool:
	# Check allies in splash radius
	for u in M.get_all_units():
		if u == null or not is_instance_valid(u):
			continue
		if u.team != Unit.Team.ALLY:
			continue

		var d = abs(target_cell.x - u.cell.x) + abs(target_cell.y - u.cell.y)
		if d <= storm_splash_radius:
			return false

	return true

func _fire_projectile(M: MapController, from_cell: Vector2i, to_cell: Vector2i) -> void:
	if projectile_scene == null:
		await get_tree().create_timer(0.3).timeout
		return

	var proj := projectile_scene.instantiate()
	if proj == null:
		return

	var from_pos := _cell_to_global(M, from_cell)
	from_pos.y -= iso_feet_offset_y

	var to_pos := _cell_to_global(M, to_cell)
	to_pos.y -= iso_feet_offset_y

	if proj is Node2D:
		proj.global_position = from_pos
		proj.z_index = 999

	M.add_child(proj)

	# Animate projectile
	var distance := from_pos.distance_to(to_pos)
	var duration := distance / 500.0

	var tween := create_tween()
	tween.tween_property(proj, "global_position", to_pos, duration)
	await tween.finished

	if is_instance_valid(proj):
		proj.queue_free()

# -------------------------
# Helpers
# -------------------------
func _cell_to_global(M: MapController, c: Vector2i) -> Vector2:
	if M != null and M.terrain != null:
		var map_local := M.terrain.map_to_local(c)
		return M.terrain.to_global(map_local)
	return Vector2(c.x * 32, c.y * 32)

func _cell_in_bounds(M: MapController, c: Vector2i) -> bool:
	if M.grid != null and M.grid.has_method("in_bounds"):
		return bool(M.grid.in_bounds(c))
	if M.grid != null and ("w" in M.grid) and ("h" in M.grid):
		return c.x >= 0 and c.y >= 0 and c.x < int(M.grid.w) and c.y < int(M.grid.h)
	return true

func _sfx_at_cell(M: MapController, sfx_id: StringName, c: Vector2i) -> void:
	if M == null or sfx_id == &"":
		return
	if M.has_method("_sfx"):
		M.call("_sfx", sfx_id, 1.0, randf_range(0.97, 1.03), _cell_to_global(M, c))

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
	var anim: AnimatedSprite2D = null
	var n := get_node_or_null("AnimatedSprite2D")
	if n is AnimatedSprite2D:
		anim = n
	else:
		n = get_node_or_null("Animate")
		if n is AnimatedSprite2D:
			anim = n

	if anim == null:
		return

	var M: MapController = null
	var maps := get_tree().get_nodes_in_group("MapController")
	if maps.size() > 0 and maps[0] is MapController:
		M = maps[0] as MapController

	if M == null:
		var root := get_tree().current_scene
		if root != null and ("map_controller" in root):
			M = root.map_controller as MapController

	if M == null:
		return

	var terrain: TileMap = null
	if "terrain" in M and M.terrain != null:
		terrain = M.terrain as TileMap
	else:
		var root := get_tree().current_scene
		if root != null and ("terrain" in root) and root.terrain != null:
			terrain = root.terrain as TileMap

	if terrain == null:
		return

	var my_pos := terrain.map_to_local(cell)
	var target_pos := terrain.map_to_local(target_cell)

	if target_pos.x > my_pos.x:
		anim.flip_h = true
	elif target_pos.x < my_pos.x:
		anim.flip_h = false

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

func _play_idle_anim() -> void:
	var sprA := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprA == null:
		sprA = get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D
	if sprA == null:
		return

	var anim := String(idle_anim_name)
	if sprA.sprite_frames == null:
		return
	if not sprA.sprite_frames.has_animation(anim):
		return

	sprA.play(anim)

func _alive() -> bool:
	return is_instance_valid(self) and (not ("_dying" in self and self._dying)) and hp > 0

func get_hud_extras() -> Dictionary:
	return {
		"Malfunction Radius": str(malfunction_max_radius),
		"Malfunction Damage": str(malfunction_damage + attack_damage),
		"Storm Range": str(storm_range),
		"Storm Targets": str(storm_max_targets),
		"Storm Damage": str(storm_damage + attack_damage),
	}
