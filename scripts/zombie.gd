extends Unit
class_name Zombie

func _ready() -> void:
	footprint_size = Vector2i(1, 1)
	move_range = 3
	attack_range = 1
	attack_repeats = 2
	hp = 1
