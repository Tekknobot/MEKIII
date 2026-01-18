extends Unit
class_name Human

func _ready() -> void:
	set_meta("portrait_tex", preload("res://sprites/Portraits/soldier_port.png"))
	set_meta("display_name", "Soldier")
	
	footprint_size = Vector2i(1, 1)
	move_range = 3
	attack_range = 4
	attack_repeats = 1
	
	tnt_throw_range = 3

	# ✅ Do NOT hard reset hp/max_hp here.
	# If you want a baseline, clamp UP not down:
	max_hp = max(max_hp, 3)
	hp = clamp(hp, 0, max_hp)

	# ✅ Run Unit setup (hp=max_hp + sprite base pos)
	super._ready()
