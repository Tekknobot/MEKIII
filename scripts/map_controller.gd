extends Node
class_name MapController

@export var terrain_path: NodePath
@export var units_root_path: NodePath
@export var overlay_root_path: NodePath

@export var ally_scenes: Array[PackedScene] = []
@export var enemy_zombie_scene: PackedScene

@export var move_tile_scene: PackedScene
@export var attack_tile_scene: PackedScene

var grid

var terrain: TileMap
var units_root: Node2D
var overlay_root: Node2D

var units_by_cell: Dictionary = {}  # Vector2i -> Unit
var selected: Unit = null

var game_ref: Node = null

enum AimMode { MOVE, ATTACK }
var aim_mode: AimMode = AimMode.MOVE

@export var mouse_offset := Vector2(0, 8)

var valid_move_cells: Dictionary = {} # Vector2i -> true (for current selected)
@export var move_speed_cells_per_sec := 4.0

var _is_moving := false

@export var attack_flash_time := 0.10
@export var attack_anim_lock_time := 0.18   # small pause so attack feels visible

@export var max_zombies: int = 4
@export var ally_count: int = 3

@export var turn_manager_path: NodePath
@onready var TM: TurnManager = get_node_or_null(turn_manager_path) as TurnManager

func _ready() -> void:
	terrain = get_node_or_null(terrain_path) as TileMap
	units_root = get_node_or_null(units_root_path) as Node2D
	overlay_root = get_node_or_null(overlay_root_path) as Node2D

	if terrain == null:
		push_error("MapController: terrain_path not set or invalid.")
	if units_root == null:
		push_error("MapController: units_root_path not set or invalid. Add a Node2D named 'Units' and assign it.")
	if overlay_root == null:
		push_error("MapController: overlay_root_path not set or invalid. Add a Node2D named 'Overlays' and assign it.")
	if ally_scenes.is_empty():
		push_error("MapController: ally_scenes is empty. Add 3 ally scenes in Inspector.")
	else:
		for i in range(ally_scenes.size()):
			if ally_scenes[i] == null:
				push_error("MapController: ally_scenes[%d] is null." % i)
	if enemy_zombie_scene == null:
		push_error("MapController: enemy_zombie_scene is not assigned in Inspector.")
	if move_tile_scene == null:
		push_warning("MapController: move_tile_scene is not assigned (move overlay won't show).")
	if attack_tile_scene == null:
		push_warning("MapController: attack_tile_scene is not assigned (attack overlay won't show).")

func setup(game) -> void:
	game_ref = game
	grid = game.grid

func spawn_units() -> void:
	if terrain == null or units_root == null or grid == null:
		return

	clear_all()

	# Structure-blocked cells from Game
	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked

	# --- Build list of all valid walkable + unblocked cells ---
	var valid_cells: Array[Vector2i] = []
	var w := int(grid.w)
	var h := int(grid.h)

	for x in range(w):
		for y in range(h):
			var c := Vector2i(x,y)
			if not _is_walkable(c):
				continue
			if structure_blocked.has(c):
				continue
			valid_cells.append(c)

	if valid_cells.is_empty():
		return

	# ---------------------------------------------------
	# 1) Pick a random "ally cluster center"
	# ---------------------------------------------------
	var cluster_center = valid_cells.pick_random()

	# Sort valid cells by distance to cluster center
	valid_cells.sort_custom(func(a:Vector2i, b:Vector2i) -> bool:
		var da = abs(a.x - cluster_center.x) + abs(a.y - cluster_center.y)
		var db = abs(b.x - cluster_center.x) + abs(b.y - cluster_center.y)
		return da < db
	)

	# --- Spawn allies close together: one of each ally_scenes ---
	for i in range(min(ally_scenes.size(), valid_cells.size())):
		var c = valid_cells.pop_front()
		_spawn_specific_ally(c, ally_scenes[i])

	# ---------------------------------------------------
	# 2) Zombies: far zone + clusters
	# ---------------------------------------------------
	var enemy_center := _pick_far_center(valid_cells, cluster_center)

	# Build an enemy-zone pool near enemy_center (tweak radius)
	var enemy_zone_radius := 6
	var enemy_zone_cells := _cells_within_radius(valid_cells, enemy_center, enemy_zone_radius)

	# If the zone is too small, fall back to all remaining valid cells
	if enemy_zone_cells.size() < max_zombies:
		enemy_zone_cells = valid_cells.duplicate()

	_spawn_zombies_in_clusters(enemy_zone_cells, max_zombies)

	print("Spawned allies:", ally_count, "zombies:", max_zombies)

func _pick_far_center(cells: Array[Vector2i], from_center: Vector2i) -> Vector2i:
	if cells.is_empty():
		return Vector2i(-1, -1)

	var best := cells[0]
	var best_d := -1
	for c in cells:
		var d = abs(c.x - from_center.x) + abs(c.y - from_center.y)
		if d > best_d:
			best_d = d
			best = c
	return best


func _cells_within_radius(cells: Array[Vector2i], center: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		var d = abs(c.x - center.x) + abs(c.y - center.y)
		if d <= r:
			out.append(c)
	return out


func _spawn_zombies_in_clusters(zone_cells: Array[Vector2i], total: int) -> void:
	if total <= 0 or zone_cells.is_empty():
		return

	zone_cells.shuffle()

	# 2–3 clusters depending on zombie count
	var cluster_count = clamp(int(ceil(float(total) / 2.0)), 2, 3)

	for k in range(cluster_count):
		if total <= 0 or zone_cells.is_empty():
			break

		# pick an anchor for this cluster
		var anchor = zone_cells.pop_back()

		# spawn size: 1–3 (but not more than remaining)
		var size = min(total, randi_range(1, 3))

		# spawn anchor first
		_spawn_unit_walkable(anchor, Unit.Team.ENEMY)
		total -= 1

		# find nearby cells for the rest of this cluster (tight radius)
		var near := _neighbors_sorted_by_distance(zone_cells, anchor, 3)

		for i in range(size - 1):
			if total <= 0 or near.is_empty():
				break
			var c = near.pop_front()
			_spawn_unit_walkable(c, Unit.Team.ENEMY)
			total -= 1

			# remove used cell from the zone pool
			var idx := zone_cells.find(c)
			if idx != -1:
				zone_cells.remove_at(idx)


func _neighbors_sorted_by_distance(cells: Array[Vector2i], anchor: Vector2i, max_r: int) -> Array[Vector2i]:
	var near: Array[Vector2i] = []
	for c in cells:
		var d = abs(c.x - anchor.x) + abs(c.y - anchor.y)
		if d > 0 and d <= max_r:
			near.append(c)

	near.sort_custom(func(a:Vector2i, b:Vector2i) -> bool:
		var da = abs(a.x - anchor.x) + abs(a.y - anchor.y)
		var db = abs(b.x - anchor.x) + abs(b.y - anchor.y)
		return da < db
	)
	return near

func _spawn_specific_ally(preferred: Vector2i, scene: PackedScene) -> void:
	var c := _find_nearest_open_walkable(preferred)
	if c.x < 0:
		push_warning("MapController: no WALKABLE open land found near %s" % [preferred])
		return

	if scene == null:
		push_error("MapController: ally scene is null.")
		return

	var inst := scene.instantiate()
	var u := inst as Unit
	if u == null:
		push_error("MapController: ally scene root is not a Unit.")
		return

	units_root.add_child(u)

	u.team = Unit.Team.ALLY
	u.hp = u.max_hp
	u.set_cell(c, terrain)
	units_by_cell[c] = u

	print("Spawned ALLY", scene.resource_path.get_file(), "at", c)

func clear_all() -> void:
	if units_root:
		for ch in units_root.get_children():
			ch.queue_free()
	units_by_cell.clear()
	_clear_overlay()
	selected = null

func _spawn_unit_walkable(preferred: Vector2i, team: int) -> void:
	var c := _find_nearest_open_walkable(preferred)
	if c.x < 0:
		push_warning("MapController: no WALKABLE open land found near %s" % [preferred])
		return

	var scene: PackedScene

	if team == Unit.Team.ALLY:
		if ally_scenes.is_empty():
			push_error("MapController: ally_scenes is empty.")
			return
		scene = ally_scenes.pick_random()
	else:
		scene = enemy_zombie_scene
		if scene == null:
			push_error("MapController: enemy_zombie_scene not assigned.")
			return

	var inst := scene.instantiate()
	var u := inst as Unit
	if u == null:
		push_error("MapController: scene root is not a Unit (must extend Unit).")
		return

	units_root.add_child(u)

	u.team = team
	u.hp = u.max_hp

	u.set_cell(c, terrain)
	units_by_cell[c] = u

	print("Spawned", ("ALLY" if team == Unit.Team.ALLY else "ZOMBIE"), "at", c, "world", u.global_position)

# --------------------------
# Walkable + placement search
# --------------------------
func _is_walkable(c: Vector2i) -> bool:
	if grid == null or not grid.has_method("in_bounds"):
		return false
	if not grid.in_bounds(c):
		return false
	# T_WATER == 5 in your Game
	return grid.terrain[c.x][c.y] != 5

func _find_nearest_open_walkable(start: Vector2i) -> Vector2i:
	if grid == null:
		return Vector2i(-1, -1)

	var w := int(grid.w) if "w" in grid else 0
	var h := int(grid.h) if "h" in grid else 0
	if w <= 0 or h <= 0:
		return Vector2i(-1, -1)

	var best := Vector2i(-1, -1)
	var best_d := 999999

	for x in range(w):
		for y in range(h):
			var c := Vector2i(x, y)
			if not _is_walkable(c):
				continue
			if units_by_cell.has(c):
				continue
			var d = abs(start.x - c.x) + abs(start.y - c.y)
			if d < best_d:
				best_d = d
				best = c

	return best

# --------------------------
# Input: select + attack
# --------------------------
func _input(event: InputEvent) -> void:
	if _is_moving:
		return

	if event is InputEventMouseButton and event.pressed:
		# Right click = ATTACK mode (arm)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			aim_mode = AimMode.ATTACK
			_refresh_overlays()
			return

		# Only left click below
		if event.button_index != MOUSE_BUTTON_LEFT:
			return

		var cell := _mouse_to_cell()
		if cell.x < 0:
			_unselect()
			return

		var clicked := unit_at_cell(cell)

		# If nothing selected yet: left click selects (MOVE mode)
		if selected == null:
			aim_mode = AimMode.MOVE
			if clicked != null:
				_select(clicked)
			return

		# -------------------------
		# ATTACK MODE: left click ONLY attacks, never moves
		# -------------------------
		if aim_mode == AimMode.ATTACK:
			# valid target -> attack
			if clicked != null and selected != null and is_instance_valid(selected):
				if clicked.team != selected.team and _in_attack_range(selected, clicked.cell):
					if TM != null and not TM.can_attack(selected):
						aim_mode = AimMode.MOVE
						_refresh_overlays()
						return

					await _do_attack(selected, clicked)
					# after attacking, disarm back to MOVE
					aim_mode = AimMode.MOVE
					_refresh_overlays()
					return

			# anything else: just DISARM (no move, no select switching)
			aim_mode = AimMode.MOVE
			_refresh_overlays()
			return

		# -------------------------
		# MOVE MODE behavior
		# -------------------------
		if _is_valid_move_target(cell):
			_move_selected_to(cell)
			return

		if clicked != null:
			if clicked == selected:
				_refresh_overlays()
				return
			_select(clicked)
			return

		_unselect()

func _mouse_to_cell() -> Vector2i:
	if terrain == null:
		return Vector2i(-1, -1)

	# ✅ Match GridCursor math exactly
	var mouse_global := get_viewport().get_mouse_position()
	mouse_global = get_viewport().get_canvas_transform().affine_inverse() * mouse_global
	mouse_global += mouse_offset

	var local := terrain.to_local(mouse_global)
	var cell := terrain.local_to_map(local)

	if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(cell):
		return Vector2i(-1, -1)

	return cell

func unit_at_cell(c: Vector2i) -> Unit:
	if units_by_cell.has(c):
		var u := units_by_cell[c] as Unit
		if u and is_instance_valid(u):
			return u
		units_by_cell.erase(c)
	return null

func _select(u: Unit) -> void:
	if TM != null and not TM.can_select(u):
		return
	if selected == u:
		return
	_unselect()
	selected = u
	selected.set_selected(true)
	_refresh_overlays()


func _unselect() -> void:
	if selected and is_instance_valid(selected):
		selected.set_selected(false)
	selected = null
	_clear_overlay()

func _in_attack_range(attacker: Unit, target_cell: Vector2i) -> bool:
	var d = abs(attacker.cell.x - target_cell.x) + abs(attacker.cell.y - target_cell.y)
	if d > attacker.attack_range:
		return false

	# ✅ must have clear attack path (structures block)
	return _has_clear_attack_path(attacker.cell, target_cell)

func _has_clear_attack_path(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if from_cell == to_cell:
		return true

	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked

	# Build two L paths (x->y and y->x), like your move logic
	var p1 := _build_L_path(from_cell, to_cell, true)
	var p2 := _build_L_path(from_cell, to_cell, false)

	# A path is clear if NONE of the intermediate cells (excluding destination) are blocked by structures.
	if _path_clear_of_structures(p1, to_cell, structure_blocked):
		return true
	if _path_clear_of_structures(p2, to_cell, structure_blocked):
		return true

	return false

func _path_clear_of_structures(path: Array[Vector2i], dest: Vector2i, structure_blocked: Dictionary) -> bool:
	for c in path:
		# allow hitting the destination even if it's "occupied" by a unit
		if c == dest:
			continue
		if structure_blocked.has(c):
			return false
	return true

func _play_attack_anim(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return

	# Preferred: unit-defined helpers
	if u.has_method("play_attack_anim"):
		u.call("play_attack_anim")
		return

	# Fallback: AnimatedSprite2D with "attack"
	var a := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if a == null:
		return
	if a.sprite_frames != null and a.sprite_frames.has_animation("attack"):
		a.play("attack")

func _play_idle_anim(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return
	if u.has_method("play_idle_anim"):
		u.call("play_idle_anim")
		return

	var a := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if a == null:
		return
	if a.sprite_frames != null and a.sprite_frames.has_animation("idle"):
		a.play("idle")

func _flash_unit_white(u: Unit, t: float) -> void:
	if u == null or not is_instance_valid(u):
		return

	# Try common visuals first
	var spr := u.get_node_or_null("Sprite2D") as Sprite2D
	if spr != null:
		_flash_canvasitem_white(spr, t)
		return

	var anim := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim != null:
		_flash_canvasitem_white(anim, t)
		return

	# Fallback: any CanvasItem child
	for ch in u.get_children():
		if ch is CanvasItem:
			_flash_canvasitem_white(ch as CanvasItem, t)
			return

func _flash_canvasitem_white(ci: CanvasItem, t: float) -> void:
	if ci == null or not is_instance_valid(ci):
		return

	var prev: Color = ci.modulate

	# Brighten (not pure white) so it reads even with darker sprites
	var peak := Color(
		min(prev.r * 2.0, 2.0),
		min(prev.g * 2.0, 2.0),
		min(prev.b * 2.0, 2.0),
		prev.a
	)

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)

	# Fade up quickly
	tw.tween_property(ci, "modulate", peak, max(0.01, t * 0.35))

	# Fade back a bit slower
	tw.set_ease(Tween.EASE_IN)
	tw.tween_property(ci, "modulate", prev, max(0.01, t * 0.65))

func _cleanup_dead_at(cell: Vector2i) -> void:
	if not units_by_cell.has(cell):
		return

	var v = units_by_cell[cell]  # <-- DO NOT cast yet

	# Freed or not even an Object anymore -> remove
	if v == null or not (v is Object) or not is_instance_valid(v):
		units_by_cell.erase(cell)
		return

	# Now it's safe to cast/use as Unit
	var u := v as Unit
	if u == null or u.hp <= 0:
		units_by_cell.erase(cell)

func _do_attack(attacker: Unit, defender: Unit) -> void:
	if attacker == null or defender == null:
		return
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return

	var def_cell := defender.cell  # ✅ store before defender can die/free

	_face_unit_toward_world(attacker, defender.global_position)
	_face_unit_toward_world(defender, attacker.global_position)

	_play_attack_anim(attacker)

	_flash_unit_white(defender, attack_flash_time)
	_jitter_unit(defender, 3.0, 6, attack_flash_time)
	defender.take_damage(attacker.attack_damage)

	await _wait_for_attack_anim(attacker)
	await get_tree().create_timer(attack_anim_lock_time).timeout

	if TM != null and attacker.team == Unit.Team.ALLY:
		TM.notify_player_attacked(attacker)

	# ✅ defender might be freed now, so never pass it as a typed arg
	_cleanup_dead_at(def_cell)

	_play_idle_anim(attacker)

# --------------------------
# Overlay helpers
# --------------------------
func _clear_overlay() -> void:
	if overlay_root == null:
		return
	for ch in overlay_root.get_children():
		ch.queue_free()

func _draw_move_range(u: Unit) -> void:
	if overlay_root == null or move_tile_scene == null:
		return

	valid_move_cells.clear()

	var r := u.move_range
	var origin := u.cell

	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked

	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var c := origin + Vector2i(dx, dy)

			if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(c):
				continue
			if abs(dx) + abs(dy) > r:
				continue

			if not _is_walkable(c):
				continue
			if structure_blocked.has(c):
				continue
			if c != origin and units_by_cell.has(c):
				continue

			# Only consider it valid if an L path exists
			if _pick_clear_L_path(origin, c).is_empty():
				continue

			valid_move_cells[c] = true

			var t := move_tile_scene.instantiate() as Node2D
			overlay_root.add_child(t)

			t.global_position = terrain.to_global(terrain.map_to_local(c))
			t.z_as_relative = false
			t.z_index = 1 + (c.x + c.y)

func _draw_attack_range(u: Unit) -> void:
	if overlay_root == null or attack_tile_scene == null:
		return

	var r := u.attack_range
	var origin := u.cell

	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked

	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var c := origin + Vector2i(dx, dy)

			# Bounds
			if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(c):
				continue

			# Manhattan range
			if abs(dx) + abs(dy) > r:
				continue

			# ✅ NEW: don't draw on water
			if not _is_walkable(c):
				continue

			# Don't draw on blocking structures
			if structure_blocked.has(c):
				continue

			# ✅ NEW: don't draw if structure blocks line-of-sight
			if not _has_clear_attack_path(origin, c):
				continue

			var t := attack_tile_scene.instantiate() as Node2D
			overlay_root.add_child(t)
			t.global_position = terrain.to_global(terrain.map_to_local(c))

			# Iso depth
			t.z_as_relative = false
			t.z_index = 1 + (c.x + c.y)

func _refresh_overlays() -> void:
	_clear_overlay()
	if selected == null or not is_instance_valid(selected):
		return

	# ✅ If unit already moved this turn, don't show move range again
	if aim_mode == AimMode.MOVE:
		if TM != null and not TM.can_move(selected):
			return
		_draw_move_range(selected)
	else:
		_draw_attack_range(selected)

func _is_valid_move_target(c: Vector2i) -> bool:
	if selected == null or not is_instance_valid(selected):
		return false
	if not valid_move_cells.has(c):
		return false
	if TM != null and not TM.can_move(selected):
		return false
	return true


func _play_move_anim(u: Unit, moving: bool) -> void:
	if u == null or not is_instance_valid(u):
		return

	# Preferred: unit-defined helpers
	if moving and u.has_method("play_move_anim"):
		u.call("play_move_anim")
		return
	if (not moving) and u.has_method("play_idle_anim"):
		u.call("play_idle_anim")
		return

	# Fallback: AnimatedSprite2D with "move"/"idle"
	var a := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if a == null:
		return
	if moving:
		if a.sprite_frames != null and a.sprite_frames.has_animation("move"):
			a.play("move")
	else:
		if a.sprite_frames != null and a.sprite_frames.has_animation("idle"):
			a.play("idle")

func _set_unit_depth_from_world(u: Unit, world_pos: Vector2) -> void:
	# Convert world pos to an approximate cell, then apply x+y sum.
	# This keeps depth stable while sliding between tiles.
	if u == null or not is_instance_valid(u):
		return
	if terrain == null:
		return

	var local := terrain.to_local(world_pos)
	var c := terrain.local_to_map(local)

	u.z_as_relative = false
	# Match your Unit.gd base if you use one (default I suggested was 200000)
	var base := 200000
	if "z_base" in u:
		base = int(u.z_base)
	var per := 1
	if "z_per_cell" in u:
		per = int(u.z_per_cell)

	u.z_index = base + ((c.x + c.y) * per)

func _move_selected_to(target: Vector2i) -> void:
	# Hard gates FIRST
	if TM != null:
		if not TM.player_input_allowed():
			return
		if selected != null and is_instance_valid(selected) and not TM.can_move(selected):
			return

	if _is_moving:
		return
	if selected == null or not is_instance_valid(selected):
		return
	if not _is_valid_move_target(target):
		return

	var u := selected
	var from_cell := u.cell

	# L path
	var path := _pick_clear_L_path(from_cell, target)
	if path.is_empty():
		return

	_is_moving = true

	_clear_overlay()

	# Reserve destination
	units_by_cell.erase(from_cell)
	units_by_cell[target] = u

	_play_move_anim(u, true)

	var step_time := _duration_for_step()
	for step_cell in path:
		var from_world := u.global_position
		var to_world := _cell_world(step_cell)

		_face_unit_for_step(u, from_world, to_world)

		var tw := create_tween()
		tw.set_trans(Tween.TRANS_LINEAR)
		tw.set_ease(Tween.EASE_IN_OUT)

		tw.tween_method(func(p: Vector2):
			u.global_position = p
			_set_unit_depth_from_world(u, p)
		, from_world, to_world, step_time)

		await tw.finished

	u.set_cell(target, terrain)
	_play_move_anim(u, false)

	_is_moving = false

	if TM != null:
		TM.notify_player_moved(u)

	# Optional: once moved, force attack mode overlays or clear selection
	# aim_mode = AimMode.ATTACK
	# _refresh_overlays()

func _face_unit_for_step(u: Unit, from_world: Vector2, to_world: Vector2) -> void:
	if u == null or not is_instance_valid(u):
		return

	var dx := to_world.x - from_world.x
	if abs(dx) < 0.001:
		return

	# Default faces LEFT, so flip when moving RIGHT
	var flip := dx > 0.0

	# Try a few common child names first
	var spr := u.get_node_or_null("Sprite2D") as Sprite2D
	if spr != null:
		spr.flip_h = flip
		return

	var anim := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim != null:
		anim.flip_h = flip
		return

	# Generic fallback: find the first Sprite2D / AnimatedSprite2D anywhere under the unit
	for ch in u.get_children():
		if ch is Sprite2D:
			(ch as Sprite2D).flip_h = flip
			return
		if ch is AnimatedSprite2D:
			(ch as AnimatedSprite2D).flip_h = flip
			return

func _is_blocked_for_move(c: Vector2i, origin: Vector2i) -> bool:
	# blocks: out of bounds, water, structures, occupied (except origin)
	if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(c):
		return true
	if not _is_walkable(c):
		return true

	# structures
	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked
	if structure_blocked.has(c):
		return true

	# occupied (allow starting cell)
	if c != origin and units_by_cell.has(c):
		return true

	return false


func _build_L_path(from_cell: Vector2i, to_cell: Vector2i, x_first: bool) -> Array[Vector2i]:
	# Returns cells visited INCLUDING the destination, EXCLUDING the start.
	var path: Array[Vector2i] = []
	var c := from_cell

	if x_first:
		while c.x != to_cell.x:
			c.x += (1 if to_cell.x > c.x else -1)
			path.append(c)
		while c.y != to_cell.y:
			c.y += (1 if to_cell.y > c.y else -1)
			path.append(c)
	else:
		while c.y != to_cell.y:
			c.y += (1 if to_cell.y > c.y else -1)
			path.append(c)
		while c.x != to_cell.x:
			c.x += (1 if to_cell.x > c.x else -1)
			path.append(c)

	return path


func _pick_clear_L_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var p1 := _build_L_path(from_cell, to_cell, true)   # X then Y
	var p2 := _build_L_path(from_cell, to_cell, false)  # Y then X

	# Check p1
	var ok1 := true
	for step in p1:
		if _is_blocked_for_move(step, from_cell):
			ok1 = false
			break

	# Check p2
	var ok2 := true
	for step in p2:
		if _is_blocked_for_move(step, from_cell):
			ok2 = false
			break

	# Prefer the one that works; if both work, pick shorter (they're same length usually)
	if ok1:
		return p1
	if ok2:
		return p2
	return []


func _cell_world(c: Vector2i) -> Vector2:
	return terrain.to_global(terrain.map_to_local(c))


func _duration_for_step() -> float:
	# One cell move duration based on your cells/sec.
	return max(0.04, 1.0 / move_speed_cells_per_sec)

func _face_unit_toward_world(u: Unit, look_at_world: Vector2) -> void:
	if u == null or not is_instance_valid(u):
		return

	var dx := look_at_world.x - u.global_position.x
	if abs(dx) < 0.001:
		return

	# Default faces LEFT, so flip when looking RIGHT
	var flip := dx > 0.0

	# Try common child names first
	var spr := u.get_node_or_null("Sprite2D") as Sprite2D
	if spr != null:
		spr.flip_h = flip
		return

	var anim := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim != null:
		anim.flip_h = flip
		return

	# Generic fallback: find first Sprite2D / AnimatedSprite2D child
	for ch in u.get_children():
		if ch is Sprite2D:
			(ch as Sprite2D).flip_h = flip
			return
		if ch is AnimatedSprite2D:
			(ch as AnimatedSprite2D).flip_h = flip
			return

func _jitter_unit(u: Unit, strength := 3.0, shakes := 6, total_time := 0.12) -> void:
	if u == null or not is_instance_valid(u):
		return

	var original := u.global_position
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_LINEAR)
	tw.set_ease(Tween.EASE_IN_OUT)

	var step_time := total_time / float(shakes * 2)

	for i in range(shakes):
		var offset := Vector2(
			randf_range(-strength, strength),
			randf_range(-strength, strength)
		)
		tw.tween_property(u, "global_position", original + offset, step_time)
		tw.tween_property(u, "global_position", original, step_time)

	# Safety snap at end
	tw.tween_callback(func():
		if u != null and is_instance_valid(u):
			u.global_position = original
	)

func _get_attack_anim_length(u: Unit) -> float:
	# If the Unit exposes a custom duration, use it
	if "attack_anim_time" in u:
		return float(u.attack_anim_time)

	# If AnimatedSprite2D exists and has "attack", estimate from FPS + frame count
	var a := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if a != null and a.sprite_frames != null and a.sprite_frames.has_animation("attack"):
		var fps := float(a.sprite_frames.get_animation_speed("attack"))
		var frames := a.sprite_frames.get_frame_count("attack")
		if fps > 0.0 and frames > 0:
			return frames / fps

	# fallback
	return attack_anim_lock_time

func _wait_for_attack_anim(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return

	var a := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var fallback := _get_attack_anim_length(u)

	# No AnimatedSprite2D attack anim -> just wait fallback time
	if a == null or a.sprite_frames == null or not a.sprite_frames.has_animation("attack"):
		await get_tree().create_timer(max(0.01, fallback)).timeout
		return

	# If attack isn't currently playing, just time fallback
	if a.animation != "attack":
		await get_tree().create_timer(max(0.01, fallback)).timeout
		return

	var done := false
	var cb := func() -> void:
		done = true

	var callable := Callable(cb)

	# Connect once
	if not a.animation_finished.is_connected(callable):
		a.animation_finished.connect(callable)

	# Wait until finished OR timeout
	var t := 0.0
	while not done and t < fallback + 0.25:
		await get_tree().process_frame
		t += get_process_delta_time()

	# Disconnect safely
	if a != null and is_instance_valid(a) and a.animation_finished.is_connected(callable):
		a.animation_finished.disconnect(callable)

func get_all_units() -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units_by_cell.values():
		if u != null and is_instance_valid(u):
			out.append(u)
	return out

# used by TurnManager AI
func can_attack_cell(attacker: Unit, target_cell: Vector2i) -> bool:
	return _in_attack_range(attacker, target_cell)

func ai_reachable_cells(u: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if u == null or not is_instance_valid(u):
		return out

	var r := u.move_range
	var origin := u.cell

	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked

	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var c := origin + Vector2i(dx, dy)

			if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(c):
				continue
			if abs(dx) + abs(dy) > r:
				continue
			if not _is_walkable(c):
				continue
			if structure_blocked.has(c):
				continue
			if c != origin and units_by_cell.has(c):
				continue
			if _pick_clear_L_path(origin, c).is_empty():
				continue

			out.append(c)

	return out

func ai_move(u: Unit, target: Vector2i) -> void:
	# Drive the existing move logic safely:
	if u == null or not is_instance_valid(u):
		return
	if _is_moving:
		return

	# Temporarily select the unit so _move_selected_to works
	var prev := selected
	selected = u
	_clear_overlay()
	valid_move_cells.clear()
	valid_move_cells[target] = true

	_move_selected_to(target)
	# wait until movement finishes
	while _is_moving:
		await get_tree().process_frame

	selected = prev

func ai_attack(attacker: Unit, defender: Unit) -> void:
	if attacker == null or defender == null:
		return
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return
	await _do_attack(attacker, defender)

func set_unit_exhausted(u: Unit, exhausted: bool) -> void:
	if u == null or not is_instance_valid(u):
		return

	var mul := 0.55 if exhausted else 1.0
	var tint := Color(mul, mul, mul, 1.0)

	# Try common visuals
	var spr := u.get_node_or_null("Sprite2D") as Sprite2D
	if spr != null:
		spr.modulate = tint
		return

	var anim := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim != null:
		anim.modulate = tint
		return

	# Fallback: first CanvasItem child
	for ch in u.get_children():
		if ch is CanvasItem:
			(ch as CanvasItem).modulate = tint
			return
