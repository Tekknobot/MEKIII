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

@export var global_upgrade_thumb: Texture2D
@export var fallback_thumb: Texture2D

# -------------------------
# UI refs
# -------------------------
var root: Control
var title_label: Label
var body_label: RichTextLabel

# Upgrade cards container (so we can hide it completely on campaign win / loss)
var upgrades_col: VBoxContainer

var upgrade_buttons: Array[Button] = []
var upgrade_descs: Array[Label] = []
var upgrade_thumbs: Array[TextureRect] = []

var continue_button: Button
var restart_button: Button

# Quirk award UI
var quirk_block: VBoxContainer
var quirk_title: Label
var quirk_flow: HFlowContainer

# Campaign victory roster UI
var roster_block: VBoxContainer
var roster_title: Label

# ✅ now grids (4x4)
var unlock_grid: GridContainer
var roster_grid: GridContainer

var _shown_upgrades: Array = []   # Array[Dictionary] {id,title,desc,unit_name?,thumb?}

var _picked := false
var _picked_upgrade: StringName = &""

# -------------------------
# QUIRK PILL STYLE (match HUD)
# -------------------------
@export var quirk_pill_font: Font
@export var quirk_pill_font_size: int = 14

@export var quirk_pill_text_color: Color = Color("E8FFF2")
@export var quirk_pill_bg_mul: float = 0.22
@export var quirk_pill_border_mul: float = 0.95
@export var quirk_pill_border_width: int = 2
@export var quirk_pill_corner_radius: int = 10
@export var quirk_pill_pad_x: int = 10
@export var quirk_pill_pad_y: int = 5

# Tooltip theme (optional, but matches your HUD)
@export var tooltip_bg_color: Color = Color("0B1F24")
@export var tooltip_border_color: Color = Color("3CFFB2")
@export var tooltip_text_color: Color = Color("DFFFEF")
@export var tooltip_border_width: int = 2
@export var tooltip_corner_radius: int = 10
@export var tooltip_pad_x: int = 10
@export var tooltip_pad_y: int = 8


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

	if roster_title != null:
		_apply_font_to_label(roster_title, title_font, body_font_size)

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
	sb.bg_color = Color(0.05, 0.05, 0.05, 1.0)
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
	body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_label.name = "Body"
	body_label.bbcode_enabled = false
	body_label.fit_content = true
	body_label.custom_minimum_size = Vector2(0, 120)
	v.add_child(body_label)

	body_label.fit_content = true
	body_label.scroll_active = false
	body_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body_label.custom_minimum_size = Vector2(0, 0)

	# -------------------------
	# Quirk Award Block (hidden unless quirks awarded)
	# -------------------------
	quirk_block = VBoxContainer.new()
	quirk_block.name = "QuirkBlock"
	quirk_block.visible = false
	quirk_block.add_theme_constant_override("separation", 6)
	v.add_child(quirk_block)

	quirk_title = Label.new()
	quirk_title.text = "NEW QUIRK ACQUIRED"
	quirk_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# -------------------------
	# Campaign Victory Roster Block
	# -------------------------
	roster_block = VBoxContainer.new()
	roster_block.name = "RosterBlock"
	roster_block.visible = false
	roster_block.add_theme_constant_override("separation", 8)
	v.add_child(roster_block)

	# NEW UNLOCKS title
	var unlock_title := Label.new()
	unlock_title.name = "UnlockTitle"
	unlock_title.text = "NEW UNLOCKS"
	unlock_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unlock_title.modulate = Color(1, 0.85, 0.25)
	unlock_title.visible = false
	roster_block.add_child(unlock_title)

	# ✅ centered 4x4 unlock grid
	var unlock_center := CenterContainer.new()
	unlock_center.name = "UnlockCenter"
	unlock_center.visible = false
	roster_block.add_child(unlock_center)

	unlock_grid = GridContainer.new()
	unlock_grid.name = "UnlockFlow"
	unlock_grid.columns = 4
	unlock_grid.add_theme_constant_override("h_separation", 6)
	unlock_grid.add_theme_constant_override("v_separation", 6)
	unlock_center.add_child(unlock_grid)

	# roster title
	roster_title = Label.new()
	roster_title.text = "ACTIVE ROSTER"
	roster_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roster_block.add_child(roster_title)

	# ✅ centered 4x4 roster grid
	var roster_center := CenterContainer.new()
	roster_center.name = "RosterCenter"
	roster_block.add_child(roster_center)

	roster_grid = GridContainer.new()
	roster_grid.name = "RosterFlow"
	roster_grid.columns = 4
	roster_grid.add_theme_constant_override("h_separation", 6)
	roster_grid.add_theme_constant_override("v_separation", 6)
	roster_center.add_child(roster_grid)

	# use the same title font as the panel header
	if title_font != null:
		quirk_title.add_theme_font_override("font", title_font)
		quirk_title.add_theme_font_size_override("font_size", body_font_size)

	quirk_title.modulate = Color(0.55, 1.0, 0.75, 0.95)  # softer neon
	quirk_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quirk_block.add_child(quirk_title)

	quirk_flow = HFlowContainer.new()
	quirk_flow.name = "QuirkFlow"
	quirk_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quirk_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	quirk_flow.add_theme_constant_override("h_separation", 8)
	quirk_flow.add_theme_constant_override("v_separation", 8)
	quirk_block.add_child(quirk_flow)

	# Upgrades column (ONE COLUMN)
	upgrades_col = VBoxContainer.new()
	upgrades_col.name = "Upgrades"
	upgrades_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrades_col.add_theme_constant_override("separation", 10)
	v.add_child(upgrades_col)

	upgrade_buttons.clear()
	upgrade_descs.clear()
	upgrade_thumbs.clear()

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

		# ---- HBOX: thumbnail left, text right ----
		var card_h := HBoxContainer.new()
		card_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_h.add_theme_constant_override("separation", 10)
		card_margin.add_child(card_h)

		# Thumbnail
		var t := TextureRect.new()
		t.name = "Thumb%d" % i
		t.custom_minimum_size = Vector2(64, 64)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.texture = null
		t.visible = false
		t.modulate = Color(1, 1, 1, 0.95)
		card_h.add_child(t)
		upgrade_thumbs.append(t)

		# Text column
		var card_v := VBoxContainer.new()
		card_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_v.add_theme_constant_override("separation", 6)
		card_h.add_child(card_v)

		# Title button
		var b := Button.new()
		b.name = "UpgradeBtn%d" % i
		b.text = "Upgrade"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _pick_upgrade(i))

		b.add_theme_stylebox_override("normal", _make_card_style(Color(0, 0, 0, 0.35), Color(1,1,1,0.18)))
		b.add_theme_stylebox_override("hover",  _make_card_style(Color(0, 0, 0, 0.45), Color(1,1,1,0.24)))
		b.add_theme_stylebox_override("pressed",_make_card_style(Color(0, 0, 0, 0.55), Color(1,1,1,0.30)))

		card_v.add_child(b)
		upgrade_buttons.append(b)

		# Description
		var d := Label.new()
		d.name = "UpgradeDesc%d" % i
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.text = ""
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		d.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		card_v.add_child(d)
		upgrade_descs.append(d)

	# Footer
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_theme_constant_override("separation", 10)
	v.add_child(footer)

	continue_button = Button.new()
	continue_button.name = "Continue"
	continue_button.text = "Continue"
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	continue_button.custom_minimum_size.x = 140
	continue_button.disabled = true
	continue_button.pressed.connect(func():
		if not _picked:
			return
		emit_signal("continue_pressed")
		hide_panel()
	)
	footer.add_child(continue_button)

	# Optional restart (kept as var, but not created by default)
	restart_button = Button.new()

	# Apply font overrides after all nodes exist
	refresh_fonts()

# -------------------------
# Public API
# -------------------------
func show_win(rounds_survived: int, upgrades: Array, is_event: bool = false) -> void:
	_shown_upgrades = upgrades

	_picked = false
	_picked_upgrade = &""
	if continue_button != null:
		continue_button.disabled = true

	if title_label != null:
		title_label.text = ("EVENT COMPLETE" if is_event else "MISSION COMPLETE")

	if body_label != null:
		if is_event:
			body_label.text = "Objective complete.\nRounds survived: %d\n\nChoose ONE upgrade:" % rounds_survived
		else:
			body_label.text = "Satellite sweep confirmed.\nRounds survived: %d\n\nChoose ONE upgrade:" % rounds_survived

	_apply_quirk_awards_ui()
	if roster_block != null:
		roster_block.visible = false
	_apply_upgrade_ui()
	show_panel()

func _apply_quirk_awards_ui() -> void:
	if quirk_block == null or quirk_flow == null:
		return

	for ch in quirk_flow.get_children():
		ch.queue_free()

	_sync_quirk_style_from_hud_if_possible()
	_apply_tooltip_theme_to_root()

	var rs := get_tree().root.get_node_or_null("RunState")
	if rs == null:
		rs = get_tree().root.get_node_or_null("RunStateNode")
	if rs == null:
		quirk_block.visible = false
		return

	if not ("last_awarded_quirks" in rs):
		quirk_block.visible = false
		return

	var awarded: Array = rs.last_awarded_quirks
	if awarded.is_empty():
		quirk_block.visible = false
		return

	quirk_block.visible = true

	for a in awarded:
		if not (a is Dictionary):
			continue

		var qid := a.get("quirk_id", &"") as StringName
		if qid == &"":
			continue

		var def := QuirkDB.get_def(qid)
		if def.is_empty():
			continue

		var title := str(def.get("title", String(qid)))
		var desc := str(def.get("desc", ""))
		var col := QuirkDB.get_color(qid)

		var who := ""
		var uid := str(a.get("unit_id", ""))
		if uid != "":
			who = _unit_display_name_from_id(rs, uid)

		var tip := "%s\n%s" % [title, desc]
		if who != "":
			tip += "\n\nAwarded to: %s" % who

		var pill := _make_quirk_pill(title, col, tip)
		quirk_flow.add_child(pill)

		pill.scale = Vector2(0.9, 0.9)
		var tw := create_tween()
		tw.tween_property(pill, "scale", Vector2(1.08, 1.08), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(pill, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func show_event_success(title_text: String, body_text: String, button_text: String = "EVAC") -> void:
	_shown_upgrades = []
	_picked = true
	_picked_upgrade = &""

	if continue_button != null:
		continue_button.disabled = false
		continue_button.text = button_text

	if title_label != null:
		title_label.text = title_text
	if body_label != null:
		body_label.text = "[center]%s[/center]" % body_text

	if roster_block != null:
		roster_block.visible = false
	_apply_upgrade_ui()
	show_panel()

func show_loss(msg: String, button_text: String = "MAIN MENU") -> void:
	_shown_upgrades = []
	_picked = true
	_picked_upgrade = &""

	if continue_button != null:
		continue_button.disabled = false
		continue_button.text = button_text

	if title_label != null:
		title_label.text = "MISSION FAILED"
	if body_label != null:
		body_label.text = msg

	_apply_upgrade_ui()
	if roster_block != null:
		roster_block.visible = false
	show_panel()

func show_campaign_victory(stats: Dictionary, button_text: String = "RETURN TO SQUAD DEPLOY") -> void:
	_shown_upgrades = []
	_picked = true
	_picked_upgrade = &""

	if continue_button != null:
		continue_button.disabled = false
		continue_button.text = button_text

	if title_label != null:
		title_label.text = "CAMPAIGN COMPLETE"

	var missions := int(stats.get("missions_cleared", 0))
	var rounds := int(stats.get("rounds", 0))
	var mechs_lost := int(stats.get("mechs_lost", 0))
	var survivors := int(stats.get("survivors", 0))

	if body_label != null:
		body_label.text = "Sector stabilized.\n\nMissions cleared: %d\nRounds survived: %d\nMechs lost: %d\nSurvivors: %d" % [missions, rounds, mechs_lost, survivors]

	_apply_upgrade_ui()
	_apply_campaign_roster_ui()
	show_panel()

# -------------------------
# Internals
# -------------------------
func _apply_upgrade_ui() -> void:
	if upgrades_col != null:
		upgrades_col.visible = (_shown_upgrades.size() > 0)
	if _shown_upgrades.is_empty():
		for i in range(3):
			if i < upgrade_buttons.size():
				upgrade_buttons[i].disabled = true
				upgrade_buttons[i].text = ""
			if i < upgrade_descs.size():
				upgrade_descs[i].text = ""
			if i < upgrade_thumbs.size() and upgrade_thumbs[i] != null:
				upgrade_thumbs[i].texture = null
				upgrade_thumbs[i].visible = false
		return

	for i in range(3):
		if _shown_upgrades.size() > i:
			var up: Dictionary = _shown_upgrades[i]

			upgrade_buttons[i].disabled = false
			upgrade_buttons[i].text = str(up.get("title", "Upgrade"))
			upgrade_descs[i].text = str(up.get("desc", ""))

			var tex: Texture2D = up.get("thumb", null)

			if tex == null:
				var sid := String(up.get("id", &""))
				if sid.begins_with("all_"):
					tex = global_upgrade_thumb

			if tex == null:
				var unit_class := str(up.get("unit_class", ""))
				if unit_class != "":
					tex = _thumb_from_runstate_by_class(unit_class)
					if tex == null:
						tex = _thumb_from_unit_scene_by_class(unit_class)

			if tex == null:
				var unit_name := str(up.get("unit_name", ""))
				if unit_name != "":
					tex = _thumb_from_runstate(unit_name)

			if tex == null:
				tex = fallback_thumb

			if i < upgrade_thumbs.size() and upgrade_thumbs[i] != null:
				upgrade_thumbs[i].texture = tex
				upgrade_thumbs[i].visible = (tex != null)
		else:
			upgrade_buttons[i].disabled = true
			upgrade_buttons[i].text = ""
			upgrade_descs[i].text = ""

			if i < upgrade_thumbs.size() and upgrade_thumbs[i] != null:
				upgrade_thumbs[i].texture = null
				upgrade_thumbs[i].visible = false

func _thumb_from_runstate_by_class(unit_class: String) -> Texture2D:
	var rs := get_tree().root.get_node_or_null("RunState")
	if rs == null:
		rs = get_tree().root.get_node_or_null("RunStateNode")
	if rs == null:
		return null

	if rs.has_method("get_unit_thumb_by_class"):
		var t = rs.call("get_unit_thumb_by_class", unit_class)
		if t is Texture2D:
			return t
	return null

func _thumb_from_unit_scene_by_class(unit_class: String) -> Texture2D:
	var rs := get_tree().root.get_node_or_null("RunState")
	if rs == null:
		rs = get_tree().root.get_node_or_null("RunStateNode")
	if rs == null:
		return null

	for p in rs.squad_scene_paths:
		var path := str(p)
		var res := load(path)
		if not (res is PackedScene):
			continue

		var inst := (res as PackedScene).instantiate()
		if inst == null:
			continue

		var cls := _find_script_global_class_in_tree(inst)
		var tex := _find_thumbnail_in_tree(inst)
		inst.queue_free()

		if cls == unit_class and tex is Texture2D:
			return tex
	return null

func _find_script_global_class_in_tree(n: Node) -> String:
	if n == null:
		return ""
	var sc = n.get_script()
	if sc != null and sc is Script:
		var gn := (sc as Script).get_global_name()
		if gn != null and str(gn) != "":
			return str(gn)

	for ch in n.get_children():
		var got := _find_script_global_class_in_tree(ch)
		if got != "":
			return got
	return ""

func _find_thumbnail_in_tree(n: Node) -> Texture2D:
	if n == null:
		return null

	if "thumbnail" in n:
		var t = n.get("thumbnail")
		if t is Texture2D:
			return t

	for ch in n.get_children():
		var got := _find_thumbnail_in_tree(ch)
		if got != null:
			return got
	return null

func _pick_upgrade(i: int) -> void:
	if i < 0 or i >= _shown_upgrades.size():
		return

	var up: Dictionary = _shown_upgrades[i]
	var id: StringName = up.get("id", &"")
	if id == &"":
		return

	for b in upgrade_buttons:
		b.disabled = true

	_picked = true
	_picked_upgrade = id

	var rs := get_tree().root.get_node_or_null("RunState")
	if rs == null:
		rs = get_tree().root.get_node_or_null("RunStateNode")

	if rs != null:
		if rs.has_method("add_upgrade"):
			rs.call("add_upgrade", id)
		if rs.has_method("save_to_disk"):
			rs.call("save_to_disk")

	if continue_button != null:
		continue_button.disabled = false

	emit_signal("upgrade_selected", id)

func _thumb_from_runstate(unit_display_name: String) -> Texture2D:
	var rs := get_tree().root.get_node_or_null("RunState")
	if rs == null:
		rs = get_tree().root.get_node_or_null("RunStateNode")
	if rs == null:
		return null

	if rs.has_method("get_unit_thumb_by_display_name"):
		var t = rs.call("get_unit_thumb_by_display_name", unit_display_name)
		if t is Texture2D:
			return t
	return null

func _apply_campaign_roster_ui() -> void:
	if roster_block == null:
		return

	var unlock_title := roster_block.get_node_or_null("UnlockTitle") as Label
	var unlock_center := roster_block.get_node_or_null("UnlockCenter") as CenterContainer
	var unlock_flow := roster_block.get_node_or_null("UnlockFlow") as GridContainer

	var roster_center := roster_block.get_node_or_null("RosterCenter") as CenterContainer
	if roster_grid == null:
		roster_grid = roster_block.get_node_or_null("RosterFlow") as GridContainer

	if roster_grid == null:
		roster_block.visible = false
		return

	# Clear previous
	for ch in roster_grid.get_children():
		ch.queue_free()
	if unlock_flow != null:
		for ch in unlock_flow.get_children():
			ch.queue_free()

	var rs := get_tree().root.get_node_or_null("RunStateNode")
	if rs == null:
		rs = get_tree().root.get_node_or_null("RunState")
	if rs == null:
		roster_block.visible = false
		return

	# -------------------------
	# NEW UNLOCKS (separate)
	# -------------------------
	var unlocked_paths: Array[String] = []
	if ("last_unlocked_roster" in rs) and (rs.last_unlocked_roster is Array):
		for x in rs.last_unlocked_roster:
			var s := str(x)
			if s != "" and ResourceLoader.exists(s):
				unlocked_paths.append(s)

	var has_unlocks := (unlocked_paths.size() > 0)
	if unlock_title != null:
		unlock_title.visible = has_unlocks
	if unlock_center != null:
		unlock_center.visible = has_unlocks

	if unlock_flow != null and has_unlocks:
		for p in unlocked_paths:
			var tex := _thumb_from_scene_path(p)
			var chip := _make_roster_portrait_chip(tex, true) # highlight border
			unlock_flow.add_child(chip)
			_start_new_unlock_pulse(chip) # ✅ reliable pulse

	# -------------------------
	# ACTIVE ROSTER (full list)
	# -------------------------
	if roster_center != null:
		roster_center.visible = true

	var roster_paths: Array[String] = []

	if ("roster_units" in rs) and (rs.roster_units is Array):
		for e_any in rs.roster_units:
			if not (e_any is Dictionary):
				continue
			var p := str((e_any as Dictionary).get("path", ""))
			if p != "" and ResourceLoader.exists(p):
				roster_paths.append(p)
	elif ("squad_scene_paths" in rs) and (rs.squad_scene_paths is Array):
		for p_any in rs.squad_scene_paths:
			var p2 := str(p_any)
			if p2 != "" and ResourceLoader.exists(p2):
				roster_paths.append(p2)

	for p3 in roster_paths:
		var tex3 := _thumb_from_scene_path(p3)
		var chip3 := _make_roster_portrait_chip(tex3, false)
		roster_grid.add_child(chip3)

	roster_block.visible = true

func _start_new_unlock_pulse(chip: Control) -> void:
	if chip == null or not is_instance_valid(chip):
		return

	# ✅ wait 1 frame so it's definitely inside tree + laid out
	await get_tree().process_frame
	if chip == null or not is_instance_valid(chip):
		return

	chip.scale = Vector2.ONE
	chip.modulate = Color(1, 1, 1, 1)

	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(chip, "scale", Vector2(1.08, 1.08), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(chip, "modulate", Color(1, 1, 1, 0.78), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(chip, "scale", Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(chip, "modulate", Color(1, 1, 1, 1.0), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _thumb_from_scene_path(scene_path: String) -> Texture2D:
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		return null
	var res := load(scene_path)
	if not (res is PackedScene):
		return null
	var inst := (res as PackedScene).instantiate()
	if inst == null:
		return null

	var tex: Texture2D = null
	if ("portrait_tex" in inst):
		var t = inst.get("portrait_tex")
		if t is Texture2D:
			tex = t
	if tex == null and ("thumbnail" in inst):
		var t2 = inst.get("thumbnail")
		if t2 is Texture2D:
			tex = t2

	inst.queue_free()
	return tex

func _make_roster_portrait_chip(tex: Texture2D, is_new: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(72, 72)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.18)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.set_corner_radius_all(10)

	sb.border_color = (Color(1.0, 0.85, 0.20, 1.0) if is_new else Color(1, 1, 1, 0.18))
	panel.add_theme_stylebox_override("panel", sb)

	var stack := Control.new()
	stack.custom_minimum_size = Vector2(72, 72)
	panel.add_child(stack)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 6)
	m.add_theme_constant_override("margin_right", 6)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(m)

	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(60, 60)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = tex
	tr.modulate = Color(1, 1, 1, 0.98)
	m.add_child(tr)

	if is_new:
		var badge := Label.new()
		badge.text = "NEW"
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_color_override("font_color", Color(0,0,0,1))

		if button_font != null:
			badge.add_theme_font_override("font", button_font)
		badge.add_theme_font_size_override("font_size", 14)

		var badge_bg := PanelContainer.new()
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(1.0, 0.85, 0.20, 1.0)
		bsb.border_color = Color(1.0, 1.0, 1.0, 0.35)
		bsb.border_width_left = 1
		bsb.border_width_top = 1
		bsb.border_width_right = 1
		bsb.border_width_bottom = 1
		bsb.set_corner_radius_all(6)
		badge_bg.add_theme_stylebox_override("panel", bsb)

		badge_bg.add_child(badge)
		stack.add_child(badge_bg)

		badge_bg.position = Vector2(4, 4)
		badge_bg.custom_minimum_size = Vector2(36, 20)

	return panel

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

func set_panel_title(t: String) -> void:
	if title_label != null:
		title_label.text = t

func _sync_quirk_style_from_hud_if_possible() -> void:
	var hud := get_tree().get_first_node_in_group("HUD")
	if hud == null or not is_instance_valid(hud):
		return

	if ("quirk_pill_text_color" in hud): quirk_pill_text_color = hud.quirk_pill_text_color
	if ("quirk_pill_bg_mul" in hud): quirk_pill_bg_mul = hud.quirk_pill_bg_mul
	if ("quirk_pill_border_mul" in hud): quirk_pill_border_mul = hud.quirk_pill_border_mul
	if ("quirk_pill_border_width" in hud): quirk_pill_border_width = hud.quirk_pill_border_width
	if ("quirk_pill_corner_radius" in hud): quirk_pill_corner_radius = hud.quirk_pill_corner_radius
	if ("quirk_pill_pad_x" in hud): quirk_pill_pad_x = hud.quirk_pill_pad_x
	if ("quirk_pill_pad_y" in hud): quirk_pill_pad_y = hud.quirk_pill_pad_y

	if ("tooltip_bg_color" in hud): tooltip_bg_color = hud.tooltip_bg_color
	if ("tooltip_border_color" in hud): tooltip_border_color = hud.tooltip_border_color
	if ("tooltip_text_color" in hud): tooltip_text_color = hud.tooltip_text_color
	if ("tooltip_border_width" in hud): tooltip_border_width = hud.tooltip_border_width
	if ("tooltip_corner_radius" in hud): tooltip_corner_radius = hud.tooltip_corner_radius
	if ("tooltip_pad_x" in hud): tooltip_pad_x = hud.tooltip_pad_x
	if ("tooltip_pad_y" in hud): tooltip_pad_y = hud.tooltip_pad_y

func _apply_tooltip_theme_to_root() -> void:
	if root == null:
		return

	var base: Theme = root.theme
	if base == null:
		base = ThemeDB.get_default_theme()

	var t := base.duplicate()

	if body_font != null:
		t.set_font("font", "TooltipLabel", body_font)
		t.set_font_size("font_size", "TooltipLabel", body_font_size)

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

	root.theme = t

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

	var font_to_use: Font = quirk_pill_font
	var font_size_to_use: int = quirk_pill_font_size

	if font_to_use == null:
		if body_font != null:
			font_to_use = body_font
			font_size_to_use = body_font_size
		elif title_font != null:
			font_to_use = title_font
			font_size_to_use = title_font_size

	if font_to_use != null:
		lbl.add_theme_font_override("font", font_to_use)
		if font_size_to_use > 0:
			lbl.add_theme_font_size_override("font_size", font_size_to_use)

	pill.add_child(lbl)
	return pill

func _unit_display_name_from_id(rs: Node, uid: String) -> String:
	if "roster_units" in rs:
		for e in rs.roster_units:
			if not (e is Dictionary):
				continue
			if str(e.get("id", "")) != uid:
				continue

			var dn := str(e.get("display_name", ""))
			if dn != "":
				return dn

			var p := str(e.get("path", ""))
			if p != "" and ResourceLoader.exists(p):
				var packed := load(p)
				if packed is PackedScene:
					var inst := (packed as PackedScene).instantiate()
					var name2 := ""
					if inst != null:
						if "display_name" in inst:
							name2 = str(inst.display_name)
						elif inst.has_method("get_display_name"):
							name2 = str(inst.call("get_display_name"))
						inst.queue_free()
					if name2 != "":
						return name2
	return uid

func _make_portrait(tex: Texture2D, highlight := false) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(64, 64)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	if highlight:
		r.modulate = Color(1,1,1,1)
		r.add_theme_constant_override("outline_size", 3)
	else:
		r.modulate = Color(1,1,1,0.9)

	return r
