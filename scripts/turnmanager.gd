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

@export var human_tnt_throw_range := 8          # Manhattan cells from human origin to landing cell
@export var human_tnt_min_enemy_hits := 2       # only throw if it will hit at least this many enemies
@export var human_tnt_ally_avoid := true        # don't throw if it would hit any ally

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
# AUTO BATTLE (your existing)
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
			# wrap index if needed
			if ally_i >= allies.size():
				ally_i = 0

			# find next valid ally this step
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

		# Flip side after every single action (this is the key)
		side = (Unit.Team.ENEMY if side == Unit.Team.ALLY else Unit.Team.ALLY)

# ----------------------------
# ONE PLAYER (player = ALLY, AI = ENEMY)
# ----------------------------
func _one_player_loop() -> void:
	# Player starts
	current_side = Unit.Team.ALLY
	waiting_for_player_action = true

	# Optional: tell Map to enter player-control mode (prevents ally AI moves)
	if M.has_method("set_player_mode"):
		M.set_player_mode(true)

	while true:
		if _check_end():
			return

		# PLAYER PHASE: wait until player performs ONE action
		if current_side == Unit.Team.ALLY:
			waiting_for_player_action = true
			await _wait_for_player_action()
			current_side = Unit.Team.ENEMY

		# ENEMY PHASE: AI moves all zombies
		if current_side == Unit.Team.ENEMY:
			var enemies = M.get_units(Unit.Team.ENEMY)
			for u in enemies:
				if not is_instance_valid(u): continue
				await _unit_take_ai_turn(u)
				await get_tree().create_timer(think_delay).timeout

			current_side = Unit.Team.ALLY

func notify_player_action_complete() -> void:
	# Map calls this after the player successfully moves OR attacks.
	waiting_for_player_action = false

func _wait_for_player_action() -> void:
	# Simple wait loop
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
	if u == null or not is_instance_valid(u):
		return

	# ✅ Humans (both types): try TNT first
	if (u is Human) or (u is HumanTwo):
		var pick = _pick_best_tnt_target_for_thrower(u)

		if pick.size() > 0:
			var cell: Vector2i = pick["cell"]
			var target_u: Unit = M.unit_at_cell(cell) # can be null
			await M.perform_human_tnt_throw(u, cell, target_u)
			return

	# ---- default behavior (attack / move / attack) ----
	var target: Unit = M.nearest_enemy(u)
	if target == null:
		return

	# 1) If already in range -> attack
	if M._attack_distance(u, target) <= u.attack_range:
		await M.perform_attack(u, target)
		return

	# 2) Otherwise move toward target
	var start = M.get_unit_origin(u)
	if M._is_big_unit(u):
		start = M.snap_origin_for_unit(start, u)

	var reachable = M.compute_reachable_origins(u, start, u.move_range)
	if reachable.is_empty():
		return

	var goal = M.get_unit_origin(target)
	if M._is_big_unit(target):
		goal = M.snap_origin_for_unit(goal, target)

	var best = start
	var best_d := 999999
	for cell in reachable:
		var d = abs(cell.x - goal.x) + abs(cell.y - goal.y)
		if d < best_d:
			best_d = d
			best = cell

	if best != start:
		await M.perform_move(u, best)

	# 3) After moving, try attack
	if not is_instance_valid(u): return
	if not is_instance_valid(target): return

	if M._attack_distance(u, target) <= u.attack_range:
		await M.perform_attack(u, target)

func _pick_best_tnt_target_for_thrower(h: Unit) -> Dictionary:
	if h == null or not is_instance_valid(h):
		return {}
	if M == null:
		return {}

	# Needs TNT setup on Map
	if M.tnt_projectile_scene == null or M.tnt_explosion_scene == null:
		return {}
	if human_tnt_throw_range <= 0:
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
		if d_throw > human_tnt_throw_range:
			continue

		var enemy_hits := _count_team_hits_in_splash(cell, enemies, M.tnt_splash_radius)
		if enemy_hits < human_tnt_min_enemy_hits:
			continue

		var ally_hits := _count_team_hits_in_splash(cell, allies, M.tnt_splash_radius)

		# avoid friendly fire if desired
		if human_tnt_ally_avoid and ally_hits > 0:
			continue

		# Pick best:
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

func _pick_best_tnt_target_for_human(h: Human) -> Dictionary:
	if h == null or not is_instance_valid(h):
		return {}
	if M == null:
		return {}

	# Needs TNT setup on Map
	if M.tnt_projectile_scene == null or M.tnt_explosion_scene == null:
		return {}
	if human_tnt_throw_range <= 0:
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
		if d_throw > human_tnt_throw_range:
			continue

		var enemy_hits := _count_team_hits_in_splash(cell, enemies, M.tnt_splash_radius)
		if enemy_hits < human_tnt_min_enemy_hits:
			continue

		var ally_hits := _count_team_hits_in_splash(cell, allies, M.tnt_splash_radius)

		# avoid friendly fire if desired
		if human_tnt_ally_avoid and ally_hits > 0:
			continue

		# Pick best:
		# 1) more enemies hit
		# 2) fewer allies hit (if not avoiding)
		# 3) shorter throw distance (feels snappier)
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

		# Use origin cell; big units count from their origin (consistent with your damage logic)
		var uc = M.get_unit_origin(u)
		if M._is_big_unit(u):
			uc = M.snap_origin_for_unit(uc, u)

		var d = abs(uc.x - center.x) + abs(uc.y - center.y)
		if d <= radius:
			hits += 1
	return hits
