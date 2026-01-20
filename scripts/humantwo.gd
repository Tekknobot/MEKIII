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
	if M == null or not is_instance_valid(M):
		return

	# -----------------------------
	# 0) Build target list: all enemies in blade_range
	# - includes the clicked target first (if valid)
	# - then nearest enemies outward
	# -----------------------------
	var enemies: Array[Unit] = []
	var clicked := M.unit_at_cell(target_cell)

	# Helper: in range + enemy + alive
	var _is_valid_enemy := func(u: Unit) -> bool:
		if u == null or not is_instance_valid(u):
			return false
		if u.team == team:
			return false
		if u.hp <= 0:
			return false
		# manhattan range from CURRENT cell at time of building list
		var d = abs(u.cell.x - cell.x) + abs(u.cell.y - cell.y)
		return d <= blade_range

	# Add clicked target first if valid
	if _is_valid_enemy.call(clicked):
		enemies.append(clicked)

	# Add all other enemies in range
	for u in M.get_all_units():
		if u == null or not is_instance_valid(u):
			continue
		if u == clicked:
			continue
		if _is_valid_enemy.call(u):
			enemies.append(u)

	# Sort remaining by distance to us (keeps the chain feeling snappy)
	enemies.sort_custom(func(a: Unit, b: Unit) -> bool:
		var da = abs(a.cell.x - cell.x) + abs(a.cell.y - cell.y)
		var db = abs(b.cell.x - cell.x) + abs(b.cell.y - cell.y)
		return da < db
	)

	if enemies.is_empty():
		return

	# -----------------------------
	# Helpers
	# -----------------------------
	var _adjacent_open_to := func(tcell: Vector2i) -> Vector2i:
		# Prefer tiles closest to our current cell so dashes look natural
		var adj: Array[Vector2i] = [
			tcell + Vector2i(1, 0),
			tcell + Vector2i(-1, 0),
			tcell + Vector2i(0, 1),
			tcell + Vector2i(0, -1),
		]

		var best := Vector2i(-1, -1)
		var best_d := 999999

		# Structures block (so we don't dash into a building)
		var structure_blocked: Dictionary = {}
		if M.game_ref != null and "structure_blocked" in M.game_ref:
			structure_blocked = M.game_ref.structure_blocked

		for c in adj:
			if M.grid != null and M.grid.has_method("in_bounds") and not M.grid.in_bounds(c):
				continue
			if not M._is_walkable(c):
				continue
			if structure_blocked.has(c):
				continue
			if M.units_by_cell.has(c):
				continue

			var d = abs(c.x - cell.x) + abs(c.y - cell.y)
			if d < best_d:
				best_d = d
				best = c

		return best

	var _hit_once := func(v: Unit, dmg: int, flash_time: float, cleanup_cell: Vector2i) -> void:
		if v == null or not is_instance_valid(v) or v.team == team:
			return

		M._face_unit_toward_world(self, v.global_position)
		M._play_attack_anim(self)
		M._sfx(&"attack_swing", M.sfx_volume_world, randf_range(0.95, 1.05), global_position)

		M._flash_unit_white(v, flash_time)
		v.take_damage(dmg)

		# Full cycle
		await M._wait_for_attack_anim(self)
		await M.get_tree().create_timer(M.attack_anim_lock_time).timeout

		M._cleanup_dead_at(cleanup_cell)

	# -----------------------------
	# 1) For EACH target: move adjacent -> hit -> cleave
	# -----------------------------
	var seen: Dictionary = {} # Unit -> true (prevents double-processing)

	for t in enemies:
		if t == null or not is_instance_valid(t):
			continue
		if t.team == team:
			continue
		if seen.has(t):
			continue
		seen[t] = true

		# Target might have moved/died since list creation; reacquire by cell
		var tcell := t.cell
		var target := M.unit_at_cell(tcell)
		if target == null or not is_instance_valid(target) or target.team == team:
			continue

		# Still in range from our *current* position?
		if abs(tcell.x - cell.x) + abs(tcell.y - cell.y) > blade_range:
			continue

		# Find open adjacent tile to dash into
		var dash_to = _adjacent_open_to.call(tcell)
		if dash_to.x < 0:
			# no adjacent open tile, skip this target
			continue

		# Dash into position
		if cell != dash_to:
			await M._push_unit_to_cell(self, dash_to)

		# Reacquire after dash (target could die to something else, etc.)
		target = M.unit_at_cell(tcell)
		if target == null or not is_instance_valid(target) or target.team == team:
			continue

		# Primary hit
		await _hit_once.call(target, blade_damage, 0.12, tcell)

		# Cleave around target cell (each is its own full cycle)
		var around := [
			tcell + Vector2i(1, 0),
			tcell + Vector2i(-1, 0),
			tcell + Vector2i(0, 1),
			tcell + Vector2i(0, -1),
		]
		for c in around:
			var v := M.unit_at_cell(c)
			if v != null and is_instance_valid(v) and v.team != team:
				await _hit_once.call(v, blade_cleave_damage, 0.10, c)

	# Return to idle at end
	M._play_idle_anim(self)

# Human.gd (example)
func get_available_specials() -> Array[String]:
	return ["Blade", "Stim"]  # only humans can place mines (example)

func can_use_special(id: String) -> bool:
	# your cooldown logic here
	return true

func get_special_range(id: String) -> int:
	id = id.to_lower()
	if id == "blade":
		return blade_range
	if id == "stim":
		return 0
	return 0


# -----------------------------
# Special: Stim (instant buff)
# -----------------------------
@export var stim_duration_turns := 1          # lasts N enemy turns
@export var stim_move_bonus := 2              # +move_range while active
@export var stim_attack_damage_bonus := 1     # +attack_damage while active

func perform_stim(M: MapController) -> void:
	# Instant: no target cell
	if not can_use_special("stim"):
		return

	# Apply as meta so you don’t need new classes
	set_meta("stim_turns", stim_duration_turns)
	set_meta("stim_move_bonus", stim_move_bonus)
	set_meta("stim_damage_bonus", stim_attack_damage_bonus)

	# Optional feedback
	if M != null and is_instance_valid(M):
		M._say(self, "Stim!")
		M._sfx(&"ui_stim", M.sfx_volume_ui, 1.0, global_position)

	# Cooldown example
	mark_special_used("stim", 3)
