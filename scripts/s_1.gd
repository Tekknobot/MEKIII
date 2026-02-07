extends Unit
class_name S1
# Robotic Treadmill - mobile scanner platform
# Special 1: LASER GRID - projects a scanning grid that detonates at intersections
# Special 2: OVERCHARGE - charges up and fires multiple laser beams in a cone, exploding on impact

# -------------------------
# Visual / identity
# -------------------------
@export var portrait_tex: Texture2D = preload("res://sprites/Portraits/dog_port.png") # swap to treadmill portrait
@export var thumbnail: Texture2D
@export var specials: Array[String] = ["LASER GRID", "OVERCHARGE"]
@export var special_desc: String = "Deploy scanning grids or unleash overcharged laser volleys."

@export var attack_anim_name: StringName = &"attack"
@export var idle_anim_name: StringName = &"idle"

# -------------------------
# Base stats
# -------------------------
@export var base_move_range := 4
@export var base_attack_range := 4
@export var base_max_hp := 6
@export var basic_laser_damage := 2

# -------------------------
# Basic Attack - Scanner Laser
# -------------------------
@export var scanner_line_color: Color = Color(0.2, 0.8, 1.0, 0.9)  # cyan laser
@export var scanner_line_width := 3.0
@export var scanner_glow_color: Color = Color(0.4, 1.0, 1.0, 0.7)
@export var scanner_duration := 0.5
@export var scanner_sfx_id: StringName = &"laser_fire"

# -------------------------
# Special 1: LASER GRID tuning
# -------------------------
@export var grid_range := 6
@export var grid_size := 3  # creates a 3x3 grid
@export var grid_damage := 2
@export var grid_cooldown := 5
@export var grid_min_safe_dist := 2

# Grid visuals
@export var grid_line_color: Color = Color(1.0, 0.3, 0.3, 0.8)  # red grid
@export var grid_line_width := 2.0
@export var grid_glow_color: Color = Color(1.0, 0.5, 0.5, 0.6)
@export var grid_setup_duration := 0.6  # time to draw grid
@export var grid_detonate_delay := 0.3  # delay before explosions

# Grid explosions
@export var grid_explosion_scene: PackedScene
@export var grid_explosion_z := 999
@export var grid_sfx_id: StringName = &"grid_setup"
@export var grid_detonate_sfx_id: StringName = &"grid_detonate"

@export var iso_feet_offset_y := 16.0

# -------------------------
# Special 2: OVERCHARGE tuning
# -------------------------
@export var overcharge_range := 7
@export var overcharge_beam_count := 5  # number of beams in the cone
@export var overcharge_cone_angle := 60.0  # degrees
@export var overcharge_damage := 3
@export var overcharge_cooldown := 6
@export var overcharge_min_safe_dist := 1

# Overcharge visuals
@export var overcharge_line_color: Color = Color(1.0, 0.9, 0.2, 1.0)  # yellow-orange beam
@export var overcharge_line_width := 5.0
@export var overcharge_glow_color: Color = Color(1.0, 0.7, 0.0, 0.8)
@export var overcharge_charge_duration := 0.4  # charging animation
@export var overcharge_fire_duration := 0.3  # beams visible time
@export var overcharge_pulse_speed := 15.0

# Overcharge SFX
@export var overcharge_charge_sfx_id: StringName = &"overcharge_charge"
@export var overcharge_fire_sfx_id: StringName = &"overcharge_fire"
@export var overcharge_hit_sfx_id: StringName = &"overcharge_hit"

# Overcharge explosions
@export var overcharge_explosion_scene: PackedScene

func _ready() -> void:
	set_meta("portrait_tex", portrait_tex)
	set_meta("display_name", display_name)

	footprint_size = Vector2i(1, 1)
	move_range = base_move_range
	attack_range = base_attack_range

	max_hp = max(max_hp, base_max_hp)
	hp = clamp(hp, 0, max_hp)

	super._ready()

# -------------------------
# Specials list (for UI)
# -------------------------
func get_available_specials() -> Array[String]:
	return specials

func can_use_special(id: String) -> bool:
	id = id.to_lower().replace(" ", "_")
	if id == "laser_grid":
		return int(special_cd.get("laser_grid", 0)) <= 0
	elif id == "overcharge":
		return int(special_cd.get("overcharge", 0)) <= 0
	return false

func get_special_range(id: String) -> int:
	id = id.to_lower().replace(" ", "_")
	if id == "laser_grid":
		return grid_range
	elif id == "overcharge":
		return overcharge_range
	return 0

func get_special_min_distance(id: String) -> int:
	id = id.to_lower().replace(" ", "_")
	if id == "laser_grid":
		return grid_min_safe_dist
	elif id == "overcharge":
		return overcharge_min_safe_dist
	return 0

# -------------------------------------------------------
# Basic attack - Scanner Laser Beam
# -------------------------------------------------------
func perform_basic_attack(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
		return
	if not _alive():
		return

	# range check (Manhattan)
	if abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y) > attack_range:
		return

	var tgt := M.unit_at_cell(target_cell)
	if tgt == null or not is_instance_valid(tgt):
		return
	if ("team" in tgt) and (tgt.team == team):
		return

	_face_toward_cell(target_cell)
	_play_attack_anim_once()
	_sfx_at_cell(M, scanner_sfx_id, cell)

	_apply_damage_safely(tgt, basic_laser_damage + attack_damage)

	if M.has_method("_flash_unit_white"):
		M.call("_flash_unit_white", tgt, 0.10)
	elif M.has_method("flash_unit_white"):
		M.call("flash_unit_white", tgt, 0.10)

	_play_idle_anim()

# -------------------------------------------------------
# Special 1: LASER GRID
# Projects a grid of laser lines that explode at intersections
# -------------------------------------------------------
func perform_laser_grid(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
		return
	if not _alive():
		return

	var id_key := "laser_grid"
	if int(special_cd.get(id_key, 0)) > 0:
		return

	var d = abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y)
	if d < grid_min_safe_dist or d > grid_range:
		return

	_face_toward_cell(target_cell)
	_play_attack_anim_once()
	_sfx_at_cell(M, grid_sfx_id, cell)

	# Calculate grid bounds (grid_size x grid_size centered on target)
	var half_size := grid_size / 2
	var grid_start := target_cell - Vector2i(half_size, half_size)

	# Build intersection cells ONLY (no drawing)
	var intersection_cells: Array[Vector2i] = []
	for y in range(grid_size + 1):
		var yy := grid_start.y + y
		for x in range(grid_size + 1):
			var inter := Vector2i(grid_start.x + x, yy)
			if _cell_in_bounds(M, inter):
				intersection_cells.append(inter)

	# Keep your setup pacing (still feels like “deploying”)
	await get_tree().create_timer(grid_setup_duration).timeout
	if not _alive():
		return

	await get_tree().create_timer(grid_detonate_delay).timeout
	if not _alive():
		return

	_sfx_at_cell(M, grid_detonate_sfx_id, target_cell)

	# Explode at all intersections
	for inter_cell in intersection_cells:
		if not _alive():
			break

		# SKY STRIKE LINE (from above -> cell)
		var strike := _create_sky_strike(M, inter_cell)

		_spawn_grid_explosion(M, inter_cell)

		var tgt := M.unit_at_cell(inter_cell)
		if tgt != null and is_instance_valid(tgt):
			if ("team" in tgt) and (tgt.team == team):
				# still fade the strike
				_fade_and_free(strike, 0.10)
				continue

			if M.has_method("_flash_unit_white"):
				M.call("_flash_unit_white", tgt, 0.10)
			elif M.has_method("flash_unit_white"):
				M.call("flash_unit_white", tgt, 0.10)

			_apply_damage_safely(tgt, grid_damage + attack_damage)

		# let the beam be visible briefly, then fade
		await get_tree().create_timer(0.02).timeout
		_fade_and_free(strike, 0.10)

	_play_idle_anim()
	special_cd[id_key] = grid_cooldown

func _create_sky_strike(M: MapController, hit_cell: Vector2i) -> Node2D:
	# A vertical-ish beam from "sky" down to the cell.
	var hit_pos := _cell_to_global(M, hit_cell)
	hit_pos.y -= iso_feet_offset_y

	# Start above the viewport so it reads as "from the sky"
	var vp := get_viewport().get_visible_rect().size
	var start_pos := hit_pos
	start_pos.y = -64.0  # offscreen top (tweak)

	var line := Line2D.new()
	line.width = grid_line_width * 1.0
	line.default_color = grid_glow_color
	line.antialiased = true
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.add_point(start_pos)
	line.add_point(hit_pos)

	# inner core
	var core := Line2D.new()
	core.width = grid_line_width
	core.default_color = grid_line_color
	core.antialiased = true
	core.begin_cap_mode = Line2D.LINE_CAP_ROUND
	core.end_cap_mode = Line2D.LINE_CAP_ROUND
	core.add_point(start_pos)
	core.add_point(hit_pos)

	var container := Node2D.new()
	container.add_child(line) # glow first
	container.add_child(core) # core on top

	# depth
	var z_base := 1000
	var z_per := 1
	if M != null and ("z_base" in M): z_base = int(M.z_base)
	if M != null and ("z_per_cell" in M): z_per = int(M.z_per_cell)
	container.z_index = z_base + (hit_cell.x + hit_cell.y) * z_per + 50

	M.add_child(container)
	return container

func _fade_and_free(n: Node2D, t: float = 0.12) -> void:
	if n == null or not is_instance_valid(n):
		return
	var tw := create_tween()
	tw.tween_property(n, "modulate:a", 0.0, t)
	tw.tween_callback(n.queue_free)

# -------------------------------------------------------
# Special 2: OVERCHARGE
# Fires multiple laser beams in a cone, each exploding on impact
# -------------------------------------------------------
func perform_overcharge(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
		return
	if not _alive():
		return

	var id_key := "overcharge"
	if int(special_cd.get(id_key, 0)) > 0:
		return

	# keep your click-gate
	var d = abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y)
	if d < overcharge_min_safe_dist or d > overcharge_range:
		return

	_face_toward_cell(target_cell)

	# -------------------------------------------------
	# Charge phase: replay attack anim repeatedly
	# -------------------------------------------------
	_sfx_at_cell(M, overcharge_charge_sfx_id, cell)

	var tick := 0.12 # how often to replay attack during charge (tweak)
	var elapsed := 0.0
	while elapsed < overcharge_charge_duration:
		if not _alive():
			return
		_play_attack_anim_once()
		await get_tree().create_timer(tick).timeout
		elapsed += tick

	if not _alive():
		return

	# Collect ALL valid enemy targets in range (Manhattan)
	var targets := _get_enemy_cells_in_range(M, overcharge_range)

	# Fire phase
	_sfx_at_cell(M, overcharge_fire_sfx_id, cell)
	if not _alive():
		return

	# Travel + hit each target (grid-step laser)
	for c in targets:
		if not _alive():
			break

		await _animate_overcharge_bresenham(
			M,
			cell,
			c,
			overcharge_line_color,
			overcharge_glow_color,
			overcharge_line_width,
			0.03 # step_time
		)

		# impact FX + damage
		if overcharge_explosion_scene != null:
			_spawn_overcharge_explosion(M, c)

		_sfx_at_cell(M, overcharge_hit_sfx_id, c)

		var tgt := M.unit_at_cell(c)
		if tgt != null and is_instance_valid(tgt):
			if ("team" in tgt) and (tgt.team == team):
				continue

			if M.has_method("_flash_unit_white"):
				M.call("_flash_unit_white", tgt, 0.15)
			elif M.has_method("flash_unit_white"):
				M.call("flash_unit_white", tgt, 0.15)

			_apply_damage_safely(tgt, overcharge_damage + attack_damage)

		await get_tree().create_timer(0.02).timeout

	_play_idle_anim()
	special_cd[id_key] = overcharge_cooldown

func _bresenham_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []

	var x0 := a.x
	var y0 := a.y
	var x1 := b.x
	var y1 := b.y

	var dx = abs(x1 - x0)
	var dy = -abs(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err = dx + dy

	while true:
		cells.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 = err * 2
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy

	return cells

func _animate_overcharge_bresenham(
	M: MapController,
	from_cell: Vector2i,
	to_cell: Vector2i,
	color: Color,
	glow: Color,
	width: float,
	step_time := 0.035
) -> void:
	if M == null:
		return

	var cells := _bresenham_cells(from_cell, to_cell)
	if cells.size() < 2:
		return

	# beam visuals
	var container := Node2D.new()
	var glow_line := Line2D.new()
	var core_line := Line2D.new()

	glow_line.width = width * 1.0
	glow_line.default_color = glow
	glow_line.antialiased = true

	core_line.width = width
	core_line.default_color = color
	core_line.antialiased = true

	container.add_child(glow_line)
	container.add_child(core_line)
	container.z_index = 1000

	M.add_child(container)

	# walk the grid path
	for i in range(cells.size()):
		var pts: Array[Vector2] = []

		for j in range(i + 1):
			var p := _cell_to_global(M, cells[j])
			p.y -= iso_feet_offset_y
			pts.append(p)

		glow_line.clear_points()
		core_line.clear_points()
		for p in pts:
			glow_line.add_point(p)
			core_line.add_point(p)

		await get_tree().create_timer(step_time).timeout

	# quick fade
	var tw := create_tween()
	tw.tween_property(container, "modulate:a", 0.0, 0.12)
	tw.tween_callback(container.queue_free)

func _get_enemy_cells_in_range(M: MapController, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []

	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var c := cell + Vector2i(dx, dy)
			if abs(dx) + abs(dy) > r:
				continue
			if not _cell_in_bounds(M, c):
				continue

			var u := M.unit_at_cell(c)
			if u == null or not is_instance_valid(u):
				continue
			if ("team" in u) and (u.team == team):
				continue
			if ("hp" in u) and int(u.hp) <= 0:
				continue

			out.append(c)

	return out

# -------------------------
# LASER GRID helpers
# -------------------------
func _create_grid_line(M: MapController, from_cell: Vector2i, to_cell: Vector2i) -> Node2D:
	var line := Line2D.new()
	line.width = grid_line_width
	line.default_color = grid_line_color
	line.antialiased = true
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND

	var from_pos := _cell_to_global(M, from_cell)
	from_pos.y -= iso_feet_offset_y

	var to_pos := _cell_to_global(M, to_cell)
	to_pos.y -= iso_feet_offset_y

	line.add_point(from_pos)
	line.add_point(to_pos)

	# Add glow effect
	var glow := Line2D.new()
	glow.width = grid_line_width * 2.5
	glow.default_color = grid_glow_color
	glow.antialiased = true
	glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	glow.end_cap_mode = Line2D.LINE_CAP_ROUND
	glow.add_point(from_pos)
	glow.add_point(to_pos)
	glow.z_index = -1

	var container := Node2D.new()
	container.add_child(glow)
	container.add_child(line)
	container.z_index = 1000

	M.add_child(container)
	return container

func _animate_grid_pulse(grid_lines: Array[Node2D], duration: float) -> void:
	if grid_lines.is_empty():
		return

	var elapsed := 0.0
	
	while elapsed < duration:
		elapsed += get_process_delta_time()
		var t := elapsed / duration
		
		for line_container in grid_lines:
			if not is_instance_valid(line_container):
				continue
			
			var glow := line_container.get_child(0) as Line2D
			if glow != null:
				var pulse := sin(t * 10.0 * TAU) * 0.5 + 0.5
				var alpha := grid_glow_color.a * (0.4 + pulse * 0.6)
				glow.default_color = Color(grid_glow_color.r, grid_glow_color.g, grid_glow_color.b, alpha)
		
		await get_tree().process_frame

func _spawn_grid_explosion(M: MapController, c: Vector2i) -> void:
	if M == null or grid_explosion_scene == null:
		return

	var fx := grid_explosion_scene.instantiate()
	if fx == null:
		return

	if fx is Node2D:
		var n := fx as Node2D
		var p := _cell_to_global(M, c)
		p.y -= iso_feet_offset_y
		n.global_position = p

		var z_base := 0
		var z_per := 1
		if "z_base" in M: z_base = int(M.z_base)
		if "z_per_cell" in M: z_per = int(M.z_per_cell)
		n.z_index = z_base + (c.x + c.y) * z_per + 1

	M.add_child(fx)

# -------------------------
# OVERCHARGE helpers
# -------------------------
func _calculate_cone_targets(M: MapController, center_target: Vector2i) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	
	# Direction vector from unit to target
	var dir := Vector2(center_target - cell)
	if dir.length() < 0.1:
		return targets
	
	dir = dir.normalized()
	
	# Calculate perpendicular vector for cone spread
	var perp := Vector2(-dir.y, dir.x)
	
	# Generate beam targets in a cone
	var half_beams := overcharge_beam_count / 2
	for i in range(overcharge_beam_count):
		var offset_factor := (i - half_beams) / float(max(1, half_beams))
		var angle_rad := deg_to_rad(offset_factor * overcharge_cone_angle * 0.5)
		
		# Rotate direction by angle
		var rotated := Vector2(
			dir.x * cos(angle_rad) - dir.y * sin(angle_rad),
			dir.x * sin(angle_rad) + dir.y * cos(angle_rad)
		)
		
		# Find hit point along this beam direction
		var max_dist := overcharge_range
		var hit_cell := _raycast_to_cell(M, cell, rotated, max_dist)
		
		if hit_cell != cell:  # Valid hit
			targets.append(hit_cell)
	
	return targets

func _raycast_to_cell(M: MapController, start_cell: Vector2i, direction: Vector2, max_dist: int) -> Vector2i:
	# Step along direction until we hit something or reach max distance
	for dist in range(1, max_dist + 1):
		var check_pos := Vector2(start_cell) + direction * float(dist)
		var check_cell := Vector2i(round(check_pos.x), round(check_pos.y))
		
		if not _cell_in_bounds(M, check_cell):
			return start_cell + Vector2i(round(direction.x * (dist - 1)), round(direction.y * (dist - 1)))
		
		# Check for unit or structure
		var unit := M.unit_at_cell(check_cell)
		if unit != null and is_instance_valid(unit):
			return check_cell
		
		var structure: Object = null
		if M.has_method("_structure_at_cell"):
			structure = M.call("_structure_at_cell", check_cell)
		elif M.has_method("structure_at_cell"):
			structure = M.call("structure_at_cell", check_cell)
		if structure != null and is_instance_valid(structure):
			return check_cell
	
	# No hit, return max range cell
	return start_cell + Vector2i(round(direction.x * max_dist), round(direction.y * max_dist))

func _show_charge_effect(M: MapController) -> void:
	# Could add visual charging particles here
	await get_tree().create_timer(overcharge_charge_duration).timeout

func _animate_overcharge_pulse(beams: Array[Node2D], duration: float) -> void:
	if beams.is_empty():
		return

	var elapsed := 0.0
	
	while elapsed < duration:
		elapsed += get_process_delta_time()
		var t := elapsed / duration
		
		for beam_container in beams:
			if not is_instance_valid(beam_container):
				continue
			
			var glow := beam_container.get_child(0) as Line2D
			if glow != null:
				var pulse := sin(t * overcharge_pulse_speed * TAU) * 0.5 + 0.5
				var alpha := overcharge_glow_color.a * (0.5 + pulse * 0.5)
				glow.default_color = Color(overcharge_glow_color.r, overcharge_glow_color.g, overcharge_glow_color.b, alpha)
		
		await get_tree().process_frame

func _spawn_overcharge_explosion(M: MapController, c: Vector2i) -> void:
	if M == null or overcharge_explosion_scene == null:
		return

	var fx := overcharge_explosion_scene.instantiate()
	if fx == null:
		return

	if fx is Node2D:
		var n := fx as Node2D
		var p := _cell_to_global(M, c)
		p.y -= iso_feet_offset_y
		n.global_position = p

		var z_base := 0
		var z_per := 1
		if "z_base" in M: z_base = int(M.z_base)
		if "z_per_cell" in M: z_per = int(M.z_per_cell)
		n.z_index = z_base + (c.x + c.y) * z_per + 1

	M.add_child(fx)

# -------------------------
# Generic laser beam creator
# -------------------------
func _create_laser_beam(M: MapController, from_cell: Vector2i, to_cell: Vector2i, color: Color, glow: Color, width: float) -> Node2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.antialiased = true
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND

	var from_pos := _cell_to_global(M, from_cell)
	from_pos.y -= iso_feet_offset_y

	var to_pos := _cell_to_global(M, to_cell)
	to_pos.y -= iso_feet_offset_y

	line.add_point(from_pos)
	line.add_point(to_pos)

	# Add glow effect
	var glow_line := Line2D.new()
	glow_line.width = width * 3.0
	glow_line.default_color = glow
	glow_line.antialiased = true
	glow_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	glow_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	glow_line.add_point(from_pos)
	glow_line.add_point(to_pos)
	glow_line.z_index = -1

	var container := Node2D.new()
	container.add_child(glow_line)
	container.add_child(line)
	container.z_index = 1000

	M.add_child(container)
	return container

# -------------------------
# Helpers
# -------------------------
func _cleanup_lines(lines: Array[Node2D]) -> void:
	for line in lines:
		if is_instance_valid(line):
			_fade_out_line(line)

func _fade_out_line(line_container: Node2D) -> void:
	if not is_instance_valid(line_container):
		return

	var tween := create_tween()
	tween.tween_property(line_container, "modulate:a", 0.0, 0.2)
	tween.tween_callback(line_container.queue_free)

func _cell_to_global(M: MapController, c: Vector2i) -> Vector2:
	if M != null and M.terrain != null:
		var map_local := M.terrain.map_to_local(c)
		return M.terrain.to_global(map_local)
	return Vector2(c.x * 32, c.y * 32)

func _cell_in_bounds(M: MapController, c: Vector2i) -> bool:
	if M.grid != null and M.grid.has_method("in_bounds"):
		return bool(M.grid.in_bounds(c))
	if M.grid != null and ("w" in M.grid) and ("h" in M.grid):
		return c.x >= 0 and c.y >= 0 and c.x < int(M.grid.w) and c.y < int(M.grid.h)
	return true

func _sfx_at_cell(M: MapController, sfx_id: StringName, c: Vector2i) -> void:
	if M == null:
		return
	if sfx_id == &"":
		return
	if M.has_method("_sfx"):
		M.call("_sfx", sfx_id, 1.0, randf_range(0.97, 1.03), _cell_to_global(M, c))

func _apply_damage_safely(tgt: Object, dmg: int) -> void:
	if tgt == null:
		return

	if tgt.has_method("take_damage"):
		var m := tgt.get_method_list().filter(func(x): return x.name == "take_damage")
		if m.size() > 0 and m[0].args.size() >= 2:
			tgt.call("take_damage", dmg, self)
		else:
			tgt.call("take_damage", dmg)
		return

	if tgt.has_method("apply_damage"):
		var m2 := tgt.get_method_list().filter(func(x): return x.name == "apply_damage")
		if m2.size() > 0 and m2[0].args.size() >= 2:
			tgt.call("apply_damage", dmg, self)
		else:
			tgt.call("apply_damage", dmg)
		return

	if "hp" in tgt:
		tgt.hp -= dmg
		if tgt.hp <= 0:
			if tgt.has_method("die"):
				tgt.call("die")
			else:
				tgt.queue_free()

func _face_toward_cell(target_cell: Vector2i) -> void:
	var spr2 := get_node_or_null("Sprite2D") as Sprite2D
	if spr2 == null:
		spr2 = get_node_or_null("Visual/Sprite2D") as Sprite2D
	if spr2 == null:
		return
	if target_cell.x < cell.x:
		spr2.flip_h = true
	elif target_cell.x > cell.x:
		spr2.flip_h = false

func _play_attack_anim_once() -> void:
	var sprA := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprA == null:
		sprA = get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D
	if sprA == null:
		return

	var anim := String(attack_anim_name)
	if sprA.sprite_frames == null:
		return
	if not sprA.sprite_frames.has_animation(anim):
		return

	sprA.stop()
	sprA.play(anim)

func _play_idle_anim() -> void:
	var sprA := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprA == null:
		sprA = get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D
	if sprA == null:
		return

	var anim := String(idle_anim_name)
	if sprA.sprite_frames == null:
		return
	if not sprA.sprite_frames.has_animation(anim):
		return

	sprA.play(anim)

func _alive() -> bool:
	return is_instance_valid(self) and (not ("_dying" in self and self._dying)) and hp > 0

func get_hud_extras() -> Dictionary:
	return {
		"Grid Range": str(grid_range),
		"Grid Damage": str(grid_damage + attack_damage),
		"Overcharge Range": str(overcharge_range),
		"Overcharge Damage": str(overcharge_damage + attack_damage),
	}
