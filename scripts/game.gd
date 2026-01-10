extends Node2D

# IMPORTANT:
# - map_width/map_height are in GRID CELLS (your 16x16 logical map)
# - each cell is one tile in the TileMap (your tiles are 32x32 pixels in the TileSet)
@export var map_width := 16
@export var map_height := 16

# Terrain IDs (also TileSet SOURCE IDs) for Terrain TileMap
const T_DIRT := 0
const T_SANDSTONE := 1
const T_SNOW := 2
const T_GRASS := 3
const T_ICE := 4
const T_WATER := 5

const LAYER_TERRAIN := 0

# --- Highlight overlay (hover/selection) ---
@onready var highlight: TileMap = $Highlight
const LAYER_HIGHLIGHT := 0
const HOVER_TILE_SMALL_SOURCE_ID := 99   # 1x1 hover tile source id
const HOVER_TILE_BIG_SOURCE_ID := 100    # 2x2 hover tile source id
const HOVER_ATLAS := Vector2i(0, 0)

# --- Movement overlay ---
@onready var move_range: TileMap = $MoveRange
const LAYER_MOVE := 0
const MOVE_TILE_SMALL_SOURCE_ID := 0     # 1x1 move tile source id
const MOVE_TILE_BIG_SOURCE_ID := 1       # 2x2 move tile source id
const MOVE_ATLAS := Vector2i(0, 0)

# --- Attack overlay ---
@onready var attack_range: TileMap = $AttackRange
const LAYER_ATTACK := 0
const ATTACK_TILE_SMALL_SOURCE_ID := 0   # set these to your attack tile sources
const ATTACK_TILE_BIG_SOURCE_ID := 1
const ATTACK_ATLAS := Vector2i(0, 0)

enum Season { DIRT, SANDSTONE, SNOW, GRASS, ICE }
@export var season: Season = Season.GRASS
@export_range(0.0, 1.0, 0.05) var season_strength := 0.75

@export_range(0.0, 0.6, 0.01) var target_water := 0.15
@export_range(1, 20, 1) var water_blobs := 3
@export_range(2, 40, 1) var blob_steps := 10
@export_range(0.0, 1.0, 0.05) var freeze_water_chance := 0.65
@export_range(0, 2000, 1) var max_fix_iterations := 500
@export_range(0, 999999, 1) var map_seed := 0

# Spawning
@export var human_count := 3
@export var mech_count := 2
@export var human_scene: PackedScene
@export var mech_scene: PackedScene

@onready var terrain: TileMap = $Terrain
@onready var units_root: Node2D = $Units

var grid := GridData.new()
var rng := RandomNumberGenerator.new()

# Keep origins for later (selection/highlight will use this later)
var unit_origin := {} # Dictionary: Unit -> Vector2i

var selected_unit: Unit = null
var hovered_unit: Unit = null

# Mouse / move helpers
var hovered_cell: Vector2i = Vector2i(-1, -1)
var reachable_set := {} # Dictionary used like a Set: cell -> true

var move_tween: Tween = null
var is_moving_unit := false
var is_attacking_unit := false

# --- Overlay pixel offsets (match your cursor offsets) ---
@export var hover_offset_1x1 := Vector2(0, 0)
@export var hover_offset_2x2 := Vector2(0, 16)

@export var move_offset_1x1 := Vector2(0, 0)
@export var move_offset_2x2 := Vector2(0, 16)

@export var attack_offset_1x1 := Vector2(0, 0)
@export var attack_offset_2x2 := Vector2(0, 0)

var attackable_set := {}  # Dictionary[Vector2i, bool]

func _unit_sprite(u: Unit) -> AnimatedSprite2D:
	if u == null:
		return null
	# Change this path if your sprite is named differently
	if u.has_node("AnimatedSprite2D"):
		return u.get_node("AnimatedSprite2D") as AnimatedSprite2D
	return null

func _play_anim(u: Unit, anim_name: StringName) -> void:
	var spr := _unit_sprite(u)
	if spr == null:
		return
	if spr.sprite_frames != null and spr.sprite_frames.has_animation(anim_name):
		spr.play(anim_name)

func _play_idle(u: Unit) -> void:
	var spr := _unit_sprite(u)
	if spr == null:
		return
	if spr.sprite_frames != null and spr.sprite_frames.has_animation("idle"):
		spr.play("idle")
	else:
		spr.stop()

func _ready() -> void:
	_seed_rng()

	# GridData should be 16x16 here
	grid.setup(map_width, map_height)

	generate_map()
	terrain.update_internals()
	spawn_units()


func _process(_delta: float) -> void:
	_update_hovered_cell()
	_update_hovered_unit()


func _seed_rng() -> void:
	if map_seed == 0:
		rng.randomize()
	else:
		rng.seed = map_seed


# -----------------------
# Mouse -> map helpers
# -----------------------
func _update_hovered_cell() -> void:
	var mouse_global := get_global_mouse_position()
	var local_in_terrain := terrain.to_local(mouse_global)
	hovered_cell = terrain.local_to_map(local_in_terrain)

func _update_hovered_unit() -> void:
	var u := unit_at_cell(hovered_cell)
	set_hovered_unit(u)


# -----------------------
# Terrain placement (ID-only)
# -----------------------
func set_tile_id(cell: Vector2i, tile_id: int) -> void:
	if tile_id < 0 or tile_id > 5:
		terrain.set_cell(LAYER_TERRAIN, cell, -1, Vector2i(-1, -1), -1)
		return
	terrain.set_cell(LAYER_TERRAIN, cell, tile_id, Vector2i(0, 0), 0)


func season_main_tile() -> int:
	match season:
		Season.DIRT: return T_DIRT
		Season.SANDSTONE: return T_SANDSTONE
		Season.SNOW: return T_SNOW
		Season.GRASS: return T_GRASS
		Season.ICE: return T_ICE
	return T_GRASS


func pick_tile_for_season_no_water() -> int:
	var main := season_main_tile()
	if rng.randf() < season_strength:
		return main

	# less random: bias toward "similar" tiles instead of any tile
	match main:
		T_GRASS:
			return (T_DIRT if rng.randf() < 0.7 else T_SANDSTONE)
		T_DIRT:
			return (T_GRASS if rng.randf() < 0.6 else T_SANDSTONE)
		T_SANDSTONE:
			return (T_DIRT if rng.randf() < 0.7 else T_GRASS)
		T_SNOW:
			return (T_ICE if rng.randf() < 0.7 else T_GRASS)
		T_ICE:
			return (T_SNOW if rng.randf() < 0.7 else T_WATER) # note: you later add water anyway
	return main


func _neighbors8(c: Vector2i) -> Array[Vector2i]:
	return [
		c + Vector2i(1, 0),  c + Vector2i(-1, 0),
		c + Vector2i(0, 1),  c + Vector2i(0, -1),
		c + Vector2i(1, 1),  c + Vector2i(1, -1),
		c + Vector2i(-1, 1), c + Vector2i(-1, -1),
	]


func _smooth_terrain(passes: int, keep_main_bias := true) -> void:
	var main := season_main_tile()

	for _p in range(passes):
		var next := []
		next.resize(map_width)
		for x in range(map_width):
			next[x] = []
			next[x].resize(map_height)

		for x in range(map_width):
			for y in range(map_height):
				var c := Vector2i(x, y)

				# don't smooth water here; your water system already handles it
				if grid.terrain[x][y] == T_WATER:
					next[x][y] = T_WATER
					continue

				var counts := {}
				for nb in _neighbors8(c):
					if not _in_bounds(nb):
						continue
					var tid = grid.terrain[nb.x][nb.y]
					if tid == T_WATER:
						continue
					counts[tid] = (counts.get(tid, 0) + 1)

				# pick majority neighbor tile
				var best_tid = grid.terrain[x][y]
				var best_n := -1
				for tid in counts.keys():
					var n = counts[tid]
					if n > best_n:
						best_n = n
						best_tid = tid

				# optional: gently bias back toward the season main tile
				if keep_main_bias and rng.randf() < 0.08:
					best_tid = main

				next[x][y] = best_tid

		# commit
		for x in range(map_width):
			for y in range(map_height):
				grid.terrain[x][y] = next[x][y]


func generate_map() -> void:
	_seed_rng()

	for x in range(map_width):
		for y in range(map_height):
			grid.terrain[x][y] = pick_tile_for_season_no_water()

	_smooth_terrain(3)
	_add_water_blobs()
	_ensure_walkable_connected()
	_remove_dead_ends()

	for x in range(map_width):
		for y in range(map_height):
			set_tile_id(Vector2i(x, y), grid.terrain[x][y])


# -----------------------
# Units: spawning
# -----------------------
func spawn_units() -> void:
	if human_scene == null or mech_scene == null:
		push_warning("Assign human_scene and mech_scene in the Inspector.")
		return

	for child in units_root.get_children():
		child.queue_free()
	grid.occupied.clear()
	unit_origin.clear()

	for i in range(mech_count):
		_spawn_one(mech_scene)

	for i in range(human_count):
		_spawn_one(human_scene)


func _spawn_one(scene: PackedScene) -> void:
	var tries := 300
	while tries > 0:
		tries -= 1

		var unit := scene.instantiate() as Unit
		if unit == null:
			return

		var origin := Vector2i(rng.randi_range(0, map_width - 1), rng.randi_range(0, map_height - 1))

		# Big units should spawn on even origins so they always align to the 2-step grid.
		if _is_big_unit(unit):
			origin = snap_origin_for_unit(origin, unit)

		var cells := unit.footprint_cells(origin)

		var ok := true
		for c in cells:
			if not grid.in_bounds(c):
				ok = false
				break
			if grid.terrain[c.x][c.y] == T_WATER:
				ok = false
				break
			if grid.is_occupied(c):
				ok = false
				break

		if not ok:
			unit.queue_free()
			continue

		for c in cells:
			grid.set_occupied(c, unit)

		unit.grid_pos = origin
		unit_origin[unit] = origin
		units_root.add_child(unit)

		# TileMap positions are already in "cell space"; tile size (32x32) is handled by TileMap.
		unit.global_position = cell_to_world_for_unit(origin, unit)
		unit.update_layering()
		return


# -----------------------
# Connectivity + dead-end fixer (non-water walkable)
# -----------------------
func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < map_width and c.y < map_height


func _neighbors4(c: Vector2i) -> Array[Vector2i]:
	return [
		c + Vector2i(1, 0),
		c + Vector2i(-1, 0),
		c + Vector2i(0, 1),
		c + Vector2i(0, -1),
	]


func _is_walkable_tile_id(tid: int) -> bool:
	return tid != T_WATER


func _count_walkable_neighbors(c: Vector2i) -> int:
	var n := 0
	for nb in _neighbors4(c):
		if _in_bounds(nb) and _is_walkable_tile_id(grid.terrain[nb.x][nb.y]):
			n += 1
	return n


func _flood_walkable(start: Vector2i) -> Dictionary:
	var visited := {}
	if start.x < 0:
		return visited
	if not _is_walkable_tile_id(grid.terrain[start.x][start.y]):
		return visited

	var q: Array[Vector2i] = [start]
	visited[start] = true

	while not q.is_empty():
		var c = q.pop_front()
		for nb in _neighbors4(c):
			if not _in_bounds(nb):
				continue
			if visited.has(nb):
				continue
			if not _is_walkable_tile_id(grid.terrain[nb.x][nb.y]):
				continue
			visited[nb] = true
			q.append(nb)

	return visited


func _walkable_components() -> Array[Dictionary]:
	var seen := {}
	var comps: Array[Dictionary] = []

	for x in range(map_width):
		for y in range(map_height):
			var c := Vector2i(x, y)
			if seen.has(c):
				continue
			if not _is_walkable_tile_id(grid.terrain[x][y]):
				continue

			var comp := _flood_walkable(c)
			for k in comp.keys():
				seen[k] = true
			comps.append(comp)

	return comps


func _ensure_walkable_connected() -> void:
	var iter := 0
	while iter < max_fix_iterations:
		iter += 1
		var comps := _walkable_components()
		if comps.size() <= 1:
			return

		var best_a = comps[0].keys()[0]
		var best_b = comps[1].keys()[0]
		var best_d := 999999

		for i in range(comps.size()):
			for j in range(i + 1, comps.size()):
				for ca in comps[i].keys():
					for cb in comps[j].keys():
						var d = abs(ca.x - cb.x) + abs(ca.y - cb.y)
						if d < best_d:
							best_d = d
							best_a = ca
							best_b = cb

		_carve_bridge(best_a, best_b)


func _carve_bridge(from: Vector2i, to: Vector2i) -> void:
	var main := season_main_tile()
	var c := from

	while c.x != to.x:
		c.x += (1 if to.x > c.x else -1)
		if _in_bounds(c) and grid.terrain[c.x][c.y] == T_WATER:
			grid.terrain[c.x][c.y] = main

	while c.y != to.y:
		c.y += (1 if to.y > c.y else -1)
		if _in_bounds(c) and grid.terrain[c.x][c.y] == T_WATER:
			grid.terrain[c.x][c.y] = main


func _add_water_blobs() -> void:
	var total := map_width * map_height
	var desired := int(round(total * target_water))
	if desired <= 0:
		return

	var placed := 0
	for i in range(water_blobs):
		if placed >= desired:
			break

		var c := Vector2i(rng.randi_range(0, map_width - 1), rng.randi_range(0, map_height - 1))
		for s in range(blob_steps):
			if placed >= desired:
				break
			if grid.terrain[c.x][c.y] != T_WATER:
				grid.terrain[c.x][c.y] = T_WATER
				placed += 1

			var nbs := _neighbors4(c)
			var next := nbs[rng.randi_range(0, nbs.size() - 1)]
			if _in_bounds(next):
				c = next

	if season == Season.ICE:
		for x in range(map_width):
			for y in range(map_height):
				if grid.terrain[x][y] == T_WATER and rng.randf() < freeze_water_chance:
					grid.terrain[x][y] = T_ICE


func _remove_dead_ends() -> void:
	var iter := 0
	var main := season_main_tile()

	while iter < max_fix_iterations:
		iter += 1

		var dead_ends: Array[Vector2i] = []
		for x in range(map_width):
			for y in range(map_height):
				var c := Vector2i(x, y)
				if not _is_walkable_tile_id(grid.terrain[x][y]):
					continue
				if _count_walkable_neighbors(c) <= 1:
					dead_ends.append(c)

		if dead_ends.is_empty():
			return

		for c in dead_ends:
			var candidates: Array[Vector2i] = []
			for nb in _neighbors4(c):
				if _in_bounds(nb) and grid.terrain[nb.x][nb.y] == T_WATER:
					candidates.append(nb)

			if candidates.is_empty():
				continue

			var pick := candidates[rng.randi_range(0, candidates.size() - 1)]
			grid.terrain[pick.x][pick.y] = main

	_ensure_walkable_connected()


# -----------------------
# Unit lookup / origins
# -----------------------
func unit_at_cell(cell: Vector2i) -> Unit:
	if grid.is_occupied(cell):
		return grid.occupied[cell] as Unit
	return null


func get_unit_origin(u: Unit) -> Vector2i:
	if u == null:
		return Vector2i(-1, -1)
	if unit_origin.has(u):
		return unit_origin[u]
	return u.grid_pos


func _is_big_unit(u: Unit) -> bool:
	if u == null:
		return false
	return u.footprint_size.x > 1 or u.footprint_size.y > 1

# -----------------------
# “8x8 feel” snapping for big units
# - map is still 16x16 cells
# - big unit ORIGINS snap to even coords (0,2,4,...)
# -----------------------
func snap_origin_for_unit(cell: Vector2i, u: Unit) -> Vector2i:
	if u == null:
		return cell

	if _is_big_unit(u):
		cell.x = (cell.x / 2) * 2
		cell.y = (cell.y / 2) * 2
		cell.x = clampi(cell.x, 0, map_width - 2)
		cell.y = clampi(cell.y, 0, map_height - 2)
	else:
		cell.x = clampi(cell.x, 0, map_width - 1)
		cell.y = clampi(cell.y, 0, map_height - 1)

	return cell


func _neighbors4_for_unit(c: Vector2i, u: Unit) -> Array[Vector2i]:
	var step := 2 if _is_big_unit(u) else 1
	return [
		c + Vector2i(step, 0),
		c + Vector2i(-step, 0),
		c + Vector2i(0, step),
		c + Vector2i(0, -step),
	]


# -----------------------
# Hover / Selection overlays (small vs big tile switching)
# -----------------------
func clear_selection_highlight() -> void:
	highlight.clear()
	highlight.position = hover_offset_1x1

func clear_move_range() -> void:
	move_range.clear()
	reachable_set.clear()
	move_range.position = move_offset_1x1

func draw_unit_hover(u: Unit) -> void:
	highlight.clear()

	if u == null:
		highlight.position = hover_offset_1x1
		return

	var origin := get_unit_origin(u)
	var big := _is_big_unit(u)

	# ✅ offset the hover overlay TileMap itself
	highlight.position = (hover_offset_2x2 if big else hover_offset_1x1)

	if big:
		# big hover tile is a single 2x2 tile placed at the origin cell
		highlight.set_cell(LAYER_HIGHLIGHT, origin, HOVER_TILE_BIG_SOURCE_ID, HOVER_ATLAS, 0)
	else:
		for c in u.footprint_cells(origin):
			highlight.set_cell(LAYER_HIGHLIGHT, c, HOVER_TILE_SMALL_SOURCE_ID, HOVER_ATLAS, 0)

func set_hovered_unit(u: Unit) -> void:
	if hovered_unit == u:
		return
	hovered_unit = u
	if selected_unit == null:
		draw_unit_hover(hovered_unit)

func select_unit(u: Unit) -> void:
	selected_unit = u

	if selected_unit != null:
		draw_unit_hover(selected_unit)
		draw_move_range_for_unit(selected_unit)
		draw_attack_range_for_unit(selected_unit)
	else:
		clear_selection_highlight()
		clear_move_range()
		clear_attack_range()

func clear_attack_range() -> void:
	attack_range.clear()
	attackable_set.clear()
	attack_range.position = attack_offset_1x1

func draw_attack_range_for_unit(u: Unit) -> void:
	clear_attack_range()
	if u == null:
		return

	# ✅ Keep AttackRange TileMap in ONE consistent offset (small)
	attack_range.position = attack_offset_1x1

	# Mark ONLY units that can be attacked
	for child in units_root.get_children():
		var target := child as Unit
		if target == null:
			continue
		if target == u:
			continue

		if _attack_distance(u, target) > u.attack_range:
			continue

		var target_origin := get_unit_origin(target)
		var target_big := _is_big_unit(target)

		if target_big:
			# draw big tile at even origin
			target_origin = snap_origin_for_unit(target_origin, target)
			attackable_set[target_origin] = true
			attack_range.set_cell(LAYER_ATTACK, target_origin, ATTACK_TILE_BIG_SOURCE_ID, ATTACK_ATLAS, 0)
		else:
			# ✅ small tile written normally (TileMap is already in small offset)
			attackable_set[target_origin] = true
			attack_range.set_cell(LAYER_ATTACK, target_origin, ATTACK_TILE_SMALL_SOURCE_ID, ATTACK_ATLAS, 0)

func _unhandled_input(event: InputEvent) -> void:
	if is_moving_unit or is_attacking_unit:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_update_hovered_cell()
		_update_hovered_unit()

		# 1) If we have a selected unit and clicked another unit -> try attack first
		if selected_unit != null and hovered_unit != null and hovered_unit != selected_unit:
			if await try_attack_selected(hovered_unit):
				return

		# 2) If we have a selected unit and clicked ground -> try move
		if selected_unit != null:
			if await try_move_selected_to(hovered_cell):
				return

		# 3) Otherwise select what we're hovering
		select_unit(hovered_unit)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		select_unit(null)


func try_attack_selected(target: Unit) -> bool:
	if selected_unit == null or target == null:
		return false
	if is_moving_unit or is_attacking_unit:
		return false
	if target == selected_unit:
		return false

	var attacker := selected_unit

	var t_origin := get_unit_origin(target)
	if _is_big_unit(target):
		t_origin = snap_origin_for_unit(t_origin, target)

	if not attackable_set.has(t_origin):
		return false

	# range check (uses footprint vs footprint, so 2x2 behaves properly)
	var dist := _attack_distance(attacker, target)
	if dist > attacker.attack_range:
		return false

	is_attacking_unit = true

	# face target + attack anim
	var from_pos := attacker.global_position
	var to_pos := target.global_position
	_set_facing_from_world_delta(attacker, from_pos, to_pos)

	var repeats = max(attacker.attack_repeats, 1)
	for i in range(repeats):
		await _play_anim_and_wait(attacker, attacker.attack_anim)
		await _flash_unit(target)

	_play_idle(attacker)
	is_attacking_unit = false
	return true


func _attack_distance(a: Unit, b: Unit) -> int:
	var ao := get_unit_origin(a)
	var bo := get_unit_origin(b)

	var a_cells := a.footprint_cells(ao)
	var b_cells := b.footprint_cells(bo)

	var best := 999999
	for ca in a_cells:
		for cb in b_cells:
			var d = abs(ca.x - cb.x) + abs(ca.y - cb.y)
			if d < best:
				best = d
	return best


func _play_anim_and_wait(u: Unit, anim_name: StringName) -> void:
	var spr := _unit_sprite(u)
	if spr == null:
		await get_tree().create_timer(0.15).timeout
		return

	if spr.sprite_frames == null or not spr.sprite_frames.has_animation(anim_name):
		# fallback: still wait a tiny bit so timing feels like an attack
		await get_tree().create_timer(0.15).timeout
		return

	spr.play(anim_name)
	await spr.animation_finished


func _flash_unit(u: Unit) -> void:
	var spr := _unit_sprite(u)
	if spr == null:
		return

	# Quick bright flash, then back
	var base := spr.modulate

	var t := create_tween()
	t.tween_property(spr, "modulate", Color(2, 2, 2, base.a), 0.05)
	t.tween_property(spr, "modulate", base, 0.10)
	await t.finished

# -----------------------
# Movement range drawing (small vs big tile switching)
# -----------------------
func draw_move_range_for_unit(u: Unit) -> void:
	clear_move_range()
	if u == null:
		return

	var origin := get_unit_origin(u)
	var big := _is_big_unit(u)

	# ✅ offset the move overlay TileMap itself
	move_range.position = (move_offset_2x2 if big else move_offset_1x1)

	if big:
		origin = snap_origin_for_unit(origin, u)

	var reachable := compute_reachable_origins(u, origin, u.move_range)
	var source_id := (MOVE_TILE_BIG_SOURCE_ID if big else MOVE_TILE_SMALL_SOURCE_ID)

	for cell in reachable:
		reachable_set[cell] = true
		move_range.set_cell(LAYER_MOVE, cell, source_id, MOVE_ATLAS, 0)

# -----------------------
# Moving selected unit on click
# -----------------------
func try_move_selected_to(dest: Vector2i) -> bool:
	if selected_unit == null:
		return false
	if is_moving_unit:
		return false

	var u := selected_unit
	var from_origin := get_unit_origin(u)

	# big units must align to even coords (LOGIC)
	if _is_big_unit(u):
		dest = snap_origin_for_unit(dest, u)

	if not reachable_set.has(dest):
		return false
	if not _can_stand(u, dest):
		return false

	# --- update grid occupancy immediately (LOGIC commits now) ---
	for c in u.footprint_cells(from_origin):
		if grid.is_occupied(c) and grid.occupied[c] == u:
			grid.occupied.erase(c)

	for c in u.footprint_cells(dest):
		grid.set_occupied(c, u)

	u.grid_pos = dest
	unit_origin[u] = dest

	# --- smooth visual move ---
	var target_pos := cell_to_world_for_unit(dest, u)

	is_moving_unit = true
	var from_pos := u.global_position

	_set_facing_from_world_delta(u, from_pos, target_pos)
	_play_anim(u, "move")

	if move_tween != null and move_tween.is_valid():
		move_tween.kill()

	move_tween = create_tween()
	move_tween.set_trans(Tween.TRANS_SINE)
	move_tween.set_ease(Tween.EASE_IN_OUT)

	# tune this: either constant duration, or scale by distance
	var duration := 0.8
	move_tween.tween_property(u, "global_position", target_pos, duration)

	await move_tween.finished

	u.global_position = target_pos
	u.update_layering()

	_play_idle(u)
	is_moving_unit = false

	# refresh overlays AFTER arrival so they match the final spot
	draw_unit_hover(u)
	draw_move_range_for_unit(u)
	draw_attack_range_for_unit(u)

	return true

# -----------------------
# Pathing helpers
# -----------------------
func _is_cell_walkable(c: Vector2i) -> bool:
	return grid.in_bounds(c) and grid.terrain[c.x][c.y] != T_WATER


func _can_stand(u: Unit, origin: Vector2i) -> bool:
	for c in u.footprint_cells(origin):
		if not _is_cell_walkable(c):
			return false
		if grid.is_occupied(c) and grid.occupied[c] != u:
			return false
	return true


func compute_reachable_origins(u: Unit, start: Vector2i, max_cost: int) -> Array[Vector2i]:
	var dist := {}
	var q: Array[Vector2i] = []

	# big units: ensure start is aligned
	if _is_big_unit(u):
		start = snap_origin_for_unit(start, u)

	if not _can_stand(u, start):
		return []

	dist[start] = 0
	q.append(start)

	while not q.is_empty():
		var cur = q.pop_front()
		var cur_d: int = dist[cur]

		if cur_d >= max_cost:
			continue

		for nb in _neighbors4_for_unit(cur, u):
			var nd := cur_d + 1
			if nd > max_cost:
				continue

			if _is_big_unit(u):
				nb = snap_origin_for_unit(nb, u)

			if dist.has(nb) and dist[nb] <= nd:
				continue
			if not _can_stand(u, nb):
				continue

			dist[nb] = nd
			q.append(nb)

	var out: Array[Vector2i] = []
	for k in dist.keys():
		out.append(k)
	return out

func cell_to_world_for_unit(origin: Vector2i, u: Unit) -> Vector2:
	var p00 := terrain.map_to_local(origin) # center of origin cell (in terrain local space)

	if _is_big_unit(u):
		# center of 2x2 footprint = midpoint between origin cell and (origin+1, origin+1)
		var p11 := terrain.map_to_local(origin + Vector2i(1, 1))
		var mid := (p00 + p11) * 0.5
		return terrain.to_global(mid)

	return terrain.to_global(p00)

func _set_facing_from_world_delta(u: Unit, from_pos: Vector2, to_pos: Vector2) -> void:
	var spr := _unit_sprite(u)
	if spr == null:
		return

	var dx := to_pos.x - from_pos.x
	if abs(dx) < 0.01:
		return # don't change facing if basically no horizontal movement

	# default facing LEFT => flip_h=false
	# moving RIGHT => flip_h=true
	spr.flip_h = (dx > 0.0)
