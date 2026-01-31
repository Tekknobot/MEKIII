extends Control

@export var game_scene: PackedScene = preload("res://scenes/squad_deploy_screen.tscn")
@export var continue_scene: PackedScene
@export var fade_time := 0.25

@onready var fade: ColorRect = $Fade
@onready var start_button: Button = $Center/PanelContainer/MarginContainer/VBoxContainer/Buttons/StartButton
@onready var quit_button: Button = $Center/PanelContainer/MarginContainer/VBoxContainer/Buttons/QuitButton
@onready var restart_button: Button = $Center/PanelContainer/MarginContainer/VBoxContainer/Buttons/RestartButton
@onready var title: TextureRect = $Center/PanelContainer/MarginContainer/VBoxContainer/Title


# --- Story (typewriter) ---
@onready var story_clip: Control = $StoryClip
@onready var story: RichTextLabel = $StoryClip/PanelContainer/MarginContainer/Story

@export var type_chars_per_sec := 45.0
@export var type_start_delay := 0.35
@export var newline_speed_boost := 0.4 # adds “extra chars” after \n so blank lines finish faster

var _story_full := ""
var _type_index := 0
var _type_accum := 0.0
var _type_running := false
var _type_timer: SceneTreeTimer = null

@export var sick_color_a := Color("1a1a1aff") # neon green
@export var sick_color_b := Color("4b4b4bff") # lighter green
@export var sick_pulse_time := 0.55

var _busy := false
var _tw: Tween = null
var _title_tw: Tween = null
var _sick_tw: Tween = null

# --- Fonts (pick in Inspector) ---
@export var title_font: Font
@export var title_font_size := 64

@export var body_font: Font
@export var body_font_size := 18

@export var button_font: Font
@export var button_font_size := 20

# Optional: story text color (default pure white)
@export var story_color := Color(1, 1, 1, 1)

# --- Background slideshow ---
@export var bg_texture_rect_path: NodePath
@onready var bg: TextureRect = get_node_or_null(bg_texture_rect_path)

@export var bg_textures: Array[Texture2D] = []   # drag your PNGs in Inspector
@export var bg_change_every := 2.0               # seconds between swaps
@export var bg_fade_time := 0.6                  # fade duration

var _bg_timer: SceneTreeTimer = null
var _bg_tw: Tween = null
var _bg_last_index := -1

# --- Clouds (2-layer crossfade + drift) ---
@export var clouds_a_path: NodePath
@export var clouds_b_path: NodePath
@onready var clouds_a: TextureRect = get_node_or_null(clouds_a_path)
@onready var clouds_b: TextureRect = get_node_or_null(clouds_b_path)

@export var cloud_textures: Array[Texture2D] = []  # drag cloud PNGs here
@export var cloud_swap_every := 4.0               # seconds between cloud changes
@export var cloud_crossfade_time := 1.0

@export var cloud_drift_px := Vector2(40, 0)      # how far it drifts before looping back
@export var cloud_drift_time := 12.0              # seconds to drift that far

var _cloud_timer: SceneTreeTimer = null
var _cloud_tw: Tween = null
var _cloud_drift_tw: Tween = null
var _cloud_last_index := -1
var _cloud_showing_a := true
var _cloud_base_pos_a := Vector2.ZERO
var _cloud_base_pos_b := Vector2.ZERO

var _desat_tw: Tween = null
@export var desat_time := 0.12
@export var resat_time := 0.20
@export var desat_hold := 0.06

func _ready() -> void:
	#MusicManagerNode.play_stream(preload("res://audio/Music/Track 1.wav"))	
	
	# Fade in from black
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.modulate.a = 1.0
	_kill_tw()
	_tw = create_tween()
	_tw.tween_property(fade, "modulate:a", 0.0, fade_time)

	# Hook buttons
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	start_button.grab_focus()

	# Story setup (NO SCROLLING)
	story.bbcode_enabled = true
	story.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_story_full = _default_story_bbcode()
	story.text = "" # start empty

	_apply_fonts()

	# Start typewriter
	_start_typewriter()

	_start_bg_cycle()
	_start_clouds()

	var rs := get_tree().root.get_node_or_null("RunState")
	if rs == null:
		rs = get_tree().root.get_node_or_null("RunStateNode")

	var can_continue := _has_save(rs) and _has_selected_squad(rs)

	start_button.text = ("CONTINUE" if can_continue else "START")


func _process(delta: float) -> void:
	if _busy:
		return
	_update_typewriter(delta)

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("ui_accept"):
			_on_start_pressed()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("ui_cancel"):
			_on_quit_pressed()
			get_viewport().set_input_as_handled()
			return
		else:
			# Any other key: finish typing if mid-type, otherwise restart
			if _type_running:
				_finish_typewriter()
			else:
				_start_typewriter()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.pressed:
		# Click: finish typing if mid-type, otherwise restart
		if _type_running:
			_finish_typewriter()
		else:
			_start_typewriter()
		get_viewport().set_input_as_handled()
		return

func _on_start_pressed() -> void:
	if _busy:
		return
	_busy = true
	_type_running = false
	await _fade_out()

	var rs := get_tree().root.get_node_or_null("RunState")
	if rs == null:
		rs = get_tree().root.get_node_or_null("RunStateNode")

	var can_continue := _has_save(rs) and _has_selected_squad(rs)

	if can_continue and continue_scene != null:
		get_tree().change_scene_to_packed(continue_scene)
	else:
		# no save OR no squad selected -> go pick squad
		get_tree().change_scene_to_packed(game_scene)

func _on_quit_pressed() -> void:
	if _busy:
		return
	_busy = true
	_type_running = false
	await _fade_out()
	get_tree().quit()

func _fade_out() -> void:
	_kill_tw()
	fade.modulate.a = 0.0
	_tw = create_tween()
	_tw.tween_property(fade, "modulate:a", 1.0, fade_time)
	await _tw.finished

func _kill_tw() -> void:
	if _tw != null and is_instance_valid(_tw):
		_tw.kill()
	_tw = null

# -------------------------
# Typewriter (NO SCROLLING)
# -------------------------
func _start_typewriter() -> void:
	_type_running = false
	_type_index = 0
	_type_accum = 0.0
	story.text = ""

	# refresh full text in case you edit it live
	_story_full = _default_story_bbcode()

	_type_running = true

	if _type_timer != null:
		_type_timer = null
	_type_timer = get_tree().create_timer(type_start_delay)

func _finish_typewriter() -> void:
	_type_running = false
	_type_index = _story_full.length()
	story.text = _story_full

func _update_typewriter(delta: float) -> void:
	if not _type_running:
		return
	if story == null:
		return

	# Wait out the start delay timer (non-blocking)
	if _type_timer != null:
		if _type_timer.time_left > 0.0:
			return
		_type_timer = null

	_type_accum += delta * type_chars_per_sec
	var n := int(_type_accum)
	if n <= 0:
		return
	_type_accum -= n

	for i in range(n):
		if _type_index >= _story_full.length():
			_type_running = false
			return

		var ch := _story_full.substr(_type_index, 1)
		_type_index += 1
		story.text += ch

		# Make blank lines / breaks feel snappier
		if ch == "\n":
			_type_accum += newline_speed_boost

func _apply_fonts() -> void:
	# Story (RichTextLabel)
	if story != null:
		if body_font != null:
			story.add_theme_font_override("normal_font", body_font)
			story.add_theme_font_override("bold_font", body_font)
			story.add_theme_font_override("italics_font", body_font)
			story.add_theme_font_override("bold_italics_font", body_font)
			story.add_theme_font_override("mono_font", body_font)
		if body_font_size > 0:
			story.add_theme_font_size_override("normal_font_size", body_font_size)

		# keep story white
		story.modulate = story_color

	# Buttons
	_apply_button_font(start_button)
	_apply_button_font(quit_button)

func _apply_button_font(b: Button) -> void:
	if b == null:
		return
	if button_font != null:
		b.add_theme_font_override("font", button_font)
	if button_font_size > 0:
		b.add_theme_font_size_override("font_size", button_font_size)

# -------------------------
# Story text
# -------------------------
func _default_story_bbcode() -> String:
	var s := ""
	s += "[b]MISSION: SIGNAL 7 // BEACON FALL[/b]\n\n"

	s += "The uplink cities are silent.\n"
	s += "Only road relays still broadcast.\n"
	s += "The infection owns everything else.\n\n"

	s += "You command the last salvage squad.\n"
	s += "Your job: rebuild the beacon.\n\n"

	s += "How to win:\n"
	s += "1. Destroy infected to recover disk fragments.\n"
	s += "2. Collect enough fragments to assemble the beacon.\n"
	s += "3. Move a squad member onto the beacon to begin upload.\n"
	s += "4. Hold position until the satellite sweep completes.\n\n"

	s += "[i]When the sweep fires, every infected signal is erased.[/i]\n\n"

	s += "How to lose:\n"
	s += "1. All squad members are killed.\n"
	s += "2. The swarm overruns the zone.\n\n"

	s += "[i]Drop window open. Good luck, salvage crew.[/i]\n"
	return s

func _start_bg_cycle() -> void:
	if bg == null:
		return
	if bg_textures.is_empty():
		return

	# Ensure we can fade it
	bg.modulate.a = 1.0

	# Pick an initial texture instantly
	_bg_last_index = _pick_bg_index()
	bg.texture = bg_textures[_bg_last_index]

	# Kick the loop
	_schedule_next_bg_swap()


func _schedule_next_bg_swap() -> void:
	if not is_inside_tree():
		return
	_bg_timer = get_tree().create_timer(bg_change_every)
	_bg_timer.timeout.connect(_on_bg_timer_timeout)


func _on_bg_timer_timeout() -> void:
	# If scene is leaving / busy, stop cycling
	if _busy:
		return
	_bg_swap_random_fade()
	_schedule_next_bg_swap()


func _bg_swap_random_fade() -> void:
	if bg == null or bg_textures.is_empty():
		return

	var idx := _pick_bg_index()
	if idx == _bg_last_index and bg_textures.size() > 1:
		# try once more to avoid repeats
		idx = _pick_bg_index()

	_bg_last_index = idx
	var next_tex := bg_textures[idx]

	# Kill previous tween cleanly
	if _bg_tw != null and is_instance_valid(_bg_tw):
		_bg_tw.kill()
	_bg_tw = null

	_bg_tw = create_tween()
	_bg_tw.set_trans(Tween.TRANS_SINE)
	_bg_tw.set_ease(Tween.EASE_IN_OUT)

	# Fade out -> swap -> fade in
	_bg_tw.tween_property(bg, "modulate:a", 0.0, bg_fade_time)
	_bg_tw.tween_callback(func():
		if bg != null and is_instance_valid(bg):
			bg.texture = next_tex
	)
	_bg_tw.tween_property(bg, "modulate:a", 1.0, bg_fade_time)


func _pick_bg_index() -> int:
	if bg_textures.size() == 1:
		return 0
	# try a couple times to avoid immediate repeats
	for attempt in range(4):
		var idx := randi() % bg_textures.size()
		if idx != _bg_last_index:
			return idx
	return int(max(0, _bg_last_index)) # fallback

func _start_clouds() -> void:
	if clouds_a == null or clouds_b == null:
		return

	_cloud_base_pos_a = clouds_a.position
	_cloud_base_pos_b = clouds_b.position

	# Always visible
	clouds_a.modulate.a = 1.0
	clouds_b.modulate.a = 1.0

	# DO NOT set textures here. Set them in the editor on CloudsA/CloudsB.
	_start_cloud_drift()

func _start_cloud_drift() -> void:
	if clouds_a == null or clouds_b == null:
		return

	# Start from base
	clouds_a.position = _cloud_base_pos_a
	clouds_b.position = _cloud_base_pos_b

	if _cloud_drift_tw != null and is_instance_valid(_cloud_drift_tw):
		_cloud_drift_tw.kill()

	_cloud_drift_tw = create_tween()
	_cloud_drift_tw.set_loops()
	_cloud_drift_tw.set_trans(Tween.TRANS_SINE)
	_cloud_drift_tw.set_ease(Tween.EASE_IN_OUT)

	# A: go out and back, forever
	_cloud_drift_tw.tween_property(clouds_a, "position", _cloud_base_pos_a + cloud_drift_px, cloud_drift_time)
	_cloud_drift_tw.tween_property(clouds_a, "position", _cloud_base_pos_a, cloud_drift_time)

	# B: go out and back, forever
	_cloud_drift_tw.tween_property(clouds_b, "position", _cloud_base_pos_b + cloud_drift_px, cloud_drift_time)
	_cloud_drift_tw.tween_property(clouds_b, "position", _cloud_base_pos_b, cloud_drift_time)

func _pick_cloud_index() -> int:
	if cloud_textures.size() == 1:
		return 0
	for attempt in range(6):
		var idx := randi() % cloud_textures.size()
		if idx != _cloud_last_index:
			return idx
	return int(max(0, _cloud_last_index))

func _desaturate_bg_pulse() -> void:
	if bg == null:
		return

	var mat := bg.material as ShaderMaterial
	if mat == null:
		return
	if not mat.shader:
		return

	# kill previous desat tween
	if _desat_tw != null and is_instance_valid(_desat_tw):
		_desat_tw.kill()
	_desat_tw = null

	# start from "normal" every time
	mat.set_shader_parameter("saturation", 1.0)

	_desat_tw = create_tween()
	_desat_tw.set_trans(Tween.TRANS_SINE)
	_desat_tw.set_ease(Tween.EASE_OUT)

	# down to grayscale
	_desat_tw.tween_method(func(v: float) -> void:
		if bg != null and is_instance_valid(bg):
			var m := bg.material as ShaderMaterial
			if m != null:
				m.set_shader_parameter("saturation", v)
	, 1.0, 0.0, desat_time)

	# tiny hold (so it actually reads)
	_desat_tw.tween_interval(desat_hold)

	# back to normal
	_desat_tw.set_ease(Tween.EASE_IN_OUT)
	_desat_tw.tween_method(func(v: float) -> void:
		if bg != null and is_instance_valid(bg):
			var m := bg.material as ShaderMaterial
			if m != null:
				m.set_shader_parameter("saturation", v)
	, 0.0, 1.0, resat_time)

func _on_restart_pressed() -> void:
	if _busy:
		return
	_busy = true
	_type_running = false
	await _fade_out()

	var rs := get_tree().root.get_node_or_null("RunState")
	if rs == null:
		rs = get_tree().root.get_node_or_null("RunStateNode")

	# ✅ clear disk save + reset in-memory state if you have it
	if rs != null:
		if rs.has_method("wipe_save"):
			rs.call("wipe_save")
		# optional but recommended: reset the runtime values too
		if rs.has_method("reset_run"):
			rs.call("reset_run")

	# go to squad select
	get_tree().change_scene_to_packed(game_scene)

func _get_rs() -> Node:
	var rs := get_tree().root.get_node_or_null("RunState")
	if rs == null:
		rs = get_tree().root.get_node_or_null("RunStateNode")
	return rs

func _has_save(rs: Node) -> bool:
	return rs != null and rs.has_method("has_save") and bool(rs.call("has_save"))

func _has_selected_squad(rs: Node) -> bool:
	if rs == null:
		return false
	# most common: Array of scene paths
	if "squad_scene_paths" in rs:
		var a: Array = rs.squad_scene_paths
		return a != null and a.size() > 0
	# fallback: starting squad paths
	if "starting_squad_paths" in rs:
		var b: Array = rs.starting_squad_paths
		return b != null and b.size() > 0
	return false
