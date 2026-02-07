extends Node2D

# -------------------------
# Starfield settings
# -------------------------
var star_count = 300
var stars = []
var speed = 50.0
var max_depth = 500.0

# Mask settings
@export var mask_radius = 150.0

# -------------------------
# Visitor settings (comets/asteroids)
# -------------------------
@export var visitor_min_time := 2.5      # seconds
@export var visitor_max_time := 7.0      # seconds
@export var comet_chance := 0.65         # otherwise asteroid

@export var comet_speed := 280.0
@export var asteroid_speed := 140.0

@export var comet_trail_len := 26        # pixels
@export var asteroid_trail_len := 14

var _visitor_timer := 0.0
var _next_visitor_time := 3.5

var visitors: Array = []

var pixels: Array = []

class PixelPuff:
	var pos: Vector2
	var vel: Vector2
	var life: float
	var max_life: float
	var size: int
	var col: Color

class Star:
	var x: float
	var y: float
	var z: float
	var prev_x: float
	var prev_y: float

class Visitor:
	var pos: Vector2
	var vel: Vector2
	var life: float
	var max_life: float
	var is_comet: bool
	var size: int
	var trail: PackedVector2Array

func _ready():
	set_process(true)
	z_index = -1

	_schedule_next_visitor()

	# Initialize stars
	for i in range(star_count):
		var star = Star.new()
		star.x = randf_range(-get_viewport_rect().size.x, get_viewport_rect().size.x)
		star.y = randf_range(-get_viewport_rect().size.y, get_viewport_rect().size.y)
		star.z = randf_range(1, max_depth)
		star.prev_x = 0
		star.prev_y = 0
		stars.append(star)

func _schedule_next_visitor() -> void:
	_next_visitor_time = randf_range(visitor_min_time, visitor_max_time)
	_visitor_timer = 0.0

func _spawn_visitor() -> void:
	var vp := get_viewport_rect().size
	var center := vp * 0.5

	var v := Visitor.new()
	v.is_comet = randf() < comet_chance

	# --- pick a random point INSIDE the circle (uniform area) ---
	var ang := randf_range(0.0, TAU)
	var rr = sqrt(randf()) * (mask_radius - 6.0) # sqrt for uniform distribution
	var start = center + Vector2(cos(ang), sin(ang)) * rr

	# --- pick a direction and speed ---
	var dir := Vector2.RIGHT.rotated(randf_range(0.0, TAU)).normalized()
	# optional: bias to "hurdling" across rather than drifting
	dir = dir.rotated(randf_range(-0.25, 0.25)).normalized()

	var spd := comet_speed if v.is_comet else asteroid_speed
	v.vel = dir * spd
	v.pos = start

	# Life = long enough to cross the circle
	var base_time = (mask_radius * 2.0) / spd
	v.max_life = base_time + randf_range(0.25, 0.55)
	v.life = v.max_life

	v.size = randi_range(2, 3) if v.is_comet else randi_range(3, 5)
	v.trail = PackedVector2Array([v.pos])

	visitors.append(v)

func _process(delta):
	# Move stars forward
	for star in stars:
		star.z -= speed * delta
		if star.z <= 0:
			star.x = randf_range(-get_viewport_rect().size.x, get_viewport_rect().size.x)
			star.y = randf_range(-get_viewport_rect().size.y, get_viewport_rect().size.y)
			star.z = max_depth

	# Visitor timer + spawn
	_visitor_timer += delta
	if _visitor_timer >= _next_visitor_time:
		_spawn_visitor()
		_schedule_next_visitor()

	# Update visitors
	for i in range(visitors.size() - 1, -1, -1):
		var v: Visitor = visitors[i]
		v.life -= delta
		v.pos += v.vel * delta
		_emit_pixel_puffs(v.pos, v.vel, v.is_comet)

		# Add to trail
		v.trail.append(v.pos)
		var max_points := 18 if v.is_comet else 12
		while v.trail.size() > max_points:
			v.trail.remove_at(0)

		# Kill when life ends (or far off)
		if v.life <= 0.0:
			visitors.remove_at(i)

	# Update pixel particles
	for i in range(pixels.size() - 1, -1, -1):
		var p: PixelPuff = pixels[i]
		p.life -= delta
		if p.life <= 0.0:
			pixels.remove_at(i)
			continue

		p.pos += p.vel * delta

		# simple drag so it feels like "spark dust"
		p.vel *= pow(0.08, delta)  # strong decay, still frame-rate independent

	queue_redraw()

func _draw():
	var vp := get_viewport_rect().size
	var center := vp * 0.5

	# --- stars (your original) ---
	for star in stars:
		var k = 128.0 / star.z
		var px = star.x * k + center.x
		var py = star.y * k + center.y

		var dist_from_center = Vector2(px, py).distance_to(center)
		if dist_from_center > mask_radius:
			continue

		var prev_z = star.z + speed * get_process_delta_time()
		if prev_z > 0:
			var prev_k = 128.0 / prev_z
			star.prev_x = star.x * prev_k + center.x
			star.prev_y = star.y * prev_k + center.y

		if px >= 0 and px < vp.x and py >= 0 and py < vp.y:
			var size = remap(star.z, 0, max_depth, 3, 1)
			size = floor(size)

			var brightness = remap(star.z, 0, max_depth, 1.0, 0.3)

			# NOTE: this randf() causes sparkle/flicker.
			# If you like it: keep it. If not: store a per-star seed.
			var color: Color
			var rand_color = randf()
			if rand_color < 0.6:
				color = Color(brightness, brightness, brightness)
			elif rand_color < 0.8:
				color = Color(brightness * 0.5, brightness * 0.7, brightness)
			else:
				color = Color(brightness * 0.3, brightness * 0.5, brightness * 0.8)

			# --- pixel particles ---
			for p in pixels:
				if p.pos.distance_to(center) > mask_radius:
					continue

				var t = clamp(p.life / p.max_life, 0.0, 1.0)
				var col = p.col * t  # fade brightness

				var s = p.size
				draw_rect(Rect2(floor(p.pos.x), floor(p.pos.y), s, s), col, true)

			if size >= 2:
				draw_rect(Rect2(floor(px), floor(py), size, size), color, true)
			else:
				draw_rect(Rect2(floor(px), floor(py), 1, 1), color, true)

	# --- visitors (comets/asteroids) ---
	for v in visitors:
		# Only draw inside mask
		if v.pos.distance_to(center) > mask_radius:
			continue

		if v.is_comet:
			_draw_comet(v, center)
		else:
			_draw_asteroid(v, center)

func _draw_comet(v: Visitor, _center: Vector2) -> void:
	var head := v.pos
	var t = clamp(v.life / v.max_life, 0.0, 1.0)
	var head_col = Color(1.0, 1.0, 1.0) * (0.8 + 0.2 * t)
	var s := v.size
	draw_rect(Rect2(floor(head.x), floor(head.y), s, s), head_col, true)


func _draw_asteroid(v: Visitor, _center: Vector2) -> void:
	var head := v.pos
	var t = clamp(v.life / v.max_life, 0.0, 1.0)
	var rock_col = Color(0.55, 0.55, 0.6) * (0.6 + 0.4 * t)

	var s := v.size
	draw_rect(Rect2(floor(head.x), floor(head.y), s, s), rock_col, true)
	draw_rect(Rect2(floor(head.x) + 1, floor(head.y) - 1, max(1, s - 2), 1), rock_col * 0.85, true)
	draw_rect(Rect2(floor(head.x) - 1, floor(head.y) + 1, 1, max(1, s - 2)), rock_col * 0.8, true)

func _emit_pixel_puffs(at: Vector2, base_dir: Vector2, is_comet: bool) -> void:
	# emit a few per frame
	var count := 3 if is_comet else 2

	for j in range(count):
		var p := PixelPuff.new()
		p.pos = at + Vector2(randi_range(-1, 1), randi_range(-1, 1))

		# Mostly backwards from motion + some jitter
		var back := (-base_dir).normalized()
		var jitter := Vector2.RIGHT.rotated(randf_range(0.0, TAU)) * randf_range(8.0, 22.0)
		p.vel = back * randf_range(35.0, 90.0) + jitter

		p.max_life = randf_range(0.18, 0.38) if is_comet else randf_range(0.25, 0.55)
		p.life = p.max_life

		p.size = 1 if is_comet else randi_range(1, 2)

		# Color (comet = brighter)
		if is_comet:
			p.col = Color(0.7, 0.9, 1.0)
		else:
			p.col = Color(0.45, 0.45, 0.5)

		pixels.append(p)
