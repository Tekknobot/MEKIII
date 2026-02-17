# res://scripts/fail_surge_controller.gd
extends Node
class_name FailSurgeController

signal finished

@export var surge_distance_px: float = 16.0
@export var surge_duration: float = 5.0
@export var settle_duration: float = 0.25

@export var pulse_enemies: bool = true
@export var enemy_pulse_time: float = 0.22

@export var camera_shake: bool = true
@export var camera_shake_strength: float = 2.5
@export var camera_shake_duration: float = 5.0

@export var play_enemy_move_anim: bool = true
@export var enemy_move_anim: StringName = &"move" # change to &"walk" or &"run" if your units use that

@export var play_growl_sfx: bool = true
@export var growl_sfx_id: StringName = &"zombie_growl"

# Optional: if you want a dedicated audio player path (fallback)
@export var growl_audio_path: NodePath

@export var flip_to_direction: bool = true
@export var sprite_faces_left_by_default: bool = true

var M: Node = null
var cam: Camera2D = null

var _running := false
var _rng := RandomNumberGenerator.new()
var _shake_time_left := 0.0
var _cam_base_offset := Vector2.ZERO

func setup(map_controller: Node, camera: Camera2D) -> void:
	M = map_controller
	cam = camera

func play() -> void:
	if _running:
		return
	_running = true

	_rng.randomize()

	# --- collect units ---
	var enemies: Array = []
	var allies: Array = []

	if M != null and is_instance_valid(M) and M.has_method("get_all_units"):
		for u in M.call("get_all_units"):
			if u == null or not is_instance_valid(u):
				continue
			if ("hp" in u) and int(u.hp) <= 0:
				continue
			if ("team" in u) and int(u.team) == int(Unit.Team.ENEMY):
				enemies.append(u)
			elif ("team" in u) and int(u.team) == int(Unit.Team.ALLY):
				allies.append(u)

	# If nothing to animate, just finish immediately
	if enemies.is_empty():
		_finish()
		return

	# --- compute ally center for “surge toward the living” ---
	var ally_center := Vector2.ZERO
	if not allies.is_empty():
		for a in allies:
			ally_center += a.global_position
		ally_center /= float(allies.size())
	else:
		# fallback: surge toward camera / center-ish
		ally_center = (cam.global_position if cam != null else enemies[0].global_position)

	# --- surge audio (once) ---
	_try_play_growl()

	# --- optional enemy pulse (pure presentation) ---
	if pulse_enemies and M != null and is_instance_valid(M) and M.has_method("_start_enemy_red_pulse"):
		for z in enemies:
			if z == null or not is_instance_valid(z):
				continue
			M.call("_start_enemy_red_pulse", z, enemy_pulse_time)

	# --- camera shake setup ---
	if camera_shake and cam != null and is_instance_valid(cam):
		_cam_base_offset = cam.offset
		_shake_time_left = camera_shake_duration
		set_process(true)

	# --- animate all enemies in parallel (one “wave lurch”) ---
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)

	for z in enemies:
		if z == null or not is_instance_valid(z):
			continue

		# play the move animation while we lurch (independent of pulse)
		_try_play_enemy_move_anim(z)

		var from = z.global_position
		var dir = (ally_center - from)
				
		if dir.length() < 0.001:
			dir = Vector2(1, 0)
		dir = dir.normalized()

		_try_face_dir(z, dir)

		# Small lurch toward allies
		var to = from + dir * surge_distance_px
		tw.tween_property(z, "global_position", to, surge_duration)

		# Snap back/settle so it feels like a “surge bump”
		tw.tween_property(z, "global_position", from, settle_duration).set_delay(surge_duration)

	tw.finished.connect(_finish)

func _process(delta: float) -> void:
	if not _running:
		set_process(false)
		return

	if cam == null or not is_instance_valid(cam):
		set_process(false)
		return

	if _shake_time_left > 0.0:
		_shake_time_left -= delta
		var s := camera_shake_strength
		cam.offset = _cam_base_offset + Vector2(
			_rng.randf_range(-s, s),
			_rng.randf_range(-s, s)
		)
	else:
		# restore
		cam.offset = _cam_base_offset
		set_process(false)

func _finish() -> void:
	if cam != null and is_instance_valid(cam):
		cam.offset = _cam_base_offset

	_running = false
	emit_signal("finished")

func _try_play_growl() -> void:
	if not play_growl_sfx:
		return

	# Preferred: use your existing sfx helper if MapController exposes one
	if M != null and is_instance_valid(M) and M.has_method("_sfx"):
		# Common signature in your project: _sfx(name, volume, pitch) OR _sfx(name)
		# We'll try the simple version first.
		var ok := false
		# Godot doesn't have try/catch; so we "probe" by checking arg count isn't possible.
		# We'll just call the simplest and if your _sfx requires args, use the fallback below.
		M.call("_sfx", growl_sfx_id)
		return

	# Fallback: play via a dedicated AudioStreamPlayer you point at in the inspector
	if growl_audio_path != NodePath():
		var p := get_node_or_null(growl_audio_path)
		if p != null and is_instance_valid(p) and p is AudioStreamPlayer:
			(p as AudioStreamPlayer).play()

func _try_play_enemy_move_anim(z: Node) -> void:
	if not play_enemy_move_anim:
		return
	if z == null or not is_instance_valid(z):
		return

	# 1) If your Unit exposes a method
	if z.has_method("play_anim"):
		z.call("play_anim", enemy_move_anim)
		return
	if z.has_method("play_move_anim"):
		z.call("play_move_anim")
		return

	# 2) AnimationPlayer child
	var ap := z.get_node_or_null("AnimationPlayer")
	if ap != null and ap is AnimationPlayer:
		var A := ap as AnimationPlayer
		if A.has_animation(enemy_move_anim):
			A.play(enemy_move_anim)
			return
		# small fallback names
		if A.has_animation("walk"):
			A.play("walk")
			return
		if A.has_animation("move"):
			A.play("move")
			return

	# 3) AnimatedSprite2D child
	var spr := z.get_node_or_null("AnimatedSprite2D")
	if spr != null and spr is AnimatedSprite2D:
		var S := spr as AnimatedSprite2D
		# If you have an animation named "move"/"walk"
		S.play(String(enemy_move_anim))
		return

func _try_face_dir(z: Node, dir: Vector2) -> void:
	if not flip_to_direction:
		return
	if z == null or not is_instance_valid(z):
		return

	# We only care about left/right
	if absf(dir.x) < 0.001:
		return

	# Want to face left when moving left (dir.x < 0), right when moving right (dir.x > 0)
	var want_face_left := dir.x < 0.0

	# If the art faces LEFT by default, then:
	# - want_face_left => flip_h false
	# - want_face_right => flip_h true
	# If the art faces RIGHT by default, invert the logic.
	var flip_h := false
	if sprite_faces_left_by_default:
		flip_h = not want_face_left
	else:
		flip_h = want_face_left

	# 1) If Unit has a facing method, prefer that
	if z.has_method("set_facing_left"):
		z.call("set_facing_left", want_face_left)
		return
	if z.has_method("set_facing_dir"):
		z.call("set_facing_dir", dir)
		return
	if z.has_method("face_dir"):
		z.call("face_dir", dir)
		return

	# 2) Try common child nodes
	var spr2 := z.get_node_or_null("Sprite2D")
	if spr2 != null and spr2 is Sprite2D:
		(spr2 as Sprite2D).flip_h = flip_h
		return

	var as2 := z.get_node_or_null("AnimatedSprite2D")
	if as2 != null and as2 is AnimatedSprite2D:
		(as2 as AnimatedSprite2D).flip_h = flip_h
		return

	# 3) Fallback: flip the whole node (only if you haven't already got scale-based facing)
	if z is Node2D:
		var n := z as Node2D
		var s := n.scale
		s.x = absf(s.x)
		if flip_h:
			s.x = -s.x
		n.scale = s
