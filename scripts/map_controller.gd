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
	if event is InputEventMouseButton and event.pressed:
		# Toggle mode based on button (vice versa)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			aim_mode = AimMode.ATTACK
			_refresh_overlays()
			return

		if event.button_index != MOUSE_BUTTON_LEFT:
			return

		# Left click: normal interaction (and sets MOVE mode)
		aim_mode = AimMode.MOVE

		var cell := _mouse_to_cell()
		if cell.x < 0:
			_unselect()
			return

		var clicked := unit_at_cell(cell)

		# select first
		if selected == null:
			if clicked != null:
				_select(clicked)
				_refresh_overlays()
			return

		# If we clicked a unit:
		if clicked != null:
			# Attack only when we're in ATTACK mode and clicked enemy
			if aim_mode == AimMode.ATTACK and clicked.team != selected.team:
				if _in_attack_range(selected, clicked.cell):
					_do_attack(selected, clicked)
				_refresh_overlays()
				return

			# Otherwise just select
			_select(clicked)
			_refresh_overlays()
			return

		# Clicked empty cell: clear selection
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

func _do_attack(attacker: Unit, defender: Unit) -> void:
	defender.take_damage(attacker.attack_damage)
	if defender.hp <= 0:
		units_by_cell.erase(defender.cell)
		defender.queue_free()

	# refresh overlays
	if selected and is_instance_valid(selected):
		_draw_move_range(selected)
		_draw_attack_range(selected)

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

	var r := u.move_range
	var origin := u.cell

	# Structure blocked dictionary from Game (built during spawn_structures)
	# If not present, we just treat as no structures.
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

			# ✅ skip water
			if not _is_walkable(c):
				continue

			# ✅ skip structures
			if structure_blocked.has(c):
				continue

			# ✅ skip occupied (allow the origin tile)
			if c != origin and units_by_cell.has(c):
				continue

			var t := move_tile_scene.instantiate() as Node2D
			overlay_root.add_child(t)

			t.global_position = terrain.to_global(terrain.map_to_local(c))

			# x+y sum layering (keep your preference)
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
