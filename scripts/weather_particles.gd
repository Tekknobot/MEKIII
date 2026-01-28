extends Node2D
class_name WeatherParticles2D

enum Weather { NONE, RAIN, SNOW, ASH }

@export var weather: Weather = Weather.RAIN
@export var intensity := 0.75 # 0..1
@export var wind := Vector2(90, 0) # px/s (x wind, y extra fall)
@export var follow_camera := true

# How big an area to cover (in pixels). If follow_camera=true this is centered on camera.
@export var cover_size := Vector2(1152, 648)

# Optional: set this if you want it to follow a specific Camera2D node
@export var camera_path: NodePath

var _cam: Camera2D
var _rain: GPUParticles2D
var _snow: GPUParticles2D
var _ash: GPUParticles2D

@export var base_cover_size := Vector2(1152, 648)
# This is the size your particle box was authored for

var _last_cover := Vector2.ZERO

func _ready() -> void:
	_cam = get_node_or_null(camera_path) as Camera2D
	_build()

	get_viewport().size_changed.connect(_fit_to_viewport)

	# wait one frame so viewport/camera sizes are valid
	await get_tree().process_frame

	_fit_to_viewport()
	_apply_all()
	_set_weather(weather)

func _process(_delta: float) -> void:
	if follow_camera:
		var c := _get_camera_center()
		global_position = c

func set_weather(w: Weather) -> void:
	weather = w
	_set_weather(w)

func set_intensity(v: float) -> void:
	intensity = clampf(v, 0.0, 1.0)
	_apply_all()

func set_wind(v: Vector2) -> void:
	wind = v
	_apply_all()

# -------------------------------------------------
# Build nodes
# -------------------------------------------------
func _build() -> void:
	_rain = _make_particles("Rain")
	_snow = _make_particles("Snow")
	_ash  = _make_particles("Ash")

	add_child(_rain)
	add_child(_snow)
	add_child(_ash)

	# Start with all off, then enable chosen one
	_rain.emitting = false
	_snow.emitting = false
	_ash.emitting = false

func _make_particles(n: String) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = n
	p.one_shot = false
	p.preprocess = 6.2
	p.explosiveness = 0.0
	p.local_coords = true
	p.draw_order = GPUParticles2D.DRAW_ORDER_INDEX
	p.amount = 400
	p.visibility_rect = Rect2(-cover_size * 0.5, cover_size)
	return p

# -------------------------------------------------
# Configure looks
# -------------------------------------------------
func _apply_all() -> void:
	_apply_rain()
	_apply_snow()
	_apply_ash()

func _apply_rain() -> void:
	if _rain == null: return
	_rain.visibility_rect = Rect2(-cover_size * 0.5, cover_size)

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(cover_size.x * 0.5, cover_size.y * 0.5, 0.0) # ✅ full centered box
	pm.emission_shape_offset = Vector3.ZERO # ✅ centered

	
	# Rain: fast down, slight wind
	var fall := 900.0 + (intensity * 800.0)
	pm.gravity = Vector3(wind.x, fall + wind.y, 0.0)

	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0

	pm.scale_min = 0.45
	pm.scale_max = 0.85

	pm.angle_min = -8.0
	pm.angle_max = 8.0

	pm.lifetime_randomness = 0.05
	_rain.lifetime = max(0.35, cover_size.y / fall)

	# Amount
	_rain.amount = int(lerpf(120.0, 1100.0, intensity))

	# Use a tiny stretched raindrop texture made in code (no external file)
	_rain.texture = _make_drop_texture(2, 18)
	_rain.process_material = pm

	# Subtle fade-out at end
	_rain.modulate = Color(1, 1, 1, 0.75)

func _apply_snow() -> void:
	if _snow == null: return
	_snow.visibility_rect = Rect2(-cover_size * 0.5, cover_size)

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(cover_size.x * 0.5, cover_size.y * 0.5, 0.0) # ✅ full centered box
	pm.emission_shape_offset = Vector3.ZERO # ✅ centered
	
	var fall := 110.0 + (intensity * 160.0)
	pm.gravity = Vector3(wind.x * 0.35, fall + wind.y * 0.15, 0.0)

	pm.initial_velocity_min = 10.0
	pm.initial_velocity_max = 40.0

	# gentle sideways drift
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 25.0

	pm.angular_velocity_min = -40.0
	pm.angular_velocity_max = 40.0

	pm.scale_min = 0.6
	pm.scale_max = 1.6

	pm.lifetime_randomness = 0.35
	_snow.lifetime = max(2.0, cover_size.y / fall)

	_snow.amount = int(lerpf(40.0, 420.0, intensity))
	_snow.texture = _make_dot_texture(6)
	_snow.process_material = pm
	_snow.modulate = Color(1, 1, 1, 0.85)

func _apply_ash() -> void:
	if _ash == null: return
	_ash.visibility_rect = Rect2(-cover_size * 0.5, cover_size)

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(cover_size.x * 0.5, cover_size.y * 0.5, 0.0)

	# Ash: slow float, lots of sideways
	var fall := 30.0 + (intensity * 40.0)
	pm.gravity = Vector3(wind.x * 0.6, fall + wind.y * 0.05, 0.0)

	pm.initial_velocity_min = 10.0
	pm.initial_velocity_max = 55.0
	pm.spread = 60.0

	pm.angular_velocity_min = -80.0
	pm.angular_velocity_max = 80.0

	pm.scale_min = 0.7
	pm.scale_max = 2.4

	pm.lifetime_randomness = 0.55
	_ash.lifetime = 16.0

	_ash.amount = int(lerpf(30.0, 300.0, intensity))
	_ash.texture = _make_dot_texture(5)
	_ash.process_material = pm
	_ash.modulate = Color(0.95, 0.92, 0.85, 0.55)

# -------------------------------------------------
# Enable / disable
# -------------------------------------------------
func _set_weather(w: Weather) -> void:
	if _rain: _rain.emitting = (w == Weather.RAIN)
	if _snow: _snow.emitting = (w == Weather.SNOW)
	if _ash:  _ash.emitting  = (w == Weather.ASH)

# -------------------------------------------------
# Helpers
# -------------------------------------------------
func _get_camera_center() -> Vector2:
	# Use explicit camera if provided; else use viewport camera if available.
	if _cam != null and is_instance_valid(_cam):
		return _cam.get_screen_center_position()

	var v := get_viewport()
	if v != null:
		var c := v.get_camera_2d()
		if c != null:
			return c.get_screen_center_position()

	# FINAL fallback (fixes "Not all code paths return")
	return global_position


func _make_dot_texture(size_px: int) -> Texture2D:
	var img := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var r := float(size_px) * 0.45
	var center := Vector2(size_px * 0.5, size_px * 0.5)

	for y in range(size_px):
		for x in range(size_px):
			var d := center.distance_to(Vector2(x + 0.5, y + 0.5))
			if d <= r:
				img.set_pixel(x, y, Color(1, 1, 1, 1))

	return ImageTexture.create_from_image(img)


func _make_drop_texture(w: int, h: int) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	for y in range(h):
		var a = 1.0 - (float(y) / max(1.0, float(h - 1))) * 0.55
		for x in range(w):
			img.set_pixel(x, y, Color(1, 1, 1, a))

	return ImageTexture.create_from_image(img)

func _fit_to_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return

	var view_px := vp.get_visible_rect().size
	if view_px.x < 2 or view_px.y < 2:
		return

	# If you use camera zoom, convert pixels -> world units
	var z := Vector2.ONE
	var c := _cam
	if c == null or not is_instance_valid(c):
		c = vp.get_camera_2d()
	if c != null:
		z = c.zoom

	cover_size = view_px * z

	_apply_all()
