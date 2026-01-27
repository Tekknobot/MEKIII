# res://ui/unit_card.gd
extends Button
class_name UnitCard

signal hovered(data: Dictionary)
signal unhovered()

var _cached_data: Dictionary

@onready var portrait: TextureRect = get_node_or_null("HBox/Portrait") as TextureRect
@onready var thumbnail: TextureRect = get_node_or_null("HBox/Thumbnail") as TextureRect
@onready var name_label: Label = get_node_or_null("HBox/VBox/Name") as Label
@onready var stats_label: Label = get_node_or_null("HBox/VBox/Stats") as Label

var unit_path: String = ""

func _ready() -> void:
	# Loud error so you don’t wonder why nothing shows up.
	if name_label == null or stats_label == null:
		push_error("UnitCard.tscn mismatch. Expected: HBox/VBox/Name and HBox/VBox/Stats.")
	# Portrait nodes can be optional; we just skip if missing.

	mouse_entered.connect(_on_mouse_enter)
	mouse_exited.connect(_on_mouse_exit)

func _on_mouse_enter() -> void:
	if not _cached_data.is_empty():
		emit_signal("hovered", _cached_data)

func _on_mouse_exit() -> void:
	emit_signal("unhovered")
		
func set_empty(text: String = "EMPTY") -> void:
	unit_path = ""
	if portrait: portrait.texture = null
	if thumbnail: thumbnail.texture = null
	if name_label: name_label.text = text
	if stats_label: stats_label.text = ""
	disabled = true
	modulate = Color(1, 1, 1, 0.75)

func set_data(data: Dictionary) -> void:
	_cached_data = data
	unit_path = str(data.get("path", ""))

	var portrait_tex: Texture2D = data.get("portrait", null)
	var thumb_tex: Texture2D = data.get("thumb", null)

	# Portrait always
	if portrait:
		portrait.texture = portrait_tex
		portrait.visible = (portrait_tex != null)

	# Thumbnail only if provided
	if thumbnail:
		if thumb_tex != null:
			thumbnail.texture = thumb_tex
			thumbnail.visible = true
		else:
			thumbnail.texture = null
			thumbnail.visible = false

	if name_label:
		name_label.text = str(data.get("name", unit_path.get_file().get_basename()))

	var hp := int(data.get("hp", 0))
	var mv := int(data.get("move_range", 0))
	var rng := int(data.get("attack_range", 0))
	var dmg := int(data.get("attack_damage", 0))
	if stats_label:
		stats_label.text = "HP %d  •  MV %d  •  RNG %d  •  DMG %d" % [hp, mv, rng, dmg]

	disabled = false
	modulate = Color(1, 1, 1, 1)

func set_selected(on: bool) -> void:
	# subtle tint highlight
	modulate = (Color(0.85, 1.0, 0.85, 1.0) if on else Color(1, 1, 1, 1))
