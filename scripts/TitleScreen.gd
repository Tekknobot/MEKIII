extends Control

@export var game_scene: PackedScene = preload("res://scenes/Game.tscn")
@export var fade_time := 0.25

@onready var fade: ColorRect = $Fade
@onready var start_button: Button = $Center/Buttons/StartButton
@onready var quit_button: Button = $Center/Buttons/QuitButton

@onready var title: Label = $Center/Title

# --- Story (typewriter) ---
@onready var story_clip: Control = $StoryClip
@onready var story: RichTextLabel = $StoryClip/Story

@export var type_chars_per_sec := 45.0
@export var type_start_delay := 0.35
@export var newline_speed_boost := 0.4 # adds “extra chars” after \n so blank lines finish faster

var _story_full := ""
var _type_index := 0
var _type_accum := 0.0
var _type_running := false
var _type_timer: SceneTreeTimer = null

# --- Title vibe ---
@export var title_float_px := 6.0
@export var title_float_time := 1.4

@export var sick_color_a := Color("#7CFF63") # neon green
@export var sick_color_b := Color("#B6FF9A") # lighter green
@export var sick_pulse_time := 0.55

var _busy := false
var _tw: Tween = null
var _title_tw: Tween = null
var _sick_tw: Tween = null

func _ready() -> void:
	# Fade in from black
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.modulate.a = 1.0
	_kill_tw()
	_tw = create_tween()
	_tw.tween_property(fade, "modulate:a", 0.0, fade_time)

	# Hook buttons
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	start_button.grab_focus()

	# Story setup (NO SCROLLING)
	story.bbcode_enabled = true
	story.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_story_full = _default_story_bbcode()
	story.text = "" # start empty

	# Start animations
	_start_title_anim()
	_start_sick_color_anim()

	# Start typewriter
	_start_typewriter()

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
# Title animations
# -------------------------
func _start_title_anim() -> void:
	if title == null:
		return

	if _title_tw != null and is_instance_valid(_title_tw):
		_title_tw.kill()
	_title_tw = null

	var base_y := title.position.y

	_title_tw = create_tween()
	_title_tw.set_loops()
	_title_tw.set_trans(Tween.TRANS_SINE)
	_title_tw.set_ease(Tween.EASE_IN_OUT)

	_title_tw.tween_property(title, "position:y", base_y - title_float_px, title_float_time)
	_title_tw.tween_property(title, "position:y", base_y, title_float_time)

func _start_sick_color_anim() -> void:
	if _sick_tw != null and is_instance_valid(_sick_tw):
		_sick_tw.kill()
	_sick_tw = null

	_sick_tw = create_tween()
	_sick_tw.set_loops()
	_sick_tw.set_trans(Tween.TRANS_SINE)
	_sick_tw.set_ease(Tween.EASE_IN_OUT)

	if title != null:
		_sick_tw.tween_property(title, "modulate", sick_color_a, sick_pulse_time)
		_sick_tw.tween_property(title, "modulate", sick_color_b, sick_pulse_time)

	# Story tied to same vibe (slightly dimmer)
	var story_a := sick_color_a * Color(1, 1, 1, 0.90)
	var story_b := sick_color_b * Color(1, 1, 1, 0.90)

	if story != null:
		_sick_tw.tween_property(story, "modulate", story_a, sick_pulse_time)
		_sick_tw.tween_property(story, "modulate", story_b, sick_pulse_time)

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

# -------------------------
# Story text
# -------------------------
func _default_story_bbcode() -> String:
	var s := ""
	s += "[b]SIGNAL 7 // BEACON FALL[/b]\n\n"

	s += "Uplink cities went dark three days ago.\n"
	s += "Road relays still hum.\n"
	s += "Something moves in the static.\n\n"

	s += "You are a salvage crew.\n"
	s += "Last contract still standing.\n\n"

	s += "Drop in.\n"
	s += "Recover disk fragments from infected.\n"
	s += "Assemble the beacon.\n"
	s += "Hold position until satellite sweep.\n\n"

	s += "[i]If orbital lock succeeds — everything infected gets erased.[/i]\n\n"

	s += "Mission parameters:\n"
	s += "• Collect parts from fallen infected.\n"
	s += "• Upload at beacon site.\n"
	s += "• Survive until sweep completes.\n\n"

	s += "Failure condition:\n"
	s += "• Squad eliminated.\n\n"

	s += "[i]Static rises. Deployment window open.[/i]\n"
	return s
