# res://scripts/RunState.gd
extends Node
class_name RunState

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
