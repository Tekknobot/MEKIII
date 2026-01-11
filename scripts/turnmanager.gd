extends Node
class_name TurnManager

@export var map: NodePath              # drag Map node
@export var start_on_ready := true
@export var think_delay := 0.15

enum Mode { AUTO_BATTLE, ONE_PLAYER }
@export var mode: Mode = Mode.AUTO_BATTLE

var M

# For ONE_PLAYER mode
var current_side := Unit.Team.ALLY
var waiting_for_player_action := false

func _ready() -> void:
	M = get_node(map)
	if start_on_ready:
		await get_tree().process_frame
		start_battle()

func start_battle() -> void:
	match mode:
		Mode.AUTO_BATTLE:
			_battle_loop_auto()
		Mode.ONE_PLAYER:
			_one_player_loop()

# ----------------------------
# AUTO BATTLE (your existing)
# ----------------------------
func _battle_loop_auto() -> void:
	while true:
		if _check_end():
			return

		var allies = M.get_units(Unit.Team.ALLY)
		for u in allies:
			if not is_instance_valid(u): continue
			await _unit_take_ai_turn(u)
			await get_tree().create_timer(think_delay).timeout

		var enemies = M.get_units(Unit.Team.ENEMY)
		for u in enemies:
			if not is_instance_valid(u): continue
			await _unit_take_ai_turn(u)
			await get_tree().create_timer(think_delay).timeout

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
		return true
	if enemies.is_empty():
		print("ALLIES WIN")
		return true
	return false

func _unit_take_ai_turn(u: Unit) -> void:
	var target: Unit = M.nearest_enemy(u)
	if target == null:
		return

	# 1) If already in range -> attack
	if M._attack_distance(u, target) <= u.attack_range:
		await M.perform_attack(u, target)
		return

	# 2) Otherwise move toward target (your current logic)
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
