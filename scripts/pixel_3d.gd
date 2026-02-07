extends Node2D

# Starfield settings
var star_count = 300
var stars = []
var speed = 50.0
var max_depth = 500.0

# Mask settings
@export var mask_radius = 150.0  # Adjust this in the inspector or via code

class Star:
	var x: float
	var y: float
	var z: float
	var prev_x: float
	var prev_y: float

func _ready():
	set_process(true)
	z_index = -1
	
	# Initialize stars
	for i in range(star_count):
		var star = Star.new()
		star.x = randf_range(-get_viewport_rect().size.x, get_viewport_rect().size.x)
		star.y = randf_range(-get_viewport_rect().size.y, get_viewport_rect().size.y)
		star.z = randf_range(1, max_depth)
		star.prev_x = 0
		star.prev_y = 0
		stars.append(star)

func _process(delta):
	# Move stars forward
	for star in stars:
		star.z -= speed * delta
		
		# Reset star if it goes past camera
		if star.z <= 0:
			star.x = randf_range(-get_viewport_rect().size.x, get_viewport_rect().size.x)
			star.y = randf_range(-get_viewport_rect().size.y, get_viewport_rect().size.y)
			star.z = max_depth
	
	queue_redraw()

func _draw():
	var center = get_viewport_rect().size / 2
	
	for star in stars:
		# Project star position
		var k = 128.0 / star.z
		var px = star.x * k + center.x
		var py = star.y * k + center.y
		
		# Check if star is OUTSIDE the mask circle (skip if it is)
		var dist_from_center = Vector2(px, py).distance_to(center)
		if dist_from_center > mask_radius:
			continue  # Skip this star, it's OUTSIDE the masked area
		
		# Calculate previous position for trail effect
		var prev_z = star.z + speed * get_process_delta_time()
		if prev_z > 0:
			var prev_k = 128.0 / prev_z
			star.prev_x = star.x * prev_k + center.x
			star.prev_y = star.y * prev_k + center.y
		
		# Only draw if on screen
		if px >= 0 and px < get_viewport_rect().size.x and py >= 0 and py < get_viewport_rect().size.y:
			# Size based on depth (closer = bigger)
			var size = remap(star.z, 0, max_depth, 3, 1)
			size = floor(size)  # Pixelated sizing
			
			# Brightness based on depth
			var brightness = remap(star.z, 0, max_depth, 1.0, 0.3)
			
			# Retro color palette - blues and whites
			var color: Color
			var rand_color = randf()
			if rand_color < 0.6:
				color = Color(brightness, brightness, brightness)  # White
			elif rand_color < 0.8:
				color = Color(brightness * 0.5, brightness * 0.7, brightness)  # Light blue
			else:
				color = Color(brightness * 0.3, brightness * 0.5, brightness * 0.8)  # Blue
			
			# Draw star trail (motion blur effect)
			if star.prev_x != 0:
				draw_line(Vector2(star.prev_x, star.prev_y), Vector2(px, py), color * 0.5, 1.0)
			
			# Draw the star pixel(s)
			if size >= 2:
				# Draw as a small pixelated square
				draw_rect(Rect2(floor(px), floor(py), size, size), color, true)
			else:
				# Single pixel
				draw_rect(Rect2(floor(px), floor(py), 1, 1), color, true)
	
	# Optional: Draw the mask circle outline for debugging
	# draw_arc(center, mask_radius, 0, TAU, 32, Color.RED, 1.0)
