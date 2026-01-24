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
				"Attack a zombie.\n\nTip: Right-click to arm ATTACK, then left-click a zombie.",
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
				_hint_once(&"hint_attack_armed", "Attack mode armed.\n\nNow left-click a zombie in range.")

		"attack_mode_disarmed":
			if step == Step.INTRO_ATTACK:
				_hint_once(&"hint_attack_disarmed", "Attack mode off.\n\nRight-click again to arm ATTACK.")

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
	# stop tutorial toast from fighting the UI
	_hide_toast()

	# If you want to fully lock tutorial after win:
	enabled = false

	# Show your upgrade panel
	if end_panel != null and is_instance_valid(end_panel):
		if end_panel.has_method("show_win"):
			# try to pass a rounds value if you have it
			var rounds := 0
			if TM != null and is_instance_valid(TM) and "round_index" in TM:
				rounds = int(TM.round_index)
			end_panel.call("show_win", rounds, _roll_3_upgrades())
		else:
			# fallback: just make it visible
			end_panel.visible = true

	if end_panel != null and is_instance_valid(end_panel):
		if end_panel.has_signal("continue_pressed") and not end_panel.continue_pressed.is_connected(_on_continue_pressed):
			end_panel.continue_pressed.connect(_on_continue_pressed)

func _on_continue_pressed() -> void:
	reset_tutorial(Step.INTRO_SELECT)

	if M != null and is_instance_valid(M) and M.game_ref != null and is_instance_valid(M.game_ref):
		var G = M.game_ref
		if G.has_method("regenerate_map_faded"):
			G.call("regenerate_map_faded")

func _roll_3_upgrades() -> Array:
	var pool: Array = [
		# -------------------------
		# GLOBAL TEAM UPGRADES
		# -------------------------
		{"id": &"all_hp_plus_1", "title": "ARMOR PLATING", "desc": "+1 Max HP to all allies."},
		{"id": &"all_move_plus_1", "title": "FIELD DRILLS", "desc": "+1 Move to all allies."},
		{"id": &"all_dmg_plus_1", "title": "HOT LOADS", "desc": "+1 Attack Damage to all allies."},

		# -------------------------
		# SOLDIER (Human)
		# -------------------------
		{"id": &"soldier_move_plus_1", "title": "SPRINT TRAINING", "desc": "+1 Move for Soldier."},
		{"id": &"soldier_range_plus_1", "title": "MARKSMAN KIT", "desc": "+1 Attack Range for Soldier."},
		{"id": &"soldier_dmg_plus_1", "title": "HOLLOW POINTS", "desc": "+1 Damage for Soldier."},

		# -------------------------
		# MERCENARY (HumanTwo)
		# -------------------------
		{"id": &"merc_move_plus_1", "title": "QUICK CONTRACT", "desc": "+1 Move for Mercenary."},
		{"id": &"merc_range_plus_1", "title": "LONG SIGHT", "desc": "+1 Attack Range for Mercenary."},
		{"id": &"merc_dmg_plus_1", "title": "OVERCHARGED ROUNDS", "desc": "+1 Damage for Mercenary."},

		# -------------------------
		# ROBODOG (Mech)
		# -------------------------
		{"id": &"dog_hp_plus_2", "title": "REINFORCED ARMOR", "desc": "+2 Max HP for Robodog."},
		{"id": &"dog_move_plus_1", "title": "HYDRAULIC LEGS", "desc": "+1 Move for Robodog."},
		{"id": &"dog_dmg_plus_1", "title": "SERVO STRIKE", "desc": "+1 Damage for Robodog."},
	]

	var picked: Array = []
	while picked.size() < 3 and pool.size() > 0:
		var i := randi() % pool.size()
		picked.append(pool[i])
		pool.remove_at(i)

	return picked

func reset_tutorial(start_step: Step = Step.INTRO_SELECT) -> void:
	enabled = true
	step = start_step

	_last_hint_id = &""
	_last_hint_time_ms = 0

	# Optional: clear any lingering UI state
	_hide_toast()

	# Show first prompt again (deferred avoids timing issues if UI/map is mid-refresh)
	call_deferred("_show_step")
