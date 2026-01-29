extends Unit
class_name Human

@export var portrait_tex: Texture2D = preload("res://sprites/Portraits/soldier_port.png")
@export var thumbnail: Texture2D

@export var specials: Array[String] = ["HELLFIRE", "SUPRESS"]
@export var special_desc: String = "Throw TNT causing splash damage.\nFire at targets and disable their next turn."

func _ready() -> void:
	footprint_size = Vector2i(1, 1)
	move_range = 4
	attack_range = 5
	attack_damage = 2

	max_hp = max(max_hp, 3)
	hp = clamp(hp, 0, max_hp)

	super._ready()

# -----------------------------
# Special: Hellfire
# -----------------------------
@export var hellfire_range := 6
@export var hellfire_damage := 1
@export var hellfire_delay := 0.1

@export var hellfire_projectile_scene: PackedScene
@export var hellfire_flight_time := 0.40
@export var hellfire_arc_height := 46.0
@export var hellfire_spin_turns := 1.25

func perform_hellfire(M: MapController, target: Vector2i) -> void:
	M._face_unit_toward_world(self, M._cell_world(target))

	await M.launch_projectile_arc(
		cell,
		target,
		hellfire_projectile_scene,
		hellfire_flight_time,
		hellfire_arc_height,
		hellfire_spin_turns
	)

	var cells: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			cells.append(target + Vector2i(dx, dy))

	for c in cells:
		M._face_unit_toward_world(self, M._cell_world(target))

		if M.grid != null and M.grid.has_method("in_bounds") and not M.grid.in_bounds(c):
			continue
		if not M._is_walkable(c):
			continue

		M.spawn_explosion_at_cell(c)

		var victim := M.unit_at_cell(c)
		if victim != null and is_instance_valid(victim) and victim.team != team:
			M._flash_unit_white(victim, 0.12)
			victim.take_damage(hellfire_damage + attack_range)
			M._cleanup_dead_at(c)

		await get_tree().create_timer(hellfire_delay).timeout

# -----------------------------
# Special: Suppress
# -----------------------------
@export var suppress_range := 5
@export var suppress_damage := 1
@export var suppress_move_penalty := 2
@export var suppress_duration_turns := 1

func perform_suppress(map: MapController, target_cell: Vector2i) -> void:
	if map == null or not is_instance_valid(map):
		return

	# Build list: ALL enemies in range (LOS respected)
	var targets: Array[Unit] = []
	for e in map.get_all_units():
		if e == null or not is_instance_valid(e):
			continue
		if e.team == team:
			continue
		if e.hp <= 0:
			continue

		var d = abs(e.cell.x - cell.x) + abs(e.cell.y - cell.y)
		if d > suppress_range:
			continue
		if not map._has_clear_attack_path(cell, e.cell):
			continue

		targets.append(e)

	if targets.is_empty():
		return

	# Optional: closest first
	targets.sort_custom(func(a: Unit, b: Unit) -> bool:
		var da = abs(a.cell.x - cell.x) + abs(a.cell.y - cell.y)
		var db = abs(b.cell.x - cell.x) + abs(b.cell.y - cell.y)
		return da < db
	)

	# Tune these
	var shot_gap := 0.0   # time between shots (feel)
	var lock := 0.38

	# Fire at ALL targets
	for t in targets:
		if t == null or not is_instance_valid(t) or t.hp <= 0:
			continue

		var c := t.cell

		# ✅ Face + play attack EACH shot
		map._face_unit_toward_world(self, t.global_position)
		map._play_attack_anim(self)
		map._sfx(&"attack_swing", map.sfx_volume_world, randf_range(0.95, 1.05), global_position)

		# hit
		map._flash_unit_white(t, 0.12)
		t.take_damage(suppress_damage + attack_damage)

		# debuff via meta
		t.set_meta("suppress_turns", suppress_duration_turns)
		t.set_meta("suppress_move_penalty", suppress_move_penalty)

		# allow the attack anim to show
		#await map._wait_for_attack_anim(self)
		await map.get_tree().create_timer(lock).timeout

		# cleanup if dead
		map._cleanup_dead_at(c)

		# small pacing between targets (optional)
		if shot_gap > 0.0:
			await map.get_tree().create_timer(shot_gap).timeout

	map._play_idle_anim(self)

# -----------------------------
# Specials API for your UI / preview
# -----------------------------
func get_available_specials() -> Array[String]:
	# Make sure these match the ids you pass to activate_special()
	return ["Hellfire", "Suppress"]

func can_use_special(id: String) -> bool:
	# plug your cooldown logic here if/when you have it
	return true

func get_special_range(id: String) -> int:
	id = id.to_lower()
	if id == "hellfire":
		return hellfire_range
	if id == "suppress":
		return suppress_range
	return 0
