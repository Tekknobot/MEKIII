extends Unit
class_name M3

# -------------------------
# Visual / identity
# -------------------------
@export var portrait_tex: Texture2D = preload("res://sprites/Portraits/pilots/l0_por01.png")
@export var thumbnail: Texture2D
@export var special: String = "ARTILLERY STRIKE / LASER SWEEP"
@export var special_desc: String = "Fire explosive artillery or sweep enemies with a piercing laser beam"

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
	if d <= 0 or d > artillery_range:
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
	if not can_use_special("laser_sweep"):
		return
	if M == null:
		return

	# Determine direction from self to target
	var dx := target_cell.x - cell.x
	var dy := target_cell.y - cell.y
	
	var dir := Vector2i.ZERO
	
	# Snap to cardinal direction (strongest axis)
	if abs(dx) > abs(dy):
		dir = Vector2i(signi(dx), 0)  # East or West
	else:
		dir = Vector2i(0, signi(dy))  # North or South
	
	if dir == Vector2i.ZERO:
		return

	# Face direction
	_face_toward_cell(M, cell + dir)

	# Charge up visual
	await _laser_charge_effect(M)

	# Collect all cells in beam path
	var beam_cells: Array[Vector2i] = []
	for i in range(1, laser_range + 1):
		var check_cell := cell + (dir * i)
		if not _cell_in_bounds(M, check_cell):
			break
		beam_cells.append(check_cell)

	# Fire laser beam visual
	await _fire_laser_beam(M, beam_cells, dir)

	# SFX
	if M.has_method("_sfx"):
		var global_pos := global_position
		M.call("_sfx", &"laser", 1.0, randf_range(0.95, 1.05), global_pos)

	# Damage all units in beam path
	for bc in beam_cells:
		var u := M.unit_at_cell(bc)
		if u == null or not is_instance_valid(u):
			continue
		
		if u == self:
			continue
		
		# Friendly fire check
		if not laser_friendly_fire and u.team == team:
			continue
		
		_apply_damage_safely(u, laser_damage)

	mark_special_used("laser_sweep", laser_cooldown)

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
		"Artillery Range": str(artillery_range),
		"Artillery Damage": str(artillery_damage),
		"Artillery AOE": str(artillery_aoe_radius),
		"Laser Range": str(laser_range),
		"Laser Damage": str(laser_damage),
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
