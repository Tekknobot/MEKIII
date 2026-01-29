# res://scripts/RunState.gd
extends Node
class_name RunState

# Overworld / mission
var overworld_seed: int = 0
var overworld_current_node_id: int = -1

var mission_seed: int = 0
var mission_node_type: StringName = &"combat"  # "combat/supply/event/elite/boss/start"
var mission_difficulty: float = 0.0            # 0..1
var mission_node_id: int = -1

# -------------------------
# Upgrades (existing)
# -------------------------
var run_upgrades: Array[StringName] = []
var run_upgrade_counts: Dictionary = {} # StringName -> int

# -------------------------
# Squad selection
# -------------------------
var squad_scene_paths: Array[String] = []  # ordered .tscn paths

# -------------------------
# Roster + Recruit pool (NEW)
# -------------------------
var roster_scene_paths: Array[String] = []        # all ally unit .tscn paths discovered
var recruit_pool_paths: Array[String] = []        # remaining recruitable .tscn paths (excludes squad + already recruited)
var recruited_scene_paths: Array[String] = []     # what you’ve recruited so far (optional bookkeeping)

func clear() -> void:
	run_upgrades.clear()
	run_upgrade_counts.clear()

	# reset run selections
	squad_scene_paths.clear()

	# ✅ reset roster/pool
	roster_scene_paths.clear()
	recruit_pool_paths.clear()
	recruited_scene_paths.clear()

func add_upgrade(id: StringName) -> void:
	run_upgrades.append(id)
	run_upgrade_counts[id] = int(run_upgrade_counts.get(id, 0)) + 1

func has_upgrade(id: StringName) -> bool:
	return run_upgrade_counts.has(id)

func get_upgrade_count(id: StringName) -> int:
	return int(run_upgrade_counts.get(id, 0))

func set_squad(paths: Array[String]) -> void:
	squad_scene_paths = paths.duplicate()

func has_squad() -> bool:
	return not squad_scene_paths.is_empty()

func clear_squad() -> void:
	squad_scene_paths.clear()

func get_squad_packed_scenes() -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	for p in squad_scene_paths:
		var res := load(p)
		if res is PackedScene:
			out.append(res)
	return out

# -------------------------
# Roster / recruitment API
# -------------------------
func set_roster(paths: Array[String]) -> void:
	# store all possible ally scenes
	roster_scene_paths = paths.duplicate()

func rebuild_recruit_pool() -> void:
	# pool = roster - squad - already recruited
	recruit_pool_paths.clear()

	var taken: Dictionary = {} # path -> true
	for p in squad_scene_paths:
		taken[str(p)] = true
	for p in recruited_scene_paths:
		taken[str(p)] = true

	for p in roster_scene_paths:
		var sp := str(p)
		if not taken.has(sp):
			recruit_pool_paths.append(sp)

func get_remaining_recruit_count() -> int:
	return recruit_pool_paths.size()

func has_remaining_recruits() -> bool:
	return not recruit_pool_paths.is_empty()

func take_random_recruit_scene() -> PackedScene:
	if recruit_pool_paths.is_empty():
		return null

	var idx := randi() % recruit_pool_paths.size()
	var path := recruit_pool_paths[idx]

	# remove from pool so it can’t be recruited again
	recruit_pool_paths.remove_at(idx)
	recruited_scene_paths.append(path)

	var res := load(path)
	if res is PackedScene:
		return res

	# if load failed, just skip it and try again
	return take_random_recruit_scene()

func _unit_key_from_display_name(s: String) -> String:
	return s.strip_edges().to_upper()

func apply_upgrades_to_unit(u: Node) -> void:
	if u == null or not is_instance_valid(u):
		return

	# --- read display_name ---
	var dn := ""
	if "display_name" in u:
		dn = str(u.display_name)
	elif u.has_meta("display_name"):
		dn = str(u.get_meta("display_name"))
	elif u.has_method("get_display_name"):
		dn = str(u.call("get_display_name"))

	var key := _unit_key_from_display_name(dn)

	# --- current stats ---
	var hp := int(u.max_hp) if ("max_hp" in u) else 0
	var mv := int(u.move_range) if ("move_range" in u) else 0
	var rng := int(u.attack_range) if ("attack_range" in u) else 0
	var dmg := int(u.attack_damage) if ("attack_damage" in u) else 0

	# -------------------------
	# GLOBAL TEAM UPGRADES
	# -------------------------
	hp += get_upgrade_count(&"all_hp_plus_1")
	mv += get_upgrade_count(&"all_move_plus_1")
	dmg += get_upgrade_count(&"all_dmg_plus_1")

	# -------------------------
	# PER-UNIT UPGRADES
	# -------------------------
	match key:

		# 1) Soldier
		"SOLDIER":
			mv += get_upgrade_count(&"soldier_move_plus_1")
			rng += get_upgrade_count(&"soldier_range_plus_1")
			dmg += get_upgrade_count(&"soldier_dmg_plus_1")

		# 2) Mercenary
		"MERCENARY":
			mv += get_upgrade_count(&"merc_move_plus_1")
			rng += get_upgrade_count(&"merc_range_plus_1")
			dmg += get_upgrade_count(&"merc_dmg_plus_1")

		# 3) Robodog
		"ROBODOG":
			hp += 2 * get_upgrade_count(&"dog_hp_plus_2")
			mv += get_upgrade_count(&"dog_move_plus_1")
			dmg += get_upgrade_count(&"dog_dmg_plus_1")

		# 4) Battleangel
		"BATTLEANGEL":
			hp += get_upgrade_count(&"angel_hp_plus_1")
			mv += get_upgrade_count(&"angel_move_plus_1")
			dmg += get_upgrade_count(&"angel_dmg_plus_1")

		# 5) Bladeguard
		"BLADEGUARD":
			hp += get_upgrade_count(&"blade_hp_plus_1")
			mv += get_upgrade_count(&"blade_move_plus_1")
			dmg += get_upgrade_count(&"blade_dmg_plus_1")

		# 6) Pantherbot
		"PANTHERBOT":
			mv += get_upgrade_count(&"panther_move_plus_1")
			dmg += get_upgrade_count(&"panther_dmg_plus_1")

		# 7) Kannon
		"KANNON":
			rng += get_upgrade_count(&"kannon_range_plus_1")
			dmg += get_upgrade_count(&"kannon_dmg_plus_1")

		# 8) Skimmer
		"SKIMMER":
			mv += get_upgrade_count(&"skimmer_move_plus_1")
			dmg += get_upgrade_count(&"skimmer_dmg_plus_1")

		# 9) Destroyer A.I.
		"DESTROYER A.I.":
			hp += get_upgrade_count(&"destroyer_hp_plus_2")
			dmg += get_upgrade_count(&"destroyer_dmg_plus_1")

	# --- write back ---
	if "max_hp" in u:
		u.max_hp = hp
	if "hp" in u:
		u.hp = clamp(int(u.hp), 0, hp)

	if "move_range" in u:
		u.move_range = mv
	if "attack_range" in u:
		u.attack_range = rng
	if "attack_damage" in u:
		u.attack_damage = dmg
