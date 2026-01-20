extends Unit
class_name Human

func _ready() -> void:
	set_meta("portrait_tex", preload("res://sprites/Portraits/soldier_port.png"))
	set_meta("display_name", "Soldier")

	footprint_size = Vector2i(1, 1)
	move_range = 3
	attack_range = 4
	attack_damage = 1

	# Do NOT hard reset; clamp up
	max_hp = max(max_hp, 3)
	hp = clamp(hp, 0, max_hp)

	super._ready()

@export var hellfire_range := 6
@export var hellfire_damage := 1
@export var hellfire_delay := 0.1

@export var hellfire_projectile_scene: PackedScene
@export var hellfire_flight_time := 0.40
@export var hellfire_arc_height := 46.0
@export var hellfire_spin_turns := 1.25

func perform_hellfire(M: MapController, target: Vector2i) -> void:
	# ✅ Launch TNT arc to target first
	await M.launch_projectile_arc(
		cell,                         # from THIS unit's cell
		target,
		hellfire_projectile_scene,
		hellfire_flight_time,
		hellfire_arc_height,
		hellfire_spin_turns,
	)

	# ✅ Then trigger the hellfire bombardment (3x3)
	var cells: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			cells.append(target + Vector2i(dx, dy))

	for c in cells:
		if M.grid != null and M.grid.has_method("in_bounds") and not M.grid.in_bounds(c):
			continue
		if not M._is_walkable(c):
			continue

		# Explosion visuals
		M.spawn_explosion_at_cell(c)

		var victim := M.unit_at_cell(c)
		if victim != null and is_instance_valid(victim) and victim.team != team:
			M._flash_unit_white(victim, 0.12)
			victim.take_damage(hellfire_damage)
			M._cleanup_dead_at(c)

		await get_tree().create_timer(hellfire_delay).timeout

# Human.gd (example)
func get_available_specials() -> Array[String]:
	return ["Hellfire"]  # only humans can place mines (example)

func can_use_special(id: String) -> bool:
	# your cooldown logic here
	return true
