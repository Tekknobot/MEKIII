extends Unit
class_name Human

func _ready() -> void:
	footprint_size = Vector2i(1, 1)
	move_range = 3
	attack_range = 4
	attack_repeats = 3
