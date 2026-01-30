extends Unit
class_name Weakpoint

@export var hurt_flash_time := 0.10
@export var hurt_flash_color := Color(1, 0.25, 0.25, 1)

var _hurt_tw: Tween = null
var _base_modulate: Color = Color(1,1,1,1)

func _ready() -> void:
	# Identity (metas used by your UI)
	if not has_meta("display_name"):
		set_meta("display_name", "Boss Zombie")
	if not has_meta("portrait_tex"):
		set_meta("portrait_tex", preload("res://sprites/Portraits/zombie_port.png"))

	# ✅ Make it behave like a zombie/enemy in AI systems
	team = Unit.Team.ENEMY

	# ✅ Vision range used by TurnManager (see patch below)
	# If you want it to match regular zombies, set this to whatever you consider “zombie vision”.
	if not has_meta("vision"):
		set_meta("vision", 8) # tweak (6–10 feels good)

	footprint_size = Vector2i(1, 1)
	move_range = 4
	attack_range = 1
	attack_damage = 1

	# BossController sets max_hp/hp before or after _ready depending on how you spawn.
	max_hp = max(1, max_hp)
	hp = clamp(hp, 0, max_hp)

	super._ready()

	var ci := _get_render_item()
	if ci != null:
		_base_modulate = ci.modulate


func take_damage(amount: int) -> void:
	# Let Unit do its normal logic first (hp reduction, death, etc.)
	super.take_damage(amount)

	# Hurt flash when still alive
	if hp > 0:
		_flash_hurt()

	# If we died, notify boss (ONCE)
	if hp <= 0:
		_notify_boss_once()

func _notify_boss_once() -> void:
	if has_meta("boss_notified_dead") and bool(get_meta("boss_notified_dead")):
		return
	set_meta("boss_notified_dead", true)

	# Only notify if this is actually marked as boss part
	if not (has_meta("is_boss_part") and bool(get_meta("is_boss_part"))):
		return

	var part_id: StringName = get_meta("boss_part_id", &"") as StringName
	var boss_dmg: int = int(get_meta("boss_damage_on_destroy", 0))

	# Find BossController via group (simple + reliable)
	var boss := get_tree().get_first_node_in_group("BossController") as BossController
	if boss != null and is_instance_valid(boss):
		boss.on_weakpoint_destroyed(part_id, boss_dmg)

func _flash_hurt() -> void:
	var ci := _get_render_item()
	if ci == null:
		return

	if _hurt_tw != null and is_instance_valid(_hurt_tw):
		_hurt_tw.kill()

	_hurt_tw = create_tween()
	_hurt_tw.tween_property(ci, "modulate", hurt_flash_color, hurt_flash_time * 0.5)
	_hurt_tw.tween_property(ci, "modulate", _base_modulate, hurt_flash_time * 0.5)

func _get_render_item() -> CanvasItem:
	# Match your Zombie style: try common names first, then any CanvasItem child
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	if spr != null:
		return spr
	var anim := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim != null:
		return anim
	for ch in get_children():
		if ch is CanvasItem:
			return ch as CanvasItem
	return null
