extends CanvasLayer
class_name EndGamePanelRuntime

signal upgrade_selected(id: StringName)
signal continue_pressed()
signal restart_pressed()

# -------------------------
# FONT CONTROLS (Inspector)
# -------------------------
@export var title_font: Font
@export var body_font: Font
@export var button_font: Font

@export var title_font_size := 28
@export var body_font_size := 18
@export var button_font_size := 20

@export var desc_font: Font            # optional: upgrade card description font
@export var desc_font_size := 16

# -------------------------
# UI refs
# -------------------------
var root: Control
var title_label: Label
var body_label: RichTextLabel
var upgrade_buttons: Array[Button] = []
var upgrade_descs: Array[Label] = []
var continue_button: Button
var restart_button: Button

var _shown_upgrades: Array = []   # Array[Dictionary] {id,title,desc}

var _picked := false
var _picked_upgrade: StringName = &""

func _ready() -> void:
	_build_ui()
	hide_panel()

# -------------------------
# Theme override helpers
# -------------------------
func _apply_font_to_label(lbl: Label, f: Font, size: int) -> void:
	if lbl == null:
		return
	if f != null:
		lbl.add_theme_font_override("font", f)
	if size > 0:
		lbl.add_theme_font_size_override("font_size", size)

func _apply_font_to_rich(rt: RichTextLabel, f: Font, size: int) -> void:
	if rt == null:
		return
	if f != null:
		rt.add_theme_font_override("normal_font", f)
	if size > 0:
		rt.add_theme_font_size_override("normal_font_size", size)

func _apply_font_to_button(btn: Button, f: Font, size: int) -> void:
	if btn == null:
		return
	if f != null:
		btn.add_theme_font_override("font", f)
	if size > 0:
		btn.add_theme_font_size_override("font_size", size)

func refresh_fonts() -> void:
	_apply_font_to_label(title_label, title_font, title_font_size)
	_apply_font_to_rich(body_label, body_font, body_font_size)

	for b in upgrade_buttons:
		_apply_font_to_button(b, button_font, button_font_size)

	var use_desc_font: Font = desc_font if desc_font != null else body_font
	for d in upgrade_descs:
		_apply_font_to_label(d, use_desc_font, desc_font_size)

	_apply_font_to_button(continue_button, button_font, button_font_size)
	_apply_font_to_button(restart_button, button_font, button_font_size)

# -------------------------
# Build UI
# -------------------------
func _build_ui() -> void:
	refresh_fonts()
	
	# Root (full screen)
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Dim background
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	# Center container
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(360, 560)
	center.add_child(panel)
	# Panel background style (controls transparency)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.05, 1.0)  # ← last value is alpha
	sb.border_color = Color(0.3, 0.3, 0.3, 1.0)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8

	panel.add_theme_stylebox_override("panel", sb)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.name = "VBox"
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(v)

	# Title
	title_label = Label.new()
	title_label.name = "Title"
	title_label.text = "MISSION COMPLETE"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title_label)

	# Body
	body_label = RichTextLabel.new()
	body_label.name = "Body"
	body_label.bbcode_enabled = false
	body_label.fit_content = true
	body_label.custom_minimum_size = Vector2(0, 120)
	v.add_child(body_label)

	# Upgrades column (ONE COLUMN)
	var upgrades_col := VBoxContainer.new()
	upgrades_col.name = "Upgrades"
	upgrades_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrades_col.add_theme_constant_override("separation", 10)
	v.add_child(upgrades_col)

	upgrade_buttons.clear()
	upgrade_descs.clear()

	for i in range(3):
		# Card panel
		var card_panel := PanelContainer.new()
		card_panel.name = "CardPanel%d" % i
		card_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_panel.custom_minimum_size = Vector2(0, 110) # height per card

		# subtle dark card background
		card_panel.add_theme_stylebox_override("panel", _make_card_style(Color(0, 0, 0, 0.20)))
		upgrades_col.add_child(card_panel)

		var card_margin := MarginContainer.new()
		card_margin.add_theme_constant_override("margin_left", 12)
		card_margin.add_theme_constant_override("margin_right", 12)
		card_margin.add_theme_constant_override("margin_top", 10)
		card_margin.add_theme_constant_override("margin_bottom", 10)
		card_panel.add_child(card_margin)

		var card_v := VBoxContainer.new()
		card_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_v.add_theme_constant_override("separation", 6)
		card_margin.add_child(card_v)

		# Title button (full width)
		var b := Button.new()
		b.name = "UpgradeBtn%d" % i
		b.text = "Upgrade"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _pick_upgrade(i))

		# Slightly brighter button background so it reads like a choice
		b.add_theme_stylebox_override("normal", _make_card_style(Color(0, 0, 0, 0.35), Color(1,1,1,0.18)))
		b.add_theme_stylebox_override("hover",  _make_card_style(Color(0, 0, 0, 0.45), Color(1,1,1,0.24)))
		b.add_theme_stylebox_override("pressed",_make_card_style(Color(0, 0, 0, 0.55), Color(1,1,1,0.30)))

		card_v.add_child(b)
		upgrade_buttons.append(b)

		# Description under it
		var d := Label.new()
		d.name = "UpgradeDesc%d" % i
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.text = ""
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		d.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		card_v.add_child(d)
		upgrade_descs.append(d)

	# Footer buttons (ONLY ONCE)
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_theme_constant_override("separation", 10)
	v.add_child(footer)

	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	continue_button = Button.new()
	continue_button.name = "Continue"
	continue_button.text = "Continue"
	continue_button.disabled = true  # locked until upgrade picked
	continue_button.pressed.connect(func():
		if not _picked:
			return
		emit_signal("continue_pressed")
		hide_panel()
	)
	footer.add_child(continue_button)

	#restart_button = Button.new()
	#restart_button.name = "Restart"
	#restart_button.text = "Restart"
	#restart_button.pressed.connect(func():
	#	emit_signal("restart_pressed")
	#	hide_panel()
	#)
	#footer.add_child(restart_button)

	# Apply font overrides after all nodes exist
	refresh_fonts()

# -------------------------
# Public API
# -------------------------
func show_win(rounds_survived: int, upgrades: Array) -> void:
	_shown_upgrades = upgrades

	_picked = false
	_picked_upgrade = &""
	if continue_button != null:
		continue_button.disabled = true

	if title_label != null:
		title_label.text = "MISSION COMPLETE"
	if body_label != null:
		body_label.text = "Satellite sweep confirmed.\nRounds survived: %d\n\nChoose ONE upgrade:" % rounds_survived

	_apply_upgrade_ui()
	show_panel()


func show_loss(msg: String) -> void:
	_shown_upgrades = []
	if title_label != null:
		title_label.text = "MISSION FAILED"
	if body_label != null:
		body_label.text = msg
	_apply_upgrade_ui()
	show_panel()

# -------------------------
# Internals
# -------------------------
func _apply_upgrade_ui() -> void:
	for i in range(3):
		if _shown_upgrades.size() > i:
			var up: Dictionary = _shown_upgrades[i]
			upgrade_buttons[i].disabled = false
			upgrade_buttons[i].text = str(up.get("title", "Upgrade"))
			upgrade_descs[i].text = str(up.get("desc", ""))
		else:
			upgrade_buttons[i].disabled = true
			upgrade_buttons[i].text = "—"
			upgrade_descs[i].text = ""

func _pick_upgrade(i: int) -> void:
	if i < 0 or i >= _shown_upgrades.size():
		return

	var up: Dictionary = _shown_upgrades[i]
	var id: StringName = up.get("id", &"")
	if id == &"":
		return

	# lock after pick
	for b in upgrade_buttons:
		b.disabled = true

	_picked = true
	_picked_upgrade = id
	
	RunStateNode.add_upgrade(id)

	# allow continue now
	if continue_button != null:
		continue_button.disabled = false

	emit_signal("upgrade_selected", id)

func show_panel() -> void:
	visible = true
	if root != null:
		root.visible = true

func hide_panel() -> void:
	if root != null:
		root.visible = false
	visible = false

func _make_card_style(bg: Color, border: Color = Color(1,1,1,0.10)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb
