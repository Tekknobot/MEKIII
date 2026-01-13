extends Unit
class_name HumanTwo

func _ready() -> void:
	footprint_size = Vector2i(1, 1)
	move_range = 4
	attack_range = 1
	attack_repeats = 1

	tnt_throw_range = 4
	
	# ✅ Do NOT hard reset hp/max_hp here.
	# If you want a baseline, clamp UP not down:
	max_hp = max(max_hp, 4)
	hp = clamp(hp, 0, max_hp)

	# ✅ Run Unit setup (hp=max_hp + sprite base pos)
	super._ready()	
