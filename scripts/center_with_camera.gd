extends TextureRect

@export var screen_offset := Vector2.ZERO  # (+x = right, +y = down)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	position = -size * 0.5

func _process(_delta: float) -> void:
	var vp := get_viewport_rect().size
	global_position = (vp - size) * 0.5 + screen_offset
