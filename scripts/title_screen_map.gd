extends Node2D
class_name TitleScreenMapDecor

# -------------------------------------------------
# TITLESCREEN DECOR MAP
# - Generates terrain
# - Paints roads using: RoadsDL / RoadsDR / RoadsX
# - Spawns structures into "Structures"
# - NOTHING ELSE (no units, no turns, no UI, no input)
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

# Terrain tile SOURCE IDs (your TileSet source meaning)
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

const ROAD_SIZE := 2

# --- Nodes (match your tree) ---
@export var terrain_path: NodePath = NodePath("Terrain")
@export var roads_dl_path: NodePath = NodePath("RoadsDL")
@export var roads_dr_path: NodePath = NodePath("RoadsDR")
@export var roads_x_path: NodePath  = NodePath("RoadsX")
@export var structures_root_path: NodePath = NodePath("Structures")

@onready var terrain: TileMap = get_node_or_null(terrain_path) as TileMap
@onready var roads_dl: TileMap = get_node_or_null(roads_dl_path) as TileMap
@onready var roads_dr: TileMap = get_node_or_null(roads_dr_path) as TileMap
@onready var roads_x: TileMap  = get_node_or_null(roads_x_path) as TileMap
@onready var structures_root: Node2D = get_node_or_null(structures_root_path) as Node2D

# Road pixel offsets (keep your old defaults)
@export var road_pixel_offset_x := Vector2(0, 16)
@export var road_pixel_offset_dl := Vector2(0, 16)
@export var road_pixel_offset_dr := Vector2(0, 16)

@export var enable_roads := true

# Water blobs
@export var water_patch_count := 2
@export var water_patch_radius_min := 2
@export var water_patch_radius_max := 4
@export var water_noise := 0.35

# Structures
@export var building_scenes: Array[PackedScene] = []
@export var building_count_min := 6
@export var building_count_max := 12
@export var building_footprint := Vector2i(1, 1)
@export var avoid_roads := true
@export var avoid_water := true

# Optional unique scenes (each can appear once)
@export var unique_building_scenes: Array[PackedScene] = []
var _unique_used: Dictionary = {} # resource_path -> true

# Regenerate (optional, for title decor)
@export var regenerate_on_ready := true
@export var regen_key_enabled := true
@export var regen_key := KEY_R

var grid: GridData
var rng := RandomNumberGenerator.new()

# road_blocked: terrain-cell -> true
var road_blocked := {}
# structure_blocked: terrain-cell -> true
var structure_blocked := {}

func _ready() -> void:
	rng.randomize()
	if regenerate_on_ready:
		regenerate()

func _unhandled_input(event: InputEvent) -> void:
	if not regen_key_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == regen_key:
		regenerate()

# -------------------------------------------------
# Public
# -------------------------------------------------
func regenerate() -> void:
	if randomize_season_each_generation:
		season = SEASONS[rng.randi_range(0, SEASONS.size() - 1)]

	if grid == null:
		grid = GridData.new()
	grid.setup(map_width, map_height, T_DIRT)

	_clear_structures()
	generate_map()
	spawn_structures()

# -------------------------------------------------
# Map Generation
# -------------------------------------------------
func generate_map() -> void:
	if terrain == null:
		push_error("TitleScreenMapDecor: Terrain TileMap missing.")
		return

	_generate_base_terrain_only()

	if enable_roads:
		_add_roads()
	else:
		_clear_roads()

	_add_water_patches()
	_ensure_walkable_connected()
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

func _pick_land_tile_for_season_varied(_cell: Vector2i) -> int:
	var r := rng.randf()
	match season:
		Season.DIRT:
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
	return T_DIRT

func _is_walkable(c: Vector2i) -> bool:
	return grid.in_bounds(c) and grid.terrain[c.x][c.y] != T_WATER

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

func _pick_tile_for_season_no_water() -> int:
	match season:
		Season.DIRT: return T_DIRT
		Season.SANDSTONE: return T_SANDSTONE
		Season.SNOW: return T_SNOW
		Season.GRASS: return T_GRASS
		Season.ICE: return T_ICE
	return T_DIRT

func _dig_corridor(a: Vector2i, b: Vector2i) -> void:
	var c := a
	while c.x != b.x:
		if grid.terrain[c.x][c.y] == T_WATER:
			grid.terrain[c.x][c.y] = _pick_tile_for_season_no_water()
		c.x += (1 if b.x > c.x else -1)
	while c.y != b.y:
		if grid.terrain[c.x][c.y] == T_WATER:
			grid.terrain[c.x][c.y] = _pick_tile_for_season_no_water()
		c.y += (1 if b.y > c.y else -1)
	if grid.terrain[c.x][c.y] == T_WATER:
		grid.terrain[c.x][c.y] = _pick_tile_for_season_no_water()

func _ensure_walkable_connected() -> void:
	var start := _find_any_walkable_cell()
	if start.x < 0:
		var mid := Vector2i(map_width / 2, map_height / 2)
		grid.terrain[mid.x][mid.y] = _pick_tile_for_season_no_water()
		return

	var connected := _flood_fill_walkable(start)
	for x in range(map_width):
		for y in range(map_height):
			var c := Vector2i(x, y)
			if not _is_walkable(c): continue
			if connected.has(c): continue
			var target := _nearest_cell_in_set(c, connected)
			_dig_corridor(c, target)
			connected = _flood_fill_walkable(start)

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
				if not grid.in_bounds(c): continue
				if dx * dx + dy * dy > r * r: continue
				if rng.randf() < water_noise: continue
				if enable_roads and road_blocked.has(c): continue
				grid.terrain[x][y] = T_WATER

# -------------------------------------------------
# Roads
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
	rmap.position = terrain.position + (terrain_origin_local - roads_origin_local) + px_off
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

	var road_col := rng.randi_range(0, cols - 1)
	var road_row := rng.randi_range(0, rows - 1)

	var conn := {}

	for ry in range(rows):
		var rc := Vector2i(road_col, ry)
		conn[rc] = int(conn.get(rc, 0)) | 1
	for rx in range(cols):
		var rc := Vector2i(rx, road_row)
		conn[rc] = int(conn.get(rc, 0)) | 2

	# Optional extra road
	if rng.randf() < 0.5:
		var add_vertical := rng.randi_range(0, 1) == 0
		var min_sep := 3
		if add_vertical:
			var col2 := road_col
			var tries := 64
			while tries > 0 and abs(col2 - road_col) < min_sep:
				col2 = rng.randi_range(0, cols - 1)
				tries -= 1
			if abs(col2 - road_col) >= min_sep:
				for ry in range(rows):
					var rc2 := Vector2i(col2, ry)
					conn[rc2] = int(conn.get(rc2, 0)) | 1
		else:
			var row2 := road_row
			var tries := 64
			while tries > 0 and abs(row2 - road_row) < min_sep:
				row2 = rng.randi_range(0, rows - 1)
				tries -= 1
			if abs(row2 - road_row) >= min_sep:
				for rx in range(cols):
					var rc2 := Vector2i(rx, row2)
					conn[rc2] = int(conn.get(rc2, 0)) | 2

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
	var center_world := rmap.to_global(rmap.map_to_local(rc))
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
# Structures
# -------------------------------------------------
func spawn_structures() -> void:
	structure_blocked.clear()
	_unique_used.clear()

	if structures_root == null:
		structures_root = self

	_clear_structures()

	if building_scenes.is_empty():
		return

	var size := building_footprint
	var candidates: Array[Vector2i] = []
	for x in range(map_width - size.x + 1):
		for y in range(map_height - size.y + 1):
			var origin := Vector2i(x, y)
			if _is_structure_origin_ok(origin, size):
				candidates.append(origin)
	candidates.shuffle()

	var target_count := rng.randi_range(building_count_min, building_count_max)

	var placed := 0
	var tries := 0
	while placed < target_count and tries < 5000 and not candidates.is_empty():
		tries += 1
		var origin: Vector2i = candidates.pop_back()
		if _is_structure_blocked(origin, size):
			continue

		var scene: PackedScene = _pick_building_scene()
		if scene == null:
			continue

		var inst := scene.instantiate()
		var b := inst as Node2D
		if b == null:
			continue

		b.add_to_group("Structures")
		structures_root.add_child(b)

		if b.has_method("set_origin"):
			b.call("set_origin", origin, terrain)
		else:
			b.global_position = terrain.to_global(terrain.map_to_local(origin))

		_mark_structure_blocked(origin, size)

		if _is_unique_scene(scene):
			_unique_used[_scene_key(scene)] = true

		placed += 1

func _pick_building_scene() -> PackedScene:
	var pick_tries := 32
	while pick_tries > 0:
		pick_tries -= 1
		var s := building_scenes[rng.randi_range(0, building_scenes.size() - 1)]
		if s == null:
			continue
		if _is_unique_scene(s) and _unique_used.has(_scene_key(s)):
			continue
		return s
	return null

func _is_structure_origin_ok(origin: Vector2i, size: Vector2i) -> bool:
	if origin.x < 0 or origin.y < 0: return false
	if origin.x + size.x - 1 >= map_width: return false
	if origin.y + size.y - 1 >= map_height: return false

	for dx in range(size.x):
		for dy in range(size.y):
			var c := origin + Vector2i(dx, dy)
			if not grid.in_bounds(c): return false
			if avoid_water and grid.terrain[c.x][c.y] == T_WATER: return false
			if avoid_roads and _cell_has_road(c): return false
			if structure_blocked.has(c): return false
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
			structure_blocked[origin + Vector2i(dx, dy)] = true

func _scene_key(scene: PackedScene) -> String:
	return "" if scene == null else scene.resource_path

func _is_unique_scene(scene: PackedScene) -> bool:
	if scene == null:
		return false
	if unique_building_scenes.has(scene):
		return true
	var key := _scene_key(scene)
	for s in unique_building_scenes:
		if s != null and s.resource_path == key:
			return true
	return false

func _clear_structures() -> void:
	if structures_root == null:
		return
	for ch in structures_root.get_children():
		ch.queue_free()
