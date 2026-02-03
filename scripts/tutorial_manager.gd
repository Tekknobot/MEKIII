extends Node
class_name TutorialManager

@export var map_controller_path: NodePath
@export var turn_manager_path: NodePath
@export var toast_path: NodePath   # reference to your toast UI scene/node
@export var end_game_panel_path: NodePath
var end_panel: CanvasLayer = null

@onready var M := get_node_or_null(map_controller_path)
@onready var TM := get_node_or_null(turn_manager_path)
@onready var toast := get_node_or_null(toast_path)

@export var overworld_scene_path: String = "res://scenes/overworld.tscn"

enum Step {
	INTRO_SELECT,
	INTRO_MOVE,
	INTRO_ATTACK,
	FIRST_KILL,
	FIRST_PICKUP,
	BEACON_READY,
	BEACON_UPLOAD,
	YOU_WIN,
	DONE
}

var step: Step = Step.INTRO_SELECT
var enabled := true

# Optional: prevent spammy "denied" hints every click
var _last_hint_id: StringName = &""
var _last_hint_time_ms: int = 0
const HINT_COOLDOWN_MS := 900

func _ready() -> void:
	end_panel = get_node_or_null(end_game_panel_path) as CanvasLayer
	
	if not enabled:
		return

	# -------------------------------------------------
	# This project uses ONE generic signal:
	#   tutorial_event(id: StringName, payload: Dictionary)
	# MapController emits it, TurnManager proxies it.
	# -------------------------------------------------
	var hooked := false

	if TM != null and TM.has_signal("tutorial_event"):
		TM.tutorial_event.connect(_on_tutorial_event)
		hooked = true

	# Also connect MapController directly if it has it (safe + helps if TM isn't proxying everything)
	if M != null and M.has_signal("tutorial_event"):
		M.tutorial_event.connect(_on_tutorial_event)
		hooked = true

	# Also helpful (non-critical) hooks
	if M != null and M.has_signal("selection_changed"):
		M.selection_changed.connect(func(u, _args := []):
			if u != null and is_instance_valid(u):
				_on_tutorial_event(&"ally_selected", {"cell": u.cell})
		)

	# If nothing is hooked, still show the first hint so you notice
	call_deferred("_show_step")

func _show_step() -> void:
	match step:
		Step.INTRO_SELECT:
			_toast(
				"Click an ally to select them.\n\nTip: Left-click selects. Right-click arms attack mode.",
				"FIELD OPS"
			)
		Step.INTRO_MOVE:
			_toast(
				"Move your selected ally.\n\nTip: Click a green tile to move.",
				"FIELD OPS"
			)
		Step.INTRO_ATTACK:
			_toast(
				"Attack a zombie.\n\nTip: Right-click to arm ATTACK, then left-click a zombie. Rapid click for multi-damage",
				"FIELD OPS"
			)
		Step.FIRST_KILL:
			_toast(
				"Nice. Zombies sometimes drop floppy disks.\n\nThey appear about 1 in 4 kills.\nCollect them to power the beacon.",
				"FIELD OPS"
			)
		Step.FIRST_PICKUP:
			_toast(
				"Pick up a floppy disk by stepping on it.\nCollect 3 to arm the beacon.",
				"FIELD OPS"
			)
		Step.BEACON_READY:
			_toast(
				"Beacon armed!\n\nMove an ally onto the beacon tile to upload.",
				"FIELD OPS"
			)
		Step.BEACON_UPLOAD:
			_toast(
				"Uploading…\n\nSatellite sweep incoming!",
				"FIELD OPS"
			)
		Step.YOU_WIN:
			_toast(
				"Zombies cleared!\nYou WIN!",
				"FIELD OPS"
			)		
		Step.DONE:
			_hide_toast()


func _toast(msg: String, header: String = "TIP") -> void:
	if toast == null:
		return

	# If your toast has its own show_message(), use it
	if toast.has_method("show_message"):
		toast.call("show_message", msg, header)

	# Ensure it's visually shown without changing layout
	if toast is CanvasItem:
		(toast as CanvasItem).modulate.a = 1.0

	if toast is Control:
		(toast as Control).mouse_filter = Control.MOUSE_FILTER_STOP

func _hide_toast() -> void:
	if toast == null:
		return

	if toast is CanvasItem:
		(toast as CanvasItem).modulate.a = 0.0

	if toast is Control:
		(toast as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

func _advance(to_step: Step) -> void:
	if to_step <= step:
		return
	step = to_step
	_show_step()


func _hint_once(id: StringName, msg: String) -> void:
	# stops the same hint spamming constantly
	var now := Time.get_ticks_msec()
	if id == _last_hint_id and (now - _last_hint_time_ms) < HINT_COOLDOWN_MS:
		return
	_last_hint_id = id
	_last_hint_time_ms = now
	_toast(msg, "FIELD OPS")


# -------------------------------------------------
# tutorial_event router
# -------------------------------------------------
func _on_tutorial_event(id: StringName, payload: Dictionary) -> void:
	if not enabled:
		return

	match String(id):
		# -------------------------
		# Core progression
		# -------------------------
		"ally_selected":
			if step == Step.INTRO_SELECT:
				_advance(Step.INTRO_MOVE)

		"ally_moved":
			if step == Step.INTRO_MOVE:
				_advance(Step.INTRO_ATTACK)
				#_on_you_win()

		"attack_mode_armed":
			# don't auto-advance, just reinforce if they're stuck
			if step == Step.INTRO_ATTACK:
				_hint_once(&"hint_attack_armed", "Attack mode auto armed.\n\nLeft-click again to dis-arm.")

		"attack_mode_disarmed":
			if step == Step.INTRO_ATTACK:
				_hint_once(&"hint_attack_disarmed", "Attack mode armed.\n\nNow left-click a zombie in range.")

		"ally_attacked":
			if step == Step.INTRO_ATTACK:
				_advance(Step.FIRST_KILL)

		"enemy_died":
			# ✅ If they kill on their first attack, we won't miss the kill event.
			if step == Step.INTRO_ATTACK:
				_advance(Step.FIRST_PICKUP) # or FIRST_KILL first if you prefer
			elif step == Step.FIRST_KILL:
				_advance(Step.FIRST_PICKUP)
				
		"beacon_ready":
			if step < Step.BEACON_READY:
				_advance(Step.BEACON_READY)

		"beacon_upload_started":
			if step < Step.BEACON_UPLOAD:
				_advance(Step.BEACON_UPLOAD)

		"satellite_sweep_finished":
			_advance(Step.YOU_WIN)

		"extraction_finished":
			# ✅ NOW the round is truly over; show upgrades
			_on_you_win()

		# -------------------------
		# Helpful “deny / stuck” hints
		# (These correspond to the emits you added)
		# -------------------------
		"move_denied_already_moved":
			if step == Step.INTRO_MOVE:
				_hint_once(&"hint_move_already", "That unit already moved.\n\nSelect a different ally, or End Turn.")

		"move_denied_input_locked":
			_hint_once(&"hint_move_locked", "Hold on — you can’t move right now.\n\nWait for the current action/phase to finish.")

		"move_denied_tm_gate":
			if step == Step.INTRO_MOVE:
				_hint_once(&"hint_move_tm_gate", "Move not allowed right now.\n\nTry selecting another ally, or End Turn.")

		"attack_denied_tm_gate":
			if step == Step.INTRO_ATTACK:
				_hint_once(&"hint_attack_tm_gate", "Attack not allowed right now.\n\nMake sure it’s your turn and the unit can still attack.")

		"attack_denied_already_attacked":
			if step == Step.INTRO_ATTACK:
				_hint_once(&"hint_attack_already", "That unit already attacked.\n\nSelect another ally, or End Turn.")

		# -------------------------
		# Special mode hints (optional)
		# -------------------------
		"special_mode_armed":
			_hint_once(&"hint_special_armed", "Special mode armed.\n\nClick a valid highlighted tile to use it.")

		"special_mode_disarmed":
			_hint_once(&"hint_special_off", "Special mode off.")

		"overwatch_set":
			_hint_once(&"hint_overwatch_set", "Overwatch set.\n\nEnemies moving into range will trigger a shot.")

		"overwatch_cleared":
			_hint_once(&"hint_overwatch_clear", "Overwatch cleared.")

		# Mines (optional)
		"mine_picked_up":
			_hint_once(&"hint_mine_pickup", "Mine picked up.\n\nUse your mine ability to place it again.")

		"mine_detonated":
			_hint_once(&"hint_mine_boom", "Mine detonated!\n\nNice trap.")

		"recruit_spawned":
			_hint_once(&"hint_recruit", "Reinforcement deployed!\n\nSelect them and take your actions.")


# Optional helpers if you want to manually skip during testing
func force_step(s: Step) -> void:
	step = s
	_show_step()

func set_enabled(v: bool) -> void:
	enabled = v
	if not enabled:
		_hide_toast()
	else:
		_show_step()

func _on_you_win() -> void:
	_hide_toast()
	enabled = false

	var rs := get_tree().root.get_node_or_null("RunStateNode")

	# Detect EVENT map (works with your RunState.mission_node_type StringName)
	var is_event := false
	if rs != null and "mission_node_type" in rs:
		is_event = (rs.mission_node_type == &"event")

	# (Optional) if you also have a local flag for special events like titan overwatch:
	# is_event = is_event or _is_titan_event

	# Show your upgrade panel
	if end_panel != null and is_instance_valid(end_panel):
		if end_panel.has_method("show_win"):
			var rounds := 0
			if TM != null and is_instance_valid(TM) and "round_index" in TM:
				rounds = int(TM.round_index)

			# pass the extra flag (you'll add this param next)
			end_panel.call("show_win", rounds, _roll_3_upgrades(), is_event)
		else:
			end_panel.visible = true

	if end_panel != null and is_instance_valid(end_panel):
		if end_panel.has_signal("continue_pressed") and not end_panel.continue_pressed.is_connected(_on_continue_pressed):
			end_panel.continue_pressed.connect(_on_continue_pressed)

	if rs != null:
		var nid := int(rs.mission_node_id)
		if nid >= 0:
			rs.overworld_cleared[str(nid)] = true
			rs.overworld_current_node_id = nid
		rs.save_to_disk()

func _on_continue_pressed() -> void:
	reset_tutorial(Step.INTRO_SELECT)

	# ✅ leave Game and return to overworld
	get_tree().change_scene_to_file(overworld_scene_path)

func _roll_3_upgrades() -> Array:
	var pool: Array = []

	# -------------------------
	# 1) GLOBAL TEAM UPGRADES (always eligible)
	# -------------------------
	pool.append_array([
		{"id": &"all_hp_plus_1", "title": "ARMOR PLATING", "desc": "+1 Max HP to all allies."},
		{"id": &"all_move_plus_1", "title": "FIELD DRILLS", "desc": "+1 Move to all allies."},
		{"id": &"all_dmg_plus_1", "title": "HOT LOADS", "desc": "+1 Attack Damage to all allies."},
	])

	# -------------------------
	# 2) Squad thumbs by DISPLAY_NAME KEY (from RunState.squad_scene_paths)
	# -------------------------
	# Returns Dictionary: { "SOLDIER": Texture2D, "MERCENARY": Texture2D, ... }
	var key_to_thumb: Dictionary = _get_squad_key_to_thumb()

	print("[UPGRADES] squad_scene_paths count = ", (get_tree().root.get_node_or_null("RunStateNode") as Node).squad_scene_paths.size() if get_tree().root.get_node_or_null("RunStateNode") != null and "squad_scene_paths" in get_tree().root.get_node_or_null("RunStateNode") else -1)
	print("[UPGRADES] key_to_thumb keys = ", key_to_thumb.keys())

	var has_unit := func(key: String) -> bool:
		return key_to_thumb.has(key)

	var thumb := func(key: String) -> Texture2D:
		return key_to_thumb.get(key, null)

	# -------------------------
	# 3) Unit-specific upgrades ONLY if unit is in squad
	#    (each carries "thumb" so EndGamePanel shows the image)
	# -------------------------

	# SOLDIER
	if has_unit.call("SOLDIER"):
		var t: Texture2D = thumb.call("SOLDIER")
		pool.append_array([
			{"id": &"soldier_move_plus_1",  "title": "SPRINT TRAINING", "desc": "+1 Move for Soldier.",          "thumb": t},
			{"id": &"soldier_range_plus_1", "title": "MARKSMAN KIT",   "desc": "+1 Attack Range for Soldier.",  "thumb": t},
			{"id": &"soldier_dmg_plus_1",   "title": "HOLLOW POINTS",  "desc": "+1 Damage for Soldier.",        "thumb": t},
		])

	# MERCENARY
	if has_unit.call("MERCENARY"):
		var t: Texture2D = thumb.call("MERCENARY")
		pool.append_array([
			{"id": &"merc_move_plus_1",  "title": "QUICK CONTRACT",      "desc": "+1 Move for Mercenary.",          "thumb": t},
			{"id": &"merc_range_plus_1", "title": "LONG SIGHT",          "desc": "+1 Attack Range for Mercenary.",  "thumb": t},
			{"id": &"merc_dmg_plus_1",   "title": "OVERCHARGED ROUNDS",  "desc": "+1 Damage for Mercenary.",        "thumb": t},
		])

	# ROBODOG
	if has_unit.call("ROBODOG"):
		var t: Texture2D = thumb.call("ROBODOG")
		pool.append_array([
			{"id": &"dog_hp_plus_2",   "title": "REINFORCED ARMOR", "desc": "+2 Max HP for Robodog.", "thumb": t},
			{"id": &"dog_move_plus_1", "title": "HYDRAULIC LEGS",   "desc": "+1 Move for Robodog.",   "thumb": t},
			{"id": &"dog_dmg_plus_1",  "title": "SERVO STRIKE",     "desc": "+1 Damage for Robodog.", "thumb": t},
		])

	# BATTLEANGEL
	if has_unit.call("BATTLEANGEL"):
		var t: Texture2D = thumb.call("BATTLEANGEL")
		pool.append_array([
			{"id": &"angel_hp_plus_1",   "title": "HALO ARMOR",    "desc": "+1 Max HP for Battleangel.", "thumb": t},
			{"id": &"angel_move_plus_1", "title": "WING BOOSTERS", "desc": "+1 Move for Battleangel.",   "thumb": t},
			{"id": &"angel_dmg_plus_1",  "title": "DIVINE EDGE",   "desc": "+1 Damage for Battleangel.", "thumb": t},
		])

	# BLADEGUARD
	if has_unit.call("BLADEGUARD"):
		var t: Texture2D = thumb.call("BLADEGUARD")
		pool.append_array([
			{"id": &"blade_hp_plus_1",   "title": "CARBON PLATING", "desc": "+1 Max HP for Bladeguard.", "thumb": t},
			{"id": &"blade_move_plus_1", "title": "SERVO JOINTS",   "desc": "+1 Move for Bladeguard.",   "thumb": t},
			{"id": &"blade_dmg_plus_1",  "title": "MONO EDGE",      "desc": "+1 Damage for Bladeguard.", "thumb": t},
		])

	# PANTHERBOT
	if has_unit.call("PANTHERBOT"):
		var t: Texture2D = thumb.call("PANTHERBOT")
		pool.append_array([
			{"id": &"panther_move_plus_1", "title": "PREDATOR LEGS", "desc": "+1 Move for Pantherbot.",  "thumb": t},
			{"id": &"panther_dmg_plus_1",  "title": "RAZOR CLAWS",   "desc": "+1 Damage for Pantherbot.","thumb": t},
		])

	# KANNON
	if has_unit.call("KANNON"):
		var t: Texture2D = thumb.call("KANNON")
		pool.append_array([
			{"id": &"kannon_range_plus_1", "title": "EXTENDED BARREL",    "desc": "+1 Range for Kannon.",  "thumb": t},
			{"id": &"kannon_dmg_plus_1",   "title": "HIGH-IMPACT SHELLS", "desc": "+1 Damage for Kannon.", "thumb": t},
		])

	# SKIMMER
	if has_unit.call("SKIMMER"):
		var t: Texture2D = thumb.call("SKIMMER")
		pool.append_array([
			{"id": &"skimmer_move_plus_1", "title": "VECTOR THRUST", "desc": "+1 Move for Skimmer.",   "thumb": t},
			{"id": &"skimmer_dmg_plus_1",  "title": "SEISMIC COILS", "desc": "+1 Damage for Skimmer.", "thumb": t},
		])

	# ARACHNOBOT
	if has_unit.call("ARACHNOBOT"):
		var t: Texture2D = thumb.call("ARACHNOBOT")
		pool.append_array([
			{"id": &"arachno_hp_plus_1",    "title": "CHITIN PLATING",   "desc": "+1 Max HP for Arachnobot.",      "thumb": t},
			{"id": &"arachno_move_plus_1",  "title": "SKITTER SERVOS",   "desc": "+1 Move for Arachnobot.",        "thumb": t},
			{"id": &"arachno_dmg_plus_1",   "title": "NOVA CAPACITORS",  "desc": "+1 Damage for Arachnobot.",      "thumb": t},
		])

	# DESTROYER A.I.
	# NOTE: your key will be whatever display_name becomes after strip+upper.
	# If your display_name is "Destroyer A.I." then the key is "DESTROYER A.I."
	if has_unit.call("DESTROYER A.I."):
		var t: Texture2D = thumb.call("DESTROYER A.I.")
		pool.append_array([
			{"id": &"destroyer_hp_plus_2",  "title": "TITAN CORE",           "desc": "+2 Max HP for Destroyer A.I.", "thumb": t},
			{"id": &"destroyer_dmg_plus_1", "title": "ANNIHILATOR CIRCUITS", "desc": "+1 Damage for Destroyer A.I.", "thumb": t},
		])


	# -------------------------
	# 4) Pick 3
	# -------------------------
	var picked: Array = []
	while picked.size() < 3 and pool.size() > 0:
		var i := randi() % pool.size()
		picked.append(pool[i])
		pool.remove_at(i)

	return picked


# -------------------------
# Helpers
# -------------------------

func _get_squad_display_names() -> Array[String]:
	var out: Array[String] = []

	var rs := get_tree().root.get_node_or_null("RunStateNode")
	if rs == null:
		rs = get_tree().root.get_node_or_null("RunState")
	if rs == null:
		return out
	if not ("squad_scene_paths" in rs):
		return out

	for p in rs.squad_scene_paths:
		var path := str(p)
		var res := load(path)
		if not (res is PackedScene):
			continue

		var inst := (res as PackedScene).instantiate()
		if inst == null:
			continue

		var name := _find_display_name_in_tree(inst)
		if name != "":
			out.append(name)

		inst.queue_free()

	return out


func _find_display_name_in_tree(n: Node) -> String:
	if n == null:
		return ""

	if "display_name" in n:
		var v = n.get("display_name")
		if v != null and str(v) != "":
			return str(v)

	if n.has_meta("display_name"):
		var m = n.get_meta("display_name")
		if m != null and str(m) != "":
			return str(m)

	for ch in n.get_children():
		var got := _find_display_name_in_tree(ch)
		if got != "":
			return got

	return ""


func _make_name_set(names: Array[String]) -> Dictionary:
	var d: Dictionary = {}
	for n in names:
		d[str(n)] = true
	return d


func _squad_has_name_fuzzy(name_set: Dictionary, want: String) -> bool:
	# exact
	if name_set.has(want):
		return true

	var want_l := want.to_lower()

	for k in name_set.keys():
		var s := str(k)
		var s_l := s.to_lower()

		if s_l.find(want_l) != -1:
			return true
		if want_l.find(s_l) != -1:
			return true

	return false

func reset_tutorial(start_step: Step = Step.INTRO_SELECT) -> void:
	enabled = true
	step = start_step

	_last_hint_id = &""
	_last_hint_time_ms = 0

	# Optional: clear any lingering UI state
	_hide_toast()

	# Show first prompt again (deferred avoids timing issues if UI/map is mid-refresh)
	call_deferred("_show_step")

func _get_squad_name_to_thumb() -> Dictionary:
	# Returns: { "Soldier": Texture2D, "Mercenary": Texture2D, ... } by DISPLAY NAME
	var out: Dictionary = {}

	var rs := get_tree().root.get_node_or_null("RunStateNode")
	if rs == null:
		rs = get_tree().root.get_node_or_null("RunState")
	if rs == null:
		return out
	if not ("squad_scene_paths" in rs):
		return out

	for p in rs.squad_scene_paths:
		var path := str(p)
		var res := load(path)
		if not (res is PackedScene):
			continue

		var inst := (res as PackedScene).instantiate()
		if inst == null:
			continue

		var name := _find_display_name_in_tree(inst)  # <-- YOU ALREADY HAVE THIS
		var thumb := _find_thumbnail_in_tree(inst)

		if name != "" and thumb != null and not out.has(name):
			out[name] = thumb

		inst.queue_free()

	return out


func _find_script_global_class_in_tree(n: Node) -> String:
	if n == null:
		return ""

	# Prefer script global name (Godot 4): class_name Foo -> "Foo"
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

	# your units likely have: @export var thumbnail: Texture2D
	if "thumbnail" in n:
		var t = n.get("thumbnail")
		if t is Texture2D:
			return t

	# optional fallback if you want:
	# if "portrait_tex" in n:
	# 	var p = n.get("portrait_tex")
	# 	if p is Texture2D:
	# 		return p

	for ch in n.get_children():
		var got := _find_thumbnail_in_tree(ch)
		if got != null:
			return got

	return null


func _has_class_fuzzy(class_to_thumb: Dictionary, want: String) -> bool:
	if class_to_thumb.has(want):
		return true

	var want_l := want.to_lower()
	for k in class_to_thumb.keys():
		var s_l := str(k).to_lower()
		if s_l.find(want_l) != -1 or want_l.find(s_l) != -1:
			return true

	return false


func _thumb_for_class(class_to_thumb: Dictionary, want: String) -> Texture2D:
	if class_to_thumb.has(want):
		return class_to_thumb[want]

	# fuzzy fallback
	var want_l := want.to_lower()
	for k in class_to_thumb.keys():
		var s := str(k)
		var s_l := s.to_lower()
		if s_l.find(want_l) != -1 or want_l.find(s_l) != -1:
			return class_to_thumb[k]

	return null

func _unit_key(s: String) -> String:
	return s.strip_edges().to_upper()

func _get_squad_key_to_thumb() -> Dictionary:
	var out: Dictionary = {}

	var rs := get_tree().root.get_node_or_null("RunStateNode")
	if rs == null:
		rs = get_tree().root.get_node_or_null("RunState")
	if rs == null:
		print("[SQUAD THUMBS] No RunState found")
		return out

	if not ("squad_scene_paths" in rs):
		print("[SQUAD THUMBS] RunState has no squad_scene_paths")
		return out

	# Map scene basenames -> your upgrade keys
	var alias := {
		"HUMAN": "SOLDIER",
		"HUMANTWO": "MERCENARY",
		"MECH": "ROBODOG",
	}

	for p in rs.squad_scene_paths:
		var path := str(p)
		var res := load(path)
		if not (res is PackedScene):
			continue

		var inst := (res as PackedScene).instantiate()
		if inst == null:
			continue

		var dn := _find_display_name_in_tree(inst)
		var key := _unit_key(dn)

		# Fallback: use file basename if display_name missing
		if key == "":
			var base := path.get_file().get_basename().to_upper() # human / humantwo / mech
			key = base
			if alias.has(key):
				key = alias[key]

		var th := _find_thumbnail_in_tree(inst)

		print("[SQUAD THUMBS] path=", path, " display_name=", dn, " key=", key, " thumb=", th)

		if key != "" and th != null:
			out[key] = th

		inst.queue_free()

	print("[SQUAD THUMBS] FINAL KEYS = ", out.keys())
	return out
