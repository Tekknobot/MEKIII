extends Unit
class_name Zombie

@export var suppress_twitch_strength := 0.5
@export var suppress_twitch_interval := 0.012
@export var suppress_flash_strength := 0.8

var _suppress_tw: Tween = null
var _suppress_timer: float = 0.0
var _suppress_base_pos: Vector2
var _suppress_base_modulate: Color
var _suppress_active := false

func _ready() -> void:
	set_meta("portrait_tex", preload("res://sprites/Portraits/zombie_port.png"))
	set_meta("display_name", "Zombie")

	footprint_size = Vector2i(1, 1)
	move_range = 3
	attack_range = 1
	attack_damage = 1

	max_hp = max(max_hp, 10) # <----------------- ZOMBIE HP
	hp = clamp(hp, 0, max_hp)

	super._ready()

	_suppress_base_pos = global_position
	var ci := _get_render_item()
	if ci != null:
		_suppress_base_modulate = ci.modulate
	else:
		_suppress_base_modulate = Color(1,1,1,1)

func _process(delta: float) -> void:
	# Only twitch while suppressed
	var turns := 0
	if has_meta("suppress_turns"):
		turns = int(get_meta("suppress_turns"))

	var want := turns > 0

	if want and not _suppress_active:
		_suppress_active = true
		_start_suppress_twitch()
	elif (not want) and _suppress_active:
		_suppress_active = false
		_stop_suppress_twitch()

	# keep the “base” position updated when NOT suppressed (so movement doesn't fight the twitch)
	if not _suppress_active:
		_suppress_base_pos = global_position

func _start_suppress_twitch() -> void:
	_stop_suppress_twitch() # safety

	_suppress_timer = 0.0
	_suppress_base_pos = global_position

	var ci := _get_render_item()
	if ci != null:
		_suppress_base_modulate = ci.modulate

	# Looping twitch tween
	_suppress_tw = create_tween()
	_suppress_tw.set_loops() # infinite
	_suppress_tw.set_trans(Tween.TRANS_SINE)
	_suppress_tw.set_ease(Tween.EASE_IN_OUT)

	# small jitter offsets around the base
	var step = max(0.04, suppress_twitch_interval)

	_suppress_tw.tween_callback(func():
		if self == null or not is_instance_valid(self): return
		global_position = _suppress_base_pos + Vector2(
			randf_range(-suppress_twitch_strength, suppress_twitch_strength),
			randf_range(-suppress_twitch_strength, suppress_twitch_strength)
		)
		# quick flash brighten
		var cii := _get_render_item()
		if cii != null and is_instance_valid(cii):
			var base := _suppress_base_modulate
			cii.modulate = Color(
				min(base.r * suppress_flash_strength, 2.0),
				min(base.g * suppress_flash_strength, 2.0),
				min(base.b * suppress_flash_strength, 2.0),
				base.a
			)
	)

	_suppress_tw.tween_interval(step * 0.5)

	_suppress_tw.tween_callback(func():
		if self == null or not is_instance_valid(self): return
		global_position = _suppress_base_pos
		var cii := _get_render_item()
		if cii != null and is_instance_valid(cii):
			cii.modulate = _suppress_base_modulate
	)

	_suppress_tw.tween_interval(step * 0.5)

func _stop_suppress_twitch() -> void:
	if _suppress_tw != null and is_instance_valid(_suppress_tw):
		_suppress_tw.kill()
	_suppress_tw = null

	# restore
	global_position = _suppress_base_pos
	var ci := _get_render_item()
	if ci != null and is_instance_valid(ci):
		ci.modulate = _suppress_base_modulate

func _get_render_item() -> CanvasItem:
	# find a Sprite2D or AnimatedSprite2D (or any CanvasItem child)
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

func _on_cell_changed() -> void:
	# re-anchor twitch to current cell position
	_suppress_base_pos = global_position

	# if currently suppressed, restart tween so it jitters around the NEW cell
	if _suppress_active:
		_start_suppress_twitch()
