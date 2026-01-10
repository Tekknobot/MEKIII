extends Node
class_name TurnManager

@export var map: NodePath # drag your Map node here in inspector
@export var start_on_ready := true
@export var think_delay := 0.15

var M

func _ready() -> void:
	M = get_node(map)
	if start_on_ready:
		await get_tree().process_frame
		start_battle()

func start_battle() -> void:
	_run_battle()

func _run_battle() -> void:
	# Fire-and-forget coroutine style
	_battle_loop()

func _battle_loop() -> void:
	while true:
		# win/lose check
		var allies = M.get_units(Unit.Team.ALLY)
		var enemies = M.get_units(Unit.Team.ENEMY)

		if allies.is_empty():
			print("ZOMBIES WIN")
			return
		if enemies.is_empty():
			print("ALLIES WIN")
			return

		# ALLY TURN
		for u in allies:
			if not is_instance_valid(u): continue
			await _unit_take_ai_turn(u)
			await get_tree().create_timer(think_delay).timeout

		# ENEMY TURN
		enemies = M.get_units(Unit.Team.ENEMY) # refresh
		for u in enemies:
			if not is_instance_valid(u): continue
			await _unit_take_ai_turn(u)
			await get_tree().create_timer(think_delay).timeout


func _unit_take_ai_turn(u: Unit) -> void:
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

	# 3) IMPORTANT: After moving, check range again and attack
	if not is_instance_valid(u):
		return
	if not is_instance_valid(target):
		return

	if M._attack_distance(u, target) <= u.attack_range:
		await M.perform_attack(u, target)
