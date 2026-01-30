extends Unit
class_name BossWeakpoint

@export var part_id: StringName = &"CORE"
@export var boss_damage_on_destroy: int = 3

func _ready() -> void:
	footprint_size = Vector2i(1, 1)
	move_range = 0
	attack_range = 0
	team = Unit.Team.ENEMY

	# Make it feel “structural”
	max_hp = max(1, max_hp)
	hp = clamp(hp, 0, max_hp)

	set_meta("boss_part_id", part_id)
	set_meta("boss_damage_on_destroy", boss_damage_on_destroy)

	super._ready()
