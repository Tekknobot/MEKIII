extends Unit
class_name RecruitBot

# -------------------------
# Visual / identity
# -------------------------
@export var portrait_tex: Texture2D = preload("res://sprites/Portraits/dog_port.png")
@export var thumbnail: Texture2D
@export var specials: Array[String] = ["MORTAR", "ROCKET"]
@export var special_desc: String = "Mortar Strike: one delayed area blast.\nRocket Barrage: three targeted explosions."


@export var missile_range := 8
@export var missile_flight_time := 1.65
@export var missile_arc_height_px := 104.0
@export var missile_splash_radius := 1
@export var missile_damage := 2   # “hellfire-like”

# NEW
@export var max_shots_per_action := 8          # set 2–4 if you want it limited
@export var min_safe_distance := 2              # min Manhattan distance from any ALLY to target cell
@export var avoid_self_splash := true           # don’t target cells that splash-hit the bot

@export var shot_stagger := 0.3          # time between launches
@export var impact_time_factor := 0.0    # impact happens at flight_time * this

signal support_impacts_done
var _pending_impacts := 0

func auto_support_action(M: MapController) -> void:
	if M == null or not is_instance_valid(M) or M.grid == null:
		return

	var targets := _pick_all_safe_targets_in_range(M)
	if targets.is_empty():
		return

	var shots = min(int(max_shots_per_action), targets.size())

	_pending_impacts = 0

	for i in range(shots):
		var t := targets[i]
		if t == null or not is_instance_valid(t) or t.hp <= 0:
			continue

		var impact_cell := t.cell # capture now

		var tw := M.fire_support_missile_curve_async(
			cell,
			impact_cell,
			missile_flight_time,
			missile_arc_height_px,
			32
		)

		if tw != null and is_instance_valid(tw):
			_pending_impacts += 1
			# when THIS missile tween finishes, do THIS impact
			tw.finished.connect(Callable(self, "_on_support_missile_arrived").bind(M, impact_cell))

		if shot_stagger > 0.0:
			await get_tree().create_timer(shot_stagger).timeout

	# wait until all impacts have actually resolved
	if _pending_impacts > 0:
		await support_impacts_done

	if M != null and is_instance_valid(M):
		M._set_unit_attacked(self, true)

func _on_support_missile_arrived(M: MapController, impact_cell: Vector2i) -> void:
	# M might be gone / scene changed
	if M == null or not is_instance_valid(M):
		_pending_impacts = max(0, _pending_impacts - 1)
		if _pending_impacts == 0:
			emit_signal("support_impacts_done")
		return

	await M._apply_splash_damage(impact_cell, missile_splash_radius, missile_damage + attack_damage)
	M._apply_structure_splash_damage(impact_cell, missile_splash_radius, M.structure_hit_damage)
	M.spawn_explosion_at_cell(impact_cell)

	_pending_impacts = max(0, _pending_impacts - 1)
	if _pending_impacts == 0:
		emit_signal("support_impacts_done")

func _schedule_impact(M: MapController, impact_cell: Vector2i, delay: float) -> void:
	# fire-and-forget coroutine
	_impact_task(M, impact_cell, delay)


func _impact_task(M: MapController, impact_cell: Vector2i, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if M == null or not is_instance_valid(M):
		return

	await M._apply_splash_damage(impact_cell, missile_splash_radius, missile_damage + attack_damage)
	M._apply_structure_splash_damage(impact_cell, missile_splash_radius, M.structure_hit_damage)
	M.spawn_explosion_at_cell(impact_cell)
func _spawn_impact_task(M: MapController, impact_cell: Vector2i) -> void:
	# run in background (asynchronous without blocking caller)
	_impact_coroutine(M, impact_cell)


func _impact_coroutine(M: MapController, impact_cell: Vector2i) -> void:
	# wait until near-arrival time
	var t = max(0.01, missile_flight_time * impact_time_factor)
	await get_tree().create_timer(t).timeout

	# M might be gone between frames
	if M == null or not is_instance_valid(M):
		return

	# Impact damage (splash + structures + fx)
	await M._apply_splash_damage(impact_cell, missile_splash_radius, missile_damage + attack_damage)
	M._apply_structure_splash_damage(impact_cell, missile_splash_radius, M.structure_hit_damage)
	M.spawn_explosion_at_cell(impact_cell)

# ------------------------------------------------------------
# Targeting: "safe" means splash won't hit allies (or self)
# ------------------------------------------------------------
func _pick_all_safe_targets_in_range(M: MapController) -> Array[Unit]:
	var out: Array[Unit] = []
	var enemies := M.get_all_enemies()
	if enemies.is_empty():
		return out

	for e in enemies:
		if e == null or not is_instance_valid(e) or e.hp <= 0:
			continue

		var d = abs(e.cell.x - cell.x) + abs(e.cell.y - cell.y)
		if d > missile_range:
			continue

		# ✅ Don’t shoot if splash could hit allies (or self if enabled)
		if not _target_is_safe(M, e.cell):
			continue

		out.append(e)

	# Prioritize: closest first (or swap to lowest HP if you want)
	out.sort_custom(func(a: Unit, b: Unit) -> bool:
		var da = abs(a.cell.x - cell.x) + abs(a.cell.y - cell.y)
		var db = abs(b.cell.x - cell.x) + abs(b.cell.y - cell.y)
		return da < db
	)

	return out


func _target_is_safe(M: MapController, target_cell: Vector2i) -> bool:
	# If self splash is forbidden, ensure bot isn't in splash radius
	if avoid_self_splash:
		var ds = abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y)
		if ds <= missile_splash_radius:
			return false

	# Ensure no ally would be inside splash radius
	for u in M.get_all_units():
		if u == null or not is_instance_valid(u):
			continue
		if u.team != Unit.Team.ALLY:
			continue

		# Minimum safe distance rule (stronger than splash radius)
		var d = abs(target_cell.x - u.cell.x) + abs(target_cell.y - u.cell.y)
		if d <= int(min_safe_distance):
			return false

		# Also enforce splash radius explicitly (in case min_safe_distance is smaller)
		if d <= missile_splash_radius:
			return false

	return true
func _pick_best_enemy_target(M: MapController) -> Unit:
	var enemies := M.get_all_enemies()
	if enemies.is_empty():
		return null

	# simple: closest enemy
	var best := enemies[0]
	var best_d := 999999
	for e in enemies:
		var d = abs(e.cell.x - cell.x) + abs(e.cell.y - cell.y)
		if d < best_d and d <= missile_range:
			best_d = d
			best = e

	# if none in range, don’t shoot
	return best if best_d <= missile_range else null

func _pick_closest_enemy_any_range(M: MapController) -> Unit:
	var enemies := M.get_all_enemies()
	if enemies.is_empty():
		return null

	var best := enemies[0]
	var best_d := 999999
	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue
		var d = abs(e.cell.x - cell.x) + abs(e.cell.y - cell.y)
		if d < best_d:
			best_d = d
			best = e
	return best


func _pick_best_move_toward(M: MapController, target_cell: Vector2i) -> Vector2i:
	# Evaluate reachable cells, pick the one that minimizes distance to target.
	var cells := M.ai_reachable_cells(self)
	if cells.is_empty():
		return Vector2i(-1, -1)

	var best := cell
	var best_d := 999999

	for c in cells:
		# don’t consider standing still unless nothing else helps
		var d = abs(target_cell.x - c.x) + abs(target_cell.y - c.y)
		if d < best_d:
			best_d = d
			best = c

	return best

func play_death_anim() -> void:
	var M := get_tree().get_first_node_in_group("MapController")
	var fx_parent: Node = M if M != null else get_tree().current_scene

	var p := get_tile_world_pos() + death_fx_offset

	# ✅ explosion sound at the correct tile anchor
	if M != null and M.has_method("_sfx"):
		M.call("_sfx", &"explosion_small", 1.0, randf_range(0.95, 1.05), p)
	# or, if you already have a cue name for it:
	# M.call("_sfx", &"mech_explode", 1.0, randf_range(0.95, 1.05), p)

	var boom = preload("res://scenes/explosion.tscn").instantiate()
	fx_parent.add_child(boom)
	boom.global_position = p

	# Optional: keep it on same depth layer as the unit
	if boom is Node2D:
		boom.z_as_relative = false
		boom.z_index = z_index + 5

	# wait for boom to finish (adjust to your scene)
	if boom.has_signal("finished"):
		await boom.finished
	else:
		await get_tree().create_timer(0.6).timeout

	queue_free()


# ============================================================
# DEDICATED SPECIALS: DESTROYER AI / MECHTWO
# HUD IDs: mortar = Mortar Strike, rocket = Rocket Barrage.
# Warning/render lines descend from the sky.
# ============================================================
@export var mortar_range := 8
@export var mortar_damage := 3
@export var mortar_radius := 1
@export var mortar_warning_time := 0.35
@export var rocket_barrage_range := 8
@export var rocket_barrage_damage := 2
@export var rocket_barrage_stagger := 0.16
@export_range(1, 8, 1) var rocket_barrage_hits := 8
@export var special_sky_height := 300.0
@export var special_sky_angle_x := 165.0

func get_available_specials() -> Array[String]:
	return ["MORTAR", "ROCKET"]

func get_special_range(id: String) -> int:
	var sid := id.to_lower().replace(" ", "_")
	if sid == "mortar":
		return mortar_range
	if sid == "rocket":
		return rocket_barrage_range
	return 0

func can_use_special(_id: String) -> bool:
	return hp > 0 and not _dying

func perform_mortar(M: MapController, target_cell: Vector2i) -> void:
	if M == null or not is_instance_valid(M) or not can_use_special("mortar"):
		return
	if M.grid == null or not M.grid.in_bounds(target_cell):
		return
	if abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y) > mortar_range:
		return

	# The clicked tile only confirms the special. MORTAR strikes every living
	# enemy currently inside the Destroyer's Manhattan range.
	var targets: Array[Unit] = []
	for enemy in M.get_all_enemies():
		if enemy == null or not is_instance_valid(enemy) or enemy.hp <= 0:
			continue
		var distance: int = abs(enemy.cell.x - cell.x) + abs(enemy.cell.y - cell.y)
		if distance <= mortar_range:
			targets.append(enemy)

	if targets.is_empty():
		return

	var lines: Array[Line2D] = []
	for enemy in targets:
		lines.append(_destroyer_sky_line(
			M,
			enemy.cell,
			Color(1.0, 0.12, 0.06, 0.82),
			1.0
		))

	await get_tree().create_timer(mortar_warning_time).timeout
	for line in lines:
		if line != null and is_instance_valid(line):
			line.queue_free()

	if M == null or not is_instance_valid(M):
		return

	# Resolve one centered laser hit per target. Radius zero prevents one target
	# from being damaged repeatedly by overlapping mortar splashes.
	for enemy in targets:
		if enemy == null or not is_instance_valid(enemy) or enemy.hp <= 0:
			continue
		var hit_cell: Vector2i = enemy.cell
		M.spawn_explosion_at_cell(hit_cell)
		await M._apply_splash_damage(hit_cell, 0, mortar_damage + attack_damage)
		if M.has_method("_apply_structure_splash_damage"):
			M.call("_apply_structure_splash_damage", hit_cell, 0, 1)

func perform_rocket(M: MapController, target_cell: Vector2i) -> void:
	if M == null or not is_instance_valid(M) or not can_use_special("rocket"):
		return
	if M.grid == null or not M.grid.in_bounds(target_cell):
		return
	if abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y) > rocket_barrage_range:
		return

	var cells: Array[Vector2i] = []
	var candidates: Array[Vector2i] = [
		target_cell,
		target_cell + Vector2i(1, 0), target_cell + Vector2i(-1, 0),
		target_cell + Vector2i(0, 1), target_cell + Vector2i(0, -1),
		target_cell + Vector2i(1, 1), target_cell + Vector2i(-1, 1),
		target_cell + Vector2i(1, -1), target_cell + Vector2i(-1, -1)
	]
	for c in candidates:
		if cells.size() >= rocket_barrage_hits:
			break
		if M.grid.in_bounds(c):
			cells.append(c)

	for c in cells:
		var line := _destroyer_sky_line(M, c, Color(1.0, 0.42, 0.05, 0.8), 2.0)
		await get_tree().create_timer(0.18).timeout
		if line != null and is_instance_valid(line):
			line.queue_free()
		M.spawn_explosion_at_cell(c)
		await M._apply_splash_damage(c, 0, rocket_barrage_damage + attack_damage)
		if M.has_method("_apply_structure_splash_damage"):
			M.call("_apply_structure_splash_damage", c, 0, 1)
		await get_tree().create_timer(rocket_barrage_stagger).timeout

func _destroyer_sky_line(M: MapController, to_cell: Vector2i, color: Color, width: float) -> Line2D:
	var impact: Vector2 = M._cell_target_world(to_cell)
	var side := -1.0 if ((to_cell.x + to_cell.y) % 2 == 0) else 1.0
	var sky: Vector2 = impact + Vector2(special_sky_angle_x * side, -special_sky_height)
	var line := Line2D.new()
	line.width = 1.0
	line.default_color = color
	line.antialiased = false
	line.z_index = 5000
	line.add_point(sky)
	line.add_point(impact)
	M.add_child(line)
	if M.has_method("_sfx"):
		M.call("_sfx", &"sat_laser")
	return line

func _destroyer_target_marker(M: MapController, at_cell: Vector2i, color: Color) -> Node2D:
	var root := Node2D.new()
	root.global_position = M._cell_target_world(at_cell)
	root.z_index = 5000
	var a := Line2D.new()
	a.width = 1.0
	a.default_color = color
	a.add_point(Vector2(-12, -12))
	a.add_point(Vector2(12, 12))
	root.add_child(a)
	var b := Line2D.new()
	b.width = 1.0
	b.default_color = color
	b.add_point(Vector2(-12, 12))
	b.add_point(Vector2(12, -12))
	root.add_child(b)
	M.add_child(root)
	return root
