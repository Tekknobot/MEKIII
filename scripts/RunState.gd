# res://scripts/RunState.gd
extends Node
class_name RunState

var _keep := UnitRegistry.FORCE_EXPORT

var starting_roster_size: int = 4
var unlock_per_campaign_clear: int = 2

# Overworld / mission
var overworld_seed: int = 0
var overworld_current_node_id: int = -1

var mission_seed: int = 0
var mission_node_type: StringName = &"combat"  # "combat/supply/event/elite/boss/start"
var mission_difficulty: float = 0.0            # 0..1
var mission_node_id: int = -1

var overworld_cleared: Dictionary = {} # node_id -> true
var overworld_current_node: int = -1

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

const SAVE_PATH := "user://runstate_save.json"
const SAVE_VERSION := 1

var boss_defeated_this_run: bool = false
var bomber_unlocked_this_run: bool = false

var boss_mode_enabled_next_mission: bool = false
var event_mode_enabled_next_mission: bool = false
var event_id_next_mission: StringName = &""  # e.g. &"titan_overwatch"

# -------------------------
# Supply mission result (NEW)
# -------------------------
var last_supply_success: bool = false
var last_supply_crates_total: int = 0
var last_supply_crates_collected: int = 0
var last_supply_units_evaced: int = 0
var last_supply_reward_tier: int = 0  # 0 none, 1 rough, 2 clean, 3 perfect
var last_supply_failed_reason: String = "" # "missed_crate" / "no_evac" / "wiped" / etc

var dead_scene_paths: Array[String] = []

var run_over := false

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)
	
func clear() -> void:
	# "Clear run state" but KEEP unlocked roster.
	run_upgrades.clear()
	run_upgrade_counts.clear()
	squad_scene_paths.clear()

	# Don't wipe roster unlock progression
	recruit_pool_paths.clear()
	recruited_scene_paths.clear()
	dead_scene_paths.clear()

	event_mode_enabled_next_mission = false
	event_id_next_mission = &""

	rebuild_recruit_pool()
	save_to_disk()

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

		# 10) Arachnobot
		"ARACHNOBOT":
			hp += get_upgrade_count(&"arachno_hp_plus_1")
			mv += get_upgrade_count(&"arachno_move_plus_1")
			dmg += get_upgrade_count(&"arachno_dmg_plus_1")

		# 11) Scannerz
		"SCANNERZ":
			hp += get_upgrade_count(&"scannerz_hp_plus_1")
			mv += get_upgrade_count(&"scannerz_move_plus_1")
			dmg += get_upgrade_count(&"scannerz_dmg_plus_1")
			# NOTE: these are special-specific range upgrades.
			# They DO NOT affect attack_range unless you explicitly wire them into the unit's special range logic.
			# Example: u.set_meta("laser_grid_range_bonus", count) etc.

		# 12) Edward
		"EDWARD":
			hp += get_upgrade_count(&"edward_hp_plus_1")
			mv += get_upgrade_count(&"edward_move_plus_1")
			dmg += get_upgrade_count(&"edward_dmg_plus_1")
			# NOTE: your edward special range upgrades are still placeholders (<special1>/<special2>)
			# so nothing else can be applied until you pick the real ids.

		# 13) Decimator
		"DECIMATOR":
			hp += 2 * get_upgrade_count(&"decimator_hp_plus_2")
			mv += get_upgrade_count(&"decimator_move_plus_1")
			dmg += get_upgrade_count(&"decimator_dmg_plus_1")
			# NOTE: barrage/railgun range upgrades also need unit wiring (special range logic),
			# they are not generic attack_range.
			# e.g. u.set_meta("barrage_range_bonus", count), u.set_meta("railgun_range_bonus", count)

		# 14) Cobruh A.I.
		"COBRUH A.I.":
			hp += 2 * get_upgrade_count(&"cobruh_hp_plus_2")
			dmg += get_upgrade_count(&"cobruh_dmg_plus_1")

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

# --- Save / Load -------------------------------------------------
func _ready() -> void:
	load_from_disk()
	seed_roster_if_empty()

	if roster_scene_paths.is_empty():
		roster_scene_paths = UnitRegistry.ALLY_PATHS.duplicate()
		roster_scene_paths = roster_scene_paths.filter(func(p): return ResourceLoader.exists(p))
		roster_scene_paths.sort()

		if squad_scene_paths.is_empty():
			squad_scene_paths = roster_scene_paths.slice(0, min(3, roster_scene_paths.size()))

		rebuild_recruit_pool()
		save_to_disk()


func _build_roster_from_dir(dir_path: String) -> void:
	roster_scene_paths.clear()

	var d := DirAccess.open(dir_path)
	if d == null:
		push_warning("[RUNSTATE] Failed to open allies dir: " + dir_path)
		return

	d.list_dir_begin()
	while true:
		var f := d.get_next()
		if f == "":
			break
		if d.current_is_dir():
			continue
		if f.get_extension().to_lower() == "tscn":
			roster_scene_paths.append(dir_path + "/" + f)
	d.list_dir_end()

	roster_scene_paths.sort()
	print("[RUNSTATE] Roster initialized with ", roster_scene_paths.size(), " units")

func _notification(what: int) -> void:
	# Desktop close button
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_to_disk()
	# Also fires when the SceneTree is shutting down
	elif what == NOTIFICATION_PREDELETE:
		save_to_disk()

func to_save_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,

		# Overworld
		"overworld_seed": overworld_seed,
		"overworld_current_node_id": overworld_current_node_id,
		"overworld_cleared": overworld_cleared.duplicate(true),

		# Mission (optional, but harmless)
		"mission_seed": mission_seed,
		"mission_node_type": String(mission_node_type),
		"mission_difficulty": mission_difficulty,
		"mission_node_id": mission_node_id,

		# Upgrades / run
		"run_upgrades": run_upgrades.map(func(x): return String(x)),
		"run_upgrade_counts": _dict_stringname_to_string(run_upgrade_counts),

		# Squad / roster / recruits
		"squad_scene_paths": squad_scene_paths.duplicate(),
		"roster_scene_paths": roster_scene_paths.duplicate(),
		"recruit_pool_paths": recruit_pool_paths.duplicate(),
		"recruited_scene_paths": recruited_scene_paths.duplicate(),
		"dead_scene_paths": dead_scene_paths.duplicate(),

		"event_mode_enabled_next_mission": event_mode_enabled_next_mission,
		"event_id_next_mission": String(event_id_next_mission),
		
		"last_supply_success": last_supply_success,
		"last_supply_crates_total": last_supply_crates_total,
		"last_supply_crates_collected": last_supply_crates_collected,
		"last_supply_units_evaced": last_supply_units_evaced,
		"last_supply_reward_tier": last_supply_reward_tier,
		"last_supply_failed_reason": last_supply_failed_reason,
		
	}

func load_from_save_dict(d: Dictionary) -> void:
	if d.is_empty():
		return

	# Overworld
	overworld_seed = int(d.get("overworld_seed", overworld_seed))
	overworld_current_node_id = int(d.get("overworld_current_node_id", overworld_current_node_id))
	overworld_cleared = d.get("overworld_cleared", {}).duplicate(true)

	# Mission
	mission_seed = int(d.get("mission_seed", mission_seed))
	mission_node_type = StringName(str(d.get("mission_node_type", String(mission_node_type))))
	mission_difficulty = float(d.get("mission_difficulty", mission_difficulty))
	mission_node_id = int(d.get("mission_node_id", mission_node_id))

	# Upgrades
	run_upgrades.clear()
	for s in d.get("run_upgrades", []):
		run_upgrades.append(StringName(str(s)))
	run_upgrade_counts = _dict_string_to_stringname_counts(d.get("run_upgrade_counts", {}))

	# Squad / roster / recruits
	squad_scene_paths.clear()
	squad_scene_paths.append_array(d.get("squad_scene_paths", []))

	roster_scene_paths.clear()
	roster_scene_paths.append_array(d.get("roster_scene_paths", []))

	recruit_pool_paths.clear()
	recruit_pool_paths.append_array(d.get("recruit_pool_paths", []))

	recruited_scene_paths.clear()
	recruited_scene_paths.append_array(d.get("recruited_scene_paths", []))

	dead_scene_paths.clear()
	dead_scene_paths.append_array(d.get("dead_scene_paths", []))
	
	last_supply_success = bool(d.get("last_supply_success", false))
	last_supply_crates_total = int(d.get("last_supply_crates_total", 0))
	last_supply_crates_collected = int(d.get("last_supply_crates_collected", 0))
	last_supply_units_evaced = int(d.get("last_supply_units_evaced", 0))
	last_supply_reward_tier = int(d.get("last_supply_reward_tier", 0))
	last_supply_failed_reason = str(d.get("last_supply_failed_reason", ""))
	
func save_to_disk() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("RunState save failed: " + str(FileAccess.get_open_error()))
		return
	var json := JSON.stringify(to_save_dict())
	f.store_string(json)
	f.close()

func load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		load_from_save_dict(parsed)

func wipe_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func _dict_stringname_to_string(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[String(k)] = int(d[k])
	return out

func _dict_string_to_stringname_counts(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[StringName(str(k))] = int(d[k])
	return out

func reset_run() -> void:
	# Start a NEW campaign, but KEEP unlocked roster stable.

	# overworld
	# Give the new campaign a seed (optional). Using time is fine, but don't use 0.
	overworld_seed = int(Time.get_unix_time_from_system())
	overworld_current_node_id = -1
	overworld_cleared.clear()

	# mission
	mission_seed = 0
	mission_node_type = &""
	mission_difficulty = 1.0
	mission_node_id = -1

	# upgrades
	run_upgrades.clear()
	run_upgrade_counts.clear()

	# flags
	event_mode_enabled_next_mission = false
	event_id_next_mission = &""
	boss_mode_enabled_next_mission = false
	boss_defeated_this_run = false
	bomber_unlocked_this_run = false
	run_over = false

	# squad / recruits / permadeath reset (campaign-scoped)
	squad_scene_paths.clear()
	recruit_pool_paths.clear()
	recruited_scene_paths.clear()
	dead_scene_paths.clear()

	# ✅ DO NOT clear roster_scene_paths (this is your unlocked progression)
	# If this is the very first time ever and roster is empty, seed it once.
	seed_roster_if_empty()

	# Keep it clean + deterministic ordering in UI
	roster_scene_paths = roster_scene_paths.filter(func(p): return ResourceLoader.exists(p))
	roster_scene_paths.sort()

	# Recruit pool should be rebuilt from the (persistent) roster
	rebuild_recruit_pool()

	save_to_disk()

	
func seed_roster_if_empty() -> void:
	# If roster already exists, don't stomp it
	if not roster_scene_paths.is_empty():
		return

	var all: Array[String] = UnitRegistry.ALLY_PATHS.duplicate()
	all = all.filter(func(p): return ResourceLoader.exists(p))
	all.sort()

	# Deterministic shuffle based on overworld_seed (so "new run" can differ)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(overworld_seed) if overworld_seed != 0 else int(Time.get_unix_time_from_system())

	# Fisher–Yates shuffle
	for i in range(all.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := all[i]
		all[i] = all[j]
		all[j] = tmp

	# Take only first N
	var n = clamp(starting_roster_size, 1, all.size())
	roster_scene_paths.clear()
	for i in range(n):
		roster_scene_paths.append(all[i])

	# Build recruit pool from roster
	rebuild_recruit_pool()

	print("[RUNSTATE] Seeded START roster_scene_paths=", roster_scene_paths.size(),
		" recruit_pool_paths=", recruit_pool_paths.size())

func unlock_more_roster(count: int) -> Array[String]:
	var unlocked_now: Array[String] = []

	var all: Array[String] = UnitRegistry.ALLY_PATHS.duplicate()
	all = all.filter(func(p): return ResourceLoader.exists(p))
	all.sort()

	# Candidates = not already in roster, not dead
	var candidates: Array[String] = []
	for p in all:
		var sp := str(p)
		if roster_scene_paths.has(sp):
			continue
		if dead_scene_paths.has(sp):
			continue
		candidates.append(sp)

	if candidates.is_empty():
		return unlocked_now

	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_unix_time_from_system())

	for k in range(min(count, candidates.size())):
		var idx := rng.randi_range(0, candidates.size() - 1)
		var pick := candidates[idx]
		candidates.remove_at(idx)

		roster_scene_paths.append(pick)
		unlocked_now.append(pick)

	rebuild_recruit_pool()
	save_to_disk()
	return unlocked_now

func is_dead(path: String) -> bool:
	return dead_scene_paths.has(path)

func mark_dead(path: String) -> void:
	path = str(path)
	if path == "":
		return
	if dead_scene_paths.has(path):
		return

	dead_scene_paths.append(path)

	# Remove from this run only
	squad_scene_paths.erase(path)
	recruit_pool_paths.erase(path)
	recruited_scene_paths.erase(path)

func recruit_joined_team(path: String) -> void:
	# Called when a recruit is spawned on a map
	path = str(path)
	if path == "" or is_dead(path):
		return

	# Ensure it’s known to the run
	if not roster_scene_paths.has(path):
		roster_scene_paths.append(path)

	# Fill vacancies only (your “squad rebuilding”)
	if squad_scene_paths.size() < 3 and not squad_scene_paths.has(path): #squad size 3
		squad_scene_paths.append(path)

	# Make sure it’s not still considered recruitable
	recruit_pool_paths.erase(path)
	if not recruited_scene_paths.has(path):
		recruited_scene_paths.append(path)

func rebuild_recruit_pool() -> void:
	# (your existing logic, but also exclude dead)
	recruit_pool_paths.clear()

	var taken: Dictionary = {}
	for p in squad_scene_paths:
		taken[str(p)] = true
	for p in recruited_scene_paths:
		taken[str(p)] = true
	for p in dead_scene_paths:
		taken[str(p)] = true

	for p in roster_scene_paths:
		var sp := str(p)
		if not taken.has(sp):
			recruit_pool_paths.append(sp)
