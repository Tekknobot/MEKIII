extends Unit
class_name Zombie

func _ready() -> void:
	set_meta("portrait_tex", preload("res://sprites/Portraits/zombie_port.png"))
	set_meta("display_name", "Zombie")

	# --- Core stats ---
	footprint_size = Vector2i(1, 1)

	move_range = 3          # not used yet, but future-proof
	attack_range = 1
	attack_damage = 1

	# --- Health baseline ---
	max_hp = max(max_hp, 6)
	hp = clamp(hp, 0, max_hp)

	# --- Call base Unit init (sets depth + clamps hp again safely) ---
	super._ready()
