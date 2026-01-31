extends Unit
class_name EliteMech

# -------------------------
# Suppress VFX
# -------------------------
@export var suppress_twitch_strength := 0.8
@export var suppress_twitch_interval := 0.012
@export var suppress_flash_strength := 1.25

var _suppress_tw: Tween = null
var _suppress_timer: float = 0.0
var _suppress_base_pos: Vector2
var _suppress_base_modulate: Color
var _suppress_active := false

# -------------------------
# Identity / visuals
# -------------------------
@export var portrait_tex: Texture2D = preload("res://sprites/Portraits/Mechas/rob1_port.png") # swap to your asset
@export var explosion_scene: PackedScene

# Optional: if your mech scene has a Sprite2D/AnimatedSprite2D you want as primary render
@export var render_node_name: StringName = &"Sprite2D"
@export var vision := 16 

@export var dissolve_shader: Shader = preload("res://shaders/pixel_dissolve.gdshader")
@export var dissolve_time := 1.55
@export var dissolve_pixel_size := 1.0
@export var dissolve_edge_width := 0.08
@export var dissolve_edge_color := Color(0.6, 1.0, 0.6, 1.0)

var _death_tw: Tween = null
var _saved_material: Material = null

# -------------------------
# SPECIAL: Artillery Burst
# -------------------------
@export var special_name: String = "ARTILLERY"
@export var special_desc: String = "Fire a shell that explodes for splash damage."

@export var special_range: int = 6
@export var special_damage: int = 3
@export var splash_radius: int = 1          # 1 = center + 4-neighbors (Manhattan)
@export var special_cooldown_turns: int = 3

@export var projectile_scene: PackedScene   # optional (recommended)
@export var explosion_sfx: StringName = &"explosion_small"

var _special_cd: int = 0
const Z_BASE := 2
const Z_PER  := 0
const Z_PROJ_ABOVE := 0
const Z_FX_ABOVE   := 0

func _z_for_cell(c: Vector2i) -> int:
	return Z_BASE + (c.x + c.y)

func _cell_from_world(M: MapController, world_pos: Vector2) -> Vector2i:
	# convert world -> map cell (safe for your terrain usage)
	var local := M.terrain.to_local(world_pos)
	return M.terrain.local_to_map(local)

func _ready() -> void:
	# Mark as enemy + give UI identity
	team = Unit.Team.ENEMY

	set_meta("portrait_tex", portrait_tex)
	set_meta("display_name", display_name)
	set_meta(&"is_elite", true)
	set_meta("vision", vision)

	set_meta("special", special_name)
	set_meta("special_desc", special_desc)

	# If you want a simple armor hook later:
	# (Only matters if your damage code checks it)
	if not has_meta(&"armor"):
		set_meta(&"armor", 1)

	# Basic unit stats (tune as you like)
	footprint_size = Vector2i(1, 1)
	move_range = 4
	attack_range = 2
	attack_damage = 2

	# Elite durability
	max_hp = max(max_hp, 32)
	hp = clamp(hp, 0, max_hp)

	super._ready()

	var e := get_node_or_null("Emitter") as Node2D
	if e:
		e.position = visual_offset
		
	_suppress_base_pos = global_position
	var ci := _get_render_item()
	if ci != null:
		_suppress_base_modulate = ci.modulate
	else:
		_suppress_base_modulate = Color(1, 1, 1, 1)

func _process(delta: float) -> void:
	# Only twitch while suppressed
	var turns := 0
	if has_meta("suppress_turns"):
		turns = int(get_meta("suppress_turns"))

	var want := turns > 0

	if want and not _suppress_active:
		_suppress_active = true
		_start_suppress_twitch()
	elif (not want) and _suppress_active:
		_suppress_active = false
		_stop_suppress_twitch()

	# keep base position updated when NOT suppressed (so movement doesn't fight the twitch)
	if not _suppress_active:
		_suppress_base_pos = global_position

func _start_suppress_twitch() -> void:
	_stop_suppress_twitch() # safety

	_suppress_timer = 0.0
	_suppress_base_pos = global_position

	var ci := _get_render_item()
	if ci != null:
		_suppress_base_modulate = ci.modulate

	# Looping twitch tween
	_suppress_tw = create_tween()
	_suppress_tw.set_loops() # infinite
	_suppress_tw.set_trans(Tween.TRANS_SINE)
	_suppress_tw.set_ease(Tween.EASE_IN_OUT)

	# small jitter offsets around the base
	var step = max(0.04, suppress_twitch_interval)

	_suppress_tw.tween_callback(func():
		if self == null or not is_instance_valid(self): return
		global_position = _suppress_base_pos + Vector2(
			randf_range(-suppress_twitch_strength, suppress_twitch_strength),
			randf_range(-suppress_twitch_strength, suppress_twitch_strength)
		)

		# quick flash brighten
		var cii := _get_render_item()
		if cii != null and is_instance_valid(cii):
			var base := _suppress_base_modulate
			cii.modulate = Color(
				min(base.r * suppress_flash_strength, 2.0),
				min(base.g * suppress_flash_strength, 2.0),
				min(base.b * suppress_flash_strength, 2.0),
				base.a
			)
	)

	_suppress_tw.tween_interval(step * 0.5)

	_suppress_tw.tween_callback(func():
		if self == null or not is_instance_valid(self): return
		global_position = _suppress_base_pos
		var cii := _get_render_item()
		if cii != null and is_instance_valid(cii):
			cii.modulate = _suppress_base_modulate
	)

	_suppress_tw.tween_interval(step * 0.5)

func _stop_suppress_twitch() -> void:
	if _suppress_tw != null and is_instance_valid(_suppress_tw):
		_suppress_tw.kill()
	_suppress_tw = null

	# restore
	global_position = _suppress_base_pos
	var ci := _get_render_item()
	if ci != null and is_instance_valid(ci):
		ci.modulate = _suppress_base_modulate

func _get_render_item() -> CanvasItem:
	# Prefer a named child if provided
	if render_node_name != &"":
		var n := get_node_or_null(String(render_node_name))
		if n is CanvasItem:
			return n as CanvasItem

	# Fallbacks
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	if spr != null:
		return spr
	var anim := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim != null:
		return anim

	for ch in get_children():
		if ch is CanvasItem:
			return ch as CanvasItem
	return null

func play_death_anim() -> void:
	# Prevent double-run
	if _death_tw != null and is_instance_valid(_death_tw):
		return

	# Stop interaction / AI side effects while dissolving
	set_process(false)
	set_physics_process(false)

	# Optional: remove from MapController dicts immediately if you have a hook
	# (usually MapController listens to died(u) anyway)

	var ci := _get_render_canvas_item()
	if ci == null or not is_instance_valid(ci):
		queue_free()
		return

	# Save old material so you don’t permanently overwrite in-editor
	_saved_material = ci.material

	var mat := ShaderMaterial.new()
	mat.shader = dissolve_shader
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("pixel_size", dissolve_pixel_size)
	mat.set_shader_parameter("edge_width", dissolve_edge_width)
	mat.set_shader_parameter("edge_color", dissolve_edge_color)

	ci.material = mat

	# Tween dissolve progress
	_death_tw = create_tween()
	_death_tw.set_trans(Tween.TRANS_SINE)
	_death_tw.set_ease(Tween.EASE_IN_OUT)

	_death_tw.tween_method(
		func(v: float) -> void:
			if ci != null and is_instance_valid(ci) and ci.material is ShaderMaterial:
				(ci.material as ShaderMaterial).set_shader_parameter("progress", v),
		0.0, 1.0, dissolve_time
	)

	_death_tw.finished.connect(func():
		# (Optional) restore material, but we’re freeing anyway
		if is_instance_valid(self):
			queue_free()
	)

func tick_cooldowns() -> void:
	if _special_cd > 0:
		_special_cd -= 1

func can_use_special(M) -> bool:
	return _special_cd <= 0 and M != null

func special_cells(M) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if M == null:
		return out
	for x in range(-special_range, special_range + 1):
		for y in range(-special_range, special_range + 1):
			var c := cell + Vector2i(x, y)
			# Manhattan range (diamond) — change to Euclid if you want
			if abs(x) + abs(y) > special_range:
				continue
			if M._in_bounds(c): # if MapController has this; otherwise remove this line
				out.append(c)
	return out

func _splash_cells(center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in range(-splash_radius, splash_radius + 1):
		for dy in range(-splash_radius, splash_radius + 1):
			if abs(dx) + abs(dy) > splash_radius:
				continue
			out.append(center + Vector2i(dx, dy))
	return out

func ai_try_special(M: MapController) -> bool:
	# returns true if it performed the special
	if M == null:
		return false
	if not can_use_special(M):
		return false

	# pick best target cell near allies
	var target := _ai_pick_best_special_cell(M)
	if target == Vector2i(999999, 999999):
		return false

	# fire it
	await _fire_salvo_3x3(M, target)
	return true

func _ai_pick_best_special_cell(M: MapController) -> Vector2i:
	# score cells in range: prefer hitting multiple allies, avoid empty shots
	var best := Vector2i(999999, 999999)
	var best_score := -999999

	# iterate diamond in range
	for dx in range(-special_range, special_range + 1):
		for dy in range(-special_range, special_range + 1):
			if abs(dx) + abs(dy) > special_range:
				continue

			var c := cell + Vector2i(dx, dy)

			# (optional) bounds guard if you have it
			if M.has_method("_in_bounds"):
				if not M.call("_in_bounds", c):
					continue

			# score splash
			var score := 0
			var hits := 0

			for sc in _splash_cells(c):
				if not (sc in M.units_by_cell):
					continue
				var u = M.units_by_cell[sc]
				if u == null or not is_instance_valid(u) or u.hp <= 0:
					continue

				# Only score allies as targets
				if u.team != Unit.Team.ALLY:
					continue

				hits += 1
				# prefer low hp (finish kills)
				score += 10 + (20 - int(u.hp))

			# don’t waste cooldown on 0 hits
			if hits <= 0:
				continue

			# mild preference: closer (less travel time / feels snappier)
			score -= (abs(dx) + abs(dy))

			if score > best_score:
				best_score = score
				best = c

	return best

func _fire_projectile_and_explode(M, target_cell: Vector2i) -> void:
	if M == null or projectile_scene == null:
		_impact_cell(M, target_cell)
		return

	var to_world: Vector2 = M.terrain.to_global(M.terrain.map_to_local(target_cell)) + Vector2(0, -16)

	_face_world_pos(to_world)

	var emit := _emitter()
	var from_world := emit.global_position

	# 🔊 Bullet SFX at muzzle
	if M.has_method("_sfx"):
		M.call("_sfx", &"bullet", 1.0, 1.0, from_world)

	var p := projectile_scene.instantiate() as Node2D
	if p == null:
		_impact_cell(M, target_cell)
		return

	M.units_root.add_child(p)
	p.global_position = from_world
	p.z_as_relative = false

	# layer by emitter cell (so it feels "attached" to shooter depth)
	var from_cell := _cell_from_world(M, from_world)
	p.z_index = _z_for_cell(from_cell) + Z_PROJ_ABOVE

	# face travel direction
	var dir := (to_world - from_world)
	if dir.length() > 0.001:
		p.rotation = dir.angle()

	# slower projectile
	var speed_px_per_sec := 20.0
	var dist := from_world.distance_to(to_world)
	var t = clamp(dist / speed_px_per_sec, 0.20, 0.90)

	var tw := p.create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_IN_OUT)

	# optional: as it travels, update depth to match the cell it's currently over
	tw.tween_method(func(_v: float) -> void:
		if p == null or not is_instance_valid(p): return
		var c := _cell_from_world(M, p.global_position)
		p.z_index = _z_for_cell(c) + Z_PROJ_ABOVE
	, 0.0, 1.0, t)

	tw.parallel().tween_property(p, "global_position", to_world, t)

	await tw.finished
	if is_instance_valid(p):
		p.queue_free()

	_explode_once(M, target_cell)

func _explode_once(M, target_cell: Vector2i) -> void:
	if M == null:
		return

	var world_pos: Vector2 = M.terrain.to_global(M.terrain.map_to_local(target_cell)) + Vector2(0, -16)

	if explosion_scene != null:
		var e := explosion_scene.instantiate() as Node2D
		if e != null:
			M.units_root.add_child(e)
			e.global_position = world_pos
			e.z_as_relative = false
			e.z_index = _z_for_cell(target_cell) + Z_FX_ABOVE

			var ap := e.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if ap != null:
				if ap.has_animation("explode"):
					ap.play("explode")
				else:
					ap.play()
				ap.animation_finished.connect(func(_n):
					if is_instance_valid(e): e.queue_free()
				)
			else:
				var a := e.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
				if a != null:
					a.play()
					a.animation_finished.connect(func():
						if is_instance_valid(e): e.queue_free()
					)
				else:
					await get_tree().create_timer(0.35).timeout
					if is_instance_valid(e): e.queue_free()

	if M.has_method("_sfx"):
		M.call("_sfx", &"explosion_small", 1.0, 1.0, world_pos)

	_apply_splash_damage(M, target_cell)

func _apply_splash_damage(M, center: Vector2i) -> void:
	var cells := [
		center,
		center + Vector2i(1, 0),
		center + Vector2i(-1, 0),
		center + Vector2i(0, 1),
		center + Vector2i(0, -1),
	]

	var flashed := {} # Unit -> true

	for c in cells:
		var u = M.units_by_cell.get(c, null)
		if u == null or not is_instance_valid(u):
			continue
		if u == self or u.hp <= 0:
			continue

		u.take_damage(special_damage)

		# flash once per unit, immediately
		if not flashed.has(u) and is_instance_valid(u) and u.hp > 0:
			flashed[u] = true
			M._flash_unit_white(u, 0.88)

func _explode(M, center_cell: Vector2i) -> void:
	if M != null and M.has_method("_sfx"):
		M.call("_sfx", explosion_sfx, 1.0, 1.0, M.terrain.map_to_local(center_cell))

	var flashed := {} # Unit -> true (prevents double-flash)

	for c in _splash_cells(center_cell):
		if M == null:
			return # if M is null, bail; continuing makes no sense

		var u = M.units_by_cell.get(c, null)
		if u == null or not is_instance_valid(u):
			continue
		if u == self:
			continue

		# Hit ALLY team only:
		if u.team != Unit.Team.ALLY:
			continue

		# --- DAMAGE ---
		if u.has_method("take_damage"):
			u.call("take_damage", special_damage)
		elif ("hp" in u):
			u.hp -= special_damage

		# --- FLASH (immediately after damage) ---
		# If take_damage killed it and it got freed / queued, this will safely skip.
		if not flashed.has(u) and is_instance_valid(u) and (not ("hp" in u) or u.hp > 0):
			flashed[u] = true
			M._flash_unit_white(u, 0.88)

func _emitter() -> Node2D:
	var e := get_node_or_null("Emitter")
	if e is Node2D:
		return e as Node2D
	return self

func _face_world_pos(world_pos: Vector2) -> void:
	# default sprite faces LEFT
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	if spr == null:
		return

	# If target is to the RIGHT, flip to face right.
	spr.flip_h = (world_pos.x > global_position.x)

func _cells_3x3(center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			out.append(center + Vector2i(dx, dy))
	return out

func _impact_cell(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
		return

	var world_pos: Vector2 = M.terrain.to_global(M.terrain.map_to_local(target_cell))

	# VFX
	if explosion_scene != null:
		var e := explosion_scene.instantiate() as Node2D
		if e != null:
			M.units_root.add_child(e)
			e.global_position = world_pos
			e.z_index = 10_000

			var ap := e.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if ap != null:
				if ap.has_animation("explode"):
					ap.play("explode")
				else:
					ap.play()
				ap.animation_finished.connect(func(_n):
					if is_instance_valid(e): e.queue_free()
				)
			else:
				var a := e.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
				if a != null:
					a.play()
					a.animation_finished.connect(func():
						if is_instance_valid(e): e.queue_free()
					)
				else:
					e.queue_free()

	# SFX
	if M.has_method("_sfx"):
		M.call("_sfx", &"explosion_small", 1.0, 1.0, world_pos)

	# Damage ONLY the unit on that cell (any team)
	var u = M.units_by_cell.get(target_cell, null)
	if u != null and is_instance_valid(u) and u != self and u.hp > 0:
		u.take_damage(special_damage)

func _fire_salvo_3x3(M: MapController, center_cell: Vector2i) -> void:
	if M == null:
		return

	for c in _cells_3x3(center_cell):
		# (optional) bounds guard
		if M.has_method("_in_bounds") and not M.call("_in_bounds", c):
			continue

		# fire each projectile (sequential, simple + reliable)
		_fire_projectile_and_explode(M, c)
		await get_tree().create_timer(0.1).timeout
