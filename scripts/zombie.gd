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

signal death_anim_finished

@onready var visual := $AnimatedSprite2D as AnimatedSprite2D
@onready var outline := $Outline as AnimatedSprite2D

@export var threat_outline_shader: Shader
@export var threat_outline_color: Color = Color(1.0, 0.2, 0.2, 1.0)
@export var threat_outline_width: float = 1.0

func _ready() -> void:
	set_meta("portrait_tex", preload("res://sprites/Portraits/zombie_port.png"))
	set_meta("display_name", "Zombie")

	if outline != null:
		outline.z_index = visual.z_index - 1
		_sync_outline_now()

	# keep synced as animation/frame changes
	if visual != null:
		visual.frame_changed.connect(_sync_outline_now)
		visual.animation_changed.connect(_sync_outline_now)

	footprint_size = Vector2i(1, 1)
	move_range = 3
	attack_range = 1
	attack_damage = 1

	# --- map-to-map scaling via RunState.mission_difficulty (0..1) ---
	var rs = get_node_or_null("/root/RunState") as RunState
	if rs == null:
		rs = get_node_or_null("/root/RunStateNode") as RunState  # fallback if your autoload is named this

	var base_hp := 12
	var bonus_hp := 0

	if rs != null:
		# +0..+4 hp depending on mission difficulty
		bonus_hp = int(round(rs.mission_difficulty * 6.0))

	max_hp = max(max_hp, base_hp + bonus_hp)
	hp = clamp(hp, 0, max_hp)

	super._ready()

	_suppress_base_pos = global_position
	var ci := _get_render_item()
	if ci != null:
		_suppress_base_modulate = ci.modulate
	else:
		_suppress_base_modulate = Color(1,1,1,1)

	if outline != null and visual != null:
		outline.z_index = visual.z_index - 1
		outline.visible = true
		outline.modulate = Color(1,1,1,1)

		# ✅ Ensure Outline has the shader material
		if threat_outline_shader != null:
			var sm := ShaderMaterial.new()
			sm.shader = threat_outline_shader
			sm.set_shader_parameter("outline_color", threat_outline_color)
			sm.set_shader_parameter("thickness_px", threat_outline_width)
			outline.material = sm

		_sync_outline_now()

	if visual != null:
		visual.frame_changed.connect(_sync_outline_now)
		visual.animation_changed.connect(_sync_outline_now)


func _process(delta: float) -> void:
	# if you flip sprites or change scale/rotation dynamically
	_sync_outline_transform()
		
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

func _sync_outline_now() -> void:
	if visual == null or outline == null:
		return

	# keep frames + state in sync
	outline.sprite_frames = visual.sprite_frames
	outline.animation = visual.animation
	outline.frame = visual.frame
	outline.frame_progress = visual.frame_progress
	outline.flip_h = visual.flip_h
	outline.flip_v = visual.flip_v
	outline.speed_scale = visual.speed_scale

	# Godot 4: no 'playing' property
	if visual.is_playing():
		outline.play(visual.animation)
	else:
		outline.stop()

func _sync_outline_transform() -> void:
	if visual == null or outline == null:
		return
	outline.global_position = visual.global_position
	outline.global_rotation = visual.global_rotation
	outline.global_scale = visual.global_scale


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

func play_death_anim() -> void:
	# Unit._die() already set _dying = true before calling this,
	# so do NOT early-return on _dying.

	# hard-disable suppression + stop tween fighting the anim
	if has_meta("suppress_turns"):
		set_meta("suppress_turns", 0)
	_suppress_active = false
	_stop_suppress_twitch()

	# Find AnimatedSprite2D (Visual first)
	var anim := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim == null:
		anim = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D

	# Play death if present, otherwise just finish immediately
	if anim != null and anim.sprite_frames != null and anim.sprite_frames.has_animation("death"):
		anim.sprite_frames.set_animation_loop("death", false)
		anim.stop()
		anim.play("death")
		await anim.animation_finished

	emit_signal("death_anim_finished")
