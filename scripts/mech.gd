extends Unit
class_name Mech

func _ready() -> void:
	footprint_size = Vector2i(1, 1)
	move_range = 5
	attack_range = 1
	attack_repeats = 1
	
	# ✅ Do NOT hard reset hp/max_hp here.
	# If you want a baseline, clamp UP not down:
	max_hp = max(max_hp, 5)
	hp = clamp(hp, 0, max_hp)

	# ✅ Run Unit setup (hp=max_hp + sprite base pos)
	super._ready()	
