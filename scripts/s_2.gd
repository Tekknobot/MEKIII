extends Unit
class_name S2
# Helicopter-style mech
# Special: QUAKE — ripples outward; each cell "bumps" up briefly (FX) and lifts any unit on it.
# Units on bumped cells take damage at the peak.

# -------------------------
# Visual / identity
# -------------------------
@export var portrait_tex: Texture2D = preload("res://sprites/Portraits/dog_port.png") # swap to heli portrait
@export var display_name := "S2 Skimmer"
@export var thumbnail: Texture2D
@export var special: String = "QUAKE"
@export var special_desc: String = "A seismic ripple lifts tiles in a radius. Units ride the wave and take damage."

@export var attack_anim_name: StringName = &"attack"

# -------------------------
# Base stats
# -------------------------
@export var base_move_range := 6
@export var base_attack_range := 4
@export var base_max_hp := 6

# -------------------------
# Basic ranged tuning (optional)
# -------------------------
@export var basic_ranged_damage := 1

# -------------------------
# Special: QUAKE tuning
# -------------------------
@export var quake_range := 6
@export var quake_radius := 3
@export var quake_damage := 2
@export var quake_cooldown := 5

# Visual feel
@export var quake_amplitude_px := 10.0   # how high cells/units pop visually
@export var quake_ring_delay := 0.05     # delay per ring (Manhattan distance)
@export var quake_up_time := 0.08
@export var quake_down_time := 0.12
@export var quake_pause_at_peak := 0.00  # add a tiny pause if you want punchier hits

# -------------------------
# Quake explosion + splash
# -------------------------
@export var quake_explosion_scene: PackedScene          # optional VFX scene (Node2D)
@export var quake_splash_radius := 1                    # AoE radius around each ripple cell
@export var quake_splash_damage := 1                    # extra damage to units in AoE
@export var quake_splash_hits_allies := false           # keep false for “enemies only”
@export var quake_splash_hits_structures := false       # if you have structures w/ take_damage
@export var quake_explosion_z := 999                    # optional layering hint if your VFX uses z_index

# SFX (optional; uses MapController._sfx if it exists)
@export var quake_sfx_id: StringName = &"quake"
@export var quake_hit_sfx_id: StringName = &"quake_hit"

# If your visuals are anchored with a feet offset, keep this consistent with your project
@export var iso_feet_offset_y := 16.0
@export var idle_anim_name: StringName = &"idle"
@export var quake_min_safe_dist := 4 # 1 = can't target your own cell; 2 = must be 2+ away, etc.

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
	return ["Quake"]

func can_use_special(id: String) -> bool:
	id = id.to_lower()
	if id != "quake":
		return false
	return int(special_cd.get("quake", 0)) <= 0

func get_special_range(id: String) -> int:
	id = id.to_lower()
	if id == "quake":
		return quake_range
	return 0

# -------------------------------------------------------
# Basic ranged attack (optional)
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
	_apply_damage_safely(tgt, basic_ranged_damage)

# -------------------------------------------------------
# Special: QUAKE
# - Pick a target cell in range
# - Ripple bumps cells outward
# - Units on those cells are lifted and damaged at the peak
# -------------------------------------------------------
func perform_quake(M: MapController, target_cell: Vector2i) -> void:
	var id_key := "quake"
	if int(special_cd.get(id_key, 0)) > 0:
		return
	if M == null:
		return
	if quake_range <= 0 or quake_radius <= 0:
		return

	var d = abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y)
	if d < quake_min_safe_dist or d > quake_range:
		return

	_face_toward_cell(target_cell)
	_play_attack_anim_once()
	_sfx_at_cell(M, quake_sfx_id, cell)

	await _play_quake_ripple(M, target_cell)
	_play_idle_anim()

	special_cd[id_key] = quake_cooldown

# -------------------------------------------------------
# QUAKE implementation
# -------------------------------------------------------
func _play_quake_ripple(M: MapController, center_cell: Vector2i) -> void:
	# Collect affected cells (circular-ish radius) and play as rings (Manhattan dist delay)
	var affected: Array[Vector2i] = []
	for ox in range(-quake_radius, quake_radius + 1):
		for oy in range(-quake_radius, quake_radius + 1):
			var c := center_cell + Vector2i(ox, oy)
			if not _cell_in_bounds(M, c):
				continue
			# Circular mask; comment out for diamond (Manhattan) shape
			if Vector2(ox, oy).length() > float(quake_radius) + 0.01:
				continue
			affected.append(c)

	# Sort inner-first so if delays are tiny it still "feels" correct
	affected.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da = abs(a.x - center_cell.x) + abs(a.y - center_cell.y)
		var db = abs(b.x - center_cell.x) + abs(b.y - center_cell.y)
		return da < db
	)

	# Kick each bump; run them concurrently but staggered by ring delay.
	# We'll await the "outermost" completion by tracking the max delay + times.
	var max_dist := 0
	for c in affected:
		var dist = abs(c.x - center_cell.x) + abs(c.y - center_cell.y)
		if dist > max_dist:
			max_dist = dist
		_quake_bump_cell(M, c, dist)

	var total_wait := float(max_dist) * quake_ring_delay + quake_up_time + quake_pause_at_peak + quake_down_time + 0.02
	await get_tree().create_timer(max(total_wait, 0.01)).timeout

func _quake_bump_cell(M: MapController, c: Vector2i, dist: int) -> void:
	# Fire-and-forget async using a detached task
	_quake_bump_cell_async(M, c, dist)

func _quake_bump_cell_async(M: MapController, c: Vector2i, dist: int) -> void:
	# Create a tiny Node2D as the "ground bump" marker (visual proxy for tile height)
	var bump := Node2D.new()
	bump.name = "QuakeBump"
	M.add_child(bump)

	var base_pos := _cell_to_global(M, c)
	base_pos.y -= iso_feet_offset_y
	bump.global_position = base_pos

	# Find unit (if any) and a visual node to lift
	var u := M.unit_at_cell(c)
	var unit_visual: Node2D = null
	var unit_base_y := 0.0
	
	if u != null and is_instance_valid(u):
		unit_visual = _get_unit_visual_node(u)
		if unit_visual != null:
			unit_base_y = unit_visual.position.y
	
	# Stagger for ring ripple
	var delay := float(dist) * quake_ring_delay
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	# Up tween
	var up := create_tween()
	up.tween_property(bump, "global_position:y", base_pos.y - quake_amplitude_px, max(0.01, quake_up_time))
	if unit_visual != null:
		up.parallel().tween_property(unit_visual, "position:y", unit_base_y - quake_amplitude_px, max(0.01, quake_up_time))
	await up.finished

	if quake_pause_at_peak > 0.0:
		await get_tree().create_timer(quake_pause_at_peak).timeout

	# --- Peak moment (synced to ripple) ---
	_spawn_quake_explosion(M, c)
	_sfx_at_cell(M, quake_hit_sfx_id, c)
	_apply_quake_splash_damage(M, c)

	# Direct bump damage (unit standing exactly on this cell)
	if u != null and is_instance_valid(u):
		if "team" in u and u.team != team:
			_apply_damage_safely(u, quake_damage)
			_sfx_at_cell(M, quake_hit_sfx_id, c)

	# Down tween
	var down := create_tween()
	down.tween_property(bump, "global_position:y", base_pos.y, max(0.01, quake_down_time))
	if unit_visual != null:
		down.parallel().tween_property(unit_visual, "position:y", unit_base_y, max(0.01, quake_down_time))
	await down.finished

	if is_instance_valid(bump):
		bump.queue_free()

func _get_unit_visual_node(u: Node) -> Node2D:
	# Common patterns in your project
	var n := u.get_node_or_null("Visual") as Node2D
	if n != null:
		return n
	n = u.get_node_or_null("Visual/Sprite2D") as Node2D
	if n != null:
		return n
	n = u.get_node_or_null("Visual/AnimatedSprite2D") as Node2D
	if n != null:
		return n
	n = u.get_node_or_null("Sprite2D") as Node2D
	if n != null:
		return n
	n = u.get_node_or_null("AnimatedSprite2D") as Node2D
	return n

# -------------------------
# Helpers (same style as your other units)
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

func _spawn_quake_explosion(M: MapController, c: Vector2i) -> void:
	if M == null or quake_explosion_scene == null:
		return

	var fx := quake_explosion_scene.instantiate()
	if fx == null:
		return

	# Position
	if fx is Node2D:
		var n := fx as Node2D
		var p := _cell_to_global(M, c)
		p.y -= iso_feet_offset_y
		n.global_position = p

		# Depth sort by (x+y)
		# Prefer MapController's scheme if it exists; otherwise fall back
		var z_base := 0
		var z_per := 1

		# If your MapController exposes these (common in your project), use them:
		if "z_base" in M: z_base = int(M.z_base)
		if "z_per_cell" in M: z_per = int(M.z_per_cell)

		n.z_index = z_base + (c.x + c.y) * z_per

		# Optional: tiny nudge so it renders above units on same cell
		n.z_index += 1

	M.add_child(fx)

func _apply_quake_splash_damage(M: MapController, center: Vector2i) -> void:
	if M == null:
		return
	if quake_splash_radius <= 0 or quake_splash_damage <= 0:
		return

	for ox in range(-quake_splash_radius, quake_splash_radius + 1):
		for oy in range(-quake_splash_radius, quake_splash_radius + 1):
			var c := center + Vector2i(ox, oy)
			if not _cell_in_bounds(M, c):
				continue

			# Circular mask (comment out if you want square AoE)
			if Vector2(ox, oy).length() > float(quake_splash_radius) + 0.01:
				continue

			# --------------------
			# 1) Units (enemies + optional allies)
			# --------------------
			var tgt := M.unit_at_cell(c)
			if tgt != null and is_instance_valid(tgt):
				# If we DON'T want to hit allies, skip same-team targets
				if (not quake_splash_hits_allies) and ("team" in tgt) and (tgt.team == team):
					pass
				else:
					_apply_damage_safely(tgt, quake_splash_damage)

			# --------------------
			# 2) Structures (optional)
			# --------------------
			if quake_splash_hits_structures:
				var s: Object = null

				# Support multiple MapController naming styles
				if M.has_method("_structure_at_cell"):
					s = M.call("_structure_at_cell", c)
				elif M.has_method("structure_at_cell"):
					s = M.call("structure_at_cell", c)

				if s != null and is_instance_valid(s):
					_apply_damage_safely(s, quake_splash_damage)

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

func get_special_min_distance(id: String) -> int:
	id = id.to_lower()
	if id == "quake":
		return quake_min_safe_dist
	return 0
