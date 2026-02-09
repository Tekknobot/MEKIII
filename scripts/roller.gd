extends Unit
class_name Roller

# ---------------------------------------------------------
# Roller — "steamroller" mech/bot
# Special: ROLL — choose a destination; roll along a path,
# instantly killing enemies you enter (CarBot-style).
# Uses the SAME CarSFX node (ProceduralCarSFX) as CarBot.
# ---------------------------------------------------------

# -------------------------
# Visual / identity
# -------------------------
@export var portrait_tex: Texture2D = preload("res://sprites/Portraits/dog_port.png")
@export var thumbnail: Texture2D
@export var specials: Array[String] = ["ROLL"]
@export var special_desc: String = "Roll along a path and instantly crush enemies you pass through."

# -------------------------
# Roll tuning
# -------------------------
@export var roll_move_points := 6
@export var roll_step_time := 0.10
@export var crush_damage := 99999
@export var crush_sfx: StringName = &"mech_step"
@export var prefer_path_through_enemies := true

# -------------------------
# Motor vibration
# -------------------------
@export var idle_vibe_amp_px := 0.55
@export var idle_vibe_hz := 12.0
@export var roll_vibe_amp_px := 1.9
@export var roll_vibe_hz := 20.0

@export var vibrate_nearby_units := true
@export var vibe_radius := 2
@export var nearby_vibe_amp_px := 0.35

# -------------------------
# Anim names (reuse CarBot naming)
# -------------------------
@export var anim_idle: StringName = &"idle"
@export var anim_death: StringName = &"death"

# -------------------------
# Wiring / nodes
# -------------------------
@export var z_offset := 0
@onready var visual: Node2D = get_node_or_null("Visual") as Node2D
@export var flip_node_path: NodePath = NodePath("Visual/AnimatedSprite2D")
@export var anim_path: NodePath
@onready var _anim: AnimatedSprite2D = null

@export var terrain_path: NodePath
var _terrain: TileMap = null

# ✅ must be named "CarSFX" like CarBot
@onready var car_sfx: ProceduralCarSFX = get_node_or_null("CarSFX") as ProceduralCarSFX

# -------------------------
# Internal
# -------------------------
signal roll_finished
var _rolling := false
var _vibe_t := 0.0
var _vibe_amp := 0.0
var _vibe_hz := 0.0
var _death_started := false
var _last_step_dir := Vector2i(1, 1)

# -------------------------
# Anim (RecruitBot-style: flip instead of left/right anims)
# -------------------------
@export var anim_roll: StringName = &"idle"   # if you don't have a separate roll anim, keep same
@onready var _flip_node: CanvasItem = get_node_or_null(flip_node_path) as CanvasItem

# default facing LEFT
@export var default_facing_left := true
var _facing_left := true

func _ready() -> void:
	_terrain = get_node_or_null(terrain_path) as TileMap
	if _terrain == null:
		_terrain = _resolve_terrain_from_group()

	if anim_path != NodePath():
		_anim = get_node_or_null(anim_path) as AnimatedSprite2D
	if _anim == null:
		push_warning("Roller: anim_path not set or invalid")

	_facing_left = default_facing_left
	_apply_facing_flip()

	# play your one anim
	if _anim != null and anim_idle != StringName():
		_anim.play(anim_idle)

	_update_layer_from_cell()
	_set_motor_mode_idle()
	set_process(true)
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if hp <= 0 and not _dying:
		_die()

func _process(delta: float) -> void:
	if hp <= 0:
		_rolling = false
		_vibe_amp = 0.0
		_vibe_hz = 0.0
		if visual != null:
			visual.position = Vector2.ZERO
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

# ---------------------------------------------------------
# Special plumbing (match your MapController expectations)
# ---------------------------------------------------------
func get_special_range(id: String) -> int:
	var sid := id.to_lower().replace(" ", "_")
	if sid == "roll":
		return int(roll_move_points)
	return 0

# Call this from your special button handler like your other units:
#   await roller.perform_roll(M, clicked_cell)
func perform_roll(M: MapController, target_cell: Vector2i) -> void:
	if _rolling:
		return
	if M == null or not is_instance_valid(M) or M.grid == null:
		return
	if hp <= 0:
		return
	if not M.grid.in_bounds(target_cell):
		return

	# ✅ face toward the clicked destination immediately
	_update_facing_from_step(target_cell - cell)

	var path := _build_roll_path_to(M, target_cell)

	# ✅ if your L-path includes the current cell as the first entry, drop it
	if not path.is_empty() and path[0] == cell:
		path.remove_at(0)

	# nothing to do
	if path.is_empty():
		_set_motor_mode_idle()
		return

	_rolling = true
	_set_motor_mode_rolling()

	# start engine
	if car_sfx != null:
		car_sfx.set_engine(true)
		car_sfx.set_rpm01(0.70)

	# walk the path
	for next_cell in path:
		await _roll_step(M, next_cell)
		if self == null or not is_instance_valid(self) or hp <= 0:
			return

	# done
	_rolling = false

	# stop engine
	if car_sfx != null:
		car_sfx.set_rpm01(0.15)
		car_sfx.set_engine(false)

	_set_motor_mode_idle()

	# mark attacked
	if M != null and is_instance_valid(M):
		M._set_unit_attacked(self, true)

	emit_signal("roll_finished")

# ---------------------------------------------------------
# Movement step + crush
# ---------------------------------------------------------
func _roll_step(M: MapController, next_cell: Vector2i) -> void:
	if M == null or not is_instance_valid(M):
		return
	if M.grid == null or not M.grid.in_bounds(next_cell):
		return

	var grid_dir := next_cell - cell
	_last_step_dir = grid_dir

	if car_sfx != null:
		car_sfx.set_rpm01(0.85)
		car_sfx.tick(1.0)

	if _terrain == null and M != null and "terrain" in M:
		_terrain = M.terrain

	_update_facing_from_step(grid_dir)

	# crush BEFORE entering cell
	_crush_enemy_if_present(M, next_cell)

	# ✅ Use MapController mover so units_by_cell stays correct
	if M.has_method("_push_unit_to_cell"):
		await M.call("_push_unit_to_cell", self, next_cell)
	else:
		if "terrain" in M and M.terrain != null:
			set_cell(next_cell, M.terrain)
		else:
			cell = next_cell
			_snap_visual_to_cell(M)

	_apply_roll_vibe_burst(M)
	await get_tree().create_timer(roll_step_time).timeout

func _apply_facing_flip() -> void:
	if _flip_node == null:
		return

	# Facing left = default (not flipped)
	if _flip_node is Sprite2D:
		(_flip_node as Sprite2D).flip_h = not _facing_left
		return
	if _flip_node is AnimatedSprite2D:
		(_flip_node as AnimatedSprite2D).flip_h = not _facing_left
		return

	# ✅ Fallback: flip any Node2D / Control by mirroring scale.x
	# (works great when flip_node_path points to "Visual")
	if _flip_node is Node2D:
		var n := _flip_node as Node2D
		var sx = abs(n.scale.x)
		if sx < 0.0001:
			sx = 1.0
		n.scale.x = sx if _facing_left else -sx
		return
	if _flip_node is Control:
		var c := _flip_node as Control
		var sx = abs(c.scale.x)
		if sx < 0.0001:
			sx = 1.0
		c.scale.x = sx if _facing_left else -sx
		return


func _update_facing_from_step(grid_dir: Vector2i) -> void:
	grid_dir = Vector2i(signi(grid_dir.x), signi(grid_dir.y))
	if grid_dir == Vector2i.ZERO:
		return

	# Prefer terrain screen-space x to decide left/right (best for iso)
	if _terrain != null:
		var origin := _terrain.map_to_local(Vector2i.ZERO)
		var d := _terrain.map_to_local(grid_dir) - origin
		if abs(d.x) > 0.001:
			_facing_left = (d.x < 0.0)
			_apply_facing_flip()
			return

	# fallback
	if grid_dir.x != 0:
		_facing_left = (grid_dir.x < 0)
		_apply_facing_flip()
func _crush_enemy_if_present(M: MapController, at_cell: Vector2i) -> void:
	var victim := _get_enemy_at_cell(M, at_cell)
	if victim == null or not is_instance_valid(victim):
		return

	# never crush these
	if _is_avoid_unit(victim):
		return

	if victim.hp > 0:
		victim.take_damage(crush_damage)
		if car_sfx != null:
			car_sfx.hit(1.0)
		if M != null and M.has_method("_sfx"):
			M.call("_sfx", crush_sfx, 1.0, randf_range(0.95, 1.05), M._cell_world(at_cell))

# ---------------------------------------------------------
# Path building (CarBot-style L-path with roll rules)
# ---------------------------------------------------------
func _build_roll_path_to(M: MapController, dest: Vector2i) -> Array[Vector2i]:
	if M == null or not is_instance_valid(M) or M.grid == null:
		return []
	if not M.grid.in_bounds(dest):
		return []

	var r := int(roll_move_points)
	if abs(dest.x - cell.x) + abs(dest.y - cell.y) > r:
		return []

	# structure blocked (same pattern you use elsewhere)
	var structure_blocked: Dictionary = {}
	if M.game_ref != null and "structure_blocked" in M.game_ref:
		structure_blocked = M.game_ref.structure_blocked

	if structure_blocked.has(dest):
		return []
	if M.has_method("_is_walkable") and not M.call("_is_walkable", dest):
		# allow dest if it has an enemy (we can roll onto it)
		if not _cell_has_enemy(M, dest):
			return []

	# never roll onto weakpoints / elite mechs
	if _cell_has_avoid_unit(M, dest):
		return []

	# Build two L-paths, pick the one that is valid and (optionally) hits more enemies
	var p1: Array[Vector2i] = []
	var p2: Array[Vector2i] = []
	if M.has_method("_build_L_path"):
		p1 = M.call("_build_L_path", cell, dest, true)
		p2 = M.call("_build_L_path", cell, dest, false)
	else:
		return []

	var ok1 := _roll_path_ok(M, p1, structure_blocked)
	var ok2 := _roll_path_ok(M, p2, structure_blocked)

	var path: Array[Vector2i] = []
	if ok1 and ok2:
		if prefer_path_through_enemies:
			path = p1 if _count_enemies_on_path(M, p1) >= _count_enemies_on_path(M, p2) else p2
		else:
			path = p1
	elif ok1:
		path = p1
	elif ok2:
		path = p2
	else:
		return []

	# Trim (never exceed roll_move_points)
	if path.size() > roll_move_points:
		path.resize(roll_move_points)

	return path

func _roll_path_ok(M: MapController, path: Array[Vector2i], structure_blocked: Dictionary) -> bool:
	if path.is_empty():
		return false

	for step in path:
		if not M.grid.in_bounds(step):
			return false
		if structure_blocked.has(step):
			return false

		# never roll into avoid units
		if _cell_has_avoid_unit(M, step):
			return false

		# walkability: allow enemies, forbid allies
		if M.units_by_cell != null and M.units_by_cell.has(step):
			var occ = M.units_by_cell[step]
			if occ != null and is_instance_valid(occ) and (occ is Unit):
				var ou := occ as Unit
				if _is_avoid_unit(ou):
					return false
				if ou.team == Unit.Team.ALLY:
					return false
				# enemy is allowed (we crush)

		# if you also block tiles via _is_walkable, keep enemy exception
		if M.has_method("_is_walkable") and not M.call("_is_walkable", step):
			if not _cell_has_enemy(M, step):
				return false

	return true

func _count_enemies_on_path(M: MapController, path: Array[Vector2i]) -> int:
	var n := 0
	for c in path:
		if _cell_has_enemy(M, c):
			n += 1
	return n

func _cell_has_enemy(M: MapController, c: Vector2i) -> bool:
	if M == null or not is_instance_valid(M):
		return false
	if M.units_by_cell == null:
		return false
	if not M.units_by_cell.has(c):
		return false
	var occ = M.units_by_cell[c]
	if occ != null and is_instance_valid(occ) and (occ is Unit):
		var u := occ as Unit
		return (u.team == Unit.Team.ENEMY) and not _is_avoid_unit(u) and u.hp > 0
	return false

# ---------------------------------------------------------
# Anim + vibe helpers (copied pattern from CarBot)
# ---------------------------------------------------------
func _update_layer_from_cell() -> void:
	z_index = int(cell.x + cell.y + z_offset)
	z_as_relative = false

func _snap_visual_to_cell(M: MapController) -> void:
	if M != null and is_instance_valid(M) and M.has_method("_cell_world"):
		global_position = M.call("_cell_world", cell)
	_update_layer_from_cell()

func _set_motor_mode_idle() -> void:
	_vibe_amp = idle_vibe_amp_px
	_vibe_hz = idle_vibe_hz
	if _anim != null and anim_idle != StringName():
		_anim.play(anim_idle)

func _set_motor_mode_rolling() -> void:
	_vibe_amp = roll_vibe_amp_px
	_vibe_hz = roll_vibe_hz

func _apply_roll_vibe_burst(M: MapController) -> void:
	if not vibrate_nearby_units:
		return
	if M == null or not is_instance_valid(M):
		return
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

# ---------------------------------------------------------
# Death (stop engine, play death anim if available)
# ---------------------------------------------------------
func play_death_anim() -> void:
	if _death_started:
		return
	_death_started = true

	_rolling = false
	_vibe_amp = 0.0
	_vibe_hz = 0.0
	if visual != null:
		visual.position = Vector2.ZERO

	if car_sfx != null:
		car_sfx.set_engine(false)

	set_process(false)
	set_physics_process(false)

	if _anim == null and anim_path != NodePath():
		_anim = get_node_or_null(anim_path) as AnimatedSprite2D

	if _anim == null or _anim.sprite_frames == null:
		queue_free()
		return

	var death_name := anim_death
	if not _anim.sprite_frames.has_animation(death_name):
		if _anim.sprite_frames.has_animation("death"):
			death_name = &"death"
		else:
			queue_free()
			return

	_anim.sprite_frames.set_animation_loop(death_name, false)
	_anim.stop()
	_anim.play(death_name)
	await _anim.animation_finished
	queue_free()

# ---------------------------------------------------------
# Avoid rules (same as CarBot)
# ---------------------------------------------------------
func _is_avoid_unit(u: Object) -> bool:
	if u == null or not is_instance_valid(u):
		return false
	if u is Weakpoint:
		return true
	if u is EliteMech:
		return true
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

func _get_enemy_at_cell(M: MapController, c: Vector2i) -> Unit:
	if M.has_method("get_unit_at_cell"):
		var u = M.call("get_unit_at_cell", c)
		if u != null and u is Unit:
			var uu := u as Unit
			if uu.team == Unit.Team.ENEMY and uu.hp > 0 and not _is_avoid_unit(uu):
				return uu
	for e in M.get_all_enemies():
		if e == null or not is_instance_valid(e):
			continue
		if e.cell == c and e.hp > 0 and not _is_avoid_unit(e):
			return e
	return null

# ---------------------------------------------------------
# Terrain resolver (same as CarBot)
# ---------------------------------------------------------
func _resolve_terrain_from_group() -> TileMap:
	var nodes := get_tree().get_nodes_in_group("GameMap")
	for n in nodes:
		if n is TileMap:
			return n as TileMap
		if n is Node:
			var terrain_node := (n as Node).find_child("Terrain", true, false)
			if terrain_node is TileMap:
				return terrain_node as TileMap
			var stack: Array[Node] = [n as Node]
			while not stack.is_empty():
				var cur = stack.pop_back()
				for ch in cur.get_children():
					if ch is TileMap:
						return ch as TileMap
					if ch is Node:
						stack.append(ch)
	return null

func auto_roll_action(M: MapController) -> void:
	if _rolling:
		return
	if M == null or not is_instance_valid(M) or M.grid == null:
		return
	if M.get_all_enemies().is_empty():
		_set_motor_mode_idle()
		return

	var path := _pick_roll_path(M) # ✅ just picks a dest + calls your existing builder
	if path.is_empty():
		_set_motor_mode_idle()
		return

	_rolling = true
	_set_motor_mode_rolling()

	if car_sfx != null:
		car_sfx.set_engine(true)
		car_sfx.set_rpm01(0.70)

	for next_cell in path:
		await _roll_step(M, next_cell)
		if self == null or not is_instance_valid(self) or hp <= 0:
			return

	_rolling = false
	if car_sfx != null:
		car_sfx.set_rpm01(0.15)
		car_sfx.set_engine(false)

	_set_motor_mode_idle()

	if M != null and is_instance_valid(M):
		M._set_unit_attacked(self, true)

func _pick_roll_path(M: MapController) -> Array[Vector2i]:
	var enemies := M.get_all_enemies()
	if enemies.is_empty():
		return []

	var structure_blocked: Dictionary = {}
	if M.game_ref != null and "structure_blocked" in M.game_ref:
		structure_blocked = M.game_ref.structure_blocked

	# quick enemy lookup
	var enemy_by_cell: Dictionary = {}
	for e in enemies:
		if e != null and is_instance_valid(e) and e.hp > 0:
			enemy_by_cell[e.cell] = e

	var r := int(roll_move_points)
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
			if _cell_has_avoid_unit(M, dest):
				continue

			# allies block, enemies allowed
			if M.units_by_cell != null and M.units_by_cell.has(dest):
				var occ = M.units_by_cell[dest]
				if occ != null and is_instance_valid(occ) and (occ is Unit):
					var ou := occ as Unit
					if _is_avoid_unit(ou):
						continue
					if ou.team == Unit.Team.ALLY:
						continue

			# ✅ reuse your existing builder
			var path := _build_roll_path_to(M, dest)
			if path.is_empty():
				continue

			# score: prefer crushing
			var hits := 0
			for step in path:
				if enemy_by_cell.has(step):
					hits += 1

			var score := hits * 500
			if enemy_by_cell.has(dest):
				score += 300

			# small tie-break: end closer to nearest enemy
			var nearest := 999999
			for e in enemies:
				if e == null or not is_instance_valid(e) or e.hp <= 0:
					continue
				var d = abs(e.cell.x - dest.x) + abs(e.cell.y - dest.y)
				nearest = min(nearest, d)
			score += (200 - nearest)

			if score > best_score:
				best_score = score
				best_path = path

	return best_path

# Called by MapController during manual player movement (world-space)
func play_move_step_anim(from_world: Vector2, to_world: Vector2) -> void:
	# If you have a terrain reference, keep it fresh
	if _terrain == null:
		_terrain = get_node_or_null(terrain_path) as TileMap
		if _terrain == null:
			_terrain = _resolve_terrain_from_group()

	var d := to_world - from_world
	if d.length() < 0.001:
		return

	# Convert screen-space delta into "left/right" facing
	_facing_left = (d.x < 0.0)
	_apply_facing_flip()

	# Optional: ensure anim is playing
	if _anim != null and anim_idle != StringName():
		_anim.play(anim_idle)


# Called by MapController if it has grid-dir available (cleaner than world-space)
func play_move_step_anim_grid(grid_dir: Vector2i, terrain_tm: TileMap) -> void:
	if terrain_tm != null:
		_terrain = terrain_tm

	_update_facing_from_step(grid_dir)

	# Optional: ensure anim is playing
	if _anim != null and anim_idle != StringName():
		_anim.play(anim_idle)
