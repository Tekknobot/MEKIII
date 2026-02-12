@tool
extends GPUParticles2D

@export var sprite_width_px := 32.0
@export var pixel_tex: Texture2D

@export var emit_rate := 70.0
@export var particle_lifetime := 0.45
@export var rise_speed := 55.0
@export var rise_speed_rand := 25.0
@export var spread_x := 14.0
@export var size_px := 2.0
@export var size_px_rand := 1.5

@export var col_hot := Color(1.0, 0.65, 0.20, 1.0)
@export var col_mid := Color(1.0, 0.25, 0.05, 1.0)
@export var col_smoke := Color(0.12, 0.06, 0.02, 0.0)

var _built := false

func _ready() -> void:
	_build_fire()

	# ✅ Editor preview
	if Engine.is_editor_hint():
		emitting = true
		preprocess = 1.5
		restart()

func _process(_dt: float) -> void:
	# ✅ If you tweak exports in-editor, rebuild once you assign a texture
	if Engine.is_editor_hint() and not _built and pixel_tex != null:
		_build_fire()
		emitting = true
		preprocess = 1.5
		restart()

func _build_fire() -> void:
	_built = true

	if pixel_tex == null:
		_built = false
		return

	one_shot = false
	emitting = true
	explosiveness = 0.0
	fixed_fps = 0

	# Texture
	texture = pixel_tex
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# Material
	var pm := ParticleProcessMaterial.new()
	process_material = pm

	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(spread_x, 1.0, 0.0)

	pm.lifetime = particle_lifetime
	amount = int(max(1.0, emit_rate * particle_lifetime))

	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.initial_velocity_min = max(0.0, rise_speed - rise_speed_rand)
	pm.initial_velocity_max = rise_speed + rise_speed_rand

	# tiny downward pull helps shape
	pm.gravity = Vector3(0.0, 10.0, 0.0)

	# Pixel chunk size (simple + readable)
	pm.scale_min = max(0.01, size_px / sprite_width_px)
	pm.scale_max = max(0.02, (size_px + size_px_rand) / sprite_width_px)

	pm.color = col_hot
	pm.color_ramp = _make_fire_ramp(col_hot, col_mid, col_smoke)

func _make_fire_ramp(a: Color, b: Color, c: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, a)
	g.add_point(0.75, b)
	g.set_color(1, c)

	var gt := GradientTexture1D.new()
	gt.gradient = g
	gt.width = 256
	return gt
