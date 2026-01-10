extends Unit
class_name Mech

func _ready() -> void:
	footprint_size = Vector2i(2, 2)
	move_range = 1
	attack_range = 2
	attack_repeats = 1
	hp = 5
