extends Unit
class_name S3
# Spiderbot-style mech
# Special 1: NOVA - an 8-point star burst (cross + diagonals) centered on a target cell,
# then a delayed "aftershock" ring one tile farther out.
# Special 2: WEB - shoot sticky webs at multiple targets, pulling them together and dealing damage

# -------------------------
# Visual / identity
# -------------------------
@export var portrait_tex: Texture2D = preload("res://sprites/Portraits/dog_port.png") # swap to spider portrait
@export var thumbnail: Texture2D
@export var specials: Array[String] = ["NOVA", "WEB"]
@export var special_desc: String = "Detonate a starburst blast, or ensnare enemies with sticky webs."

@export var attack_anim_name: StringName = &"attack"
@export var idle_anim_name: StringName = &"idle"

# -------------------------
# Base stats
# -------------------------
@export var base_move_range := 5
@export var base_attack_range := 3
@export var base_max_hp := 7
@export var basic_melee_damage := 2

# -------------------------
# Special 1: NOVA tuning
# -------------------------
@export var nova_range := 6
@export var nova_radius := 3
@export var nova_damage := 2
@export var nova_cooldown := 5
@export var nova_min_safe_dist := 2

# Aftershock ring (optional)
@export var aftershock_enabled := true
@export var aftershock_delay := 0.12
@export var aftershock_damage := 1
@export var aftershock_radius_offset := 1

# VFX / SFX (optional)
@export var nova_explosion_scene: PackedScene
@export var nova_explosion_z := 999
@export var nova_sfx_id: StringName = &"nova"
@export var nova_hit_sfx_id: StringName = &"nova_hit"

@export var iso_feet_offset_y := 16.0
@export var nova_ring_delay := 0.05
@export var nova_max_rings_per_frame := 999

# Splash (AoE around each struck cell)
@export var nova_splash_radius := 1
@export var nova_splash_damage := 1
@export var nova_splash_hits_allies := false
@export var nova_splash_hits_structures := false

# -------------------------
# Special 2: WEB tuning
# -------------------------
@export var web_range := 7
@export var web_target_count := 3  # how many enemies to tether
@export var web_damage := 2
@export var web_pull_distance := 2  # how many cells to pull enemies
@export var web_cooldown := 6
@export var web_min_safe_dist := 2

# Web visuals
@export var web_line_color: Color = Color(0.7, 0.9, 0.7, 0.8)  # greenish web
@export var web_line_width := 4.0
@export var web_glow_color: Color = Color(0.4, 1.0, 0.4, 0.6)
@export var web_duration := 0.8  # how long lines stay visible
@export var web_pull_duration := 0.4  # animation time for pull
@export var web_pulse_speed := 8.0  # energy pulse along web

# Web SFX
@export var web_shoot_sfx_id: StringName = &"web_shoot"
@export var web_hit_sfx_id: StringName = &"web_hit"
@export var web_pull_sfx_id: StringName = &"web_pull"

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
	id = id.to_lower()
	if id == "nova":
		return int(special_cd.get("nova", 0)) <= 0
	elif id == "web":
		return int(special_cd.get("web", 0)) <= 0
	return false

func get_special_range(id: String) -> int:
	id = id.to_lower()
	if id == "nova":
		return nova_range
	elif id == "web":
		return web_range
	return 0

func get_special_min_distance(id: String) -> int:
	id = id.to_lower()
	if id == "nova":
		return nova_min_safe_dist
	elif id == "web":
		return web_min_safe_dist
	return 0

# -------------------------------------------------------
# Basic attack (simple melee by default)
# -------------------------------------------------------
func perform_basic_attack(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
		return
	if abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y) > attack_range:
		return

	var tgt := M.unit_at_cell(target_cell)
	if tgt == null:
		return

	_face_toward_cell(target_cell)
	_play_attack_anim_once()
	_apply_damage_safely(tgt, basic_melee_damage)

# -------------------------------------------------------
# Special 1: NOVA
# -------------------------------------------------------
func perform_nova(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
		return
	if not _alive():
		return

	var id_key := "nova"
	if int(special_cd.get(id_key, 0)) > 0:
		return

	if nova_range <= 0 or nova_radius <= 0:
		return

	var d = abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y)
	if d < nova_min_safe_dist or d > nova_range:
		return

	_face_toward_cell(target_cell)
	_play_attack_anim_once()
	_sfx_at_cell(M, nova_sfx_id, cell)

	# Primary starburst (wavey)
	var primary_cells := _get_starburst_cells(M, target_cell, nova_radius)
	await _apply_cells_damage_wave(M, primary_cells, nova_damage + attack_damage, target_cell)
	if not _alive():
		return

	# Aftershock ring (also wavey)
	if aftershock_enabled:
		await get_tree().create_timer(max(0.01, aftershock_delay)).timeout
		if not _alive():
			return

		var ring_r = max(1, nova_radius + aftershock_radius_offset)
		var ring_cells := _get_ring_cells(M, target_cell, ring_r)
		await _apply_cells_damage_wave(M, ring_cells, aftershock_damage, target_cell)
		if not _alive():
			return

	_play_idle_anim()
	special_cd[id_key] = nova_cooldown

# -------------------------------------------------------
# Special 2: WEB
# Shoots sticky webs at multiple enemies, then pulls them together
# -------------------------------------------------------
func perform_web(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
		return
	if not _alive():
		return

	var id_key := "web"
	if int(special_cd.get(id_key, 0)) > 0:
		return

	var d = abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y)
	if d < web_min_safe_dist or d > web_range:
		return

	_face_toward_cell(target_cell)
	_play_attack_anim_once()
	_sfx_at_cell(M, web_shoot_sfx_id, cell)

	# Find enemies within range
	var targets := _find_web_targets(M, target_cell)
	if targets.is_empty():
		_play_idle_anim()
		return

	# (Optional) Draw web lines to each target (keep your current visuals)
	var web_lines: Array[Node2D] = []
	for tgt in targets:
		if not is_instance_valid(tgt):
			continue
		var line := _create_web_line(M, cell, tgt.cell)
		if line != null:
			web_lines.append(line)

	# Optional pulse
	await _animate_web_pulse(web_lines)

	# ✅ Instead of pulling: explode + damage sequentially
	for tgt in targets:
		if not is_instance_valid(tgt) or not _alive():
			continue

		# explosion (prefer MapController helper)
		if M.has_method("spawn_explosion_at_cell"):
			M.call("spawn_explosion_at_cell", tgt.cell)
		elif M.has_method("_spawn_explosion_at_cell"):
			M.call("_spawn_explosion_at_cell", tgt.cell)

		_sfx_at_cell(M, web_hit_sfx_id, tgt.cell)
		_apply_damage_safely(tgt, web_damage + attack_damage)

		# flash white on hit (keep)
		if M.has_method("_flash_unit_white"):
			M.call("_flash_unit_white", tgt, 0.10)
		elif M.has_method("flash_unit_white"):
			M.call("flash_unit_white", tgt, 0.10)

		# small beat between hits so it reads "one after the other"
		await get_tree().create_timer(0.08).timeout

	# Clean up web lines
	for line in web_lines:
		if is_instance_valid(line):
			_fade_out_web_line(line)

	_play_idle_anim()
	special_cd[id_key] = web_cooldown

func _find_web_targets(M: MapController, focus_cell: Vector2i) -> Array:
	var targets := []
	var radius := web_range

	for ox in range(-radius, radius + 1):
		for oy in range(-radius, radius + 1):
			var c := focus_cell + Vector2i(ox, oy)
			if not _cell_in_bounds(M, c):
				continue

			var dist = abs(c.x - cell.x) + abs(c.y - cell.y)
			if dist > web_range or dist < web_min_safe_dist:
				continue

			var tgt := M.unit_at_cell(c)
			if tgt == null or not is_instance_valid(tgt):
				continue
			if ("team" in tgt) and (tgt.team == team):
				continue

			targets.append(tgt)

	# Sort by distance from spider and take closest ones
	targets.sort_custom(func(a, b):
		var da = abs(a.cell.x - cell.x) + abs(a.cell.y - cell.y)
		var db = abs(b.cell.x - cell.x) + abs(b.cell.y - cell.y)
		return da < db
	)

	# Limit to web_target_count
	if targets.size() > web_target_count:
		targets = targets.slice(0, web_target_count)

	return targets

func _create_web_line(M: MapController, from_cell: Vector2i, to_cell: Vector2i) -> Node2D:
	var line := Line2D.new()
	line.width = web_line_width
	line.default_color = web_line_color
	line.antialiased = true
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND

	var from_pos := _cell_to_global(M, from_cell)
	from_pos.y -= iso_feet_offset_y

	var to_pos := _cell_to_global(M, to_cell)
	to_pos.y -= iso_feet_offset_y

	line.add_point(from_pos)
	line.add_point(to_pos)

	# Add glow effect with second line
	var glow := Line2D.new()
	glow.width = web_line_width * 2.0
	glow.default_color = web_glow_color
	glow.antialiased = true
	glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	glow.end_cap_mode = Line2D.LINE_CAP_ROUND
	glow.add_point(from_pos)
	glow.add_point(to_pos)
	glow.z_index = -1

	var container := Node2D.new()
	container.add_child(glow)
	container.add_child(line)

	# High z-index so webs appear above units
	container.z_index = 1000

	M.add_child(container)
	return container

func _animate_web_pulse(web_lines: Array[Node2D]) -> void:
	if web_lines.is_empty():
		return

	var elapsed := 0.0
	var pulse_time := 0.3

	while elapsed < pulse_time:
		elapsed += get_process_delta_time()
		var t := elapsed / pulse_time

		for line_container in web_lines:
			if not is_instance_valid(line_container):
				continue

			var glow := line_container.get_child(0) as Line2D
			if glow != null:
				var pulse := sin(t * web_pulse_speed * TAU) * 0.5 + 0.5
				var alpha := web_glow_color.a * (0.3 + pulse * 0.7)
				glow.default_color = Color(web_glow_color.r, web_glow_color.g, web_glow_color.b, alpha)

		await get_tree().process_frame

func _calculate_pull_center(targets: Array) -> Vector2i:
	if targets.is_empty():
		return cell

	var sum := Vector2i.ZERO
	for tgt in targets:
		if is_instance_valid(tgt):
			sum += tgt.cell

	return Vector2i(sum.x / targets.size(), sum.y / targets.size())

func _fade_out_web_line(line_container: Node2D) -> void:
	if not is_instance_valid(line_container):
		return

	var tween := create_tween()
	tween.tween_property(line_container, "modulate:a", 0.0, 0.3)
	tween.tween_callback(line_container.queue_free)

# -------------------------
# NOVA helpers (unchanged)
# -------------------------
func _apply_cells_damage_wave(M: MapController, cells: Array[Vector2i], dmg: int, center: Vector2i) -> void:
	if M == null or dmg <= 0:
		return
	if cells.is_empty():
		return
	if not _alive():
		return

	var rings: Dictionary = {}
	var max_ring := 0
	for c in cells:
		var dist = abs(c.x - center.x) + abs(c.y - center.y)
		if not rings.has(dist):
			rings[dist] = []
		(rings[dist] as Array).append(c)
		max_ring = max(max_ring, dist)

	for ring in range(0, max_ring + 1):
		if not _alive():
			return
		if not rings.has(ring):
			continue

		var ring_cells: Array = rings[ring]
		ring_cells.shuffle()

		for c in ring_cells:
			if not _alive():
				return

			_spawn_nova_explosion(M, c)
			_sfx_at_cell(M, nova_hit_sfx_id, c)

			_apply_damage_at_cell(M, c, dmg)
			_apply_nova_splash_damage(M, c)

		if ring < max_ring and nova_ring_delay > 0.0:
			await get_tree().create_timer(nova_ring_delay).timeout

func _apply_damage_at_cell(M: MapController, c: Vector2i, dmg: int) -> void:
	var tgt := M.unit_at_cell(c)
	if tgt != null and is_instance_valid(tgt):
		if ("team" in tgt) and (tgt.team == team):
			return

		if M.has_method("_flash_unit_white"):
			M.call("_flash_unit_white", tgt, 0.10)
		elif M.has_method("flash_unit_white"):
			M.call("flash_unit_white", tgt, 0.10)

		_apply_damage_safely(tgt, dmg)

	if nova_splash_hits_structures:
		var s: Object = null
		if M.has_method("_structure_at_cell"):
			s = M.call("_structure_at_cell", c)
		elif M.has_method("structure_at_cell"):
			s = M.call("structure_at_cell", c)
		if s != null and is_instance_valid(s):
			_apply_damage_safely(s, dmg)

func _apply_nova_splash_damage(M: MapController, center: Vector2i) -> void:
	if nova_splash_radius <= 0 or nova_splash_damage <= 0:
		return

	for ox in range(-nova_splash_radius, nova_splash_radius + 1):
		for oy in range(-nova_splash_radius, nova_splash_radius + 1):
			if ox == 0 and oy == 0:
				continue

			var c := center + Vector2i(ox, oy)
			if not _cell_in_bounds(M, c):
				continue

			if Vector2(ox, oy).length() > float(nova_splash_radius) + 0.01:
				continue

			var tgt := M.unit_at_cell(c)
			if tgt != null and is_instance_valid(tgt):
				if (not nova_splash_hits_allies) and ("team" in tgt) and (tgt.team == team):
					continue

				if M.has_method("_flash_unit_white"):
					M.call("_flash_unit_white", tgt, 0.08)
				elif M.has_method("flash_unit_white"):
					M.call("flash_unit_white", tgt, 0.08)

				_apply_damage_safely(tgt, nova_splash_damage)

			if nova_splash_hits_structures:
				var s: Object = null
				if M.has_method("_structure_at_cell"):
					s = M.call("_structure_at_cell", c)
				elif M.has_method("structure_at_cell"):
					s = M.call("structure_at_cell", c)
				if s != null and is_instance_valid(s):
					_apply_damage_safely(s, nova_splash_damage)

func _get_starburst_cells(M: MapController, center: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.append(center)

	var dirs := [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)
	]

	for dir in dirs:
		for i in range(1, r + 1):
			var c = center + dir * i
			if not _cell_in_bounds(M, c):
				continue
			out.append(c)

	return _dedupe_cells(out)

func _get_ring_cells(M: MapController, center: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ox in range(-r, r + 1):
		var oy = r - abs(ox)
		var c1 := center + Vector2i(ox, oy)
		var c2 := center + Vector2i(ox, -oy)
		if _cell_in_bounds(M, c1): out.append(c1)
		if _cell_in_bounds(M, c2): out.append(c2)
	return _dedupe_cells(out)

func _dedupe_cells(arr: Array[Vector2i]) -> Array[Vector2i]:
	var seen := {}
	var out: Array[Vector2i] = []
	for c in arr:
		if seen.has(c):
			continue
		seen[c] = true
		out.append(c)
	return out

func _apply_cells_damage(M: MapController, cells: Array[Vector2i], dmg: int, center: Vector2i) -> void:
	if M == null:
		return
	if dmg <= 0:
		return

	for c in cells:
		_spawn_nova_explosion(M, c)
		_sfx_at_cell(M, nova_hit_sfx_id, c)

		var tgt := M.unit_at_cell(c)
		if tgt != null and is_instance_valid(tgt):
			if ("team" in tgt) and (tgt.team == team):
				continue
			_apply_damage_safely(tgt, dmg)

# -------------------------
# Helpers
# -------------------------
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

func _spawn_nova_explosion(M: MapController, c: Vector2i) -> void:
	if M == null or nova_explosion_scene == null:
		return

	var fx := nova_explosion_scene.instantiate()
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

func _alive() -> bool:
	return is_instance_valid(self) and (not ("_dying" in self and self._dying)) and hp > 0

func get_hud_extras() -> Dictionary:
	return {
		"Nova Range": str(nova_range),
		"Nova Damage": str(nova_damage + attack_damage),
		"Web Range": str(web_range),
		"Web Damage": str(web_damage + attack_damage),
	}
