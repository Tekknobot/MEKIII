extends Label
class_name HPLabel

@export var unit_path: NodePath
@export var unit_group_name := ""

@export var show_as_fraction := true
@export var prefix := "HP: "

@export_range(0.0, 1.0, 0.01) var high_threshold := 0.67
@export_range(0.0, 1.0, 0.01) var mid_threshold := 0.34

@export var update_interval := 0.0

# --- Shadow styling ---
@export var shadow_color := Color(0, 0, 0, 0.85)
@export var shadow_offset := Vector2(2, 2)
@export var shadow_outline_size := 0   # keep 0 unless you want thick outline

var unit: Unit = null
var _timer: Timer = null

func _ready() -> void:
	_bind_unit()
	_apply_shadow_style()

	if update_interval > 0.0:
		_timer = Timer.new()
		_timer.one_shot = false
		_timer.wait_time = update_interval
		add_child(_timer)
		_timer.timeout.connect(_refresh)
		_timer.start()

	_refresh()

func _process(_delta: float) -> void:
	if update_interval > 0.0:
		return
	_refresh()

func _bind_unit() -> void:
	if unit_path != NodePath():
		var n := get_node_or_null(unit_path)
		if n is Unit:
			unit = n
			return

	if unit_group_name != "":
		var n2 := get_tree().get_first_node_in_group(unit_group_name)
		if n2 is Unit:
			unit = n2

func set_unit(u: Unit) -> void:
	unit = u
	_refresh()

# --- Shadow setup ---
func _apply_shadow_style() -> void:
	add_theme_color_override("font_shadow_color", shadow_color)
	add_theme_constant_override("font_shadow_offset_x", int(shadow_offset.x))
	add_theme_constant_override("font_shadow_offset_y", int(shadow_offset.y))
	add_theme_constant_override("font_shadow_outline_size", shadow_outline_size)

func _refresh() -> void:
	if unit == null or not is_instance_valid(unit):
		text = prefix + "--"
		add_theme_color_override("font_color", Color(1, 1, 1, 1))
		return

	var cur = max(0, int(unit.hp))
	var maxv = max(1, int(unit.max_hp))

	if show_as_fraction:
		text = "%s%d/%d" % [prefix, cur, maxv]
	else:
		text = "%s%d" % [prefix, cur]

	var ratio := float(cur) / float(maxv)

	var c: Color
	if ratio >= high_threshold:
		c = Color(0.25, 0.95, 0.35, 1.0)   # green
	elif ratio >= mid_threshold:
		c = Color(1.0, 0.9, 0.25, 1.0)     # yellow
	else:
		c = Color(1.0, 0.25, 0.25, 1.0)    # red

	add_theme_color_override("font_color", c)
