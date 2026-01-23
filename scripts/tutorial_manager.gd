extends Node
class_name TutorialManager

@export var map_controller_path: NodePath
@export var turn_manager_path: NodePath
@export var toast_path: NodePath   # reference to your toast UI scene/node

@onready var M := get_node(map_controller_path)
@onready var TM := get_node(turn_manager_path)
@onready var toast := get_node(toast_path)

enum Step {
	INTRO_MOVE,
	FIRST_KILL,
	FIRST_PICKUP,
	BEACON_READY,
	BEACON_UPLOAD,
	DONE
}

var step: Step = Step.INTRO_MOVE
var enabled := true

func _ready() -> void:
	if not enabled: return

	# Connect signals from your systems
	if M.has_signal("tutorial_unit_moved"):
		M.tutorial_unit_moved.connect(_on_unit_moved)
	if M.has_signal("tutorial_zombie_died"):
		M.tutorial_zombie_died.connect(_on_zombie_died)
	if M.has_signal("tutorial_pickup_collected"):
		M.tutorial_pickup_collected.connect(_on_pickup_collected)
	if M.has_signal("tutorial_beacon_ready"):
		M.tutorial_beacon_ready.connect(_on_beacon_ready)
	if M.has_signal("tutorial_beacon_upload_started"):
		M.tutorial_beacon_upload_started.connect(_on_beacon_upload_started)

	_show_step()

func _show_step() -> void:
	match step:
		Step.INTRO_MOVE:
			_toast("Move & fight\n• Click an ally to select\n• Move to blue tiles, attack with right-click")
		Step.FIRST_KILL:
			_toast("Zombies drop floppy disks sometimes.\nKill zombies to find parts.")
		Step.FIRST_PICKUP:
			_toast("Collect 3 floppy disks.\nYou need them to arm the beacon.")
		Step.BEACON_READY:
			_toast("Beacon armed!\nMove any ally onto the beacon tile to upload.")
		Step.BEACON_UPLOAD:
			_toast("Uploading…\nSatellite sweep incoming!")
		Step.DONE:
			_hide_toast()

func _toast(msg: String) -> void:
	if toast.has_method("show_message"):
		toast.show_message(msg)
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

# --- Event handlers ---
func _on_unit_moved(u) -> void:
	if step == Step.INTRO_MOVE:
		_advance(Step.FIRST_KILL)

func _on_zombie_died(cell: Vector2i) -> void:
	if step == Step.FIRST_KILL:
		_advance(Step.FIRST_PICKUP)

func _on_pickup_collected(u) -> void:
	if step == Step.FIRST_PICKUP:
		# Don’t force it to wait; beacon-ready is the real next gate
		pass

func _on_beacon_ready() -> void:
	if step < Step.BEACON_READY:
		_advance(Step.BEACON_READY)

func _on_beacon_upload_started() -> void:
	if step < Step.BEACON_UPLOAD:
		_advance(Step.BEACON_UPLOAD)
