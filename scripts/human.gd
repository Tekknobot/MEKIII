extends Unit
class_name Human

func _ready() -> void:
	set_meta("portrait_tex", preload("res://sprites/Portraits/soldier_port.png"))
	set_meta("display_name", "Soldier")

	footprint_size = Vector2i(1, 1)
	move_range = 3
	attack_range = 4
	attack_damage = 1
	tnt_throw_range = 4

	# Do NOT hard reset; clamp up
	max_hp = max(max_hp, 3)
	hp = clamp(hp, 0, max_hp)

	super._ready()
