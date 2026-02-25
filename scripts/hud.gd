extends CanvasLayer
class_name HUD

@export var unit_card_path: NodePath = NodePath("UnitCard")
@export var map_controller_group := "MapController"

# -------------------------
# Portrait quirk tiers (A) + shader anim (B)
# -------------------------
@export var quirktier_folder: String = "res://sprites/Portraits/QuirkTiers"
@export var use_portrait_quirk_tiers: bool = true
@export var use_portrait_quirk_shader: bool = true

# Optional: assign in Inspector, or we’ll create it at runtime
@export var portrait_quirk_shader: Shader = null

@export var quirk_pill_font: Font
@export var quirk_pill_font_size: int = 14

@export var quirk_pill_text_color: Color = Color("E8FFF2")
@export var quirk_pill_bg_mul: float = 0.22 # bg = quirk_color * this
@export var quirk_pill_border_mul: float = 0.95
@export var quirk_pill_border_width: int = 2
@export var quirk_pill_corner_radius: int = 10
@export var quirk_pill_pad_x: int = 10
@export var quirk_pill_pad_y: int = 5

const TAG_COLORS := {
	"MOVE": Color(0.45, 1.0, 0.55),
	"ATK":  Color(1.0, 0.55, 0.25),
	"DEF":  Color(0.45, 0.85, 1.0),
	"HAZ":  Color(0.55, 1.0, 0.45),
	"RISK": Color(1.0, 0.30, 0.30),
	"ANOM": Color(0.75, 0.55, 1.0),
	"TEAM": Color(0.65, 1.0, 0.85),
	"KILL": Color(1.0, 0.35, 0.35),
}

# ---------------------------------------------------------
# TURN BANNER (phase clarity)
# ---------------------------------------------------------
var _turn_banner: PanelContainer = null
var _turn_banner_label: Label = null
var _turn_banner_tw: Tween = null

@export var banner_font: Font
@export var banner_font_size := 32

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
var quirks_dock: VBoxContainer

var _quirk_cb: Callable

func _ready() -> void:
	add_to_group("HUD")
	
	_unit_card = get_node_or_null(unit_card_path) as Control
	if _unit_card == null:
		push_warning("HUD: UnitCard not found.")
		return

	_portrait = _unit_card.get_node("Margin/HBoxContainer/Row/PortraitFrame/Portrait") as TextureRect
	_name     = _unit_card.get_node("Margin/HBoxContainer/Row/Right/LeftInfo/Name") as Label
	_hp_label = _unit_card.get_node("Margin/HBoxContainer/Row/Right/LeftInfo/Bars/HPLabel") as Label
	_hp_bar   = _unit_card.get_node("Margin/HBoxContainer/Row/Right/LeftInfo/Bars/HPBar") as ProgressBar

	_move_val  = _unit_card.get_node("Margin/HBoxContainer/Row/Right/LeftInfo/StatsGrid/MoveVal") as Label
	_range_val = _unit_card.get_node("Margin/HBoxContainer/Row/Right/LeftInfo/StatsGrid/RangeVal") as Label
	_dmg_val   = _unit_card.get_node("Margin/HBoxContainer/Row/Right/LeftInfo/StatsGrid/DmgVal") as Label

	extras_box = _unit_card.get_node("Margin/HBoxContainer/Row/Right/LeftInfo/ExtrasBox") as VBoxContainer
	quirks_dock = _unit_card.get_node("Margin/HBoxContainer/Row/Right/QuirksDock") as VBoxContainer

	_unit_card.visible = false

	var M := get_tree().get_first_node_in_group(map_controller_group)
	if M != null and M.has_signal("selection_changed"):
		M.connect("selection_changed", Callable(self, "_on_selection_changed"))
		
	_apply_tooltip_theme()	
	_ensure_portrait_shader()
	
	_create_turn_banner()


func _quirk_desc_to_bbcode(desc: String) -> String:
	# expects desc like: "HAZ ATK When FIRE damages you..."
	desc = desc.strip_edges()
	if desc == "":
		return ""

	var words := desc.split(" ", false)
	if words.is_empty():
		return desc

	var i := 0
	var out := ""

	# color up to 2 leading tag words
	for _k in range(2):
		if i >= words.size():
			break
		var tag := words[i].to_upper()
		if TAG_COLORS.has(tag):
			var hex = TAG_COLORS[tag].to_html()
			out += "[color=%s][b]%s[/b][/color] " % [hex, tag]
			i += 1
		else:
			break

	if i < words.size():
		out += " ".join(words.slice(i, words.size()))

	return out

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

class QuirkPill extends PanelContainer:
	var tooltip_title: String = ""
	var tooltip_desc: String = ""
	var tooltip_font: Font = null
	var tooltip_font_size: int = 14
	var tooltip_text_color: Color = Color("DFFFEF")

	# Provide tag colors from HUD (we'll pass them in)
	var tag_colors: Dictionary = {}

	func _make_custom_tooltip(_for_text: String) -> Object:
		var panel := PanelContainer.new()
		panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		panel.custom_minimum_size = Vector2(320, 0) # <- gives it a sane width so it doesn't look "tiny"

		# Style directly (no theme-variation surprises)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("0B1F24")
		# no border here (the tooltip popup already frames it)
		sb.border_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(0)
		sb.set_corner_radius_all(8) # keep subtle rounding
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		panel.add_theme_stylebox_override("panel", sb)

		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		v.add_theme_constant_override("separation", 6)
		panel.add_child(v)

		# --- Title label ---
		var title_lbl := Label.new()
		title_lbl.text = tooltip_title
		title_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		title_lbl.modulate = tooltip_text_color
		title_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

		if tooltip_font != null:
			title_lbl.add_theme_font_override("font", tooltip_font)
			title_lbl.add_theme_font_size_override("font_size", tooltip_font_size)

		# Make title feel bold-ish without requiring a bold font
		title_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		title_lbl.add_theme_constant_override("outline_size", 1)

		v.add_child(title_lbl)

		# --- Desc row: [colored tags] + rest ---
		var h := HBoxContainer.new()
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_theme_constant_override("separation", 6)
		v.add_child(h)

		# Parse up to 2 tag words at start
		var desc := tooltip_desc.strip_edges()
		var words := desc.split(" ", false)
		var i := 0
		for _k in range(2):
			if i >= words.size():
				break
			var tag := words[i].to_upper()
			if tag_colors.has(tag):
				var tag_lbl := Label.new()
				tag_lbl.text = tag
				tag_lbl.modulate = tag_colors[tag]
				tag_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				if tooltip_font != null:
					tag_lbl.add_theme_font_override("font", tooltip_font)
					tag_lbl.add_theme_font_size_override("font_size", tooltip_font_size)
				h.add_child(tag_lbl)
				i += 1
			else:
				break

		# Rest of description
		var rest := ""
		if i < words.size():
			rest = " ".join(words.slice(i, words.size()))

		var desc_lbl := Label.new()
		desc_lbl.text = rest
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.modulate = tooltip_text_color
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_lbl.custom_minimum_size.x = 260

		if tooltip_font != null:
			desc_lbl.add_theme_font_override("font", tooltip_font)
			desc_lbl.add_theme_font_size_override("font_size", tooltip_font_size)

		h.add_child(desc_lbl)

		panel.reset_size()
		return panel

func _make_quirk_pill(title_text: String, quirk_color: Color, tip_title: String, tip_desc: String) -> Control:
	var pill := QuirkPill.new()
	pill.mouse_filter = Control.MOUSE_FILTER_STOP

	# MUST be non-empty so Godot requests the custom tooltip
	pill.tooltip_text = "x"

	pill.tooltip_title = tip_title
	pill.tooltip_desc = tip_desc
	pill.tooltip_font = quirk_pill_font
	pill.tooltip_font_size = quirk_pill_font_size
	pill.tooltip_text_color = tooltip_text_color
	pill.tag_colors = TAG_COLORS

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

	# ✅ pill shows NAME ONLY
	var lbl := Label.new()
	lbl.text = title_text
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
	for ch in quirks_dock.get_children():
		ch.queue_free()

	if u == null:
		return

	# Co-op robustness: some codepaths store quirks as 'quirks_meta'. Mirror it.
	if (not u.has_meta(&"quirks")) and u.has_meta(&"quirks_meta"):
		var qm = u.get_meta(&"quirks_meta", [])
		if qm is Array:
			u.set_meta(&"quirks", qm)

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

			# Put quirks on the RIGHT dock
			quirks_dock.size_flags_horizontal = Control.SIZE_SHRINK_END
			quirks_dock.add_theme_constant_override("separation", 6)

			for q in qs:
				var id := StringName(str(q))
				var d := QuirkDB.get_def(id)
				if d.is_empty():
					continue

				var title := str(d.get("title", String(id)))
				var desc := str(d.get("desc", ""))
				var col := QuirkDB.get_color(id)

				var pill := _make_quirk_pill(title, col, title, desc)

				# Optional: make pills a bit slimmer so the dock is narrow
				pill.custom_minimum_size.x = 0

				quirks_dock.add_child(pill)
				_quirk_pill_by_id[id] = pill

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

	var qc := _unit_quirk_count(_unit)

	# Option A: swap portrait texture based on quirk tiers
	_portrait.texture = _portrait_texture_for_tier(_unit, qc)

	# Option B: shader animation intensity scales with quirk count
	_ensure_portrait_shader()
	_set_portrait_quirk_intensity(qc)

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
	
	_pulse_if_buff_active(_unit)


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
		lbl.add_theme_font_size_override("font_size", quirk_pill_font_size * 2)

	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 2)

	# add to overlay canvas (CanvasLayer/Control)
	M.float_root.add_child(lbl)

	# world -> screen
	var screen_pos := M.get_viewport().get_canvas_transform() * _unit.global_position
	lbl.position = screen_pos + Vector2(-8, -28)

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
	# ✅ pill pulse only — no floating text
	hud_pulse_quirk(quirk_id)

var _last_pulse_stamp: int = -999

func _pulse_if_buff_active(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return

	# throttle: pulse at most every 0.35s
	var stamp := int(Time.get_ticks_msec() / 350)
	if stamp == _last_pulse_stamp:
		return

	# Iceblood: stim damage buff active
	var st := int(u.get_meta(&"stim_turns", 0))
	var bonus := int(u.get_meta(&"stim_damage_bonus", 0))
	if st > 0 and bonus > 0:
		_last_pulse_stamp = stamp
		hud_pulse_quirk(&"iceblood")

func _unit_quirk_count(u: Unit) -> int:
	if u == null or not is_instance_valid(u):
		return 0
	if u.has_meta(&"quirks"):
		var qs: Array = u.get_meta(&"quirks", [])
		return clampi(qs.size(), 0, 3)
	return 0


func _portrait_path_for_tier(base_tex: Texture2D, qcount: int) -> String:
	# We assume your tier files are named like: dog_port_q0.png ... dog_port_q3.png
	# and stored in quirtier_folder.
	if base_tex == null:
		return ""

	var rp := base_tex.resource_path
	if rp == "":
		return ""

	var stem := rp.get_file().get_basename()  # e.g. "dog_port"
	var p := "%s/%s_q%d.png" % [quirktier_folder, stem, clampi(qcount, 0, 3)]
	return p


func _portrait_texture_for_tier(u: Unit, qcount: int) -> Texture2D:
	var base := u.get_portrait_texture()
	if not use_portrait_quirk_tiers:
		return base

	var p := _portrait_path_for_tier(base, qcount)
	if p != "" and ResourceLoader.exists(p):
		return load(p)

	# fallback: if file not found, just use base
	return base


func _ensure_portrait_shader() -> void:
	if not use_portrait_quirk_shader:
		_portrait.material = null
		return

	# If already set to a ShaderMaterial, keep it
	if _portrait.material is ShaderMaterial:
		return

	# Use provided shader if assigned, otherwise create a default one
	var sh := portrait_quirk_shader
	if sh == null:
		sh = Shader.new()
		sh.code = """
		
shader_type canvas_item;

uniform float quirk_intensity : hint_range(0.0,1.0) = 0.0;

void fragment() {
	vec2 uv = UV;

	// =========================
	// GLITCH OFFSET
	// =========================
	float glitch_tick = step(0.96, fract(sin(TIME*7.0)*43758.5));
	float glitch_shift = glitch_tick * 0.02 * quirk_intensity;
	uv.x += glitch_shift;

	// =========================
	// CHROMATIC SPLIT (pixel safe)
	// =========================
	vec2 offset = vec2(0.003 * quirk_intensity, 0.0);

	float r = texture(TEXTURE, uv + offset).r;
	float g = texture(TEXTURE, uv).g;
	float b = texture(TEXTURE, uv - offset).b;

	vec4 col = vec4(r, g, b, texture(TEXTURE, uv).a);

	// =========================
	// SCANLINES (stronger)
	// =========================
	float scan = sin((uv.y + TIME*3.0) * 160.0);
	col.rgb -= scan * 0.08 * quirk_intensity;

	// =========================
	// PULSE BRIGHTNESS
	// =========================
	float pulse = sin(TIME*5.0) * 0.08 * quirk_intensity;
	col.rgb += pulse;

	// =========================
	// ANOMALY GREEN EMISSION
	// =========================
	col.rgb += vec3(0.0, 0.9, 0.45) * 0.25 * quirk_intensity;

	COLOR = col;
}

"""
		portrait_quirk_shader = sh

	var mat := ShaderMaterial.new()
	mat.shader = sh
	_portrait.material = mat


func _set_portrait_quirk_intensity(qcount: int) -> void:
	if not use_portrait_quirk_shader:
		return
	var mat := _portrait.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("quirk_intensity", float(clampi(qcount, 0, 3)) / 3.0)

# =========================================================
# TURN BANNER
# =========================================================
func _create_turn_banner() -> void:
	if _turn_banner != null and is_instance_valid(_turn_banner):
		return

	_turn_banner = PanelContainer.new()
	_turn_banner.name = "TurnBanner"
	
	_turn_banner.anchor_left = 0.5
	_turn_banner.anchor_right = 0.5
	_turn_banner.anchor_top = 0
	_turn_banner.anchor_bottom = 0
	_turn_banner.offset_left = -200
	_turn_banner.offset_right = 200
	_turn_banner.offset_top = 20
	_turn_banner.offset_bottom = 84

	_turn_banner.offset_left = 0
	_turn_banner.offset_right = 0
	_turn_banner.offset_top = 18
	_turn_banner.offset_bottom = 18 + 64
	_turn_banner.visible = false
	_turn_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.70)
	sb.border_color = Color(1, 1, 1, 0.10)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_turn_banner.add_theme_stylebox_override("panel", sb)

	var label := Label.new()
	label.name = "Label"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.text = ""
	label.modulate = Color(1, 1, 1, 1)

	if banner_font != null:
		label.add_theme_font_override("font", banner_font)
		label.add_theme_font_size_override("font_size", banner_font_size)

	_turn_banner.add_child(label)
	_turn_banner_label = label

	add_child(_turn_banner)


func show_turn_banner(text: String, kind: String = "") -> void:
	_create_turn_banner()
	if _turn_banner == null or not is_instance_valid(_turn_banner):
		return

	# stop previous animation cleanly
	if _turn_banner_tw != null and is_instance_valid(_turn_banner_tw):
		_turn_banner_tw.kill()
	_turn_banner_tw = null

	# color language by kind (optional)
	var accent := Color(0.35, 1.00, 0.55) # default neon green
	if kind == "enemy":
		accent = Color(1.00, 0.35, 0.35)
	elif kind == "hazard":
		accent = Color(0.55, 1.00, 0.45)
	elif kind == "boss":
		accent = Color(0.95, 0.85, 0.20)

	_turn_banner_label.text = text

	# resize banner based on text width
	await get_tree().process_frame

	var w := _turn_banner_label.get_minimum_size().x + 64
	_turn_banner.offset_left = -w * 0.5
	_turn_banner.offset_right = w * 0.5

	_turn_banner_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	# tint border slightly
	var sb := _turn_banner.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)

	# animate in/out
	_turn_banner.visible = true
	_turn_banner.modulate = Color(1, 1, 1, 0)

	var start_y := 6.0
	var mid_y := 18.0
	_turn_banner.offset_top = start_y
	_turn_banner.offset_bottom = start_y + 64

	_turn_banner_tw = create_tween()
	_turn_banner_tw.set_trans(Tween.TRANS_CUBIC)
	_turn_banner_tw.set_ease(Tween.EASE_OUT)

	# fade/slide in
	_turn_banner_tw.tween_property(_turn_banner, "modulate:a", 1.0, 0.12)
	_turn_banner_tw.parallel().tween_property(_turn_banner, "offset_top", mid_y, 0.12)
	_turn_banner_tw.parallel().tween_property(_turn_banner, "offset_bottom", mid_y + 64, 0.12)

	# hold
	_turn_banner_tw.tween_interval(0.55)

	# fade out
	_turn_banner_tw.set_ease(Tween.EASE_IN)
	_turn_banner_tw.tween_property(_turn_banner, "modulate:a", 0.0, 0.18)

	_turn_banner_tw.finished.connect(func ():
		if _turn_banner != null and is_instance_valid(_turn_banner):
			_turn_banner.visible = false
	)
