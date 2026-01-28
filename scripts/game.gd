extends Node2D
class_name Game

@export var camera: Camera2D
@export var fade_rect_path: NodePath
@export var fade_out_time := 0.88
@export var fade_in_time := 0.88
@export var fade_hold_time := 0.02

var _fade_rect: ColorRect
var _regen_in_progress := false

# -------------------------------------------------
# MAP + ROADS + STRUCTURES ONLY
# - Generates terrain
# - Paints roads using: RoadsDL / RoadsDR / RoadsX
# - Spawns structures into "Structures"
# - Stops there (no turns, no units, no UI, no input)
# -------------------------------------------------

enum Season { DIRT, SANDSTONE, SNOW, GRASS, ICE }

@export var map_width := 16
@export var map_height := 16
@export var season: Season = Season.GRASS

@export var randomize_season_each_generation := true

const SEASONS := [
	Season.DIRT,
	Season.SANDSTONE,
	Season.SNOW,
	Season.GRASS,
	Season.ICE
]

# Terrain tile SOURCE IDs (your TileSet source ids)
const T_DIRT := 0
const T_SANDSTONE := 1
const T_SNOW := 2
const T_GRASS := 3
const T_ICE := 4
const T_WATER := 5

const LAYER_TERRAIN := 0

# Roads (tile SOURCE IDs in the road tileset)
const ROAD_INTERSECTION := 6
const ROAD_DOWN_LEFT := 7
const ROAD_DOWN_RIGHT := 8
const ROAD_ATLAS := Vector2i(0, 0)

# Road-grid assumptions from your old code:
# - 64x64 roads cover about 2x2 of your 32x32 terrain cells
const ROAD_SIZE := 2

# --- Nodes (match your tree) ---
@onready var terrain: TileMap = $Terrain
@onready var roads_dl: TileMap = $RoadsDL
@onready var roads_dr: TileMap = $RoadsDR
@onready var roads_x: TileMap = $RoadsX
@onready var structures_root: Node2D = get_node_or_null("Structures") as Node2D

# Road pixel offsets (keep your old defaults)
@export var road_pixel_offset_x := Vector2(0, 16)
@export var road_pixel_offset_dl := Vector2(0, 16)
@export var road_pixel_offset_dr := Vector2(0, 16)

@export var enable_roads := true

# Water blobs (simple)
@export var water_patch_count := 2
@export var water_patch_radius_min := 2
@export var water_patch_radius_max := 4
@export var water_noise := 0.35

# Structures
@export var building_scenes: Array[PackedScene] = []
@export var building_count := 6
@export var building_footprint := Vector2i(1, 1)
@export var avoid_roads := true
@export var avoid_water := true

# ✅ Add: put your Tower / Stadium / District scenes here (each can spawn max once)
@export var unique_building_scenes: Array[PackedScene] = []

var _unique_used: Dictionary = {} # scene_key -> true

var grid: GridData
var rng := RandomNumberGenerator.new()

# road_blocked: terrain-cell -> true (so we can avoid placing buildings on roads)
var road_blocked := {}
# structure_blocked: terrain-cell -> true
var structure_blocked := {}

@onready var units_root: Node2D = get_node("Units") as Node2D
@onready var overlays_root: Node2D = get_node("Overlays") as Node2D
@onready var map_controller: MapController = get_node("MapController") as MapController

@onready var turn_manager: TurnManager = get_node_or_null("TurnManager") as TurnManager

var _start_max_zombies := 0

@export var drops_root_path: NodePath
@onready var drops_root: Node = get_node_or_null(drops_root_path)

@export var tutorial_manager_path: NodePath
@onready var tutorial_manager := get_node_or_null(tutorial_manager_path)


func add_upgrade(id: StringName) -> void:
	RunStateNode.add_upgrade(id)

func has_upgrade(id: StringName) -> bool:
	return RunStateNode.has_upgrade(id)

func clear_upgrades() -> void:
	RunStateNode.clear()

func _ready() -> void:
	_fade_rect = get_node_or_null(fade_rect_path) as ColorRect
	if _fade_rect != null:
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade_rect.visible = true
		var c := _fade_rect.color
		c.a = 1.0 # start black
		_fade_rect.color = c

	# build the map normally (no fades inside)
	_start_max_zombies = map_controller.max_zombies
	rng.randomize()
	if randomize_season_each_generation:
		season = SEASONS[rng.randi_range(0, SEASONS.size() - 1)]

	grid = GridData.new()
	grid.setup(map_width, map_height, T_DIRT)

	generate_map()
	spawn_structures()

	map_controller.terrain_path = terrain.get_path()
	map_controller.units_root_path = units_root.get_path()
	map_controller.overlay_root_path = overlays_root.get_path()
	map_controller.setup(self)

	# NEW: apply chosen squad from RunState autoload (if any)
	var rs := _rs()
	if rs != null and rs.has_method("has_squad") and rs.call("has_squad"):
		var chosen: Array[PackedScene] = rs.call("get_squad_packed_scenes")
		if not chosen.is_empty():
			map_controller.ally_scenes = chosen

	map_controller.spawn_units()


	if turn_manager != null:
		turn_manager.on_units_spawned()

	# now reveal the scene
	await get_tree().process_frame
	await _fade_to(0.0, fade_in_time)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			map_controller.max_zombies = _start_max_zombies
			await regenerate_map_faded()

		if event.keycode == KEY_1:
			map_controller.satellite_sweep()		

func _fade_alpha() -> float:
	if _fade_rect == null or not is_instance_valid(_fade_rect):
		return 0.0
	return clampf(_fade_rect.color.a, 0.0, 1.0)


func _is_faded_out() -> bool:
	# black
	return _fade_alpha() >= 0.99


func _is_faded_in() -> bool:
	# transparent
	return _fade_alpha() <= 0.01

func regenerate_map() -> void:
	camera.follow_enabled = true	
	camera.global_position.y -= 520
	
	# apply chosen squad from RunState autoload (if any)
	var rs := _rs()
	if rs != null and rs.has_method("has_squad") and rs.call("has_squad"):
		var chosen: Array[PackedScene] = rs.call("get_squad_packed_scenes")
		if not chosen.is_empty():
			map_controller.ally_scenes = chosen
				
	# sync recruit pool from RunState (non-selected only)
	if rs != null:
		map_controller.apply_recruit_pool_from_runstate(rs)
		
	map_controller._recruits_spawned_at.clear()
	map_controller.reset_recruit_pool()
		
	map_controller.reset_for_regen()
	
	rng.randomize()
	if randomize_season_each_generation:
		season = SEASONS[rng.randi_range(0, SEASONS.size() - 1)]

	if grid == null:
		grid = GridData.new()
	grid.setup(map_width, map_height, T_DIRT)

	generate_map()
	spawn_structures()

	map_controller.setup(self)
	map_controller.spawn_units()

	if turn_manager != null and is_instance_valid(turn_manager):
		turn_manager.on_units_spawned()

func regenerate_map_faded() -> void:
	if _regen_in_progress:
		return
	_regen_in_progress = true

	# Ensure fade rect is click-through no matter what
	if _fade_rect != null and is_instance_valid(_fade_rect):
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 1) If we're currently visible, fade OUT to black first
	if not _is_faded_out():
		await _fade_to(1.0, fade_out_time)

	if fade_hold_time > 0.0:
		await get_tree().create_timer(fade_hold_time).timeout

	# 2) Do the work while black
	regenerate_map()

	# let visuals apply
	await get_tree().process_frame

	# 3) Fade IN back to gameplay
	await _fade_to(0.0, fade_in_time)

	_regen_in_progress = false

func _fade_to(target_alpha: float, seconds: float) -> void:
	if _fade_rect == null or not is_instance_valid(_fade_rect):
		# no fade node wired, just skip
		return

	_fade_rect.visible = true

	# Kill old tween if you spam R
	var tw := get_tree().create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	var c := _fade_rect.color
	c.a = clampf(c.a, 0.0, 1.0)
	_fade_rect.color = c

	tw.tween_property(_fade_rect, "color:a", clampf(target_alpha, 0.0, 1.0), max(seconds, 0.001))

	await tw.finished

	# hide when fully transparent
	if target_alpha <= 0.001:
		_fade_rect.visible = false

# -------------------------------------------------
# Map Generation (terrain only)
# -------------------------------------------------
func generate_map() -> void:
	if terrain == null or not is_instance_valid(terrain):
		push_error("Terrain TileMap missing.")
		return

	# 1) Base terrain only (no water yet)
	_generate_base_terrain_only()

	# 2) Roads first (so we can protect them)
	if enable_roads:
		_add_roads() # this also rebuilds road_blocked
	else:
		_clear_roads()

	# 3) Water blobs (never on roads)
	_add_water_patches()

	# 4) Ensure connected land (may dig corridors; keeps roads intact)
	_ensure_walkable_connected()

	# 5) Paint final terrain
	_paint_terrain()

func _paint_terrain() -> void:
	terrain.clear()
	for x in range(map_width):
		for y in range(map_height):
			terrain.set_cell(LAYER_TERRAIN, Vector2i(x, y), grid.terrain[x][y], Vector2i.ZERO, 0)

func _generate_base_terrain_only() -> void:
	for x in range(map_width):
		for y in range(map_height):
			grid.terrain[x][y] = _pick_land_tile_for_season_varied(Vector2i(x, y))

func _pick_land_tile_for_season_varied(cell: Vector2i) -> int:
	# Pick a LAND tile (never water) with a season-themed bias + some variation.
	# Tweak weights to taste.

	var r := rng.randf()

	match season:
		Season.DIRT:
			# mostly dirt, some grass/sand/ice/snow as spice
			if r < 0.70: return T_DIRT
			elif r < 0.82: return T_GRASS
			elif r < 0.92: return T_SANDSTONE
			elif r < 0.97: return T_ICE
			else: return T_SNOW

		Season.SANDSTONE:
			if r < 0.70: return T_SANDSTONE
			elif r < 0.82: return T_DIRT
			elif r < 0.92: return T_GRASS
			elif r < 0.97: return T_ICE
			else: return T_SNOW

		Season.SNOW:
			if r < 0.70: return T_SNOW
			elif r < 0.82: return T_ICE
			elif r < 0.90: return T_DIRT
			elif r < 0.97: return T_GRASS
			else: return T_SANDSTONE

		Season.GRASS:
			if r < 0.70: return T_GRASS
			elif r < 0.82: return T_DIRT
			elif r < 0.92: return T_SANDSTONE
			elif r < 0.97: return T_ICE
			else: return T_SNOW

		Season.ICE:
			if r < 0.70: return T_ICE
			elif r < 0.82: return T_SNOW
			elif r < 0.90: return T_DIRT
			elif r < 0.97: return T_GRASS
			else: return T_SANDSTONE

	# fallback (never water)
	return T_DIRT

func _is_walkable(c: Vector2i) -> bool:
	return grid.in_bounds(c) and grid.terrain[c.x][c.y] != T_WATER

func _ensure_walkable_connected() -> void:
	# Find any walkable start
	var start := _find_any_walkable_cell()
	if start.x < 0:
		# all water; force at least one land tile
		var mid := Vector2i(map_width / 2, map_height / 2)
		grid.terrain[mid.x][mid.y] = _pick_tile_for_season_no_water()
		return

	var connected := _flood_fill_walkable(start)

	# For every walkable cell not in the connected set, dig a corridor to the connected region.
	for x in range(map_width):
		for y in range(map_height):
			var c := Vector2i(x, y)
			if not _is_walkable(c):
				continue
			if connected.has(c):
				continue

			# connect this isolated land to the existing connected region
			var target := _nearest_cell_in_set(c, connected)
			_dig_corridor(c, target)

			# refresh connected set after digging
			connected = _flood_fill_walkable(start)

func _find_any_walkable_cell() -> Vector2i:
	for x in range(map_width):
		for y in range(map_height):
			if grid.terrain[x][y] != T_WATER:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func _flood_fill_walkable(start: Vector2i) -> Dictionary:
	var visited: Dictionary = {}
	var stack: Array[Vector2i] = [start]
	visited[start] = true

	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var n = c + d
			if not _is_walkable(n):
				continue
			if visited.has(n):
				continue
			visited[n] = true
			stack.append(n)

	return visited

func _nearest_cell_in_set(from_cell: Vector2i, s: Dictionary) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1_000_000

	for k in s.keys():
		var c := k as Vector2i
		var d = abs(from_cell.x - c.x) + abs(from_cell.y - c.y)
		if d < best_d:
			best_d = d
			best = c

	return best

func _dig_corridor(a: Vector2i, b: Vector2i) -> void:
	# Dig a simple Manhattan corridor a->b, turning water into land.
	# (keeps it deterministic + fast)
	var c := a

	# horizontal
	while c.x != b.x:
		if grid.terrain[c.x][c.y] == T_WATER:
			grid.terrain[c.x][c.y] = _pick_tile_for_season_no_water()
		c.x += (1 if b.x > c.x else -1)

	# vertical
	while c.y != b.y:
		if grid.terrain[c.x][c.y] == T_WATER:
			grid.terrain[c.x][c.y] = _pick_tile_for_season_no_water()
		c.y += (1 if b.y > c.y else -1)

	# ensure end too
	if grid.terrain[c.x][c.y] == T_WATER:
		grid.terrain[c.x][c.y] = _pick_tile_for_season_no_water()

# -------------------------------------------------
# Terrain helpers
# -------------------------------------------------
func _pick_tile_for_season_no_water() -> int:
	# Base land tile used for corridor digging / repairs (never water)
	match season:
		Season.DIRT: return T_DIRT
		Season.SANDSTONE: return T_SANDSTONE
		Season.SNOW: return T_SNOW
		Season.GRASS: return T_GRASS
		Season.ICE: return T_ICE
	return T_DIRT

func _add_water_patches() -> void:
	if water_patch_count <= 0:
		return

	for i in range(water_patch_count):
		var cx := rng.randi_range(1, map_width - 2)
		var cy := rng.randi_range(1, map_height - 2)
		var r := rng.randi_range(water_patch_radius_min, water_patch_radius_max)

		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var x := cx + dx
				var y := cy + dy
				var c := Vector2i(x, y)

				if not grid.in_bounds(c):
					continue
				if dx * dx + dy * dy > r * r:
					continue
				if rng.randf() < water_noise:
					continue

				# ✅ NEW: never place water on road-covered terrain cells
				if enable_roads and road_blocked.has(c):
					continue

				grid.terrain[x][y] = T_WATER

# -------------------------------------------------
# Roads (3 TileMaps: DL / DR / X)
# -------------------------------------------------
func _clear_roads() -> void:
	if roads_dl: roads_dl.clear()
	if roads_dr: roads_dr.clear()
	if roads_x:  roads_x.clear()
	road_blocked.clear()

func _sync_roads_transform() -> void:
	_sync_one_roads_transform(roads_dl, road_pixel_offset_dl)
	_sync_one_roads_transform(roads_dr, road_pixel_offset_dr)
	_sync_one_roads_transform(roads_x,  road_pixel_offset_x)

func _sync_one_roads_transform(rmap: TileMap, px_off: Vector2) -> void:
	if rmap == null or terrain == null:
		return

	var terrain_origin_local := terrain.map_to_local(Vector2i.ZERO)
	var roads_origin_local := rmap.map_to_local(Vector2i.ZERO)

	# Keep roads aligned to terrain origin + your tweak offset
	rmap.position = terrain.position + (terrain_origin_local - roads_origin_local) + px_off

	# keep roads at a stable draw order
	rmap.z_as_relative = false
	rmap.z_index = 0

func _add_roads() -> void:
	if roads_dl == null or roads_dr == null or roads_x == null:
		return

	roads_dl.clear()
	roads_dr.clear()
	roads_x.clear()
	road_blocked.clear()

	_sync_roads_transform()

	var cols := int(map_width / ROAD_SIZE) * 2 - 1
	var rows := int(map_height / ROAD_SIZE) * 2 - 1
	if cols <= 0 or rows <= 0:
		return

	var margin := 0
	var road_col := rng.randi_range(margin, cols - 1 - margin)
	var road_row := rng.randi_range(margin, rows - 1 - margin)

	var conn := {}

	# main vertical lane
	for ry in range(rows):
		var rc := Vector2i(road_col, ry)
		conn[rc] = int(conn.get(rc, 0)) | 1

	# main horizontal lane
	for rx in range(cols):
		var rc := Vector2i(rx, road_row)
		conn[rc] = int(conn.get(rc, 0)) | 2

	# -----------------------------------------
	# EXTRA ROAD: 50% chance, separated by >= 3 tiles
	# -----------------------------------------
	if rng.randf() < 0.5:
		var add_vertical := rng.randi_range(0, 1) == 0
		var min_sep := 3

		if add_vertical:
			var col2 := road_col
			var tries := 64
			while tries > 0 and abs(col2 - road_col) < min_sep:
				col2 = rng.randi_range(margin, cols - 1 - margin)
				tries -= 1

			# only add if we actually found a far-enough column
			if abs(col2 - road_col) >= min_sep:
				for ry in range(rows):
					var rc2 := Vector2i(col2, ry)
					conn[rc2] = int(conn.get(rc2, 0)) | 1
		else:
			var row2 := road_row
			var tries := 64
			while tries > 0 and abs(row2 - road_row) < min_sep:
				row2 = rng.randi_range(margin, rows - 1 - margin)
				tries -= 1

			if abs(row2 - road_row) >= min_sep:
				for rx in range(cols):
					var rc2 := Vector2i(rx, row2)
					conn[rc2] = int(conn.get(rc2, 0)) | 2

	# paint tiles into the 3 maps
	for rc in conn.keys():
		var mask := int(conn[rc])
		if mask == 3:
			roads_x.set_cell(0, rc, ROAD_INTERSECTION, ROAD_ATLAS, 0)
		elif mask == 1:
			roads_dl.set_cell(0, rc, ROAD_DOWN_LEFT, ROAD_ATLAS, 0)
		elif mask == 2:
			roads_dr.set_cell(0, rc, ROAD_DOWN_RIGHT, ROAD_ATLAS, 0)

	_rebuild_road_blocked()

func _rebuild_road_blocked() -> void:
	road_blocked.clear()
	if terrain == null:
		return

	var road_maps: Array[TileMap] = [roads_dl, roads_dr, roads_x]
	for rmap in road_maps:
		if rmap == null:
			continue
		for rc in rmap.get_used_cells(0):
			_mark_terrain_cells_covered_by_road_tile(rmap, rc)

func _mark_terrain_cells_covered_by_road_tile(rmap: TileMap, rc: Vector2i) -> void:
	# Roads are 64x64 and terrain is 32x32 -> one road cell covers ~2x2 terrain cells.
	# Use multiple samples across the road tile area so offsets can't cause misses.

	var center_world := rmap.to_global(rmap.map_to_local(rc))

	# sample a 3x3 grid of points across the road tile (more robust than 4 corners)
	var offsets := [-24.0, 0.0, 24.0]
	for ox in offsets:
		for oy in offsets:
			var wp := center_world + Vector2(ox, oy)
			var tc := terrain.local_to_map(terrain.to_local(wp))
			if grid.in_bounds(tc):
				road_blocked[tc] = true

func _cell_has_road(c: Vector2i) -> bool:
	return road_blocked.has(c)

# -------------------------------------------------
# Structures (placement only)
# -------------------------------------------------
func spawn_structures() -> void:
	structure_blocked.clear()
	_unique_used.clear() # ✅ reset per regen

	if structures_root == null:
		structures_root = self

	for ch in structures_root.get_children():
		ch.queue_free()

	if building_scenes == null or building_scenes.is_empty():
		return

	var size := building_footprint
	var candidates: Array[Vector2i] = []

	for x in range(map_width - size.x + 1):
		for y in range(map_height - size.y + 1):
			var origin := Vector2i(x, y)
			if _is_structure_origin_ok(origin, size):
				candidates.append(origin)

	candidates.shuffle()

	building_count = rng.randi_range(6, 12)

	var placed := 0
	var tries := 0
	while placed < building_count and tries < 5000 and not candidates.is_empty():
		tries += 1
		var origin: Vector2i = candidates.pop_back()

		if _is_structure_blocked(origin, size):
			continue

		# ✅ pick a scene that respects "unique once"
		var scene: PackedScene = null
		var pick_tries := 32
		while pick_tries > 0:
			pick_tries -= 1
			var s := building_scenes[rng.randi_range(0, building_scenes.size() - 1)]
			if s == null:
				continue

			if _is_unique_scene(s):
				var key := _scene_key(s)
				if _unique_used.has(key):
					continue # already placed once
				scene = s
				break
			else:
				scene = s
				break

		if scene == null:
			continue

		var inst = scene.instantiate()
		var b := inst as Node2D
		if b == null:
			continue

		b.add_to_group("Structures")
		structures_root.add_child(b)
		
		_tint_structure(b, rng)

		if b.has_method("set_origin"):
			b.call("set_origin", origin, terrain)
		else:
			b.global_position = terrain.to_global(terrain.map_to_local(origin))

		_mark_structure_blocked(origin, size)

		# ✅ mark unique as used AFTER successful placement
		if _is_unique_scene(scene):
			_unique_used[_scene_key(scene)] = true

		placed += 1

# ✅ give every spawned structure a slightly different color tint
func _tint_structure(root: Node, rng: RandomNumberGenerator) -> void:
	# Subtle variation range (tweak)
	var hue_shift := rng.randf_range(-0.06, 0.06)   # small hue wobble
	var sat_mul   := rng.randf_range(0.90, 1.10)   # tiny saturation
	var val_mul   := rng.randf_range(0.90, 1.12)   # tiny brightness

	# Start from white (no tint), then generate a mild color
	var base := Color.from_hsv(0.10 + hue_shift, 0.35 * sat_mul, 1.0 * val_mul, 1.0)

	# Prefer tinting actual visual nodes (safer than tinting the whole root)
	var applied := false

	# If the structure itself is a CanvasItem (Node2D is), this works,
	# but it will tint EVERYTHING under it (including labels, shadows, etc.)
	# so we try children first.
	for n in root.get_children():
		if n is Sprite2D:
			(n as Sprite2D).self_modulate = base
			applied = true
		elif n is AnimatedSprite2D:
			(n as AnimatedSprite2D).self_modulate = base
			applied = true

	# If no direct children matched, walk deeper and tint any sprites we find.
	if not applied:
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var cur = stack.pop_back()
			for c in cur.get_children():
				if c is Sprite2D:
					(c as Sprite2D).self_modulate = base
					applied = true
				elif c is AnimatedSprite2D:
					(c as AnimatedSprite2D).self_modulate = base
					applied = true
				stack.append(c)

	# Fallback: tint the whole structure root (useful if your art is one sprite anyway)
	if not applied and root is CanvasItem:
		(root as CanvasItem).self_modulate = base

func _is_structure_origin_ok(origin: Vector2i, size: Vector2i) -> bool:
	# footprint in bounds
	if origin.x < 0 or origin.y < 0:
		return false
	if origin.x + size.x - 1 >= map_width:
		return false
	if origin.y + size.y - 1 >= map_height:
		return false

	# check footprint cells
	for dx in range(size.x):
		for dy in range(size.y):
			var c := origin + Vector2i(dx, dy)
			if not grid.in_bounds(c):
				return false

			if avoid_water and grid.terrain[c.x][c.y] == T_WATER:
				return false

			if avoid_roads and _cell_has_road(c):
				return false

			if structure_blocked.has(c):
				return false

	return true

func _is_structure_blocked(origin: Vector2i, size: Vector2i) -> bool:
	for dx in range(size.x):
		for dy in range(size.y):
			var c := origin + Vector2i(dx, dy)
			if structure_blocked.has(c):
				return true
	return false

func _mark_structure_blocked(origin: Vector2i, size: Vector2i) -> void:
	for dx in range(size.x):
		for dy in range(size.y):
			var c := origin + Vector2i(dx, dy)
			structure_blocked[c] = true

func _scene_key(scene: PackedScene) -> String:
	if scene == null:
		return ""
	# resource_path is stable + unique for a scene file
	return scene.resource_path

func _is_unique_scene(scene: PackedScene) -> bool:
	if scene == null:
		return false
	# membership check (fast)
	if unique_building_scenes.has(scene):
		return true
	# fallback: compare by path in case of different PackedScene instances
	var key := _scene_key(scene)
	for s in unique_building_scenes:
		if s != null and s.resource_path == key:
			return true
	return false

func _clear_drops() -> void:
	# Kill any nodes in the Drops group (anywhere)
	for n in get_tree().get_nodes_in_group("Drops"):
		if n != null and is_instance_valid(n):
			n.queue_free()

	# If you also keep a dedicated Drops parent, clear its children too (belt+suspenders)
	if drops_root != null and is_instance_valid(drops_root):
		for ch in drops_root.get_children():
			ch.queue_free()

	# Clear any logical maps in MapController if they exist
	if map_controller != null and is_instance_valid(map_controller):
		if "drops_by_cell" in map_controller:
			map_controller.drops_by_cell.clear()
		if "mines_by_cell" in map_controller:
			map_controller.mines_by_cell.clear()

func _rs() -> Node:
	# IMPORTANT: replace "RunStateNode" / "RunState" with your ACTUAL autoload name if different.
	var r := get_tree().root
	var rs := r.get_node_or_null("RunStateNode")
	if rs != null:
		return rs
	rs = r.get_node_or_null("RunState")
	if rs != null:
		return rs
	return null
