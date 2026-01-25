extends Control

@export var game_scene: PackedScene
@export var title_scene_path := "res://scenes/title_screen.tscn"

@export var fade_time := 0.25
@export var fade_color := Color(0, 0, 0, 1)

var _busy := false

@onready var unit_cards := [
	$SquadPanel/VBoxContainer/UnitCard_Soldier,
	$SquadPanel/VBoxContainer/UnitCard_Mercenary,
	$SquadPanel/VBoxContainer/UnitCard_Robodog
]

@onready var start_button: Button = $SquadPanel/VBoxContainer/Buttons/StartButton
@onready var back_button: Button = $SquadPanel/VBoxContainer/Buttons/BackButton
@onready var fade: ColorRect = $Fade

const SQUAD_DATA := [
	{
		"name": "Soldier",
		"hp": 5,
		"ability": "HELLFIRE BARRAGE",
		"portrait": preload("res://sprites/Portraits/soldier_port.png")
	},
	{
		"name": "Mercenary",
		"hp": 4,
		"ability": "BLADE DASH",
		"portrait": preload("res://sprites/Portraits/rambo_port.png")
	},
	{
		"name": "Robodog",
		"hp": 3,
		"ability": "MINE DEPLOY",
		"portrait": preload("res://sprites/Portraits/dog_port.png")
	}
]

func _ready() -> void:
	_setup_fade()
	_populate_cards()

	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)

	# Focus Start by default (optional but feels good)
	if is_instance_valid(start_button):
		start_button.grab_focus()

	# Fade IN at scene start (optional polish)
	await _fade_in()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		# Enter / Space = Start
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
			_on_start_pressed()
			return

		# Esc = Back
		if event.keycode == KEY_ESCAPE:
			_on_back_pressed()
			return


func _populate_cards() -> void:
	for i in range(unit_cards.size()):
		var card: Node = unit_cards[i]
		var data: Dictionary = SQUAD_DATA[i]

		var portrait := card.get_node("Portrait") as TextureRect
		var name_label := card.get_node("Info/NameLabel") as Label
		var hp_label := card.get_node("Info/HPLabel") as Label
		var ability_label := card.get_node("Info/AbilityLabel") as Label

		if portrait:
			portrait.texture = data.get("portrait", null)
		if name_label:
			name_label.text = str(data.get("name", ""))
		if hp_label:
			hp_label.text = "HP: %d" % int(data.get("hp", 0))
		if ability_label:
			ability_label.text = str(data.get("ability", ""))


func _on_start_pressed() -> void:
	if _busy:
		return
	_busy = true

	await _fade_out()

	if game_scene != null:
		get_tree().change_scene_to_packed(game_scene)
	else:
		push_warning("SquadDeployScreen: game_scene is not set.")
		_busy = false
		await _fade_in()


func _on_back_pressed() -> void:
	if _busy:
		return
	_busy = true

	await _fade_out()
	get_tree().change_scene_to_file(title_scene_path)


# -------------------------
# Fade helpers
# -------------------------

func _setup_fade() -> void:
	if fade == null:
		push_warning("SquadDeployScreen: Fade node missing.")
		return

	# Ensure it draws over everything and covers screen
	fade.color = fade_color
	fade.visible = true
	fade.mouse_filter = Control.MOUSE_FILTER_STOP

	# Full rect coverage (both anchors + offsets)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.offset_left = 0
	fade.offset_top = 0
	fade.offset_right = 0
	fade.offset_bottom = 0

	# Put it last / top visually
	fade.z_index = 999999

	# Start transparent
	var m := fade.modulate
	m.a = 0.0
	fade.modulate = m


func _kill_fade_tween_if_any() -> void:
	if fade == null:
		return
	if fade.has_meta("_fade_tw"):
		var old = fade.get_meta("_fade_tw")
		if old is Tween and is_instance_valid(old):
			(old as Tween).kill()
		fade.remove_meta("_fade_tw")


func _fade_out() -> void:
	if fade == null:
		return

	_kill_fade_tween_if_any()

	fade.visible = true
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.z_index = 999999

	var m := fade.modulate
	m.a = 0.0
	fade.modulate = m

	var tw := create_tween()
	fade.set_meta("_fade_tw", tw)
	tw.tween_property(fade, "modulate:a", 1.0, fade_time)
	await tw.finished


func _fade_in() -> void:
	if fade == null:
		return

	_kill_fade_tween_if_any()

	fade.visible = true
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.z_index = 999999

	var m := fade.modulate
	m.a = 1.0
	fade.modulate = m

	var tw := create_tween()
	fade.set_meta("_fade_tw", tw)
	tw.tween_property(fade, "modulate:a", 0.0, fade_time)
	await tw.finished

	# Keep it visible but transparent (or hide if you prefer)
	# fade.visible = false
