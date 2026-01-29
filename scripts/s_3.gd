extends Unit
class_name S3
# Spiderbot-style mech
# Special: NOVA — an 8-point star burst (cross + diagonals) centered on a target cell,
# then a delayed "aftershock" ring one tile farther out.

# -------------------------
# Visual / identity
# -------------------------
@export var portrait_tex: Texture2D = preload("res://sprites/Portraits/dog_port.png") # swap to spider portrait
@export var display_name := "S3 Arachnid"
@export var thumbnail: Texture2D
@export var special: String = "NOVA"
@export var special_desc: String = "Detonate a starburst blast, then an aftershock ring."

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
# Special: NOVA tuning
# -------------------------
@export var nova_range := 6
@export var nova_radius := 3          # length of star arms
@export var nova_damage := 2
@export var nova_cooldown := 5
@export var nova_min_safe_dist := 2   # can't target your own cell; 2 = must be 2+ away, etc.

# Aftershock ring (optional)
@export var aftershock_enabled := true
@export var aftershock_delay := 0.12
@export var aftershock_damage := 1
@export var aftershock_radius_offset := 1  # ring at (nova_radius + offset)

# VFX / SFX (optional)
@export var nova_explosion_scene: PackedScene
@export var nova_explosion_z := 999
@export var nova_sfx_id: StringName = &"nova"
@export var nova_hit_sfx_id: StringName = &"nova_hit"

# If your visuals are anchored with a feet offset, keep this consistent with your project
@export var iso_feet_offset_y := 16.0

# Wave feel
@export var nova_ring_delay := 0.05     # delay per ring (Manhattan distance from center)
@export var nova_max_rings_per_frame := 999  # keep high unless you want perf throttling

# Splash (AoE around each struck cell)
@export var nova_splash_radius := 1
@export var nova_splash_damage := 1
@export var nova_splash_hits_allies := false
@export var nova_splash_hits_structures := false

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
	return ["Nova"]

func can_use_special(id: String) -> bool:
	id = id.to_lower()
	if id != "nova":
		return false
	return int(special_cd.get("nova", 0)) <= 0

func get_special_range(id: String) -> int:
	id = id.to_lower()
	if id == "nova":
		return nova_range
	return 0

func get_special_min_distance(id: String) -> int:
	id = id.to_lower()
	if id == "nova":
		return nova_min_safe_dist
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
# Special: NOVA
# - Pick a target cell in range
# - Hit an 8-point star (cross + diagonals) out to nova_radius
# - Optional aftershock ring one tile farther out
# -------------------------------------------------------
func perform_nova(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
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
	await _apply_cells_damage_wave(M, primary_cells, nova_damage, target_cell)

	# Aftershock ring (also wavey)
	if aftershock_enabled:
		await get_tree().create_timer(max(0.01, aftershock_delay)).timeout
		var ring_r = max(1, nova_radius + aftershock_radius_offset)
		var ring_cells := _get_ring_cells(M, target_cell, ring_r)
		await _apply_cells_damage_wave(M, ring_cells, aftershock_damage, target_cell)

	_play_idle_anim()
	special_cd[id_key] = nova_cooldown

func _apply_cells_damage_wave(M: MapController, cells: Array[Vector2i], dmg: int, center: Vector2i) -> void:
	if M == null or dmg <= 0:
		return
	if cells.is_empty():
		return

	# Group by ring (Manhattan distance from center)
	var rings: Dictionary = {} # int -> Array[Vector2i]
	var max_ring := 0

	for c in cells:
		var dist = abs(c.x - center.x) + abs(c.y - center.y)
		if not rings.has(dist):
			rings[dist] = []
		(rings[dist] as Array).append(c)
		max_ring = max(max_ring, dist)

	# Play rings in order
	for ring in range(0, max_ring + 1):
		if not rings.has(ring):
			continue

		var ring_cells: Array = rings[ring]
		# Optional: randomize inside the ring so it feels organic
		ring_cells.shuffle()

		for c in ring_cells:
			# Per-cell FX + damage + splash
			_spawn_nova_explosion(M, c)
			_sfx_at_cell(M, nova_hit_sfx_id, c)

			# Direct cell hit
			_apply_damage_at_cell(M, c, dmg)

			# Splash around it
			_apply_nova_splash_damage(M, c)

		# Delay before next ring (wave feel)
		if ring < max_ring and nova_ring_delay > 0.0:
			await get_tree().create_timer(nova_ring_delay).timeout

func _apply_damage_at_cell(M: MapController, c: Vector2i, dmg: int) -> void:
	var tgt := M.unit_at_cell(c)
	if tgt != null and is_instance_valid(tgt):
		if ("team" in tgt) and (tgt.team == team):
			return
		_apply_damage_safely(tgt, dmg)

	# Optional: structures
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

			# Circular mask (comment out for square)
			if Vector2(ox, oy).length() > float(nova_splash_radius) + 0.01:
				continue

			# Units
			var tgt := M.unit_at_cell(c)
			if tgt != null and is_instance_valid(tgt):
				if (not nova_splash_hits_allies) and ("team" in tgt) and (tgt.team == team):
					continue
				_apply_damage_safely(tgt, nova_splash_damage)

			# Structures (optional)
			if nova_splash_hits_structures:
				var s: Object = null
				if M.has_method("_structure_at_cell"):
					s = M.call("_structure_at_cell", c)
				elif M.has_method("structure_at_cell"):
					s = M.call("structure_at_cell", c)
				if s != null and is_instance_valid(s):
					_apply_damage_safely(s, nova_splash_damage)

# -------------------------
# Pattern builders
# -------------------------
func _get_starburst_cells(M: MapController, center: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.append(center)

	var dirs := [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), # cross
		Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1) # diagonals
	]

	for dir in dirs:
		for i in range(1, r + 1):
			var c = center + dir * i
			if not _cell_in_bounds(M, c):
				continue
			out.append(c)

	return _dedupe_cells(out)

func _get_ring_cells(M: MapController, center: Vector2i, r: int) -> Array[Vector2i]:
	# Diamond ring (Manhattan distance == r). Feels good on grid + iso.
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

# -------------------------
# Damage + FX application
# -------------------------
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
			# Enemies only (change if you want friendly fire)
			if ("team" in tgt) and (tgt.team == team):
				continue
			_apply_damage_safely(tgt, dmg)

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

		# Depth sort by (x+y) if your project uses it
		var z_base := 0
		var z_per := 1
		if "z_base" in M: z_base = int(M.z_base)
		if "z_per_cell" in M: z_per = int(M.z_per_cell)
		n.z_index = z_base + (c.x + c.y) * z_per + 1

	M.add_child(fx)
