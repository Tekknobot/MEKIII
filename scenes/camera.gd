extends Camera2D

@export var map_width := 16
@export var map_height := 16

@onready var terrain := $"../Terrain"

func _ready():
	await get_tree().process_frame
	center_on_map()

func center_on_map():
	# Get the world position of top-left and bottom-right tiles
	var top_left = terrain.map_to_local(Vector2i(0, 0))
	var bottom_right = terrain.map_to_local(Vector2i(map_width, map_height))

	# Convert to global
	top_left = terrain.to_global(top_left)
	bottom_right = terrain.to_global(bottom_right)

	# Center point
	var center = (top_left + bottom_right) * 0.5

	global_position = center
