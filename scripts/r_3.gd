extends Unit
class_name R3
# Heavy Artillery Mech - Missile Turret Platform
# Special 1: BARRAGE - Fire up to 8 missiles in rapid succession at different targets
# Special 2: RAILGUN - Piercing laser shot that damages everything in a straight line

# -------------------------
# Visual / identity
# -------------------------
@export var portrait_tex: Texture2D = preload("res://sprites/Portraits/dog_port.png") # swap to artillery mech portrait
@export var thumbnail: Texture2D
@export var specials: Array[String] = ["BARRAGE", "RAILGUN"]
@export var special_desc: String = "Unleash devastating missile barrage, or fire a piercing railgun shot."

@export var attack_anim_name: StringName = &"attack"
@export var idle_anim_name: StringName = &"idle"

# -------------------------
# Base stats
# -------------------------
@export var base_move_range := 4
@export var base_attack_range := 5
@export var base_max_hp := 8
@export var basic_ranged_damage := 2

# -------------------------
# Special 1: BARRAGE tuning
# -------------------------
@export var barrage_range := 10
@export var barrage_max_missiles := 8
@export var barrage_damage := 2
@export var barrage_splash_radius := 1
@export var barrage_cooldown := 6
@export var barrage_min_safe_dist := 3

# Missile flight properties
@export var barrage_flight_time := 1.2
@export var barrage_arc_height_px := 120.0
@export var barrage_stagger_time := 0.15  # delay between launches
@export var barrage_impact_delay := 0.0  # extra delay before damage (0 = on arrival)

# Safety settings
@export var barrage_avoid_allies := true
@export var barrage_avoid_self := true

# VFX / SFX
@export var barrage_launch_sfx_id: StringName = &"missile_launch"
@export var barrage_impact_sfx_id: StringName = &"explosion_small"

# -------------------------
# Special 2: RAILGUN tuning
# -------------------------
@export var railgun_range := 12
@export var railgun_damage := 3
@export var railgun_pierce_damage_falloff := 0.5  # each target takes 50% less
@export var railgun_cooldown := 5
@export var railgun_min_safe_dist := 2

# Railgun beam visuals
@export var railgun_beam_width := 8.0
@export var railgun_beam_color: Color = Color(0.2, 0.7, 1.0, 0.9)  # bright blue
@export var railgun_beam_glow_color: Color = Color(0.4, 0.9, 1.0, 0.7)
@export var railgun_beam_duration := 0.5
@export var railgun_charge_time := 0.3
@export var railgun_muzzle_flash_scale := 2.0

# Railgun SFX
@export var railgun_charge_sfx_id: StringName = &"railgun_charge"
@export var railgun_fire_sfx_id: StringName = &"railgun_fire"
@export var railgun_hit_sfx_id: StringName = &"railgun_hit"

# Projectile scene (optional, for visual missile trails)
@export var missile_projectile_scene: PackedScene
@export var iso_feet_offset_y := 16.0

signal barrage_complete
var _pending_impacts: int = 0

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
	if id == "barrage":
		return int(special_cd.get("barrage", 0)) <= 0
	elif id == "railgun":
		return int(special_cd.get("railgun", 0)) <= 0
	return false

func get_special_range(id: String) -> int:
	id = id.to_lower()
	if id == "barrage":
		return barrage_range
	elif id == "railgun":
		return railgun_range
	return 0

func get_special_min_distance(id: String) -> int:
	id = id.to_lower()
	if id == "barrage":
		return barrage_min_safe_dist
	elif id == "railgun":
		return railgun_min_safe_dist
	return 0

# -------------------------------------------------------
# Basic attack (ranged projectile)
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

	# Fire single missile at target
	var tw := M.fire_support_missile_curve_async(
		cell,
		target_cell,
		0.8,
		80.0,
		32
	)

	if tw != null and is_instance_valid(tw):
		await tw.finished

	if is_instance_valid(tgt):
		_apply_damage_safely(tgt, basic_ranged_damage)
		M.spawn_explosion_at_cell(target_cell)

	_play_idle_anim()

# -------------------------------------------------------
# Special 1: BARRAGE
# Fires up to 8 missiles at different enemy targets
# -------------------------------------------------------
func perform_barrage(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
		return
	if not _alive():
		return

	var id_key := "barrage"
	if int(special_cd.get(id_key, 0)) > 0:
		return

	var d = abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y)
	if d < barrage_min_safe_dist or d > barrage_range:
		return

	_face_toward_cell(target_cell)

	# Find all valid targets
	var targets := _find_barrage_targets(M)
	if targets.is_empty():
		_play_idle_anim()
		return

	var shots = min(barrage_max_missiles, targets.size())
	var pending_impacts := 0

	for i in range(shots):
		if not _alive():
			break

		var impact_cell: Vector2i = targets[i].cell

		# ✅ play attack on EVERY missile
		_play_attack_anim_once() # make sure this restarts/plays one-shot

		_sfx_at_cell(M, barrage_launch_sfx_id, cell)

		var tw := M.fire_support_missile_curve_async(
			cell,
			impact_cell,
			barrage_flight_time,
			barrage_arc_height_px,
			32
		)

		if tw != null and is_instance_valid(tw):
			pending_impacts += 1

			# Safer than an inline lambda in some Godot setups: bind args.
			tw.finished.connect(Callable(self, "_on_barrage_missile_finished").bind(M, impact_cell))

		# Stagger launches
		if i < shots - 1 and barrage_stagger_time > 0.0:
			await get_tree().create_timer(barrage_stagger_time).timeout

	# Wait for all impacts
	if pending_impacts > 0:
		await barrage_complete

	# ✅ back to idle only when DONE
	_play_idle_anim()
	special_cd[id_key] = barrage_cooldown


func _on_barrage_missile_finished(M: MapController, impact_cell: Vector2i) -> void:
	_on_barrage_impact(M, impact_cell)
	# decrement + emit completion
	# (store pending_impacts as a member if you prefer; easiest is make it a member var)
	_pending_impacts -= 1
	if _pending_impacts <= 0:
		emit_signal("barrage_complete")

func _on_barrage_impact(M: MapController, impact_cell: Vector2i) -> void:
	if M == null or not is_instance_valid(M):
		return

	# Explosion and damage
	M.spawn_explosion_at_cell(impact_cell)
	_sfx_at_cell(M, barrage_impact_sfx_id, impact_cell)

	# Splash damage
	await M._apply_splash_damage(
		impact_cell,
		barrage_splash_radius,
		barrage_damage + attack_damage
	)

	# Structure damage
	if M.has_method("_apply_structure_splash_damage"):
		M.call("_apply_structure_splash_damage", impact_cell, barrage_splash_radius, 1)

func _find_barrage_targets(M: MapController) -> Array[Unit]:
	var out: Array[Unit] = []
	var enemies := M.get_all_enemies()
	if enemies.is_empty():
		return out

	for e in enemies:
		if e == null or not is_instance_valid(e) or e.hp <= 0:
			continue

		var d = abs(e.cell.x - cell.x) + abs(e.cell.y - cell.y)
		if d > barrage_range or d < barrage_min_safe_dist:
			continue

		# Safety check: don't hit allies with splash
		if barrage_avoid_allies and not _target_is_safe(M, e.cell):
			continue

		out.append(e)

	# Sort by distance (closest first)
	out.sort_custom(func(a: Unit, b: Unit) -> bool:
		var da = abs(a.cell.x - cell.x) + abs(a.cell.y - cell.y)
		var db = abs(b.cell.x - cell.x) + abs(b.cell.y - cell.y)
		return da < db
	)

	return out

func _target_is_safe(M: MapController, target_cell: Vector2i) -> bool:
	# Check if self would be hit
	if barrage_avoid_self:
		var ds = abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y)
		if ds <= barrage_splash_radius:
			return false

	# Check allies in splash radius
	for u in M.get_all_units():
		if u == null or not is_instance_valid(u):
			continue
		if u.team != Unit.Team.ALLY:
			continue

		var d = abs(target_cell.x - u.cell.x) + abs(target_cell.y - u.cell.y)
		if d <= barrage_splash_radius:
			return false

	return true

# -------------------------------------------------------
# Special 2: RAILGUN
# Piercing laser beam that damages all units in a line
# -------------------------------------------------------
func perform_railgun(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
		return
	if not _alive():
		return

	var id_key := "railgun"
	if int(special_cd.get(id_key, 0)) > 0:
		return

	var d = abs(target_cell.x - cell.x) + abs(target_cell.y - cell.y)
	if d < railgun_min_safe_dist or d > railgun_range:
		return

	_face_toward_cell(target_cell)
	_play_attack_anim_once()

	# Charge up effect
	_sfx_at_cell(M, railgun_charge_sfx_id, cell)
	await get_tree().create_timer(railgun_charge_time).timeout

	if not _alive():
		return

	# Fire railgun
	_sfx_at_cell(M, railgun_fire_sfx_id, cell)

	# Get all cells in line from us to target
	var line_cells := _get_line_cells(M, cell, target_cell)

	# Create beam visual
	var beam := _create_railgun_beam(M, cell, target_cell)

	# Find all units hit by the beam
	var hit_units: Array[Unit] = []
	for c in line_cells:
		var u := M.unit_at_cell(c)
		if u != null and is_instance_valid(u) and u != self:
			if "team" in u and u.team != team:
				hit_units.append(u)

	# Deal piercing damage (decreases with each hit)
	var current_damage := railgun_damage + attack_damage
	for u in hit_units:
		if not is_instance_valid(u):
			continue

		# Flash and damage
		if M.has_method("_flash_unit_white"):
			M.call("_flash_unit_white", u, 0.15)

		_apply_damage_safely(u, int(current_damage))
		_sfx_at_cell(M, railgun_hit_sfx_id, u.cell)

		# Explosion on hit cell + 8 surrounding cells
		_spawn_railgun_hit_burst(M, u.cell)

		# Reduce damage for next target
		current_damage *= railgun_pierce_damage_falloff

		await get_tree().create_timer(0.05).timeout

	# Fade out beam
	if is_instance_valid(beam):
		_fade_out_beam(beam)

	_play_idle_anim()
	special_cd[id_key] = railgun_cooldown

func _spawn_railgun_hit_burst(M: MapController, center_cell: Vector2i) -> void:
	if M == null:
		return

	# 8 neighbors around the hit cell (no center)
	var offsets := [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1,  0),                 Vector2i(1,  0),
		Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1),
	]

	# Always spawn center explosion too (keeps your current behavior)
	M.spawn_explosion_at_cell(center_cell)

	for off in offsets:
		var c = center_cell + off
		if _cell_in_bounds(M, c):
			M.spawn_explosion_at_cell(c)

func _get_line_cells(M: MapController, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	
	# Bresenham's line algorithm for grid
	var dx = abs(to.x - from.x)
	var dy = abs(to.y - from.y)
	var sx := 1 if to.x > from.x else -1
	var sy := 1 if to.y > from.y else -1
	var err = dx - dy
	
	var current := from
	
	while true:
		if _cell_in_bounds(M, current):
			cells.append(current)
		
		if current == to:
			break
			
		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			current.x += sx
		if e2 < dx:
			err += dx
			current.y += sy
	
	return cells

func _create_railgun_beam(M: MapController, from_cell: Vector2i, to_cell: Vector2i) -> Node2D:
	var beam := Line2D.new()
	beam.width = railgun_beam_width
	beam.default_color = railgun_beam_color
	beam.antialiased = true
	beam.begin_cap_mode = Line2D.LINE_CAP_ROUND
	beam.end_cap_mode = Line2D.LINE_CAP_ROUND

	var from_pos := _cell_to_global(M, from_cell)
	from_pos.y -= iso_feet_offset_y

	var to_pos := _cell_to_global(M, to_cell)
	to_pos.y -= iso_feet_offset_y

	beam.add_point(from_pos)
	beam.add_point(to_pos)

	# Add outer glow
	var glow := Line2D.new()
	glow.width = railgun_beam_width * 2.5
	glow.default_color = railgun_beam_glow_color
	glow.antialiased = true
	glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	glow.end_cap_mode = Line2D.LINE_CAP_ROUND
	glow.add_point(from_pos)
	glow.add_point(to_pos)
	glow.z_index = -1

	var container := Node2D.new()
	container.add_child(glow)
	container.add_child(beam)
	container.z_index = 1000

	M.add_child(container)
	return container

func _fade_out_beam(beam_container: Node2D) -> void:
	if not is_instance_valid(beam_container):
		return

	var tween := create_tween()
	tween.tween_property(beam_container, "modulate:a", 0.0, railgun_beam_duration)
	tween.tween_callback(beam_container.queue_free)

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
	if M == null or sfx_id == &"":
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
	# --- find AnimatedSprite2D ---
	var anim: AnimatedSprite2D = null
	var n := get_node_or_null("Animate")
	if n is AnimatedSprite2D:
		anim = n
	else:
		n = get_node_or_null("AnimatedSprite2D")
		if n is AnimatedSprite2D:
			anim = n

	if anim == null:
		print("FACE: no AnimatedSprite2D found on unit:", name)
		return

	# --- find MapController ---
	var M: MapController = null

	# 1) group (preferred)
	var maps := get_tree().get_nodes_in_group("MapController")
	if maps.size() > 0 and maps[0] is MapController:
		M = maps[0] as MapController
	else:
		print("FACE: MapController group empty (size=%d)" % maps.size())

	# 2) current scene direct child
	if M == null:
		var root := get_tree().current_scene
		if root != null:
			var direct := root.get_node_or_null("MapController")
			if direct is MapController:
				M = direct as MapController
			else:
				print("FACE: no MapController node at root/MapController")

	# 3) Game exposes it (your Game has @onready var map_controller)
	if M == null:
		var root2 := get_tree().current_scene
		if root2 != null and ("map_controller" in root2):
			M = root2.map_controller as MapController
			print("FACE: using Game.map_controller fallback")

	if M == null:
		print("FACE: FAILED to get MapController")
		return

	# --- get terrain ---
	var terrain: TileMap = null

	# preferred: M.terrain (if you added it)
	if "terrain" in M and M.terrain != null:
		terrain = M.terrain as TileMap
	else:
		print("FACE: M.terrain missing/null, trying Game.Terrain")

	# fallback: Game has @onready var terrain: TileMap = $Terrain
	if terrain == null:
		var root3 := get_tree().current_scene
		if root3 != null and ("terrain" in root3) and root3.terrain != null:
			terrain = root3.terrain as TileMap

	if terrain == null:
		print("FACE: FAILED to get Terrain TileMap")
		return

	# --- iso-safe facing using map_to_local ---
	var my_pos := terrain.map_to_local(cell)
	var target_pos := terrain.map_to_local(target_cell)

	# default art faces LEFT -> right = flip ON
	if target_pos.x > my_pos.x:
		anim.flip_h = true
	elif target_pos.x < my_pos.x:
		anim.flip_h = false

	# debug (comment out once confirmed)
	#print("FACE OK: unit=", name, " flip=", anim.flip_h, " my=", my_pos, " tgt=", target_pos)

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
		"Barrage Range": str(barrage_range),
		"Barrage Missiles": str(barrage_max_missiles),
		"Barrage Damage": str(barrage_damage + attack_damage),
		"Railgun Range": str(railgun_range),
		"Railgun Damage": str(railgun_damage + attack_damage),
	}
