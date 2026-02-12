@tool
extends AnimatedSprite2D

@export var param_name := "sprite_tex"

func _ready() -> void:
	_update_shader_tex()
	if sprite_frames:
		frame_changed.connect(_update_shader_tex)
		animation_changed.connect(_update_shader_tex)

func _update_shader_tex() -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		return
	if sprite_frames == null:
		return

	var tex := sprite_frames.get_frame_texture(animation, frame)
	if tex == null:
		return

	mat.set_shader_parameter(param_name, tex)
