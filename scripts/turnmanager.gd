extends Node
class_name TurnManager

signal battle_started
signal battle_ended(winner_team: int)

@export var map: NodePath              # drag Map node
@export var start_on_ready := true
@export var think_delay := 0.15

enum Mode { AUTO_BATTLE, ONE_PLAYER }
@export var mode: Mode = Mode.AUTO_BATTLE

var M

# For ONE_PLAYER mode
var current_side := Unit.Team.ALLY
var waiting_for_player_action := false

# TNT behavior
@export var human_tnt_throw_range := 8          # fallback if Unit doesn't have tnt_throw_range
@export var human_tnt_min_enemy_hits := 2       # only throw if it will hit at least this many enemies
@export var human_tnt_ally_avoid := true        # don't throw if it would hit any ally

# --- Anti-stall / teamwork tuning ---
@export var endgame_aggression_units_left := 3        # when total alive <= this, stop evasion loops
@export var low_hp_evade_min_enemies := 2             # only "evade" if there are at least this many enemies
@export var focus_fire_bonus := 120                   # bonus to move/attack toward team focus target
@export var protect_ally_bonus := 70                  # bonus for helping threatened ally
@export var protect_ally_low_hp_threshold := 0.40     # allies at/below this HP% get "protection"

# stores WeakRef or null
var team_focus_target := {
	Unit.Team.ALLY: null,
	Unit.Team.ENEMY: null
}

func _ready() -> void:
	M = get_node(map)
	if start_on_ready:
		await get_tree().process_frame
		start_battle()

func start_battle() -> void:
	emit_signal("battle_started")
	match mode:
		Mode.AUTO_BATTLE:
			_battle_loop_auto()
		Mode.ONE_PLAYER:
			_one_player_loop()

# ----------------------------
# AUTO BATTLE
# ----------------------------
func _battle_loop_auto() -> void:
	# AUTO mode: no player control
	if M.has_method("set_player_mode"):
		M.set_player_mode(false)

	# Alternate teams each action
	var side := Unit.Team.ALLY
	var ally_i := 0
	var enemy_i := 0

	while true:
		if _check_end():
			return

		# refresh lists each step (units can die / be freed)
		var allies: Array[Unit] = M.get_units(Unit.Team.ALLY)
		var enemies: Array[Unit] = M.get_units(Unit.Team.ENEMY)

		# If a side has no one, end check will catch it next loop,
		# but we can early-flip to avoid index errors.
		if side == Unit.Team.ALLY and allies.is_empty():
			side = Unit.Team.ENEMY
			ally_i = 0
			continue
		if side == Unit.Team.ENEMY and enemies.is_empty():
			side = Unit.Team.ALLY
			enemy_i = 0
			continue

		# Pick next unit on the current side (skip invalids safely)
		var u: Unit = null

		if side == Unit.Team.ALLY:
			if ally_i >= allies.size():
				ally_i = 0

			var tries := allies.size()
			while tries > 0:
				tries -= 1
				u = allies[ally_i]
				ally_i += 1
				if ally_i >= allies.size():
					ally_i = 0
				if u != null and is_instance_valid(u):
					break
				u = null
		else:
			if enemy_i >= enemies.size():
				enemy_i = 0

			var tries2 := enemies.size()
			while tries2 > 0:
				tries2 -= 1
				u = enemies[enemy_i]
				enemy_i += 1
				if enemy_i >= enemies.size():
					enemy_i = 0
				if u != null and is_instance_valid(u):
					break
				u = null

		# If we couldn't find a valid unit on that side (all freed), just flip and continue
		if u == null:
			side = (Unit.Team.ENEMY if side == Unit.Team.ALLY else Unit.Team.ALLY)
			await get_tree().process_frame
			continue

		# Take the action
		await _unit_take_ai_turn(u)
		await get_tree().create_timer(think_delay).timeout

		# Flip side after every single action
		side = (Unit.Team.ENEMY if side == Unit.Team.ALLY else Unit.Team.ALLY)

# ----------------------------
# ONE PLAYER (player = ALLY, AI = ENEMY)
# ----------------------------
func _one_player_loop() -> void:
	current_side = Unit.Team.ALLY
	waiting_for_player_action = true

	if M.has_method("set_player_mode"):
		M.set_player_mode(true)

	while true:
		if _check_end():
			return

		if current_side == Unit.Team.ALLY:
			waiting_for_player_action = true
			await _wait_for_player_action()
			current_side = Unit.Team.ENEMY

		if current_side == Unit.Team.ENEMY:
			var enemies = M.get_units(Unit.Team.ENEMY)
			for u in enemies:
				if u == null or not is_instance_valid(u):
					continue
				await _unit_take_ai_turn(u)
				await get_tree().create_timer(think_delay).timeout

			current_side = Unit.Team.ALLY

func notify_player_action_complete() -> void:
	# Map calls this after the player successfully moves OR attacks.
	waiting_for_player_action = false

func _wait_for_player_action() -> void:
	while waiting_for_player_action:
		await get_tree().process_frame

# ----------------------------
# Shared helpers
# ----------------------------
func _check_end() -> bool:
	var allies = M.get_units(Unit.Team.ALLY)
	var enemies = M.get_units(Unit.Team.ENEMY)

	if allies.is_empty():
		print("ZOMBIES WIN")
		emit_signal("battle_ended", Unit.Team.ENEMY)
		return true
	if enemies.is_empty():
		print("ALLIES WIN")
		emit_signal("battle_ended", Unit.Team.ALLY)
		return true
	return false

func _unit_take_ai_turn(u: Unit) -> void:
	# ✅ DROPS FIRST: deterministically go to nearest drop (if any)
	var drop_cell := _nearest_drop_cell_for(u)
	if drop_cell.x >= 0:
		var start_drop = M.get_unit_origin(u)
		if M._is_big_unit(u):
			start_drop = M.snap_origin_for_unit(start_drop, u)

		# If we're not already standing on it, move toward it and END TURN.
		if start_drop != drop_cell:
			var reachable_drop: Array[Vector2i] = M.compute_reachable_origins(u, start_drop, u.move_range)
			if not reachable_drop.is_empty():
				var best_drop := _best_move_tile_toward_cell(u, drop_cell, reachable_drop)
				if best_drop != start_drop:
					await M.perform_move(u, best_drop)
			return
	
	if u == null or not is_instance_valid(u):
		return
	if M == null:
		return

	# ✅ Humans (both types): try TNT first
	# IMPORTANT: Godot class name must match yours: Human2, HumanTwo, etc.
	# If your class is "Human2", change the check below to (u is Human2).
	if (u is Human) or (u is HumanTwo):
		var pick := _pick_best_tnt_target_for_thrower(u)
		if pick.size() > 0:
			var cell: Vector2i = pick["cell"]
			var target_u: Unit = M.unit_at_cell(cell) # can be null
			await M.perform_human_tnt_throw(u, cell, target_u)
			return

	# ✅ Smarter target selection
	var target: Unit = _best_enemy_target(u)
	if target == null or not is_instance_valid(target):
		return

	# 1) If already in range -> attack
	if M._attack_distance(u, target) <= int(u.attack_range):
		await M.perform_attack(u, target)
		return

	# 2) Otherwise move (smarter)
	var start = M.get_unit_origin(u)
	if M._is_big_unit(u):
		start = M.snap_origin_for_unit(start, u)

	var reachable: Array[Vector2i] = M.compute_reachable_origins(u, start, int(u.move_range))
	if reachable.is_empty():
		return

	var best: Vector2i = _best_move_tile_toward_target(u, target, reachable)

	if best != start:
		await M.perform_move(u, best)

	# 3) After moving, try attack again
	if not is_instance_valid(u):
		return
	if not is_instance_valid(target):
		target = _best_enemy_target(u)
		if target == null or not is_instance_valid(target):
			return

	if M._attack_distance(u, target) <= int(u.attack_range):
		await M.perform_attack(u, target)

# ----------------------------
# TNT picking
# ----------------------------
func _pick_best_tnt_target_for_thrower(h: Unit) -> Dictionary:
	if h == null or not is_instance_valid(h):
		return {}
	if M == null:
		return {}

	# Needs TNT setup on Map
	if M.tnt_projectile_scene == null or M.tnt_explosion_scene == null:
		return {}

	# ✅ range comes from unit if available, otherwise fallback export
	var max_throw := _tnt_range_for(h)
	if max_throw <= 0:
		return {}

	var h_origin = M.get_unit_origin(h)
	if M._is_big_unit(h):
		h_origin = M.snap_origin_for_unit(h_origin, h)

	# Collect units
	var enemies: Array[Unit] = []
	var allies: Array[Unit] = []
	for child in M.units_root.get_children():
		var u := child as Unit
		if u == null or not is_instance_valid(u):
			continue
		if u.team == h.team:
			allies.append(u)
		else:
			enemies.append(u)

	if enemies.is_empty():
		return {}

	# Candidate cells: enemy origins + their 4-neighbors
	var candidates := {}
	for e in enemies:
		var eo = M.get_unit_origin(e)
		if M._is_big_unit(e):
			eo = M.snap_origin_for_unit(eo, e)

		candidates[eo] = true
		for nb in M._neighbors4(eo):
			if M.grid.in_bounds(nb):
				candidates[nb] = true

	var best_cell := Vector2i(-1, -1)
	var best_enemy_hits := -1
	var best_ally_hits := 999999
	var best_throw_dist := 999999

	for cell in candidates.keys():
		if not M.grid.in_bounds(cell):
			continue

		# throw range (origin -> landing cell)
		var d_throw = abs(cell.x - h_origin.x) + abs(cell.y - h_origin.y)
		if d_throw > max_throw:
			continue

		var enemy_hits := _count_team_hits_in_splash(cell, enemies, int(M.tnt_splash_radius))
		if enemy_hits < human_tnt_min_enemy_hits:
			continue

		var ally_hits := _count_team_hits_in_splash(cell, allies, int(M.tnt_splash_radius))

		# avoid friendly fire if desired
		if human_tnt_ally_avoid and ally_hits > 0:
			continue

		var better := false
		if enemy_hits > best_enemy_hits:
			better = true
		elif enemy_hits == best_enemy_hits:
			if ally_hits < best_ally_hits:
				better = true
			elif ally_hits == best_ally_hits and d_throw < best_throw_dist:
				better = true

		if better:
			best_enemy_hits = enemy_hits
			best_ally_hits = ally_hits
			best_throw_dist = d_throw
			best_cell = cell

	if best_enemy_hits >= human_tnt_min_enemy_hits and best_cell.x >= 0:
		return {"cell": best_cell, "enemy_hits": best_enemy_hits}

	return {}

func _count_team_hits_in_splash(center: Vector2i, team_units: Array[Unit], radius: int) -> int:
	var hits := 0
	for u in team_units:
		if u == null or not is_instance_valid(u):
			continue

		var uc = M.get_unit_origin(u)
		if M._is_big_unit(u):
			uc = M.snap_origin_for_unit(uc, u)

		var d = abs(uc.x - center.x) + abs(uc.y - center.y)
		if d <= radius:
			hits += 1
	return hits

func _tnt_range_for(u: Unit) -> int:
	if u == null:
		return 0
	# If you added @export var tnt_throw_range on Unit, use it.
	# Otherwise fallback to TurnManager export.
	if "tnt_throw_range" in u:
		return int(u.tnt_throw_range)
	return int(human_tnt_throw_range)

# ----------------------------
# Targeting
# ----------------------------
func _is_low_hp(u: Unit) -> bool:
	if u == null:
		return false
	return int(u.hp) <= 1 or (int(u.max_hp) > 0 and float(u.hp) / float(u.max_hp) <= 0.34)

func _is_ranged(u: Unit) -> bool:
	return u != null and int(u.attack_range) >= 2

func _best_enemy_target(u: Unit) -> Unit:
	var enemies: Array[Unit] = M.get_units(Unit.Team.ENEMY if u.team == Unit.Team.ALLY else Unit.Team.ALLY)
	if enemies.is_empty():
		return null

	var best: Unit = null
	var best_score := -99999999

	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue

		var d = M._attack_distance(u, e)

		var hp_frac := 1.0
		if int(e.max_hp) > 0:
			hp_frac = float(e.hp) / float(e.max_hp)

		var score := 0
		score += int((10 - min(d, 10)) * 25)          # closeness
		score += int((1.0 - hp_frac) * 60.0)          # low hp bonus
		if d <= int(u.attack_range):
			score += 80                                # already in range
		if not M._is_big_unit(e):
			score += 5

		if score > best_score:
			best_score = score
			best = e

	_set_team_focus(u.team, best)
	return best

# ----------------------------
# Movement scoring
# ----------------------------
func _best_move_tile_toward_target(u: Unit, target: Unit, reachable: Array[Vector2i]) -> Vector2i:
	var start = M.get_unit_origin(u)
	if M._is_big_unit(u):
		start = M.snap_origin_for_unit(start, u)

	var ranged := _is_ranged(u)
	var enemies: Array[Unit] = M.get_units(Unit.Team.ENEMY if u.team == Unit.Team.ALLY else Unit.Team.ALLY)

	var do_evade := _should_evade(u, enemies)

	# Team focus
	var focus := _get_team_focus(u.team)
	if focus != null and is_instance_valid(focus) and focus.team != u.team:
		target = focus

	# Protect ally
	var ally_to_protect := _lowest_hp_ally(u.team)
	var threat_to_ally: Unit = null
	if ally_to_protect != null and ally_to_protect != u:
		threat_to_ally = _enemy_threatening_ally(ally_to_protect)

	var goal = M.get_unit_origin(target)
	if M._is_big_unit(target):
		goal = M.snap_origin_for_unit(goal, target)

	var protect_goal := Vector2i(-1, -1)
	if threat_to_ally != null and is_instance_valid(threat_to_ally):
		protect_goal = M.get_unit_origin(threat_to_ally)
		if M._is_big_unit(threat_to_ally):
			protect_goal = M.snap_origin_for_unit(protect_goal, threat_to_ally)

	var best = start
	var best_score := -99999999

	for cell in reachable:
		if not M.grid.in_bounds(cell):
			continue
		if not M._can_stand(u, cell):
			continue

		var score := 0

		var can_attack = (M._attack_distance_from_origin(u, cell, target) <= int(u.attack_range))
		if can_attack:
			score += 420

		var d_goal = abs(cell.x - goal.x) + abs(cell.y - goal.y)
		score += int((30 - min(d_goal, 30)) * 11)

		var danger := _danger_score_at_cell(cell, enemies)
		if do_evade:
			score -= danger * 35
		else:
			score -= danger * (12 if ranged else 7)

		if do_evade:
			var d_near := _dist_to_nearest_enemy(cell, enemies)
			score += int(min(d_near, 12) * 14)

		if focus != null and is_instance_valid(focus):
			var fo = M.get_unit_origin(focus)
			if M._is_big_unit(focus):
				fo = M.snap_origin_for_unit(fo, focus)
			var d_focus = abs(cell.x - fo.x) + abs(cell.y - fo.y)
			score += int((25 - min(d_focus, 25)) * 5)
			if M._attack_distance_from_origin(u, cell, focus) <= int(u.attack_range):
				score += focus_fire_bonus

		if protect_goal.x >= 0:
			var d_protect = abs(cell.x - protect_goal.x) + abs(cell.y - protect_goal.y)
			score += int((25 - min(d_protect, 25)) * 3)
			if threat_to_ally != null and is_instance_valid(threat_to_ally):
				if M._attack_distance_from_origin(u, cell, threat_to_ally) <= int(u.attack_range):
					score += protect_ally_bonus

		score -= _ally_clump_penalty(cell, u.team)

		if cell == start:
			score += 3
		if can_attack:
			score += 2

		if score > best_score:
			best_score = score
			best = cell

	return best

func _danger_score_at_cell(cell: Vector2i, enemies: Array[Unit]) -> int:
	var danger := 0
	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue
		var eo = M.get_unit_origin(e)
		if M._is_big_unit(e):
			eo = M.snap_origin_for_unit(eo, e)
		var d = abs(eo.x - cell.x) + abs(eo.y - cell.y)
		if d <= 1:
			danger += 1
	return danger

func _dist_to_nearest_enemy(cell: Vector2i, enemies: Array[Unit]) -> int:
	var best := 999999
	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue
		var eo = M.get_unit_origin(e)
		if M._is_big_unit(e):
			eo = M.snap_origin_for_unit(eo, e)
		var d = abs(eo.x - cell.x) + abs(eo.y - cell.y)
		if d < best:
			best = d
	return 0 if best == 999999 else best

func _ally_clump_penalty(cell: Vector2i, team_id: int) -> int:
	var allies: Array[Unit] = M.get_units(team_id)
	var p := 0
	for a in allies:
		if a == null or not is_instance_valid(a):
			continue
		var ao = M.get_unit_origin(a)
		if M._is_big_unit(a):
			ao = M.snap_origin_for_unit(ao, a)
		if abs(ao.x - cell.x) + abs(ao.y - cell.y) <= 1:
			p += 1
	return p

func _alive_units_count() -> int:
	if M == null:
		return 0
	return M.get_units(Unit.Team.ALLY).size() + M.get_units(Unit.Team.ENEMY).size()

func _should_evade(u: Unit, enemies: Array[Unit]) -> bool:
	if _alive_units_count() <= endgame_aggression_units_left:
		return false
	if enemies.size() < low_hp_evade_min_enemies:
		return false
	return _is_low_hp(u)

# ----------------------------
# Team focus helpers
# ----------------------------
func _set_team_focus(team_id: int, target: Unit) -> void:
	if target == null or not is_instance_valid(target):
		team_focus_target[team_id] = null
		return
	team_focus_target[team_id] = weakref(target)

func _get_team_focus(team_id: int) -> Unit:
	if not team_focus_target.has(team_id):
		return null
	var wr = team_focus_target[team_id]
	if wr == null:
		return null
	var t := wr.get_ref() as Unit
	if t == null or not is_instance_valid(t):
		team_focus_target[team_id] = null
		return null
	return t

func _lowest_hp_ally(team_id: int) -> Unit:
	var allies: Array[Unit] = M.get_units(team_id)
	var best: Unit = null
	var best_frac := 999.0

	for a in allies:
		if a == null or not is_instance_valid(a):
			continue
		if int(a.max_hp) <= 0:
			continue
		var frac := float(a.hp) / float(a.max_hp)
		if frac < best_frac:
			best_frac = frac
			best = a

	if best != null and int(best.max_hp) > 0:
		var f := float(best.hp) / float(best.max_hp)
		if f <= protect_ally_low_hp_threshold:
			return best
	return null

func _enemy_threatening_ally(ally: Unit) -> Unit:
	if ally == null or not is_instance_valid(ally):
		return null
	var enemies: Array[Unit] = M.get_units(Unit.Team.ENEMY if ally.team == Unit.Team.ALLY else Unit.Team.ALLY)

	var best: Unit = null
	var best_d := 999999
	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue
		var d = M._attack_distance(e, ally)
		if d <= int(e.attack_range):
			return e
		if d < best_d:
			best_d = d
			best = e
	return best

# ----------------------------
# Drops: deterministic "go nearest"
# ----------------------------

func _find_all_drops() -> Array[Node]:
	var drops: Array[Node] = []

	# Prefer explicit groups (you can add your drop nodes to one of these)
	if get_tree().has_group("Drops"):
		drops.append_array(get_tree().get_nodes_in_group("Drops"))
	if get_tree().has_group("Drop"):
		drops.append_array(get_tree().get_nodes_in_group("Drop"))

	# Deduplicate + keep only valid nodes
	var uniq := {}
	var out: Array[Node] = []
	for d in drops:
		if d == null or not is_instance_valid(d):
			continue
		if uniq.has(d):
			continue
		uniq[d] = true
		out.append(d)
	return out


func _drop_to_cell(drop: Node) -> Vector2i:
	if drop == null:
		return Vector2i(-1, -1)

	# 1) Direct API on the drop (best)
	if drop.has_method("get_grid_cell"):
		var c = drop.call("get_grid_cell")
		if typeof(c) == TYPE_VECTOR2I:
			return c

	# 2) Common variable names
	if drop.has_variable("grid_cell"):
		var c2 = drop.grid_cell
		if typeof(c2) == TYPE_VECTOR2I:
			return c2
	if drop.has_variable("cell"):
		var c3 = drop.cell
		if typeof(c3) == TYPE_VECTOR2I:
			return c3

	# 3) Convert from world position via Map (fallback)
	if M != null:
		if M.has_method("world_to_cell"):
			var c4 = M.world_to_cell((drop as Node2D).global_position)
			if typeof(c4) == TYPE_VECTOR2I:
				return c4
		if M.has_method("world_to_map"):
			var c5 = M.world_to_map((drop as Node2D).global_position)
			if typeof(c5) == TYPE_VECTOR2I:
				return c5
		if M.has_method("global_to_cell"):
			var c6 = M.global_to_cell((drop as Node2D).global_position)
			if typeof(c6) == TYPE_VECTOR2I:
				return c6

	# 4) TileMap fallback if Map exposes a TileMap named "terrain" or "Terrain"
	# (uses local_to_map)
	if M != null:
		var tm: TileMap = null
		if M.has_variable("terrain"):
			tm = M.terrain
		elif M.has_node("Terrain"):
			tm = M.get_node("Terrain") as TileMap
		if tm != null and drop is Node2D:
			var lp = tm.to_local((drop as Node2D).global_position)
			return tm.local_to_map(lp)

	return Vector2i(-1, -1)


func _nearest_drop_cell_for(u: Unit) -> Vector2i:
	if u == null or not is_instance_valid(u) or M == null:
		return Vector2i(-1, -1)

	var drops := _find_all_drops()
	if drops.is_empty():
		return Vector2i(-1, -1)

	var uo = M.get_unit_origin(u)
	if M._is_big_unit(u):
		uo = M.snap_origin_for_unit(uo, u)

	var best := Vector2i(-1, -1)
	var best_d := 999999

	for d in drops:
		var c := _drop_to_cell(d)
		if c.x < 0:
			continue
		if not M.grid.in_bounds(c):
			continue

		var dist = abs(c.x - uo.x) + abs(c.y - uo.y)
		if dist < best_d:
			best_d = dist
			best = c

	return best


func _best_move_tile_toward_cell(u: Unit, goal: Vector2i, reachable: Array[Vector2i]) -> Vector2i:
	var start = M.get_unit_origin(u)
	if M._is_big_unit(u):
		start = M.snap_origin_for_unit(start, u)

	var best = start
	var best_d := 999999

	for cell in reachable:
		if not M.grid.in_bounds(cell):
			continue
		if not M._can_stand(u, cell):
			continue

		var d = abs(cell.x - goal.x) + abs(cell.y - goal.y)

		# Deterministic tie-breaks:
		# 1) smallest distance to goal
		# 2) prefer landing exactly on the goal
		# 3) prefer not moving (stability) if still tied
		var better := false
		if d < best_d:
			better = true
		elif d == best_d:
			if cell == goal and best != goal:
				better = true
			elif cell == start and best != start:
				better = true

		if better:
			best_d = d
			best = cell

	return best
