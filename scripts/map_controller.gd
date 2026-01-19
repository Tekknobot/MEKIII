extends Node
class_name MapController

@export var terrain_path: NodePath
@export var units_root_path: NodePath
@export var overlay_root_path: NodePath

@export var ally_scene: PackedScene
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
	if ally_scene == null:
		push_error("MapController: ally_scene is not assigned in Inspector.")
	if enemy_zombie_scene == null:
		push_error("MapController: enemy_zombie_scene is not assigned in Inspector.")

	if move_tile_scene == null:
		push_warning("MapController: move_tile_scene is not assigned (move overlay won't show).")
	if attack_tile_scene == null:
		push_warning("MapController: attack_tile_scene is not assigned (attack overlay won't show).")

func setup(game) -> void:
	game_ref = game
	grid = game.grid

func spawn_one_ally_one_enemy() -> void:
	if terrain == null or units_root == null:
		push_error("MapController: cannot spawn (missing terrain/units_root).")
		return
	if ally_scene == null or enemy_zombie_scene == null:
		push_error("MapController: cannot spawn (ally_scene/enemy_zombie_scene not assigned).")
		return

	clear_all()

	var ally_cell := Vector2i(2, 2)
	var enemy_cell := Vector2i(13, 13)

	_spawn_unit_walkable(ally_cell, Unit.Team.ALLY)
	_spawn_unit_walkable(enemy_cell, Unit.Team.ENEMY)

	print("Spawned units:", units_by_cell.size())

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

	var scene := (ally_scene if team == Unit.Team.ALLY else enemy_zombie_scene)
	if scene == null:
		push_error("MapController: missing scene for team %s" % [team])
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
		# ATTACK MODE: left click attacks enemies in range
		# -------------------------
		if aim_mode == AimMode.ATTACK:
			if clicked != null and clicked.team != selected.team:
				if _in_attack_range(selected, clicked.cell):
					await _do_attack(selected, clicked)
					# After attacking, go back to MOVE mode
					aim_mode = AimMode.MOVE
					_refresh_overlays()
					return

			# Not a valid attack target -> treat as normal left click (switch to MOVE)
			aim_mode = AimMode.MOVE
			_refresh_overlays()
			# fallthrough to MOVE behavior below

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
	return d <= attacker.attack_range

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

func _cleanup_dead(defender: Unit) -> void:
	if defender == null or not is_instance_valid(defender):
		return
	if defender.hp > 0:
		return

	# Only remove from grid tracking
	units_by_cell.erase(defender.cell)

	# Do NOT queue_free here.
	# Unit._die() handles animation + freeing.

func _do_attack(attacker: Unit, defender: Unit) -> void:
	if attacker == null or defender == null:
		return
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return

	# Face each other
	_face_unit_toward_world(attacker, defender.global_position)
	_face_unit_toward_world(defender, attacker.global_position)

	# Play attack anim, small lock so it reads
	_play_attack_anim(attacker)

	# Defender flash + apply damage
	_flash_unit_white(defender, attack_flash_time)
	_jitter_unit(defender, 3.0, 6, attack_flash_time)
	defender.take_damage(attacker.attack_damage)

	# Optional tiny wait so attack anim is seen even if defender dies instantly
	await get_tree().create_timer(attack_anim_lock_time).timeout

	_cleanup_dead(defender)

	# Return attacker to idle (optional)
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

	# Structure blocked dictionary from Game
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

			# ✅ don't draw over structures
			if structure_blocked.has(c):
				continue

			var t := attack_tile_scene.instantiate() as Node2D
			overlay_root.add_child(t)

			t.global_position = terrain.to_global(terrain.map_to_local(c))

			# x+y sum layering
			t.z_as_relative = false
			t.z_index = 1 + (c.x + c.y)

func _refresh_overlays() -> void:
	_clear_overlay()
	if selected == null or not is_instance_valid(selected):
		return
	if aim_mode == AimMode.MOVE:
		_draw_move_range(selected)
	else:
		_draw_attack_range(selected)

func _is_valid_move_target(c: Vector2i) -> bool:
	return selected != null and is_instance_valid(selected) and valid_move_cells.has(c)

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
	if _is_moving:
		return
	if selected == null or not is_instance_valid(selected):
		return
	if not _is_valid_move_target(target):
		return

	var u := selected
	var from_cell := u.cell

	# ✅ L-turn pathfinding (X then Y OR Y then X)
	var path := _pick_clear_L_path(from_cell, target)
	if path.is_empty():
		# No clear L path -> don't move
		return

	_is_moving = true
	_clear_overlay()

	# Reserve destination early (prevents other moves into it)
	units_by_cell.erase(from_cell)
	units_by_cell[target] = u

	_play_move_anim(u, true)

	# Move step-by-step along the L path
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

	# Commit final logical cell (and let Unit do any final snaps)
	u.set_cell(target, terrain)

	_play_move_anim(u, false)

	_refresh_overlays()
	_is_moving = false
	
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
