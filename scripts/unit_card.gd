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

@export var desat_selected := true
@export var desat_tween_time := 0.30
@export var desat_affects_thumbnail := true

var _sat_tw: Tween = null
var _portrait_mat: ShaderMaterial = null
var _thumb_mat: ShaderMaterial = null
@export var default_saturation := 0.0 # 0=gray at start, 1=color

func _make_desat_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float saturation : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 gray = vec3(g);
	c.rgb = mix(gray, c.rgb, saturation);
	COLOR = c;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat

func _ensure_desat_mats() -> void:
	if portrait != null and _portrait_mat == null:
		_portrait_mat = _make_desat_material()
		portrait.material = _portrait_mat

	if desat_affects_thumbnail and thumbnail != null and _thumb_mat == null:
		_thumb_mat = _make_desat_material()
		thumbnail.material = _thumb_mat

func _set_saturation(v: float) -> void:
	if _portrait_mat != null:
		_portrait_mat.set_shader_parameter("saturation", v)
	if desat_affects_thumbnail and _thumb_mat != null:
		_thumb_mat.set_shader_parameter("saturation", v)

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

	# reset to default when reusing cards
	if desat_selected:
		_ensure_desat_mats()
		_set_saturation(default_saturation)
		
	if name_label:
		name_label.text = str(data.get("name", unit_path.get_file().get_basename()))

	var hp := int(data.get("hp", 0))
	# Back-compat: SquadDeploy uses keys: move/range/damage
	var mv := int(data.get("move_range", data.get("move", 0)))
	var rng := int(data.get("attack_range", data.get("range", 0)))
	var dmg := int(data.get("attack_damage", data.get("damage", 0)))
	if stats_label:
		var base := "HP %d  •  MV %d  •  RNG %d  •  DMG %d" % [hp, mv, rng, dmg]
		var quirks := str(data.get("quirks_text", ""))
		stats_label.text = base if quirks == "" else (base + "\n" + quirks)

	disabled = false
	modulate = Color(1, 1, 1, 1)


func set_selected(on: bool) -> void:
	# subtle tint highlight (keep your current behavior)
	modulate = (Color(0.85, 1.0, 0.85, 1.0) if on else Color(1, 1, 1, 1))

	if not desat_selected:
		return

	_ensure_desat_mats()
	if _portrait_mat == null and _thumb_mat == null:
		return

	if _sat_tw != null and is_instance_valid(_sat_tw):
		_sat_tw.kill()
	_sat_tw = null

	var to := 1.0 if on else 0.0

	_sat_tw = create_tween()
	_sat_tw.tween_method(func(v: float) -> void:
		_set_saturation(v)
	, _get_current_saturation(), to, desat_tween_time)

func _get_current_saturation() -> float:
	if _portrait_mat != null:
		return float(_portrait_mat.get_shader_parameter("saturation"))
	if _thumb_mat != null:
		return float(_thumb_mat.get_shader_parameter("saturation"))
	return 1.0

func force_saturation(v: float) -> void:
	if desat_selected:
		_ensure_desat_mats()
		_set_saturation(v)
