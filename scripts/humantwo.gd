extends Unit
class_name HumanTwo

func _ready() -> void:
	set_meta("portrait_tex", preload("res://sprites/Portraits/rambo_port.png"))
	set_meta("display_name", "Mercenary")
		
	footprint_size = Vector2i(1, 1)
	move_range = 4
	attack_range = 1

	tnt_throw_range = 4
	
	# ✅ Do NOT hard reset hp/max_hp here.
	# If you want a baseline, clamp UP not down:
	max_hp = max(max_hp, 4)
	hp = clamp(hp, 0, max_hp)

	# ✅ Run Unit setup (hp=max_hp + sprite base pos)
	super._ready()	

@export var blade_range := 4
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

	# Find an adjacent open cell to dash into
	var adj: Array[Vector2i] = [
		target_cell + Vector2i(1,0),
		target_cell + Vector2i(-1,0),
		target_cell + Vector2i(0,1),
		target_cell + Vector2i(0,-1),
	]
	var best := Vector2i(-1,-1)
	var best_d := 9999
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

	# Dash (uses MapController shove tween)
	await M._push_unit_to_cell(self, best)

	# Primary hit
	M._flash_unit_white(target, 0.12)
	target.take_damage(blade_damage)
	M._cleanup_dead_at(target_cell)

	# Cleave around target cell
	var around := [
		target_cell + Vector2i(1,0),
		target_cell + Vector2i(-1,0),
		target_cell + Vector2i(0,1),
		target_cell + Vector2i(0,-1),
	]
	for c in around:
		var v := M.unit_at_cell(c)
		if v != null and is_instance_valid(v) and v.team != team:
			M._flash_unit_white(v, 0.10)
			v.take_damage(blade_cleave_damage)
			M._cleanup_dead_at(c)

# Human.gd (example)
func get_available_specials() -> Array[String]:
	return ["Blade"]  # only humans can place mines (example)

func can_use_special(id: String) -> bool:
	# your cooldown logic here
	return true
