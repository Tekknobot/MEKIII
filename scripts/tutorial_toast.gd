extends CanvasLayer
class_name TutorialToast

# Assign these in the Inspector
@export var panel_path: NodePath
@export var title_path: NodePath
@export var body_path: NodePath

# Optional auto-hide (0 = stay visible until replaced/hidden)
@export var auto_hide_seconds := 0.0

var panel: Control
var title: Label
var body: RichTextLabel
var _tw: Tween


func _ready() -> void:
	panel = get_node_or_null(panel_path) as Control
	title = get_node_or_null(title_path) as Label
	body  = get_node_or_null(body_path) as RichTextLabel

	# --- Validation prints (so you instantly know what’s wrong) ---
	if panel == null:
		push_error("TutorialToast: panel_path not set or not a Control node.")
	if title == null:
		push_error("TutorialToast: title_path not set or not a Label node.")
	if body == null:
		push_error("TutorialToast: body_path not set or not a RichTextLabel node.")

	# Safe initialization
	if panel != null:
		panel.visible = false
		panel.modulate.a = 0.0


# ---------------------------------------------------
# Show a toast message
# ---------------------------------------------------
func show_message(text: String, header: String = "TIP") -> void:
	# Hard guard against missing references
	if panel == null or title == null or body == null:
		push_warning("TutorialToast.show_message(): Missing node references. Check NodePaths.")
		return

	# Assign text safely
	title.text = header
	body.bbcode_enabled = true
	body.text = text

	panel.visible = true

	# Kill existing tween if running
	if _tw != null and is_instance_valid(_tw):
		_tw.kill()

	# --- Slide + fade in ---
	var end_pos := panel.position
	var start_pos := end_pos + Vector2(-14, 0)

	panel.position = start_pos
	panel.modulate.a = 0.0

	_tw = create_tween()
	_tw.set_trans(Tween.TRANS_QUAD)
	_tw.set_ease(Tween.EASE_OUT)

	_tw.tween_property(panel, "position", end_pos, 0.18)
	_tw.parallel().tween_property(panel, "modulate:a", 1.0, 0.18)

	# Optional auto-hide
	if auto_hide_seconds > 0.0:
		_tw.tween_interval(auto_hide_seconds)
		_tw.tween_property(panel, "modulate:a", 0.0, 0.18)
		_tw.tween_callback(func():
			if panel != null:
				panel.visible = false
		)


# ---------------------------------------------------
# Force hide immediately
# ---------------------------------------------------
func hide_now() -> void:
	if _tw != null and is_instance_valid(_tw):
		_tw.kill()

	if panel != null:
		panel.visible = false
		panel.modulate.a = 0.0
