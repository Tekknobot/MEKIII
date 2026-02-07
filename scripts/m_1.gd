extends Unit
class_name M1

# ---------------------------------------------------------
# M1 — Arm-blade mech
# Special 1: SUNDER — line sweep behind target, cell-by-cell
# Special 2: SLAM   — quake-like ripple bump around a target cell
# ---------------------------------------------------------

# -------------------------
# Visual / identity
# -------------------------
@export var portrait_tex: Texture2D = preload("res://sprites/Portraits/dog_port.png")
@export var thumbnail: Texture2D
@export var specials: Array[String] = ["SUNDER", "SLAM"]
@export var special_desc: String = "Sunder: line sweep behind target. Slam: seismic ripple bumps tiles and damages enemies."

@export var attack_anim_name: StringName = &"attack"
@export var idle_anim_name: StringName = &"idle"

# Optional: if you prefer spawning an FX scene instead of AnimationPlayer
@export var attack_fx_scene: PackedScene = null

# -------------------------
# Base stats
# -------------------------
@export var base_move_range := 5
@export var base_attack_range := 1
@export var base_max_hp := 6

# -------------------------
# Special 1: SUNDER
# -------------------------
@export var sunder_range := 5
@export var sunder_damage := 2
@export var sunder_cooldown := 3
@export var sunder_step_delay := 0.08

# -------------------------
# Special 2: SLAM (quake-like)
# - target cell within slam_range (Manhattan)
# - ripple bumps cells in slam_radius (circular mask) with ring delays
# - at peak: spawn explosion + splash damage + direct cell damage
# -------------------------
@export var slam_range := 4
@export var slam_radius := 2
@export var slam_damage := 2
@export var slam_cooldown := 4
@export var slam_min_safe_dist := 1

# Visual feel
@export var slam_amplitude_px := 10.0
@export var slam_ring_delay := 0.05
@export var slam_up_time := 0.08
@export var slam_down_time := 0.12
@export var slam_pause_at_peak := 0.00

# Slam explosion + splash
@export var slam_explosion_scene: PackedScene
@export var slam_splash_radius := 1
@export var slam_splash_damage := 1
@export var slam_splash_hits_allies := false
@export var slam_splash_hits_structures := false
@export var slam_explosion_z := 999

# SFX
@export var slam_sfx_id: StringName = &"slam"
@export var slam_hit_sfx_id: StringName = &"slam_hit"

# Feet offset consistency with your project
@export var iso_feet_offset_y := 16.0

@export var slam_dip_px := 8.0
@export var slam_dip_time := 0.06
@export var slam_recover_time := 0.10
@export var slam_ground_hit_delay := 0.02 # tiny delay so it "connects"

var _slam_base_local_pos: Vector2
var _slam_base_captured := false

func _ready() -> void:
	set_meta("portrait_tex", portrait_tex)
	set_meta("display_name", display_name)

	footprint_size = Vector2i(1, 1)
	move_range = base_move_range
	attack_range = base_attack_range

	max_hp = max(max_hp, base_max_hp)
	hp = clamp(hp, 0, max_hp)

	print("M1 thumbnail = ", thumbnail, "  type=", typeof(thumbnail))

	super._ready()

# -------------------------
# Specials list (for UI)
# -------------------------
func get_available_specials() -> Array[String]:
	return ["Sunder", "Slam"]

func can_use_special(id: String) -> bool:
	id = id.to_lower()
	if id != "sunder" and id != "slam":
		return false
	return int(special_cd.get(id, 0)) <= 0

func get_special_range(id: String) -> int:
	id = id.to_lower()
	if id == "sunder":
		return sunder_range
	if id == "slam":
		return slam_range
	return 0

func get_special_min_distance(id: String) -> int:
	id = id.to_lower()
	if id == "slam":
		return slam_min_safe_dist
	return 0

# -------------------------------------------------------
# Special 1: SUNDER (line sweep behind target)
# -------------------------------------------------------
func perform_sunder(M: MapController, target_cell: Vector2i) -> void:
	if not can_use_special("sunder"):
		return
	if M == null:
		return

	# Must be in straight line (no diagonals)
	var dx := target_cell.x - cell.x
	var dy := target_cell.y - cell.y
	if dx != 0 and dy != 0:
		return

	var dist = abs(dx) + abs(dy)
	if dist <= 0 or dist > sunder_range:
		return

	if not _cell_in_bounds(M, target_cell):
		return

	# Direction from attacker -> target
	var dir := Vector2i.ZERO
	if dx != 0:
		dir.x = 1 if dx > 0 else -1
	else:
		dir.y = 1 if dy > 0 else -1

	_face_toward_cell(target_cell)
	_play_attack_fx(M, target_cell)

	var structure_blocked := _get_structure_blocked(M)

	# Start at target tile, then keep going "behind it"
	var c := target_cell
	while _cell_in_bounds(M, c) and not _cell_blocked(structure_blocked, c):

		# Face toward this strike point (optional helper if you have it)
		if M != null and M.terrain != null and M.has_method("_face_unit_toward_world"):
			var local_pos: Vector2 = M.terrain.map_to_local(c)
			var world_pos: Vector2 = M.terrain.to_global(local_pos)
			M.call("_face_unit_toward_world", self, world_pos)

		_play_attack_anim_once()
		_spawn_explosion(M, c)
		_damage_enemy_on_cell(M, c, sunder_damage + attack_damage)

		await _wait_attack_anim()

		if sunder_step_delay > 0.0:
			await get_tree().create_timer(sunder_step_delay).timeout

		c += dir

	_play_idle_anim()
	mark_special_used("sunder", sunder_cooldown)

# -------------------------------------------------------
# Special 2: SLAM (quake-like ripple)
# -------------------------------------------------------
func perform_slam(M: MapController, target_cell: Vector2i) -> void:
	if not can_use_special("slam"):
		return
	if M == null:
		return
	if slam_range <= 0 or slam_radius <= 0:
		return

	# You still "aim" somewhere, but SLAM originates from the unit
	var d = abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y)
	if d <= 0:
		return
	if d < slam_min_safe_dist or d > slam_range:
		return

	_face_toward_cell(target_cell)
	_play_attack_anim_once()

	# ✅ sell the impact: dip into the tile below
	await _play_slam_ground_hit()

	# ✅ then fire the ripple outward
	await _play_slam_ripple_from_unit_half(M, target_cell)

	_play_idle_anim()

	mark_special_used("slam", slam_cooldown)

# -------------------------------------------------------
# SLAM implementation
# -------------------------------------------------------
func _play_slam_ripple_from_unit_half(M: MapController, target_cell: Vector2i) -> void:
	var center := cell
	var start := slam_min_safe_dist

	# Direction from unit -> click (choose cardinal axis)
	var dir := Vector2i.ZERO
	var dx := target_cell.x - center.x
	var dy := target_cell.y - center.y
	if abs(dx) >= abs(dy):
		dir = Vector2i(sign(dx), 0)
	else:
		dir = Vector2i(0, sign(dy))
	if dir == Vector2i.ZERO:
		dir = Vector2i(0, 1)

	# Perpendicular axis (left/right from the direction)
	var perp := Vector2i(-dir.y, dir.x)

	# BOX SETTINGS
	var side_len := 5
	var depth := 5
	var layers_inward := 4  # ✅ 4 layers inward (thickness)

	# Anchor: front face starts at min safe distance
	var base := center + dir * start

	for layer in range(layers_inward):
		# inset grows each layer
		var inset := layer

		# remaining dims after inset
		var cur_w := side_len - inset * 2
		var cur_d := depth - inset * 2
		if cur_w <= 0 or cur_d <= 0:
			break

		var half_w := (cur_w - 1) / 2

		# shift base inward along dir and inward along perp bounds
		# (dir shift moves the rectangle "deeper" as we inset)
		var layer_base := base + dir * inset

		var cell_set: Dictionary = {}

		# Build rectangle perimeter of size cur_w x cur_d
		# v=0..cur_d-1, u=-half_w..half_w
		for v in range(cur_d):
			for u in range(-half_w, half_w + 1):
				var on_perimeter := (v == 0 or v == cur_d - 1 or u == -half_w or u == half_w)
				if not on_perimeter:
					continue

				var c := layer_base + dir * v + perp * u
				if not _cell_in_bounds(M, c):
					continue
				cell_set[c] = true

		# bump all cells in this inward layer
		for c in cell_set.keys():
			_slam_bump_cell(M, c, layer)

		if slam_ring_delay > 0.0:
			await get_tree().create_timer(slam_ring_delay).timeout

	var tail := slam_up_time + slam_pause_at_peak + slam_down_time + 0.02
	await get_tree().create_timer(max(tail, 0.01)).timeout

func _slam_bump_cell(M: MapController, c: Vector2i, dist: int) -> void:
	_slam_bump_cell_async(M, c, dist)

func _slam_bump_cell_async(M: MapController, c: Vector2i, dist: int) -> void:
	# visual proxy for tile bump
	var bump := Node2D.new()
	bump.name = "SlamBump"
	M.add_child(bump)

	var base_pos := _cell_to_global(M, c)
	base_pos.y -= iso_feet_offset_y
	bump.global_position = base_pos

	# unit lift
	var u := M.unit_at_cell(c)
	var unit_visual: Node2D = null
	var unit_base_y := 0.0
	if u != null and is_instance_valid(u):
		unit_visual = _get_unit_visual_node(u)
		if unit_visual != null:
			unit_base_y = unit_visual.position.y

	# stagger by ring
	var delay := float(dist) * slam_ring_delay
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	# up tween
	var up := create_tween()
	up.tween_property(bump, "global_position:y", base_pos.y - slam_amplitude_px, max(0.01, slam_up_time))
	if unit_visual != null:
		up.parallel().tween_property(unit_visual, "position:y", unit_base_y - slam_amplitude_px, max(0.01, slam_up_time))
	await up.finished

	if slam_pause_at_peak > 0.0:
		await get_tree().create_timer(slam_pause_at_peak).timeout

	# peak moment
	_spawn_slam_explosion(M, c)
	_apply_slam_splash_damage(M, c)

	# direct cell damage (unit standing exactly here)
	if u != null and is_instance_valid(u):
		if "team" in u and u.team != team:
			_apply_damage_safely(u, slam_damage + attack_damage)
			if M.has_method("_flash_unit_white"):
				M.call("_flash_unit_white", u, 0.10)
			elif M.has_method("flash_unit_white"):
				M.call("flash_unit_white", u, 0.10)

	# down tween
	var down := create_tween()
	down.tween_property(bump, "global_position:y", base_pos.y, max(0.01, slam_down_time))
	if unit_visual != null:
		down.parallel().tween_property(unit_visual, "position:y", unit_base_y, max(0.01, slam_down_time))
	await down.finished

	if is_instance_valid(bump):
		bump.queue_free()

func _get_unit_visual_node(u: Node) -> Node2D:
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
# Helpers
# -------------------------
func _cell_in_bounds(M: MapController, c: Vector2i) -> bool:
	if M.grid != null and M.grid.has_method("in_bounds"):
		return bool(M.grid.in_bounds(c))
	if M.grid != null and ("w" in M.grid) and ("h" in M.grid):
		return c.x >= 0 and c.y >= 0 and c.x < int(M.grid.w) and c.y < int(M.grid.h)
	return true

func _cell_to_global(M: MapController, c: Vector2i) -> Vector2:
	if M != null and M.terrain != null:
		var map_local := M.terrain.map_to_local(c)
		return M.terrain.to_global(map_local)
	return Vector2(c.x * 32, c.y * 32)

func _get_structure_blocked(M: MapController) -> Dictionary:
	if M.game_ref != null and ("structure_blocked" in M.game_ref):
		return M.game_ref.structure_blocked
	return {}

func _cell_blocked(structure_blocked: Dictionary, c: Vector2i) -> bool:
	return structure_blocked.has(c) and bool(structure_blocked[c]) == true

func _spawn_explosion(M: MapController, c: Vector2i) -> void:
	if M.has_method("spawn_explosion_at_cell"):
		M.call("spawn_explosion_at_cell", c)
		return
	if M.has_method("_spawn_explosion_at_cell"):
		M.call("_spawn_explosion_at_cell", c)
		return

	# fallback SFX only
	if M.has_method("_sfx"):
		M.call("_sfx", &"explosion_small", 1.0, randf_range(0.95, 1.05), _cell_to_global(M, c))

func _spawn_slam_explosion(M: MapController, c: Vector2i) -> void:
	# Prefer MapController explosion helper if present
	if M.has_method("spawn_explosion_at_cell"):
		M.call("spawn_explosion_at_cell", c)
		return
	if M.has_method("_spawn_explosion_at_cell"):
		M.call("_spawn_explosion_at_cell", c)
		return

	# Optional custom slam scene
	if M == null or slam_explosion_scene == null:
		return

	var fx := slam_explosion_scene.instantiate()
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

func _apply_slam_splash_damage(M: MapController, center: Vector2i) -> void:
	if M == null:
		return
	if slam_splash_radius <= 0 or slam_splash_damage <= 0:
		return

	for ox in range(-slam_splash_radius, slam_splash_radius + 1):
		for oy in range(-slam_splash_radius, slam_splash_radius + 1):
			var c := center + Vector2i(ox, oy)
			if not _cell_in_bounds(M, c):
				continue
			if Vector2(ox, oy).length() > float(slam_splash_radius) + 0.01:
				continue

			# Units
			var tgt := M.unit_at_cell(c)
			if tgt != null and is_instance_valid(tgt):
				if (not slam_splash_hits_allies) and ("team" in tgt) and (tgt.team == team):
					pass
				else:
					_apply_damage_safely(tgt, slam_splash_damage)
					if M.has_method("_flash_unit_white"):
						M.call("_flash_unit_white", tgt, 0.08)
					elif M.has_method("flash_unit_white"):
						M.call("flash_unit_white", tgt, 0.08)

			# Structures (optional)
			if slam_splash_hits_structures:
				var s: Object = null
				if M.has_method("_structure_at_cell"):
					s = M.call("_structure_at_cell", c)
				elif M.has_method("structure_at_cell"):
					s = M.call("structure_at_cell", c)
				if s != null and is_instance_valid(s):
					_apply_damage_safely(s, slam_splash_damage)

func _damage_enemy_on_cell(M: MapController, c: Vector2i, dmg: int) -> void:
	var u := M.unit_at_cell(c)
	if u != null and u.team != team:
		_apply_damage_safely(u, dmg)

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

func _play_attack_fx(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
		return

	var global_pos := Vector2.ZERO
	if M.terrain != null:
		var map_local := M.terrain.map_to_local(target_cell)
		global_pos = M.terrain.to_global(map_local)
	else:
		global_pos = Vector2(target_cell.x * 32, target_cell.y * 32)

	# Optional SFX hook
	if M.has_method("_sfx"):
		M.call("_sfx", &"sunder", 1.0, randf_range(0.95, 1.05), global_pos)

	# Try AnimationPlayer first
	var ap := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		ap = get_node_or_null("Anim") as AnimationPlayer
	if ap != null and ap.has_animation(String(attack_anim_name)):
		ap.play(String(attack_anim_name))
		return

	# Otherwise spawn an FX scene
	if attack_fx_scene != null:
		var fx := attack_fx_scene.instantiate()
		M.add_child(fx)
		if fx is Node2D:
			(fx as Node2D).global_position = global_pos

func _face_toward_cell(target_cell: Vector2i) -> void:
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	if spr == null:
		spr = get_node_or_null("Visual/Sprite2D") as Sprite2D
	if spr == null:
		return
	if target_cell.x < cell.x:
		spr.flip_h = true
	elif target_cell.x > cell.x:
		spr.flip_h = false

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

func _wait_attack_anim() -> void:
	var spr := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if spr == null:
		spr = get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D
	if spr == null:
		return

	var anim := String(attack_anim_name)
	if spr.sprite_frames == null:
		return
	if not spr.sprite_frames.has_animation(anim):
		return

	await spr.animation_finished

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

func get_hud_extras() -> Dictionary:
	return {
		"Sunder Range": str(sunder_range),
		"Sunder Damage": str(sunder_damage + attack_damage),
		"Slam Range": str(slam_range),
		"Slam Damage": str(slam_damage + attack_damage),
	}

func _play_slam_ground_hit() -> void:
	# Capture a stable baseline once (after unit is spawned/positioned)
	if not _slam_base_captured:
		_slam_base_local_pos = position
		_slam_base_captured = true
	else:
		# refresh baseline in case something legitimately moved us (eg. knockback)
		_slam_base_local_pos = position

	# Kill any previous slam tweens so they don't fight
	if has_meta("_slam_tw") and is_instance_valid(get_meta("_slam_tw")):
		var old = get_meta("_slam_tw")
		old.kill()
		set_meta("_slam_tw", null)

	# Dip DOWN (bigger y = lower on screen)
	var tw := create_tween()
	set_meta("_slam_tw", tw)
	tw.tween_property(self, "position", _slam_base_local_pos + Vector2(0, slam_dip_px), max(0.01, slam_dip_time))
	await tw.finished

	if slam_ground_hit_delay > 0.0:
		await get_tree().create_timer(slam_ground_hit_delay).timeout

	# Recover back UP (explicitly)
	var tw2 := create_tween()
	set_meta("_slam_tw", tw2)
	tw2.tween_property(self, "position", _slam_base_local_pos, max(0.01, slam_recover_time))
	# IMPORTANT: await at least one frame so you SEE the recovery begin
	await get_tree().process_frame
