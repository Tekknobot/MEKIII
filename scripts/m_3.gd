extends Unit
class_name M3

# -------------------------
# Visual / identity
# -------------------------
@export var portrait_tex: Texture2D = preload("res://sprites/Portraits/pilots/l0_por01.png")
@export var thumbnail: Texture2D
@export var special: String = "ARTILLERY STRIKE, LASER SWEEP"
@export var special_desc: String = "Fire explosive artillery or sweep enemies with a piercing laser beam that chains."

@export var attack_anim_name: StringName = &"attack"
@export var attack_fx_scene: PackedScene = null

# -------------------------
# Base stats
# -------------------------
@export var base_move_range := 3
@export var base_attack_range := 2
@export var base_max_hp := 15

# -------------------------
# SPECIAL 1: ARTILLERY STRIKE
# - Target any cell in range (doesn't need unit)
# - Arc projectile visual (Line2D)
# - Explodes on impact, AOE damage
# - Damages ALL units in blast radius
# -------------------------
@export var artillery_range := 6
@export var artillery_damage := 5
@export var artillery_aoe_radius := 2  # Manhattan distance
@export var artillery_friendly_fire := true
@export var artillery_cooldown := 4

@export var artillery_arc_height := 80.0
@export var artillery_travel_time := 0.6
@export var artillery_projectile_color := Color.ORANGE_RED
@export var artillery_projectile_width := 4.0
@export var artillery_explosion_scale := 2.0
@export var artillery_min_safe_dist := 3  # Manhattan distance (tiles) you cannot target inside


# -------------------------
# SPECIAL 2: LASER SWEEP
# - Choose cardinal direction (N/S/E/W)
# - Piercing laser beam hits all units in line
# - Line2D beam visual
# - Damages everything in path
# -------------------------
@export var laser_range := 8
@export var laser_damage := 4
@export var laser_friendly_fire := false
@export var laser_cooldown := 5

@export var laser_beam_color := Color.CYAN
@export var laser_beam_width := 12.0
@export var laser_charge_time := 0.3
@export var laser_fire_duration := 0.4
@export var laser_fade_time := 0.2

@export var sky_chain_max_hits := 8
@export var sky_chain_radius := 3          # Manhattan radius to “jump” to next enemy

@export var sky_strike_damage := 4
@export var sky_strike_radius := 1         # explosion splash radius

@export var sky_beam_height_px := 220.0    # how far “from the sky”
@export var sky_beam_width := 10.0
@export var sky_beam_color := Color.CYAN
@export var sky_beam_fade_time := 0.18


signal artillery_complete
var _pending_artillery_impacts := 0

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
	return ["Artillery Strike", "Laser Sweep"]

func can_use_special(id: String) -> bool:
	id = id.to_lower()
	if id == "artillery strike" or id == "artillery_strike":
		return int(special_cd.get("artillery_strike", 0)) <= 0
	elif id == "laser sweep" or id == "laser_sweep":
		return int(special_cd.get("laser_sweep", 0)) <= 0
	return false

func get_special_range(id: String) -> int:
	id = id.to_lower()
	if id == "artillery strike" or id == "artillery_strike":
		return artillery_range
	elif id == "laser sweep" or id == "laser_sweep":
		return laser_range
	return 0

# -------------------------------------------------------
# SPECIAL 1: ARTILLERY STRIKE
# - Fire at target cell (doesn't need to contain unit)
# - Arc projectile visual
# - AOE explosion damage
# -------------------------------------------------------
func perform_artillery_strike(M: MapController, target_cell: Vector2i) -> void:
	if M == null or not is_instance_valid(M):
		return
	if hp <= 0:
		return

	var id_key := "artillery_strike"
	if int(special_cd.get(id_key, 0)) > 0:
		return

	var d = abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y)

	# ✅ minimum safe distance (also prevents clicking your own cell)
	var min_d = max(1, artillery_min_safe_dist)  # never less than 1
	if d < min_d or d > artillery_range:
		return

	_face_toward_cell(M, target_cell)

	# ✅ Play attack once at launch (same style as barrage)
	_play_attack_anim_once()

	# Optional launch sfx
	if M.has_method("_sfx"):
		M.call("_sfx", &"bullet", 1.0, randf_range(0.95, 1.05), global_position)

	_pending_artillery_impacts = 0

	# ✅ Use MapController curve missile (like barrage)
	var tw := M.fire_support_missile_curve_async(
		cell,
		target_cell,
		artillery_travel_time,
		artillery_arc_height,
		32
	)

	if tw != null and is_instance_valid(tw):
		_pending_artillery_impacts = 1
		tw.finished.connect(Callable(self, "_on_artillery_missile_finished").bind(M, target_cell))
	else:
		# If tween failed, just impact immediately
		_on_artillery_impact(M, target_cell)

	# Wait for impact completion
	if _pending_artillery_impacts > 0:
		await artillery_complete

	_play_idle_anim()
	special_cd[id_key] = artillery_cooldown

func _on_artillery_missile_finished(M: MapController, impact_cell: Vector2i) -> void:
	_on_artillery_impact(M, impact_cell)

	_pending_artillery_impacts -= 1
	if _pending_artillery_impacts <= 0:
		emit_signal("artillery_complete")


func _on_artillery_impact(M: MapController, impact_cell: Vector2i) -> void:
	if M == null or not is_instance_valid(M):
		return

	# ✅ FX + SFX across the entire AOE diamond
	_spawn_artillery_aoe_fx(M, impact_cell, artillery_aoe_radius)

	# ✅ Damage ONCE (use your existing splash function)
	await M._apply_splash_damage(impact_cell, artillery_aoe_radius, artillery_damage)

	# Optional structures
	if M.has_method("_apply_structure_splash_damage"):
		M.call("_apply_structure_splash_damage", impact_cell, artillery_aoe_radius, 1)

func _spawn_explosion_visual(M: MapController, at_cell: Vector2i) -> void:
	if M == null or not is_instance_valid(M):
		return
	if not ("explosion_scene" in M):
		return
	if M.explosion_scene == null:
		return

	var fx := M.explosion_scene.instantiate()
	if fx == null:
		return

	var pos := _cell_to_global(M, at_cell)
	pos.y -= 8

	fx.global_position = pos
	if fx is Node2D:
		(fx as Node2D).z_index = 1 + at_cell.x + at_cell.y

	M.add_child(fx)
	M.spawn_explosion_at_cell(at_cell)
	
	# Try to play common anim names if present
	var ap := fx.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap != null:
		if ap.has_animation("explode"):
			ap.play("explode")
		elif ap.has_animation("default"):
			ap.play("default")


# -------------------------------------------------------
# SPECIAL 2: LASER SWEEP
# - Choose direction based on target_cell
# - Fire piercing beam in that direction
# - Hit all units in line
# -------------------------------------------------------
func perform_laser_sweep(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
		return
	if _dying:
		return

	var id_key := "laser_sweep"
	if int(special_cd.get(id_key, 0)) > 0:
		return

	# click gate: ANY cell in range
	var d0 = abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y)
	if d0 == 0 or d0 > laser_range:
		return

	# ✅ pick an enemy ANYWHERE in range, closest to the click
	var first := _pick_enemy_near_click(M, target_cell, laser_range)

	# none -> do nothing, do NOT spend
	if first == null:
		_play_idle_anim()
		return

	_face_toward_cell(M, first.cell)

	await _laser_charge_effect(M)

	var chain := _build_sky_chain_targets(M, first)
	if chain.is_empty():
		_play_idle_anim()
		return

	for u in chain:
		if u == null or not is_instance_valid(u) or u.hp <= 0:
			continue
		await _sky_laser_strike(M, u.cell)

	_play_idle_anim()
	special_cd[id_key] = laser_cooldown

func _build_sky_chain_targets(M: MapController, first: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	if first == null or not is_instance_valid(first):
		return out

	var used: Dictionary = {}
	used[first.get_instance_id()] = true
	out.append(first)

	var chained := false

	while out.size() < sky_chain_max_hits:
		var from_u = out.back()
		if from_u == null or not is_instance_valid(from_u) or from_u.hp <= 0:
			break

		var next := _find_nearest_enemy_within(M, from_u.cell, sky_chain_radius, used)
		if next == null:
			break

		used[next.get_instance_id()] = true
		out.append(next)
		chained = true

	# -------------------------
	# SAY RESULT (once)
	# -------------------------
	if M.has_method("_say"):
		if chained:
			M.call("_say", self, "Chain!")
		else:
			M.call("_say", self, "Chain failed")

	return out

func _find_nearest_enemy_within(M: MapController, from_cell: Vector2i, r: int, used: Dictionary) -> Unit:
	var best: Unit = null
	var best_d := 999999

	for u in M.get_all_units():
		if u == null or not is_instance_valid(u) or u.hp <= 0:
			continue
		if u.team != Unit.Team.ENEMY:
			continue
		if used.has(u.get_instance_id()):
			continue

		var d = abs(u.cell.x - from_cell.x) + abs(u.cell.y - from_cell.y)
		if d <= 0 or d > r:
			continue

		if d < best_d:
			best_d = d
			best = u

	return best

func _sky_laser_strike(M: MapController, at_cell: Vector2i) -> void:
	if M == null or not is_instance_valid(M):
		return

	# ---------------------------------------------------------
	# Positions
	# ---------------------------------------------------------
	var hit_pos := M.terrain.to_global(M.terrain.map_to_local(at_cell)) + Vector2(0, -8)
	var start_pos := hit_pos + Vector2(0, -sky_beam_height_px)
	var z := (at_cell.x + at_cell.y) + 600

	# ---------------------------------------------------------
	# Build a tiny 1x1 white pixel texture (local, no helpers)
	# ---------------------------------------------------------
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var pixel_tex := ImageTexture.create_from_image(img)

	# ---------------------------------------------------------
	# MULTI-PART LASER CONFIG
	# ---------------------------------------------------------
	var parts := 7
	if parts < 2:
		parts = 2

	var strand_count := 1
	var strand_jitter_px := 0.0

	# ---------------------------------------------------------
	# Compute segmented "jagged" points
	# ---------------------------------------------------------
	var main_pts: Array[Vector2] = []
	for i in range(parts):
		var t := float(i) / float(parts - 1)
		var p := start_pos.lerp(hit_pos, t)

		# 0 at ends, 1 near middle
		var mid = 1.0 - abs(2.0 * t - 1.0)

		# jaggedness (stronger mid-beam)
		p += Vector2(
			randf_range(0.0, 0.0),
			randf_range(0.0, 0.0)
		) * (0.0 + mid)

		main_pts.append(p)

	# ---------------------------------------------------------
	# Create multiple beam strands
	# ---------------------------------------------------------
	var beams: Array[Line2D] = []
	for s in range(strand_count):
		var beam := Line2D.new()
		beam.width = sky_beam_width
		beam.default_color = sky_beam_color
		beam.z_index = 0 + (at_cell.x + at_cell.y)
		M.add_child(beam)
		beams.append(beam)

		var off := Vector2(
			randf_range(-strand_jitter_px, strand_jitter_px),
			randf_range(-strand_jitter_px, strand_jitter_px)
		)

		for p in main_pts:
			beam.add_point(p + off)
			
		M._sfx("sat_laser")	

	# ---------------------------------------------------------
	# Spawn pixel particle bursts at each segment point
	# (NO lambdas: connect finished -> queue_free)
	# ---------------------------------------------------------
	for i in range(main_pts.size()):
		var burst_pos := main_pts[i]

		var p := CPUParticles2D.new()
		p.one_shot = true
		p.emitting = false
		p.z_index = z + 10
		p.global_position = burst_pos
		p.texture = pixel_tex

		# particle tuning (pixel sparks)
		p.amount = 1 + (i % 3) * 4
		p.lifetime = 1.22
		p.explosiveness = 0.95
		p.spread = 90.0
		p.initial_velocity_min = 18.0
		p.initial_velocity_max = 34.0
		p.gravity = Vector2.ZERO
		p.damping_min = 10.0
		p.damping_max = 26.0
		p.scale_amount_min = 1
		p.scale_amount_max = 1
		p.color = sky_beam_color

		# ✅ alternate left/right so pixels go on BOTH sides of the beam
		if (i % 2) == 0:
			p.direction = Vector2(-1, 0)  # LEFT
		else:
			p.direction = Vector2(1, 0)   # RIGHT

		# tighter cone so it reads like "side spray"
		p.spread = 35.0


		M.add_child(p)
		p.emitting = true

		# ✅ Fade pixels out over lifetime
		var tp := create_tween()
		tp.tween_property(p, "modulate:a", 0.0, p.lifetime)
		
		p.finished.connect(p.queue_free)

	# Extra impact burst
	var p2 := CPUParticles2D.new()
	p2.one_shot = true
	p2.emitting = false
	p2.z_index = z + 12
	p2.global_position = hit_pos
	p2.texture = pixel_tex
	p2.amount = 8
	p2.lifetime = 1.25
	p2.explosiveness = 0.98
	p2.spread = 180.0
	p2.initial_velocity_min = 1.0
	p2.initial_velocity_max = 1.0
	p2.gravity = Vector2.ZERO
	p2.damping_min = 12.0
	p2.damping_max = 30.0
	p2.scale_amount_min = 1.0
	p2.scale_amount_max = 1.0
	p2.color = sky_beam_color
	M.add_child(p2)
	p2.emitting = true
	p2.finished.connect(p2.queue_free)

	await get_tree().create_timer(0.05).timeout

	# ---------------------------------------------------------
	# BASE explosion (does its usual 1 dmg)
	# ---------------------------------------------------------
	await M.spawn_explosion_at_cell(at_cell)

	# ---------------------------------------------------------
	# ✅ ADDITIONAL SKY STRIKE DAMAGE
	# ---------------------------------------------------------
	for u in M.get_all_units():
		if u == null or not is_instance_valid(u) or u.hp <= 0:
			continue
		if u.team != Unit.Team.ENEMY:
			continue

		var d = abs(u.cell.x - at_cell.x) + abs(u.cell.y - at_cell.y)
		if d > sky_strike_radius:
			continue

		_apply_damage_safely(M, u, sky_strike_damage, u.cell)

	# ---------------------------------------------------------
	# Fade out all beam strands + free
	# ---------------------------------------------------------
	var tw := create_tween()
	for beam in beams:
		if beam == null or not is_instance_valid(beam):
			continue
		var c0: Color = beam.default_color
		var c1: Color = c0
		c1.a = 0.0
		tw.tween_property(beam, "default_color", c1, sky_beam_fade_time)

	await tw.finished

	for beam in beams:
		if beam != null and is_instance_valid(beam):
			beam.queue_free()

# -------------------------
# Visual Effects
# -------------------------

func _fire_artillery_projectile(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
		return

	var start_global := global_position
	var end_global := _cell_to_global(M, target_cell)

	# Create Line2D for projectile arc
	var line := Line2D.new()
	line.width = artillery_projectile_width
	line.default_color = artillery_projectile_color
	line.z_index = 100
	
	M.add_child(line)

	# Animate arc
	var steps := 20
	var tw := create_tween()
	
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var pos := start_global.lerp(end_global, t)
		
		# Add arc (parabola)
		var arc := sin(t * PI) * artillery_arc_height
		pos.y -= arc
		
		line.add_point(pos)
		
		if i < steps:
			tw.tween_callback(func(): pass).set_delay(artillery_travel_time / steps)

	await tw.finished
	
	# Cleanup
	line.queue_free()

func _play_explosion_fx(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
		return

	var global_pos := _cell_to_global(M, target_cell)

	# Create simple explosion visual (expanding circle with Line2D)
	var explosion := Node2D.new()
	M.add_child(explosion)
	explosion.global_position = global_pos
	explosion.z_index = 99

	var circle := Line2D.new()
	circle.width = 3.0
	circle.default_color = Color.ORANGE
	circle.closed = true
	explosion.add_child(circle)

	# Create circle points
	var segments := 16
	for i in range(segments + 1):
		var angle := (float(i) / segments) * TAU
		var point := Vector2(cos(angle), sin(angle)) * 10.0
		circle.add_point(point)

	# Animate explosion
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(circle, "width", 0.0, 0.3)
	tw.tween_property(circle, "default_color:a", 0.0, 0.3)
	
	# Scale up
	var final_scale := artillery_explosion_scale
	tw.tween_property(explosion, "scale", Vector2.ONE * final_scale, 0.3)
	
	await tw.finished
	explosion.queue_free()

func _laser_charge_effect(M: MapController) -> void:
	# Simple charge effect - could add particles here
	if M.has_method("_sfx"):
		M.call("_sfx", &"charge", 0.8, 1.0, global_position)
	
	await get_tree().create_timer(laser_charge_time).timeout

func _fire_laser_beam(M: MapController, beam_cells: Array[Vector2i], dir: Vector2i) -> void:
	if M == null or beam_cells.is_empty():
		return

	# Create laser beam Line2D
	var beam := Line2D.new()
	beam.width = laser_beam_width
	beam.default_color = laser_beam_color
	beam.z_index = 100
	
	M.add_child(beam)

	var start_pos := global_position
	beam.add_point(start_pos)

	# Extend beam rapidly
	var tw := create_tween()
	
	for bc in beam_cells:
		var pos := _cell_to_global(M, bc)
		beam.add_point(pos)
	
	# Beam appearance
	tw.tween_property(beam, "default_color:a", 1.0, 0.05)
	await get_tree().create_timer(laser_fire_duration).timeout
	
	# Fade out
	var tw2 := create_tween()
	tw2.tween_property(beam, "default_color:a", 0.0, laser_fade_time)
	await tw2.finished
	
	beam.queue_free()

# -------------------------
# Helpers (reused from M2)
# -------------------------

func signi(v: int) -> int:
	if v > 0: return 1
	if v < 0: return -1
	return 0

func _cell_in_bounds(M: MapController, c: Vector2i) -> bool:
	if M.grid != null and M.grid.has_method("in_bounds"):
		return bool(M.grid.in_bounds(c))
	if M.grid != null and ("w" in M.grid) and ("h" in M.grid):
		return c.x >= 0 and c.y >= 0 and c.x < int(M.grid.w) and c.y < int(M.grid.h)
	return true

func _cell_to_global(M: MapController, c: Vector2i) -> Vector2:
	if M.terrain != null:
		var map_local := M.terrain.map_to_local(c)
		return M.terrain.to_global(map_local)
	return Vector2(c.x * 32, c.y * 32)

func _apply_damage_safely(M: MapController, tgt: Object, dmg: int, c: Vector2i) -> void:
	if tgt == null:
		return

	# ✅ Visual-only explosion (no damage) — do it BEFORE/AFTER, your choice
	if M != null and is_instance_valid(M):
		_spawn_explosion_visual(M, c)

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

func _face_toward_cell(M: MapController, target_cell: Vector2i) -> void:
	var spr := get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D
	if spr == null:
		spr = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if spr == null or M == null:
		return

	var target_global := _cell_to_global(M, target_cell)

	if target_global.x < global_position.x:
		spr.flip_h = false
	elif target_global.x > global_position.x:
		spr.flip_h = true

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

func get_hud_extras() -> Dictionary:
	return {
		"Strike Range": str(artillery_range),
		"Strike Damage": str(artillery_damage),
		"Sweep Range": str(laser_range),
		"Sweep Damage": str(sky_strike_damage),
	}

func _play_idle_anim() -> void:
	var sprA := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprA == null:
		sprA = get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D
	if sprA == null:
		return

	var anim := String("idle")
	if sprA.sprite_frames == null:
		return
	if not sprA.sprite_frames.has_animation(anim):
		return

	sprA.play(anim)

func _spawn_artillery_aoe_fx(M: MapController, center: Vector2i, r: int) -> void:
	if M == null or not is_instance_valid(M):
		return
	if r <= 0:
		return

	# optional: bounds helper
	var in_bounds := func(c: Vector2i) -> bool:
		if M.grid != null and M.grid.has_method("in_bounds"):
			return bool(M.grid.in_bounds(c))
		return true

	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if abs(dx) + abs(dy) > r:
				continue

			var c := center + Vector2i(dx, dy)
			if not in_bounds.call(c):
				continue

			# ✅ Visual-only explosion (no damage)
			_spawn_explosion_visual(M, c)

			# ✅ SFX at each cell (slightly randomized pitch)
			if M.has_method("_sfx"):
				var p := _cell_to_global(M, c)
				M.call("_sfx", &"explosion_small", 0.85, randf_range(0.92, 1.08), p)
			
			await get_tree().create_timer(0.1).timeout

func _pick_enemy_near_click(M: MapController, click_cell: Vector2i, max_range: int) -> Unit:
	if M == null:
		return null

	var best: Unit = null
	var best_score := 999999

	for u in M.get_all_units():
		if u == null or not is_instance_valid(u) or u.hp <= 0:
			continue
		if u.team != Unit.Team.ENEMY:
			continue

		# must be within ability range from THIS unit
		var d_self = abs(u.cell.x - cell.x) + abs(u.cell.y - cell.y)
		if d_self <= 0 or d_self > max_range:
			continue

		# prefer closest to clicked cell
		var d_click = abs(u.cell.x - click_cell.x) + abs(u.cell.y - click_cell.y)

		# score: prioritize click closeness, tie-break by closeness to self
		var score = d_click * 100 + d_self
		if score < best_score:
			best_score = score
			best = u

	return best
