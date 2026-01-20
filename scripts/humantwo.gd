extends Unit
class_name HumanTwo

func _ready() -> void:
	set_meta("portrait_tex", preload("res://sprites/Portraits/rambo_port.png"))
	set_meta("display_name", "Mercenary")
		
	footprint_size = Vector2i(1, 1)
	move_range = 5
	attack_range = 1

	tnt_throw_range = 4
	
	# ✅ Do NOT hard reset hp/max_hp here.
	# If you want a baseline, clamp UP not down:
	max_hp = max(max_hp, 4)
	hp = clamp(hp, 0, max_hp)

	# ✅ Run Unit setup (hp=max_hp + sprite base pos)
	super._ready()	

@export var blade_range := 5
@export var blade_damage := 2
@export var blade_cleave_damage := 1

func perform_blade(M: MapController, target_cell: Vector2i) -> void:
	var target := M.unit_at_cell(target_cell)
	if target == null or not is_instance_valid(target):
		return
	if target.team == team:
		return

	# Range check (manhattan)
	if abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y) > blade_range:
		return

	# -----------------------------
	# 1) Move to adjacent open tile
	# -----------------------------
	var adj: Array[Vector2i] = [
		target_cell + Vector2i(1, 0),
		target_cell + Vector2i(-1, 0),
		target_cell + Vector2i(0, 1),
		target_cell + Vector2i(0, -1),
	]

	var best := Vector2i(-1, -1)
	var best_d := 999999
	for c in adj:
		if M.grid != null and M.grid.has_method("in_bounds") and not M.grid.in_bounds(c):
			continue
		if not M._is_walkable(c):
			continue
		if M.units_by_cell.has(c):
			continue
		var d = abs(c.x - cell.x) + abs(c.y - cell.y)
		if d < best_d:
			best_d = d
			best = c

	if best.x < 0:
		return

	# Dash into position
	if cell != best:
		await M._push_unit_to_cell(self, best)

	# Re-acquire target after dash
	target = M.unit_at_cell(target_cell)
	if target == null or not is_instance_valid(target) or target.team == team:
		return

	# Helper: do one animated hit + wait a full anim cycle
	var hit_once := func(v: Unit, dmg: int, flash_time: float, cleanup_cell: Vector2i) -> void:
		if v == null or not is_instance_valid(v) or v.team == team:
			return

		M._face_unit_toward_world(self, v.global_position)
		M._play_attack_anim(self)

		M._flash_unit_white(v, flash_time)
		v.take_damage(dmg)

		# ✅ FULL animation cycle per target
		await M._wait_for_attack_anim(self)
		await M.get_tree().create_timer(M.attack_anim_lock_time).timeout

		M._cleanup_dead_at(cleanup_cell)

	# -----------------------------
	# 2) Primary hit (1 full cycle)
	# -----------------------------
	await hit_once.call(target, blade_damage, 0.12, target_cell)

	# -----------------------------
	# 3) Cleave hits (each full cycle)
	# -----------------------------
	var around := [
		target_cell + Vector2i(1, 0),
		target_cell + Vector2i(-1, 0),
		target_cell + Vector2i(0, 1),
		target_cell + Vector2i(0, -1),
	]

	for c in around:
		var v := M.unit_at_cell(c)
		if v != null and is_instance_valid(v) and v.team != team:
			await hit_once.call(v, blade_cleave_damage, 0.10, c)

	M._play_idle_anim(self)

# Human.gd (example)
func get_available_specials() -> Array[String]:
	return ["Blade"]  # only humans can place mines (example)

func can_use_special(id: String) -> bool:
	# your cooldown logic here
	return true

func get_special_range(id: String) -> int:
	id = id.to_lower()
	if id == "blade":
		return blade_range
	return 0
