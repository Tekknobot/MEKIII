extends RefCounted
class_name GridData

var w: int = 0
var h: int = 0
var terrain: Array = []  # terrain[x][y] -> tile id

func setup(width: int, height: int, fill_value: int = 0) -> void:
	w = width
	h = height
	terrain.resize(w)
	for x in range(w):
		terrain[x] = []
		terrain[x].resize(h)
		for y in range(h):
			terrain[x][y] = fill_value

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h
