extends Unit
class_name CarBot

# -------------------------
# Visual / identity
# -------------------------
@export var portrait_tex: Texture2D = preload("res://sprites/Portraits/dog_port.png")
@export var thumbnail: Texture2D
@export var special: String = "DRIVE"
@export var special_desc: String = "Automatically drives each round, running over zombies."

# -------------------------
# Drive tuning
# -------------------------
@export var drive_move_points := 5                 # how far it auto-drives per action
@export var drive_step_time := 0.10               # time between tile steps
@export var crush_damage := 999                   # “run over” (tune if you want non-lethal)
@export var crush_sfx: StringName = &"mech_step"   # set to your engine sound key if you have one

# If true: each step tries to go *through* an enemy cell if reachable
@export var prefer_path_through_enemies := true

# -------------------------
# Motor vibration
# -------------------------
@export var idle_vibe_amp_px := 0.55
@export var idle_vibe_hz := 12.0

@export var drive_vibe_amp_px := 1.6
@export var drive_vibe_hz := 18.0

# Optional: vibrate nearby units too (small)
@export var vibrate_nearby_units := true
@export var vibe_radius := 2
@export var nearby_vibe_amp_px := 0.35

# -------------------------
# Anim names
# -------------------------
@export var anim_idle: StringName = &"idle"
@export var anim_right_up: StringName = &"right_up"
@export var anim_right_down: StringName = &"right_down"

signal drive_finished

var _driving := false
var _pending_steps := 0
var _base_pos: Vector2
var _vibe_t := 0.0
var _vibe_amp := 0.0
var _vibe_hz := 0.0

@export var z_offset := 0 # tweak if you need it above/below others
@onready var visual: Node2D = get_node_or_null("Visual") as Node2D
@export var anim_path: NodePath
@onready var _anim: AnimatedSprite2D = null

var _last_step_dir := Vector2i(1, 1)

func set_step_dir(dir: Vector2i) -> void:
	_last_step_dir = dir

func play_move_anim() -> void:
	if _anim == null:
		return

	var d := _last_step_dir

	# Godot grid:
	# x- = left, x+ = right
	# y- = up,   y+ = down

	if d.x > 0 and d.y < 0:
		_anim.play(anim_right_up)
	elif d.x > 0 and d.y > 0:
		_anim.play(anim_right_down)
	elif d.x < 0 and d.y < 0:
		_anim.play("left_up")
	elif d.x < 0 and d.y > 0:
		_anim.play("left_down")
	else:
		# fallback (straight move / weird case)
		if anim_idle != StringName():
			_anim.play(anim_idle)

func play_idle_anim() -> void:
	if _anim == null:
		return
	if anim_idle != StringName():
		_anim.play(anim_idle)

func _ready() -> void:
	_base_pos = global_position
	_update_layer_from_cell()
	_set_motor_mode_idle()
		
	if anim_path != NodePath():
		_anim = get_node_or_null(anim_path) as AnimatedSprite2D

	if _anim == null:
		push_warning("CarBot: anim_path not set or invalid")

func _process(delta: float) -> void:
	_vibe_t += delta

	if visual == null:
		return

	if _vibe_amp > 0.0:
		var x := sin(_vibe_t * TAU * _vibe_hz) * _vibe_amp
		var y := cos(_vibe_t * TAU * (_vibe_hz * 0.91)) * (_vibe_amp * 0.7)
		visual.position = Vector2(x, y)
	else:
		visual.position = Vector2.ZERO

func _update_layer_from_cell() -> void:
	# layering by grid sum
	z_index = int(cell.x + cell.y + z_offset)
	z_as_relative = false

func _snap_visual_to_cell(M: MapController) -> void:
	# hard sync sprite to the tile coordinate
	if M != null and is_instance_valid(M) and M.has_method("_cell_world"):
		global_position = M.call("_cell_world", cell)
	_base_pos = global_position
	_update_layer_from_cell()

func on_spawned_from_bomber(M: MapController) -> void:
	# call this right after you set car.cell during spawn
	_snap_visual_to_cell(M)
	_crush_enemy_if_present(M, cell)

func _crush_enemy_if_present(M: MapController, at_cell: Vector2i) -> void:
	var victim := _get_enemy_at_cell(M, at_cell)
	if victim != null and is_instance_valid(victim) and victim.hp > 0:
		victim.take_damage(crush_damage)
		if M != null and M.has_method("_sfx"):
			M.call("_sfx", crush_sfx, 1.0, randf_range(0.95, 1.05), M._cell_world(at_cell))


# ------------------------------------------------------------
# Call this the same way you call RecruitBot.auto_support_action(M)
# (e.g., after each round / start of bot's auto phase)
# ------------------------------------------------------------
func auto_drive_action(M: MapController) -> void:
	if _driving:
		return
	if M == null or not is_instance_valid(M) or M.grid == null:
		return

	# pick path (list of cells) to drive this action
	var path: Array[Vector2i] = _pick_drive_path(M)
	if path.is_empty():
		_set_motor_mode_idle()
		return

	_driving = true
	_set_motor_mode_driving()

	_pending_steps = path.size()
	for i in range(path.size()):
		var next_cell := path[i]
		await _drive_step(M, next_cell)

	# done
	_driving = false
	_set_motor_mode_idle()

	if M != null and is_instance_valid(M):
		M._set_unit_attacked(self, true)

	emit_signal("drive_finished")


# ------------------------------------------------------------
# One step of driving: animate direction, move, crush if enemy
# ------------------------------------------------------------
func _drive_step(M: MapController, next_cell: Vector2i) -> void:
	if M == null or not is_instance_valid(M):
		return
	if not M.grid.in_bounds(next_cell):
		return

	var dir := next_cell - cell
	_play_drive_anim_for_dir(dir)

	# crush BEFORE moving
	_crush_enemy_if_present(M, next_cell)

	await get_tree().create_timer(drive_step_time).timeout
		
func warp_to_cell(M: MapController) -> void:
	# last-resort positioning helper
	if M != null and M.has_method("_cell_world"):
		global_position = M.call("_cell_world", cell)
	else:
		# if your Unit has tile->world helper:
		if has_method("get_tile_world_pos"):
			global_position = get_tile_world_pos()
	_base_pos = global_position
	
	_update_layer_from_cell()

func _play_drive_anim_for_dir(dir: Vector2i) -> void:
	if _anim == null:
		return

	# Decide if we're moving left/right
	var moving_left := dir.x < 0
	var moving_right := dir.x > 0

	# Choose up/down animation (isometric-friendly: prioritize y)
	if dir.y < 0:
		_anim.play(anim_right_up)
	elif dir.y > 0:
		_anim.play(anim_right_down)
	else:
		# Pure horizontal: keep last vertical anim if you want stability
		# or pick based on dir.x:
		_anim.play(anim_right_down)  # feels better for "drive" usually


func _set_motor_mode_idle() -> void:
	_vibe_amp = idle_vibe_amp_px
	_vibe_hz = idle_vibe_hz
	if _anim != null and anim_idle != StringName():
		_anim.play(anim_idle)	


func _set_motor_mode_driving() -> void:
	_vibe_amp = drive_vibe_amp_px
	_vibe_hz = drive_vibe_hz


func _apply_drive_vibe_burst(M: MapController) -> void:
	# quick punchy rumble on each step (also optional nearby unit rumble)
	# (visual only; no physics)
	if vibrate_nearby_units and M != null and is_instance_valid(M):
		for u in M.get_all_units():
			if u == null or not is_instance_valid(u):
				continue
			var d = abs(u.cell.x - cell.x) + abs(u.cell.y - cell.y)
			if d > vibe_radius:
				continue
			# don't rumble dead / enemies if you don't want
			# if u.team != Unit.Team.ALLY: continue

			# apply a tiny temporary offset if that unit supports it
			# safest: if they have a method we can call
			if u.has_method("motor_rumble"):
				u.call("motor_rumble", nearby_vibe_amp_px, 0.12)


# ------------------------------------------------------------
# Targeting / path selection
# ------------------------------------------------------------
func _pick_drive_path(M: MapController) -> Array[Vector2i]:
	# We’ll choose up to drive_move_points steps from reachable cells.
	# Strategy:
	# 1) If any enemies are reachable in N steps, prefer a path that hits them.
	# 2) Otherwise, move toward closest enemy.

	var reachable: Array[Vector2i] = []
	if M.has_method("ai_reachable_cells"):
		reachable = M.ai_reachable_cells(self)
	if reachable.is_empty():
		return []

	# remove current cell
	reachable = reachable.filter(func(c): return c != cell)

	# No enemies? just idle.
	var enemies := M.get_all_enemies()
	if enemies.is_empty():
		return []

	# Build a quick set lookup for enemies-by-cell
	var enemy_by_cell: Dictionary = {}
	for e in enemies:
		if e == null or not is_instance_valid(e) or e.hp <= 0:
			continue
		enemy_by_cell[e.cell] = e

	# Find best destination among reachable
	var best_dest := Vector2i(-1, -1)
	var best_score := -999999

	for c in reachable:
		# score:
		# + big bonus if landing on enemy
		# + smaller bonus if close to enemy
		var score := 0
		if enemy_by_cell.has(c):
			score += 1000

		# closeness to nearest enemy
		var nearest := 999999
		for e in enemies:
			if e == null or not is_instance_valid(e) or e.hp <= 0:
				continue
			var d = abs(e.cell.x - c.x) + abs(e.cell.y - c.y)
			if d < nearest:
				nearest = d
		score += (200 - nearest) # closer = higher

		# prefer paths through enemies (not just landing) if enabled:
		# this is a rough proxy—real “through” needs path info; we’ll handle that below
		if prefer_path_through_enemies:
			# if c is between us and an enemy in Manhattan sense, slightly bump
			for e in enemies:
				if e == null or not is_instance_valid(e) or e.hp <= 0:
					continue
				var d0 = abs(e.cell.x - cell.x) + abs(e.cell.y - cell.y)
				var d1 = abs(e.cell.x - c.x) + abs(e.cell.y - c.y)
				if d1 < d0:
					score += 5
					break

		if score > best_score:
			best_score = score
			best_dest = c

	if best_dest.x < 0:
		return []

	# Now construct a step-by-step path of up to drive_move_points.
	# If MapController can give a path, use it; else do a greedy step walk.
	var path: Array[Vector2i] = []

	if M.has_method("ai_find_path"):
		# If you have something like this, great:
		# path = M.ai_find_path(self, cell, best_dest)
		path = M.call("ai_find_path", self, cell, best_dest)
	elif M.has_method("find_path"):
		path = M.call("find_path", cell, best_dest)
	else:
		# greedy Manhattan path (doesn't avoid obstacles well, but works on open maps)
		path = _greedy_step_path(M, best_dest, drive_move_points)

	# Trim to drive_move_points and drop the start cell if included
	if not path.is_empty() and path[0] == cell:
		path.remove_at(0)

	if path.size() > drive_move_points:
		path.resize(drive_move_points)

	return path


func _greedy_step_path(M: MapController, dest: Vector2i, max_steps: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [cell]
	var cur := cell

	for i in range(max_steps):
		if cur == dest:
			break

		var options := [
			cur + Vector2i(1,0),
			cur + Vector2i(-1,0),
			cur + Vector2i(0,1),
			cur + Vector2i(0,-1),
		]

		# keep in bounds + walkable
		var best := cur
		var best_d := 999999

		for n in options:
			if not M.grid.in_bounds(n):
				continue
			# if you have blocking rules, use them:
			if M.has_method("_is_walkable") and not M.call("_is_walkable", n):
				continue

			var d = abs(dest.x - n.x) + abs(dest.y - n.y)
			if d < best_d:
				best_d = d
				best = n

		if best == cur:
			break

		out.append(best)
		cur = best

	return out


func _get_enemy_at_cell(M: MapController, c: Vector2i) -> Unit:
	# Try to use a fast lookup if MapController has one
	if M.has_method("get_unit_at_cell"):
		var u = M.call("get_unit_at_cell", c)
		if u != null and u is Unit and (u as Unit).team == Unit.Team.ENEMY:
			return u as Unit

	# fallback: scan enemies
	for e in M.get_all_enemies():
		if e == null or not is_instance_valid(e):
			continue
		if e.cell == c and e.hp > 0:
			return e
	return null


# ------------------------------------------------------------
# Optional hook for OTHER units to support vibration
# (used in _apply_drive_vibe_burst if they have this method)
# ------------------------------------------------------------
func motor_rumble(amp_px: float, seconds: float) -> void:
	# local small rumble helper if YOU call it on this bot too
	var saved_amp := _vibe_amp
	var saved_hz := _vibe_hz

	_vibe_amp = max(_vibe_amp, amp_px)
	_vibe_hz = max(_vibe_hz, 18.0)

	await get_tree().create_timer(max(0.01, seconds)).timeout

	_vibe_amp = saved_amp
	_vibe_hz = saved_hz
