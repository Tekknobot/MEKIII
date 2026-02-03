extends CanvasLayer
class_name HUD

@export var unit_card_path: NodePath = NodePath("UnitCard")
@export var map_controller_group := "MapController"

var _unit_card: Control

var _portrait: TextureRect
var _name: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _move_val: Label
var _range_val: Label
var _dmg_val: Label

var _unit: Unit = null

var extras_box: VBoxContainer

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

func set_unit(u: Unit) -> void:
	if _unit != null and is_instance_valid(_unit):
		if _unit.is_connected("died", Callable(self, "_on_unit_died")):
			_unit.disconnect("died", Callable(self, "_on_unit_died"))

	_unit = u

	if _unit == null or not is_instance_valid(_unit):
		_unit_card.visible = false
		return

	_unit_card.visible = true

	if not _unit.is_connected("died", Callable(self, "_on_unit_died")):
		_unit.connect("died", Callable(self, "_on_unit_died"))

	_render_extras(u)
	_refresh()

func _render_extras(u):
	if extras_box == null:
		return

	for ch in extras_box.get_children():
		ch.queue_free()

	if u == null:
		return

	var extras := {}
	if u.has_method("get_hud_extras"):
		extras = u.call("get_hud_extras")

	for k in extras.keys():
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
