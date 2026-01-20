extends Unit
class_name Mech

func _ready() -> void:
	set_meta("portrait_tex", preload("res://sprites/Portraits/dog_port.png"))
	set_meta("display_name", "Robodog")
			
	footprint_size = Vector2i(1, 1)
	move_range = 5
	attack_range = 1
	
	# ✅ Do NOT hard reset hp/max_hp here.
	# If you want a baseline, clamp UP not down:
	max_hp = max(max_hp, 5)
	hp = clamp(hp, 0, max_hp)

	# ✅ Run Unit setup (hp=max_hp + sprite base pos)
	super._ready()	

@export var mine_place_range := 5
@export var mine_damage := 2

func perform_place_mine(M: MapController, target_cell: Vector2i) -> void:
	# range check
	if abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y) > mine_place_range:
		return

	if M.grid != null and M.grid.has_method("in_bounds") and not M.grid.in_bounds(target_cell):
		return
	if not M._is_walkable(target_cell):
		return
	if M.units_by_cell.has(target_cell):
		return
	if M.mines_by_cell.has(target_cell):
		return

	M.mines_by_cell[target_cell] = {"team": team, "damage": mine_damage}

# Human.gd (example)
func get_available_specials() -> Array[String]:
	return ["Mines"]  # only humans can place mines (example)

func can_use_special(id: String) -> bool:
	# your cooldown logic here
	return true
