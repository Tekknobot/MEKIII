extends CanvasLayer
class_name HUD

@export var unit_card_path: NodePath = NodePath("UnitCard")
@export var map_controller_group := "MapController"

@export var quirk_pill_font: Font
@export var quirk_pill_font_size: int = 14

@export var quirk_pill_text_color: Color = Color("E8FFF2")
@export var quirk_pill_bg_mul: float = 0.22 # bg = quirk_color * this
@export var quirk_pill_border_mul: float = 0.95
@export var quirk_pill_border_width: int = 2
@export var quirk_pill_corner_radius: int = 10
@export var quirk_pill_pad_x: int = 10
@export var quirk_pill_pad_y: int = 5

# ✅ Tooltip style (non-black, “your style”)
@export var tooltip_bg_color: Color = Color("0B1F24")
@export var tooltip_border_color: Color = Color("3CFFB2")
@export var tooltip_text_color: Color = Color("DFFFEF")
@export var tooltip_border_width: int = 2
@export var tooltip_corner_radius: int = 10
@export var tooltip_pad_x: int = 10
@export var tooltip_pad_y: int = 8

var _unit_card: Control

var _quirk_pill_by_id: Dictionary = {} # StringName -> Control

var _portrait: TextureRect
var _name: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _move_val: Label
var _range_val: Label
var _dmg_val: Label

var _unit: Unit = null

var extras_box: VBoxContainer

var _quirk_cb: Callable

func _ready() -> void:
	_unit_card = get_node_or_null(unit_card_path) as Control
	if _unit_card == null:
		push_warning("HUD: UnitCard not found.")
		return

	_portrait = _unit_card.get_node("Margin/Row/PortraitFrame/Portrait") as TextureRect
	_name     = _unit_card.get_node("Margin/Row/Right/Name") as Label
	_hp_label = _unit_card.get_node("Margin/Row/Right/Bars/HPLabel") as Label
	_hp_bar   = _unit_card.get_node("Margin/Row/Right/Bars/HPBar") as ProgressBar

	_move_val  = _unit_card.get_node("Margin/Row/Right/StatsGrid/MoveVal") as Label
	_range_val = _unit_card.get_node("Margin/Row/Right/StatsGrid/RangeVal") as Label
	_dmg_val   = _unit_card.get_node("Margin/Row/Right/StatsGrid/DmgVal") as Label

	extras_box = _unit_card.get_node("Margin/Row/Right/ExtrasBox") as VBoxContainer

	_unit_card.visible = false

	var M := get_tree().get_first_node_in_group(map_controller_group)
	if M != null and M.has_signal("selection_changed"):
		M.connect("selection_changed", Callable(self, "_on_selection_changed"))
		
	_apply_tooltip_theme()	

func _apply_tooltip_theme() -> void:
	if _unit_card == null:
		return

	var base: Theme = _unit_card.theme
	if base == null:
		base = ThemeDB.get_default_theme()

	var t := base.duplicate()

	var sb := StyleBoxFlat.new()
	sb.bg_color = tooltip_bg_color
	sb.border_color = tooltip_border_color
	sb.border_width_left = tooltip_border_width
	sb.border_width_top = tooltip_border_width
	sb.border_width_right = tooltip_border_width
	sb.border_width_bottom = tooltip_border_width
	sb.set_corner_radius_all(tooltip_corner_radius)
	sb.content_margin_left = tooltip_pad_x
	sb.content_margin_right = tooltip_pad_x
	sb.content_margin_top = tooltip_pad_y
	sb.content_margin_bottom = tooltip_pad_y

	t.set_stylebox("panel", "TooltipPanel", sb)
	t.set_color("font_color", "TooltipLabel", tooltip_text_color)

	# Optional: if you want tooltip font to match your UI, you can reuse existing label fonts
	# (leave as-is if you don’t want to risk mismatching theme resources)
	# t.set_font("font", "TooltipLabel", some_font)
	# t.set_font_size("font_size", "TooltipLabel", 14)

	_unit_card.theme = t


func _make_quirk_pill(text: String, quirk_color: Color, tooltip: String) -> Control:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_STOP
	pill.tooltip_text = tooltip

	var sb := StyleBoxFlat.new()
	sb.bg_color = quirk_color * quirk_pill_bg_mul
	sb.border_color = quirk_color * quirk_pill_border_mul
	sb.border_width_left = quirk_pill_border_width
	sb.border_width_top = quirk_pill_border_width
	sb.border_width_right = quirk_pill_border_width
	sb.border_width_bottom = quirk_pill_border_width
	sb.set_corner_radius_all(quirk_pill_corner_radius)
	sb.content_margin_left = quirk_pill_pad_x
	sb.content_margin_right = quirk_pill_pad_x
	sb.content_margin_top = quirk_pill_pad_y
	sb.content_margin_bottom = quirk_pill_pad_y

	pill.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = quirk_pill_text_color
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	if quirk_pill_font != null:
		lbl.add_theme_font_override("font", quirk_pill_font)
	lbl.add_theme_font_size_override("font_size", quirk_pill_font_size)

	pill.add_child(lbl)
	
	return pill

func set_unit(u: Unit) -> void:
	if _unit != null and is_instance_valid(_unit):
		_unbind_unit_quirk_signal(_unit)
		if _unit.is_connected("died", Callable(self, "_on_unit_died")):
			_unit.disconnect("died", Callable(self, "_on_unit_died"))

	_unit = u

	if _unit == null or not is_instance_valid(_unit):
		_unit_card.visible = false
		return

	_unit_card.visible = true

	_bind_unit_quirk_signal(_unit)

	if not _unit.is_connected("died", Callable(self, "_on_unit_died")):
		_unit.connect("died", Callable(self, "_on_unit_died"))

	_render_extras(u)
	_refresh()


func _render_extras(u):
	_quirk_pill_by_id.clear()

	if extras_box == null:
		return

	for ch in extras_box.get_children():
		ch.queue_free()

	if u == null:
		return

	print("HUD extras for ", u.get_display_name() if u.has_method("get_display_name") else u.name,
		" quirks_meta=", u.get_meta(&"quirks", "NO_META") if u.has_meta(&"quirks") else "MISSING")

	var extras := {}
	if u.has_method("get_hud_extras"):
		extras = u.call("get_hud_extras")

	# ✅ Always show quirks if present (as colored pills)
	if u.has_meta(&"quirks"):
		var qs: Array = u.get_meta(&"quirks", [])
		if not qs.is_empty():
			# We'll render this ourselves (not as a plain text extra)
			extras["__QUIRK_PILLS__"] = qs

	# ✅ KILL any text-based quirk extra from unit scripts (prevents duplicates)
	if extras.has("Quirks"):
		extras.erase("Quirks")
	if extras.has("quirks"):
		extras.erase("quirks")

	for k in extras.keys():
		# Special render: quirk pills
		if str(k) == "__QUIRK_PILLS__":
			var qs: Array = extras[k]

			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var key_lbl := Label.new()
			key_lbl.text = "Quirks"
			key_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			key_lbl.modulate.a = 0.85

			var flow := HFlowContainer.new()
			flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			flow.alignment = FlowContainer.ALIGNMENT_END
			flow.add_theme_constant_override("h_separation", 6)
			flow.add_theme_constant_override("v_separation", 6)

			for q in qs:
				var id := StringName(str(q))
				var d := QuirkDB.get_def(id)
				if d.is_empty():
					continue

				var title := str(d.get("title", String(id)))
				var desc := str(d.get("desc", ""))

				var col := QuirkDB.get_color(id)
				var tip := "%s\n%s" % [title, desc]

				var pill := _make_quirk_pill(title, col, tip)
				flow.add_child(pill)
				_quirk_pill_by_id[id] = pill
		
			row.add_child(key_lbl)
			row.add_child(flow)
			extras_box.add_child(row)
			continue

		# Normal extras (unchanged)
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var key_lbl := Label.new()
		key_lbl.text = str(k)
		key_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		key_lbl.modulate.a = 0.85

		var val_lbl := Label.new()
		val_lbl.text = str(extras[k])
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.modulate.a = 0.95

		row.add_child(key_lbl)
		row.add_child(val_lbl)

		extras_box.add_child(row)

		
func _process(_dt: float) -> void:
	if _unit != null and is_instance_valid(_unit) and _unit_card.visible:
		_refresh()

func _refresh() -> void:
	if _unit == null or not is_instance_valid(_unit):
		_unit_card.visible = false
		return

	_portrait.texture = _unit.get_portrait_texture()
	_name.text = _unit.get_display_name()

	# HP
	_hp_bar.max_value = max(1, _unit.max_hp)
	_hp_bar.value = clamp(_unit.hp, 0, _unit.max_hp)
	_hp_label.text = "HP %d/%d" % [_unit.hp, _unit.max_hp]
	_update_hp_color()
	
	# Stats
	_move_val.text  = str(_unit.get_move_range())
	_range_val.text = str(_unit.attack_range)
	_dmg_val.text   = str(_unit.get_attack_damage())

func _on_unit_died(_u: Unit) -> void:
	set_unit(null)

func _on_selection_changed(u: Unit) -> void:
	set_unit(u)

func _update_hp_color() -> void:
	if _unit == null or not is_instance_valid(_unit):
		return

	var ratio := float(_unit.hp) / float(max(1, _unit.max_hp))

	var col: Color
	if ratio > 0.67:
		col = Color("3cff3c") # green
	elif ratio > 0.34:
		col = Color("ffd84a") # yellow
	else:
		col = Color("ff3c3c") # red

	# Otherwise, it's a normal ProgressBar: override the "fill" stylebox
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	_hp_bar.add_theme_stylebox_override("fill", sb) # ✅ Godot 4 uses "fill"

func hud_pulse_quirk(quirk_id: StringName, text := "", col: Color = Color.WHITE) -> void:
	if not _quirk_pill_by_id.has(quirk_id):
		return
	var pill: Control = _quirk_pill_by_id[quirk_id]
	if pill == null or not is_instance_valid(pill):
		return

	# pill pop
	var tw := create_tween()
	tw.tween_property(pill, "scale", Vector2(1.10, 1.10), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(pill, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# optional: floating text near HUD (subtle)
	if text != "":
		_world_float_text(text, col)

func _world_float_text(msg: String, col: Color) -> void:
	if _unit == null or not is_instance_valid(_unit):
		return

	var M := get_tree().get_first_node_in_group(map_controller_group)
	if M == null:
		return

	var lbl := Label.new()
	lbl.text = msg
	lbl.modulate = col
	lbl.z_index = 9999
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if quirk_pill_font != null:
		lbl.add_theme_font_override("font", quirk_pill_font)
		lbl.add_theme_font_size_override("font_size", quirk_pill_font_size)

	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 2)

	# font
	if quirk_pill_font != null:
		lbl.add_theme_font_override("font", quirk_pill_font)
	lbl.add_theme_font_size_override("font_size", quirk_pill_font_size)

	# add to world (NOT HUD)
	M.add_child(lbl)

	# position above unit
	lbl.global_position = _unit.global_position + Vector2(-8, -28)

	lbl.scale = Vector2(0.6, 0.6)

	var tw := create_tween()
	tw.tween_property(lbl, "scale", Vector2(1.1, 1.1), 0.12).set_trans(Tween.TRANS_BACK)
	tw.tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.10)
	tw.tween_property(lbl, "position:y", lbl.position.y - 20, 0.45)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.45)

	await tw.finished
	if is_instance_valid(lbl):
		lbl.queue_free()

func _bind_unit_quirk_signal(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return
	if not u.has_signal("quirk_triggered"):
		return

	var cb := Callable(self, "_on_unit_quirk_triggered")
	if not u.is_connected("quirk_triggered", cb):
		u.connect("quirk_triggered", cb)


func _unbind_unit_quirk_signal(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return
	var cb := Callable(self, "_on_unit_quirk_triggered")
	if u.has_signal("quirk_triggered") and u.is_connected("quirk_triggered", cb):
		u.disconnect("quirk_triggered", cb)


func _on_unit_quirk_triggered(quirk_id: StringName, label: String, color: Color) -> void:
	hud_pulse_quirk(quirk_id, label, color)
	_world_float_text(label, color)
