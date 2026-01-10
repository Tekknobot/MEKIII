extends Resource
class_name GridData

var width: int
var height: int
var terrain := []        # 2D array of ints (terrain id)
var occupied := {}       # Dictionary: Vector2i -> unit_id or Node reference

func setup(w: int, h: int) -> void:
	width = w
	height = h
	terrain.resize(width)
	for x in range(width):
		terrain[x] = []
		terrain[x].resize(height)
		for y in range(height):
			terrain[x][y] = 0  # default terrain id

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height

func is_occupied(c: Vector2i) -> bool:
	return occupied.has(c)

func set_occupied(c: Vector2i, value) -> void:
	if value == null:
		occupied.erase(c)
	else:
		occupied[c] = value
