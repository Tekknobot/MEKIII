extends CanvasLayer
class_name InfestationHUD

# -------------------------
# VISUALS
# -------------------------
@export var zombie_portrait: Texture2D = preload("res://sprites/Portraits/zombie_port.png")
@export var portrait_size: int = 48  # square portrait size (px)

@export var zombie_limit: int = 32

# -------------------------
# FONTS (pick in Inspector)
# -------------------------
@export var title_font: Font
@export var body_font: Font
@export var button_font: Font # not used yet, but exposed for consistency

@export var title_font_size: int = 16
@export var body_font_size: int = 14
@export var button_font_size: int = 14 # not used yet

# -------------------------
# INTERNAL NODES
# -------------------------
var _root: Control
var _portrait: TextureRect
var _title: Label
var _bar: ProgressBar
var _count: Label

func _ready() -> void:
	_build_ui()
	set_counts(0, zombie_limit)

func _build_ui() -> void:
	_root = Control.new()
	add_child(_root)

	# Top-left HUD anchor
	_root.anchor_left = 0.0
	_root.anchor_top = 0.0
	_root.anchor_right = 0.0
	_root.anchor_bottom = 0.0
	_root.offset_left = 14
	_root.offset_top = 14

	var panel := PanelContainer.new()
	_root.add_child(panel)

	# Panel look (neon)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.72)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color("3cff3c")
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", sb)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	# --- Portrait frame (square) ---
	var frame := PanelContainer.new()
	row.add_child(frame)

	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0, 0, 0, 0.25)
	fsb.border_width_left = 1
	fsb.border_width_top = 1
	fsb.border_width_right = 1
	fsb.border_width_bottom = 1
	fsb.border_color = Color("3cff3c")
	fsb.corner_radius_top_left = 4
	fsb.corner_radius_top_right = 4
	fsb.corner_radius_bottom_left = 4
	fsb.corner_radius_bottom_right = 4
	frame.add_theme_stylebox_override("panel", fsb)

	var fpad := MarginContainer.new()
	fpad.add_theme_constant_override("margin_left", 0)
	fpad.add_theme_constant_override("margin_right", 0)
	fpad.add_theme_constant_override("margin_top", 0)
	fpad.add_theme_constant_override("margin_bottom", 0)
	frame.add_child(fpad)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(portrait_size, portrait_size)
	_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Square presentation:
	# - KEEP_ASPECT_CENTERED keeps it from stretching weirdly
	# - If your portrait isn't square, it will letterbox inside the square frame (usually looks clean)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture = zombie_portrait
	fpad.add_child(_portrait)

	# --- Right side ---
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)

	_title = Label.new()
	_title.text = "INFESTATION"
	_title.add_theme_color_override("font_color", Color("3cff3c"))

	# Apply TITLE font if provided
	if title_font != null:
		_title.add_theme_font_override("font", title_font)
	_title.add_theme_font_size_override("font_size", title_font_size)

	col.add_child(_title)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(220, 14)
	_bar.min_value = 0
	_bar.max_value = max(1, zombie_limit)
	_bar.value = 0
	_bar.show_percentage = false
	col.add_child(_bar)

	_count = Label.new()
	_count.text = "ZOMBIES: 0 / %d" % zombie_limit
	_count.add_theme_color_override("font_color", Color("cfefff"))

	# Apply BODY font if provided
	if body_font != null:
		_count.add_theme_font_override("font", body_font)
	_count.add_theme_font_size_override("font_size", body_font_size)

	col.add_child(_count)

	# Bar background
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.35)
	bg.corner_radius_top_left = 4
	bg.corner_radius_top_right = 4
	bg.corner_radius_bottom_left = 4
	bg.corner_radius_bottom_right = 4
	_bar.add_theme_stylebox_override("background", bg)

func set_counts(zombies: int, limit: int) -> void:
	zombie_limit = max(1, limit)

	if _bar == null:
		return

	_bar.max_value = zombie_limit
	_bar.value = clamp(zombies, 0, zombie_limit)
	_count.text = "ZOMBIES: %d / %d" % [zombies, zombie_limit]

	var ratio := float(zombies) / float(zombie_limit)

	var col: Color
	if ratio < 0.50:
		col = Color("3cff3c") # green
	elif ratio < 0.80:
		col = Color("ffd84a") # yellow
	else:
		col = Color("ff3c3c") # red

	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.corner_radius_top_left = 4
	fill.corner_radius_top_right = 4
	fill.corner_radius_bottom_left = 4
	fill.corner_radius_bottom_right = 4
	_bar.add_theme_stylebox_override("fill", fill)

	# Make border match state color
	var panel := _root.get_child(0) as PanelContainer
	if panel != null:
		var sb := panel.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			sb.border_color = col
			panel.add_theme_stylebox_override("panel", sb)
