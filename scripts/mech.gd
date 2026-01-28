extends Unit
class_name Mech

@export var thumbnail: Texture2D
@export var specials: Array[String] = ["MINES", "WATCHER"]
@export var special_desc: String = "Place mines in range.\nWatcher attacks in range every turn."

@export var mine_place_range := 5
@export var mine_damage := 2
var placing_mines := false

func _ready() -> void:
	set_meta("portrait_tex", preload("res://sprites/Portraits/dog_port.png"))
	set_meta("display_name", "ROBODOG")
			
	footprint_size = Vector2i(1, 1)
	move_range = 6
	attack_range = 1
	
	# ✅ Do NOT hard reset hp/max_hp here.
	# If you want a baseline, clamp UP not down:
	max_hp = max(max_hp, 5)
	hp = clamp(hp, 0, max_hp)

	# ✅ Run Unit setup (hp=max_hp + sprite base pos)
	super._ready()	

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
	
	# ✅ spawn mine scene visual
	M.place_mine_visual(target_cell)

func get_available_specials() -> Array[String]:
	return ["Mines", "Overwatch"]

func can_use_special(id: String) -> bool:
	return true

func get_special_range(id: String) -> int:
	id = id.to_lower()
	if id == "mines":
		return mine_place_range
	if id == "overwatch":
		return 0
	return 0

@export var overwatch_range := 4

func perform_overwatch(M: MapController) -> void:
	if not can_use_special("overwatch"):
		return
	M.set_overwatch(self, true, overwatch_range, 1) # ✅ 1 round
	mark_special_used("overwatch", 2)

func play_death_anim() -> void:
	var M := get_tree().get_first_node_in_group("MapController")
	var fx_parent: Node = M if M != null else get_tree().current_scene

	var p := get_tile_world_pos() + death_fx_offset

	# ✅ explosion sound at the correct tile anchor
	if M != null and M.has_method("_sfx"):
		M.call("_sfx", &"explosion_small", 1.0, randf_range(0.95, 1.05), p)
	# or, if you already have a cue name for it:
	# M.call("_sfx", &"mech_explode", 1.0, randf_range(0.95, 1.05), p)
	
	var boom = preload("res://scenes/explosion.tscn").instantiate()
	fx_parent.add_child(boom)
	boom.global_position = p

	# Optional: keep it on same depth layer as the unit
	if boom is Node2D:
		boom.z_as_relative = false
		boom.z_index = z_index + 5

	# wait for boom to finish (adjust to your scene)
	if boom.has_signal("finished"):
		await boom.finished
	else:
		await get_tree().create_timer(0.6).timeout

	queue_free()

func begin_mine_special() -> void:
	placing_mines = true
	# keep special usable during the session
	special_cd["mines"] = 0

func mine_placed_one() -> void:
	# keep it usable while session is active
	special_cd["mines"] = 0

func end_mine_special(commit_cooldown: bool = true) -> void:
	placing_mines = false
	if commit_cooldown:
		mark_special_used("mines", 2)
