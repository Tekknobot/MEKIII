extends Node
class_name TutorialManager

@export var map_controller_path: NodePath
@export var turn_manager_path: NodePath
@export var toast_path: NodePath   # reference to your toast UI scene/node

@onready var M := get_node(map_controller_path)
@onready var TM := get_node(turn_manager_path)
@onready var toast := get_node(toast_path)

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

func _ready() -> void:
	if not enabled: return

	# -------------------------------------------------
	# This project uses ONE generic signal:
	#   tutorial_event(id: StringName, payload: Dictionary)
	# MapController emits it, TurnManager proxies it.
	# -------------------------------------------------
	if TM != null and TM.has_signal("tutorial_event"):
		TM.tutorial_event.connect(_on_tutorial_event)
	elif M != null and M.has_signal("tutorial_event"):
		M.tutorial_event.connect(_on_tutorial_event)

	# Also helpful (non-critical) hooks
	if M != null and M.has_signal("selection_changed"):
		M.selection_changed.connect(func(u):
			if u != null and is_instance_valid(u):
				_on_tutorial_event(&"ally_selected", {"cell": u.cell})
		)

	_show_step()

func _show_step() -> void:
	match step:
		Step.INTRO_SELECT:
			_toast("Click an ally to select them.\n\nTip: Left-click selects. Right-click arms attack mode.", "TUTORIAL")
		Step.INTRO_MOVE:
			_toast("Move your selected ally.\n\nTip: Click a green tile to move.", "TUTORIAL")
		Step.INTRO_ATTACK:
			_toast("Attack a zombie.\n\nTip: Right-click to arm ATTACK, then left-click a zombie.", "TUTORIAL")
		Step.FIRST_KILL:
			_toast("Nice. Zombies sometimes drop floppy disks.\n\nThey appear about 1 in 4 kills.\nCollect them to power the beacon.", "TUTORIAL")
		Step.FIRST_PICKUP:
			var need := 3
			if M != null:
				need = int(M.beacon_parts_needed)
			_toast("Pick up a floppy disk by stepping on it.\n\nCollect %d total to arm the beacon." % need, "TUTORIAL")
		Step.BEACON_READY:
			_toast("Beacon armed!\n\nMove an ally onto the beacon tile to upload.", "TUTORIAL")
		Step.BEACON_UPLOAD:
			_toast("Uploading…\n\nSatellite sweep incoming!", "TUTORIAL")
		Step.DONE:
			_hide_toast()

func _toast(msg: String, header: String = "TIP") -> void:
	if toast.has_method("show_message"):
		toast.show_message(msg, header)
	elif toast is CanvasItem:
		toast.visible = true
		if toast.has_node("Label"):
			toast.get_node("Label").text = msg

func _hide_toast() -> void:
	if toast is CanvasItem:
		toast.visible = false

func _advance(to_step: Step) -> void:
	if to_step <= step: return
	step = to_step
	_show_step()


# -------------------------------------------------
# tutorial_event router
# -------------------------------------------------
func _on_tutorial_event(id: StringName, payload: Dictionary) -> void:
	if not enabled:
		return

	match String(id):
		"ally_selected":
			if step == Step.INTRO_SELECT:
				_advance(Step.INTRO_MOVE)
		"ally_moved":
			if step == Step.INTRO_MOVE:
				_advance(Step.INTRO_ATTACK)
		"attack_mode_armed":
			# don't auto-advance, just reinforce if they're stuck
			if step == Step.INTRO_ATTACK:
				_toast("Attack mode armed.\n\nNow left-click a zombie in range.", "TUTORIAL")
		"ally_attacked":
			if step == Step.INTRO_ATTACK:
				_advance(Step.FIRST_KILL)
		"enemy_died":
			if step == Step.FIRST_KILL:
				_advance(Step.FIRST_PICKUP)
		"pickup_collected":
			# If they already have parts, we can keep showing the beacon hint.
			if step == Step.FIRST_PICKUP and M != null:
				var need := int(M.beacon_parts_needed)
				var got := int(M.beacon_parts_collected)
				_toast("Floppy collected: %d/%d\n\nKeep collecting to arm the beacon." % [got, need], "TUTORIAL")
		"beacon_ready":
			if step < Step.BEACON_READY:
				_advance(Step.BEACON_READY)
		"beacon_upload_started":
			if step < Step.BEACON_UPLOAD:
				_advance(Step.BEACON_UPLOAD)
		"satellite_sweep_finished":
			_advance(Step.DONE)
