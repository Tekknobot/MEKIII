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

func _ready() -> void:
	# Mark as enemy + give UI identity
	team = Unit.Team.ENEMY

	set_meta("portrait_tex", portrait_tex)
	set_meta("display_name", display_name)
	set_meta(&"is_elite", true)
	set_meta("vision", vision)

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
