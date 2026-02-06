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
@export var crush_damage := 999                   # "run over" (tune if you want non-lethal)
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

# -------------------------
# Debug / Calibration
# -------------------------
@export var debug_animation := false  # Enable to see grid direction -> animation mapping

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

@export var terrain_path: NodePath
var _terrain: TileMap

@export var anim_left_up: StringName = &"left_up"
@export var anim_left_down: StringName = &"left_down"

@onready var car_sfx: ProceduralCarSFX = get_node_or_null("CarSFX") as ProceduralCarSFX

@export var anim_death: StringName = &"death"

var _death_started := false

func _ready() -> void:
	_terrain = get_node_or_null(terrain_path) as TileMap
	if _terrain == null:
		_terrain = _resolve_terrain_from_group()

	# ✅ assign anim first
	if anim_path != NodePath():
		_anim = get_node_or_null(anim_path) as AnimatedSprite2D
	if _anim == null:
		push_warning("CarBot: anim_path not set or invalid")

	_base_pos = global_position
	_update_layer_from_cell()

	# ✅ now idle can actually play
	_set_motor_mode_idle()

	if debug_animation:
		print("CarBot terrain resolved: ", _terrain, " anim=", _anim)
		
func play_death_anim() -> void:
	# NOTE: Unit._die() already set _dying = true before calling this.
	# So do NOT early-return just because _dying is true.

	if _death_started:
		return
	_death_started = true

	# stop any ongoing behavior immediately
	_driving = false
	_vibe_amp = 0.0
	_vibe_hz = 0.0
	if visual != null:
		visual.position = Vector2.ZERO

	# stop procedural engine
	if car_sfx != null:
		car_sfx.set_engine(false)

	# stop future vibration updates
	set_process(false)
	set_physics_process(false)

	# resolve anim (it's under Visual)
	if _anim == null and anim_path != NodePath():
		_anim = get_node_or_null(anim_path) as AnimatedSprite2D

	# if we can't animate, just die cleanly
	if _anim == null or _anim.sprite_frames == null:
		queue_free()
		return

	# pick correct death animation name
	var death_name := anim_death
	if not _anim.sprite_frames.has_animation(death_name):
		if _anim.sprite_frames.has_animation("death"):
			death_name = &"death"
		else:
			queue_free()
			return

	# ensure it finishes
	_anim.sprite_frames.set_animation_loop(death_name, false)
	_anim.stop()
	_anim.play(death_name)

	await _anim.animation_finished
	queue_free()

func play_idle_anim() -> void:
	if _dying:
		return	
	if _anim == null:
		return
	if anim_idle != StringName():
		_anim.play(anim_idle)

func _physics_process(_delta: float) -> void:
	if hp <= 0 and not _dying:
		_die()
		
func _process(delta: float) -> void:
	# ✅ safety: if we're dead, stop all visuals and don't keep vibrating
	if hp <= 0:
		_driving = false
		_vibe_amp = 0.0
		_vibe_hz = 0.0
		if visual != null:
			visual.position = Vector2.ZERO
		# stop engine sound too
		if car_sfx != null:
			car_sfx.set_engine(false)
		return

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
	if victim == null or not is_instance_valid(victim):
		return

	# NEW: never crush these
	if _is_avoid_unit(victim):
		return

	if victim.hp > 0:
		victim.take_damage(crush_damage)
		if car_sfx != null:
			car_sfx.hit(1.0)
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

	if car_sfx != null:
		car_sfx.set_engine(true)
		car_sfx.set_rpm01(0.65) # cruising RPM

	_pending_steps = path.size()
	for i in range(path.size()):
		var next_cell := path[i]
		await _drive_step(M, next_cell)

	# done
	_driving = false
	
	if car_sfx != null:
		car_sfx.set_rpm01(0.15)
		car_sfx.set_engine(false)
	
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
	if M.grid == null or not M.grid.in_bounds(next_cell):
		return

	# GRID dir for anim (turns included)
	var grid_dir := next_cell - cell
	_last_step_dir = grid_dir
	
	if car_sfx != null:
		car_sfx.set_rpm01(0.75) # little push per step
		car_sfx.tick(1.0)
	
	if _terrain == null and M != null and "terrain" in M:
		_terrain = M.terrain
	
	_play_anim_from_grid_direction(grid_dir)

	# crush BEFORE moving into the cell
	_crush_enemy_if_present(M, next_cell)

	# ✅ Use MapController mover so units_by_cell + mines + depth all stay correct
	if M.has_method("_push_unit_to_cell"):
		await M.call("_push_unit_to_cell", self, next_cell)
	else:
		# Fallback: keep logic consistent if that helper ever changes
		if "terrain" in M and M.terrain != null:
			set_cell(next_cell, M.terrain)
		else:
			cell = next_cell
			_snap_visual_to_cell(M)

	if self == null or not is_instance_valid(self) or hp <= 0:
		return

	_apply_drive_vibe_burst(M)
	await get_tree().create_timer(drive_step_time).timeout

# ------------------------------------------------------------
# Called by MapController during manual player movement
# ------------------------------------------------------------
func play_move_step_anim(from_world: Vector2, to_world: Vector2) -> void:
	if _terrain == null:
		return
	var d := to_world - from_world
	if d.length() < 0.001:
		return

	# Convert world delta to an equivalent "grid_dir" by picking the best basis
	var origin := _terrain.map_to_local(Vector2i.ZERO)
	var v_rd := (_terrain.map_to_local(Vector2i(1, 0)) - origin)
	var v_ld := (_terrain.map_to_local(Vector2i(0, 1)) - origin)
	var v_lu := (_terrain.map_to_local(Vector2i(-1, 0)) - origin)
	var v_ru := (_terrain.map_to_local(Vector2i(0, -1)) - origin)

	var best := Vector2i(1, 0)
	var best_dot := -1.0
	var dn := d.normalized()

	var dot := dn.dot(v_rd.normalized())
	if dot > best_dot: best_dot = dot; best = Vector2i(1, 0)
	dot = dn.dot(v_ld.normalized())
	if dot > best_dot: best_dot = dot; best = Vector2i(0, 1)
	dot = dn.dot(v_lu.normalized())
	if dot > best_dot: best_dot = dot; best = Vector2i(-1, 0)
	dot = dn.dot(v_ru.normalized())
	if dot > best_dot: best_dot = dot; best = Vector2i(0, -1)

	_play_anim_from_grid_direction(best)

func _approximate_grid_dir_from_world_movement(from_world: Vector2, to_world: Vector2) -> Vector2i:
	# Convert screen-space movement to grid direction
	var visual_dir := to_world - from_world
	
	if visual_dir.length() < 0.1:
		return Vector2i.ZERO
	
	var normalized := visual_dir.normalized()
	
	# Isometric transformation (approximate inverse)
	# Standard isometric uses a 2:1 ratio
	# Adjust these coefficients if your isometric angle is different
	
	# For standard isometric (30° angle):
	# Moving right on screen = positive x in visual
	# Moving down on screen = positive y in visual
	
	# Convert to grid coordinates
	# This reverses the typical isometric projection
	var grid_x := normalized.x - normalized.y
	var grid_y := normalized.x + normalized.y
	
	# Normalize the result
	var length := sqrt(grid_x * grid_x + grid_y * grid_y)
	if length > 0.01:
		grid_x /= length
		grid_y /= length
	
	# Snap to nearest cardinal/diagonal direction
	var result := Vector2i.ZERO
	
	# Threshold for detecting movement
	var threshold := 0.3
	
	if abs(grid_x) > threshold:
		result.x = 1 if grid_x > 0 else -1
	if abs(grid_y) > threshold:
		result.y = 1 if grid_y > 0 else -1
	
	if debug_animation:
		print("CarBot World Movement: ", visual_dir, " -> Grid Dir: ", result)
	
	return result

func _approximate_grid_dir_from_visual(visual_dir: Vector2) -> Vector2i:
	# Convert screen-space direction back to grid direction
	# This assumes standard isometric: adjust if your projection differs
	
	if visual_dir.length() < 0.1:
		return Vector2i.ZERO
	
	var normalized := visual_dir.normalized()
	
	# Isometric transformation (approximate inverse)
	# Adjust these coefficients based on your actual isometric angle
	var grid_x := normalized.x + normalized.y * 0.5
	var grid_y := -normalized.x + normalized.y * 0.5
	
	# Snap to nearest cardinal/diagonal direction
	var abs_x = abs(grid_x)
	var abs_y = abs(grid_y)
	
	var result := Vector2i.ZERO
	
	if abs_x > 0.3:
		result.x = 1 if grid_x > 0 else -1
	if abs_y > 0.3:
		result.y = 1 if grid_y > 0 else -1
	
	return result

# ------------------------------------------------------------
# Animation selection based on grid direction
# ------------------------------------------------------------
func _play_anim_from_grid_direction(grid_dir: Vector2i) -> void:
	if _anim == null:
		return
	if _dying:
		return
		
	grid_dir = Vector2i(signi(grid_dir.x), signi(grid_dir.y))
	if grid_dir == Vector2i.ZERO:
		# don't change anim if there's no movement step
		return

	var anim_name := _get_anim_name_for_grid_dir(grid_dir)

	if debug_animation:
		print("CarBot Grid Dir: ", grid_dir, " -> Animation: ", anim_name, " current=", _anim.animation)

	# Only switch if it actually changed (important for turns)
	if _anim.animation != anim_name:
		_anim.play(anim_name)

func _get_anim_name_for_grid_dir(grid_dir: Vector2i) -> StringName:
	grid_dir = Vector2i(signi(grid_dir.x), signi(grid_dir.y))
	if grid_dir == Vector2i.ZERO:
		return anim_idle

	if _terrain == null:
		return anim_idle

	var origin := _terrain.map_to_local(Vector2i.ZERO)
	var d := _terrain.map_to_local(grid_dir) - origin
	if d.length() < 0.001:
		return anim_idle

	var dn := d.normalized()

	# Build real screen-space basis vectors from your TileMap
	var v_rd := (_terrain.map_to_local(Vector2i(1, 0)) - origin).normalized()   # down-right
	var v_ld := (_terrain.map_to_local(Vector2i(0, 1)) - origin).normalized()   # down-left
	var v_lu := (_terrain.map_to_local(Vector2i(-1, 0)) - origin).normalized()  # up-left
	var v_ru := (_terrain.map_to_local(Vector2i(0, -1)) - origin).normalized()  # up-right

	# Pick best alignment via dot product (with tie-break)
	var best_anim := anim_idle
	var best_dot := -1.0
	var second_dot := -1.0

	var dot := dn.dot(v_rd)
	if dot > best_dot:
		second_dot = best_dot
		best_dot = dot
		best_anim = anim_right_down
	elif dot > second_dot:
		second_dot = dot

	dot = dn.dot(v_ld)
	if dot > best_dot:
		second_dot = best_dot
		best_dot = dot
		best_anim = anim_left_down
	elif dot > second_dot:
		second_dot = dot

	dot = dn.dot(v_lu)
	if dot > best_dot:
		second_dot = best_dot
		best_dot = dot
		best_anim = anim_left_up
	elif dot > second_dot:
		second_dot = dot

	dot = dn.dot(v_ru)
	if dot > best_dot:
		second_dot = best_dot
		best_dot = dot
		best_anim = anim_right_up
	elif dot > second_dot:
		second_dot = dot

	# ✅ If ambiguous (close call), keep current animation to avoid flicker/reverse
	# Tune threshold 0.03–0.10 depending on how “wobbly” it is.
	var tie_margin := best_dot - second_dot
	if tie_margin < 0.06 and _anim != null:
		return _anim.animation

	return best_anim

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

func _set_motor_mode_idle() -> void:
	_vibe_amp = idle_vibe_amp_px
	_vibe_hz = idle_vibe_hz
	if _anim != null and anim_idle != StringName():
		_anim.play(anim_idle)	


func _set_motor_mode_driving() -> void:
	_vibe_amp = drive_vibe_amp_px
	_vibe_hz = drive_vibe_hz


func _apply_drive_vibe_burst(M: MapController) -> void:
	if vibrate_nearby_units and M != null and is_instance_valid(M):
		for u in M.get_all_units():
			if u == self:
				continue
			if u == null or not is_instance_valid(u):
				continue
			var dist = abs(u.cell.x - cell.x) + abs(u.cell.y - cell.y)
			if dist > vibe_radius:
				continue
			if u.has_method("motor_rumble"):
				u.call("motor_rumble", nearby_vibe_amp_px, 0.12)

# ------------------------------------------------------------
# Targeting / path selection
# ------------------------------------------------------------
func _pick_drive_path(M: MapController) -> Array[Vector2i]:
	if M == null or not is_instance_valid(M) or M.grid == null:
		return []

	var enemies := M.get_all_enemies()
	if enemies.is_empty():
		return []

	# structure blocked (same as MapController uses)
	var structure_blocked: Dictionary = {}
	if M.game_ref != null and "structure_blocked" in M.game_ref:
		structure_blocked = M.game_ref.structure_blocked

	# quick enemy lookup by cell
	var enemy_by_cell: Dictionary = {}
	for e in enemies:
		if e != null and is_instance_valid(e) and e.hp > 0:
			enemy_by_cell[e.cell] = e

	# Build candidate destinations within DRIVE range (not move_range)
	var r := int(drive_move_points)
	var best_dest := Vector2i(-1, -1)
	var best_path: Array[Vector2i] = []
	var best_score := -999999

	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if abs(dx) + abs(dy) > r:
				continue

			var dest := cell + Vector2i(dx, dy)
			if not M.grid.in_bounds(dest):
				continue
			if structure_blocked.has(dest):
				continue
			if M.has_method("_is_walkable") and not M.call("_is_walkable", dest):
				continue

			# NEW: don't even consider destinations on Weakpoint / EliteMech
			if _cell_has_avoid_unit(M, dest):
				continue
				
			# Occupancy rule for car:
			if M.units_by_cell != null and M.units_by_cell.has(dest):
				var occ = M.units_by_cell[dest]
				if occ != null and is_instance_valid(occ) and (occ is Unit):
					var ou := occ as Unit

					# NEW: forbid these completely
					if _is_avoid_unit(ou):
						continue

					if ou.team == Unit.Team.ALLY:
						continue
					# enemy is allowed (we crush)

			# Build an L-path and validate each step with car rules
			var p1: Array[Vector2i] = []
			var p2: Array[Vector2i] = []
			if M.has_method("_build_L_path"):
				p1 = M.call("_build_L_path", cell, dest, true)
				p2 = M.call("_build_L_path", cell, dest, false)
			else:
				# fallback: trivial (no move)
				continue

			var ok1 := _drive_path_ok(M, p1, structure_blocked)
			var ok2 := _drive_path_ok(M, p2, structure_blocked)

			var path: Array[Vector2i] = []
			if ok1:
				path = p1
			elif ok2:
				path = p2
			else:
				continue

			if path.is_empty():
				continue

			# Trim to drive_move_points
			if path.size() > drive_move_points:
				path.resize(drive_move_points)

			# Score:
			# - big reward for crushing any enemy along the path
			# - extra reward for ending on enemy
			# - otherwise move closer to nearest enemy
			var hits := 0
			for step in path:
				if enemy_by_cell.has(step):
					hits += 1

			var score := hits * 500
			if enemy_by_cell.has(dest):
				score += 400

			var nearest := 999999
			for e in enemies:
				if e == null or not is_instance_valid(e) or e.hp <= 0:
					continue
				var d = abs(e.cell.x - dest.x) + abs(e.cell.y - dest.y)
				if d < nearest:
					nearest = d
			score += (200 - nearest)

			if score > best_score:
				best_score = score
				best_dest = dest
				best_path = path

	return best_path

func _drive_path_ok(M: MapController, path: Array[Vector2i], structure_blocked: Dictionary) -> bool:
	for step in path:
		if not M.grid.in_bounds(step):
			return false
		if structure_blocked.has(step):
			return false
		if M.has_method("_is_walkable") and not M.call("_is_walkable", step):
			return false

		# NEW: never drive onto weakpoints / elite mechs
		if _cell_has_avoid_unit(M, step):
			return false

		# Occupancy rule per step:
		# - allies block
		# - enemies allowed (we crush as we enter)
		if M.units_by_cell != null and M.units_by_cell.has(step):
			var occ = M.units_by_cell[step]
			if occ != null and is_instance_valid(occ) and (occ is Unit):
				var ou := occ as Unit
				# NEW: treat avoid units as blockers (even if enemy)
				if _is_avoid_unit(ou):
					return false
				if ou.team == Unit.Team.ALLY:
					return false

	return true

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
	if M.has_method("get_unit_at_cell"):
		var u = M.call("get_unit_at_cell", c)
		if u != null and u is Unit:
			var uu := u as Unit
			if uu.team == Unit.Team.ENEMY and not _is_avoid_unit(uu):
				return uu

	for e in M.get_all_enemies():
		if e == null or not is_instance_valid(e):
			continue
		if e.cell == c and e.hp > 0 and not _is_avoid_unit(e):
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

func play_move_step_anim_grid(grid_dir: Vector2i, terrain_tm: TileMap) -> void:
	if terrain_tm != null:
		_terrain = terrain_tm

	_last_step_dir = grid_dir
	_play_anim_from_grid_direction(grid_dir)

func _resolve_terrain_from_group() -> TileMap:
	var nodes := get_tree().get_nodes_in_group("GameMap")
	for n in nodes:
		# Case A: the TileMap node itself is in the group
		if n is TileMap:
			return n as TileMap

		# Case B: a parent/root node is in the group; TileMap is a descendant
		if n is Node:
			# Try common child name first
			var terrain_node := (n as Node).find_child("Terrain", true, false)
			if terrain_node is TileMap:
				return terrain_node as TileMap

			# Otherwise scan descendants for the first TileMap
			var stack: Array[Node] = [n as Node]
			while not stack.is_empty():
				var cur = stack.pop_back()
				for ch in cur.get_children():
					if ch is TileMap:
						return ch as TileMap
					if ch is Node:
						stack.append(ch)

	return null

func car_step_sfx() -> void:
	if car_sfx != null:
		car_sfx.set_rpm01(0.7)
		car_sfx.tick(1.0)

func car_start_move_sfx() -> void:
	if car_sfx != null:
		car_sfx.set_engine(true)
		car_sfx.set_rpm01(0.55)

func car_end_move_sfx() -> void:
	if car_sfx != null:
		car_sfx.set_rpm01(0.15)
		car_sfx.set_engine(false)

func _is_avoid_unit(u: Object) -> bool:
	if u == null or not is_instance_valid(u):
		return false

	# Avoid by class (preferred if these are class_name scripts)
	if u is Weakpoint:
		return true
	if u is EliteMech:
		return true

	# Optional: avoid by group too (uncomment if you use groups)
	# if (u as Node).is_in_group("Weakpoint"):
	# 	return true
	# if (u as Node).is_in_group("EliteMech"):
	# 	return true

	return false

func _cell_has_avoid_unit(M: MapController, c: Vector2i) -> bool:
	if M == null or not is_instance_valid(M):
		return false
	if M.units_by_cell == null:
		return false
	if not M.units_by_cell.has(c):
		return false

	var occ = M.units_by_cell[c]
	if occ != null and is_instance_valid(occ) and (occ is Unit):
		return _is_avoid_unit(occ)

	return false
