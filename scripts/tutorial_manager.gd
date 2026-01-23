extends Node
class_name TutorialManager

@export var map_controller_path: NodePath
@export var turn_manager_path: NodePath
@export var toast_path: NodePath   # reference to your toast UI scene/node

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
	DONE
}

var step: Step = Step.INTRO_SELECT
var enabled := true

# Optional: prevent spammy "denied" hints every click
var _last_hint_id: StringName = &""
var _last_hint_time_ms: int = 0
const HINT_COOLDOWN_MS := 900


func _ready() -> void:
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
		M.selection_changed.connect(func(u):
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
				"TUTORIAL"
			)
		Step.INTRO_MOVE:
			_toast(
				"Move your selected ally.\n\nTip: Click a green tile to move.",
				"TUTORIAL"
			)
		Step.INTRO_ATTACK:
			_toast(
				"Attack a zombie.\n\nTip: Right-click to arm ATTACK, then left-click a zombie.",
				"TUTORIAL"
			)
		Step.FIRST_KILL:
			_toast(
				"Nice. Zombies sometimes drop floppy disks.\n\nThey appear about 1 in 4 kills.\nCollect them to power the beacon.",
				"TUTORIAL"
			)
		Step.FIRST_PICKUP:
			var need := 3
			if M != null and "beacon_parts_needed" in M:
				need = int(M.beacon_parts_needed)
			_toast(
				"Pick up a floppy disk by stepping on it.\n\nCollect %d total to arm the beacon." % need,
				"TUTORIAL"
			)
		Step.BEACON_READY:
			_toast(
				"Beacon armed!\n\nMove an ally onto the beacon tile to upload.",
				"TUTORIAL"
			)
		Step.BEACON_UPLOAD:
			_toast(
				"Uploading…\n\nSatellite sweep incoming!",
				"TUTORIAL"
			)
		Step.DONE:
			_hide_toast()


func _toast(msg: String, header: String = "TIP") -> void:
	if toast == null:
		return

	if toast.has_method("show_message"):
		toast.call("show_message", msg, header)
		return

	if toast is CanvasItem:
		(toast as CanvasItem).visible = true
		if toast.has_node("Label"):
			var L := toast.get_node("Label")
			if L != null and L.has_method("set_text"):
				L.text = msg


func _hide_toast() -> void:
	if toast == null:
		return
	if toast is CanvasItem:
		(toast as CanvasItem).visible = false


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
	_toast(msg, "TUTORIAL")


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
			if step == Step.FIRST_KILL:
				_advance(Step.FIRST_PICKUP)

		"pickup_collected":
			if step == Step.FIRST_PICKUP and M != null and ("beacon_parts_needed" in M) and ("beacon_parts_collected" in M):
				var need := int(M.beacon_parts_needed)
				var got := int(M.beacon_parts_collected)

				if got >= need:
					# If your game emits beacon_ready separately, great; but this keeps tutorial flowing even if not.
					_advance(Step.BEACON_READY)
				else:
					_toast("Floppy collected: %d/%d\n\nKeep collecting to arm the beacon." % [got, need], "TUTORIAL")

		"beacon_ready":
			if step < Step.BEACON_READY:
				_advance(Step.BEACON_READY)

		"beacon_upload_started":
			if step < Step.BEACON_UPLOAD:
				_advance(Step.BEACON_UPLOAD)

		"satellite_sweep_finished":
			_advance(Step.DONE)

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
