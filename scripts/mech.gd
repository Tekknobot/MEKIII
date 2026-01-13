extends Unit
class_name Mech

func _ready() -> void:
	footprint_size = Vector2i(1, 1)
	move_range = 8
	attack_range = 1
	attack_repeats = 1
	hp = 8
	max_hp = 8
