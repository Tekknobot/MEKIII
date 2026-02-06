extends ColorRect
class_name MechaApproachShaderController

## Controls the mecha approach shader in sync with dialogue
## Attach this to a ColorRect that covers the screen with the shader material

@export var shader_material: ShaderMaterial

# Timeline segments matching dialogue
enum Phase {
	CALM,           # Before dialogue
	VIBRATION,      # "...do you feel that vibration?"
	SOMETHING_BIG,  # "Something big is moving out there"
	SILHOUETTE,     # "That silhouette... a giant mecha?"
	RETREAT,        # Backing away
	PANIC           # "Bomber, get us out of here!"
}

var current_phase := Phase.CALM

func _ready() -> void:
	if shader_material == null:
		push_warning("MechaApproachShaderController: No shader material assigned")
		return
	
	# Start at calm
	_set_phase(Phase.CALM)

func _set_phase(phase: Phase) -> void:
	current_phase = phase
	
	match phase:
		Phase.CALM:
			_animate_to_calm()
		Phase.VIBRATION:
			_animate_to_vibration()
		Phase.SOMETHING_BIG:
			_animate_to_something_big()
		Phase.SILHOUETTE:
			_animate_to_silhouette()
		Phase.RETREAT:
			_animate_to_retreat()
		Phase.PANIC:
			_animate_to_panic()

# --- Phase Animations ---

func _animate_to_calm() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_method(_set_timeline, 0.0, 0.0, 0.5)
	tween.tween_method(_set_vibration, 0.0, 0.0, 0.5)
	tween.tween_method(_set_silhouette, 0.0, 0.0, 0.5)

func _animate_to_vibration() -> void:
	# Subtle vibration starts - they feel it before seeing anything
	var tween := create_tween().set_parallel(true)
	tween.tween_method(_set_timeline, 0.0, 0.2, 1.2)
	tween.tween_method(_set_vibration, 0.0, 1.5, 1.5).set_ease(Tween.EASE_IN)
	
	# Subtle screen shake
	_start_ground_shake(0.5)

func _animate_to_something_big() -> void:
	# Vibration intensifies, fog rolls in
	var tween := create_tween().set_parallel(true)
	tween.tween_method(_set_timeline, 0.2, 0.45, 2.0)
	tween.tween_method(_set_vibration, 1.5, 3.0, 2.0)
	tween.tween_method(_set_fog_density, 0.3, 0.7, 2.5)
	
	# Stronger shake
	_start_ground_shake(1.0)

func _animate_to_silhouette() -> void:
	# The shape emerges from the fog
	var tween := create_tween().set_parallel(true)
	tween.tween_method(_set_timeline, 0.45, 0.75, 3.0)
	tween.tween_method(_set_silhouette, 0.0, 0.8, 3.5).set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_vibration, 3.0, 4.0, 2.0)
	
	# Environmental distortion from massive presence
	tween.tween_method(_set_heat_distortion, 0.3, 1.2, 3.0)
	tween.tween_method(_set_scale_pressure, 0.1, 0.3, 3.0)
	
	# Heavy shake
	_start_ground_shake(1.5)
	
	# Occasional energy flashes
	_start_energy_flashes()

func _animate_to_retreat() -> void:
	# Backing away - shake continues, silhouette looms
	var tween := create_tween().set_parallel(true)
	tween.tween_method(_set_timeline, 0.75, 0.85, 1.5)
	tween.tween_method(_set_silhouette, 0.8, 1.0, 1.5)
	tween.tween_method(_set_vignette, 0.8, 1.2, 1.5) # Screen closing in
	
	_start_ground_shake(2.0)

func _animate_to_panic() -> void:
	# Maximum intensity - need to escape
	var tween := create_tween().set_parallel(true)
	tween.tween_method(_set_timeline, 0.85, 1.0, 2.0)
	tween.tween_method(_set_vibration, 4.0, 5.0, 1.5)
	tween.tween_method(_set_vignette, 1.2, 1.8, 2.0)
	
	# Severe shake
	_start_ground_shake(3.0)
	
	# More frequent flashes
	_start_energy_flashes(true)

# --- Shader Parameter Setters ---

func _set_timeline(value: float) -> void:
	if shader_material:
		shader_material.set_shader_parameter("timeline", value)

func _set_vibration(value: float) -> void:
	if shader_material:
		shader_material.set_shader_parameter("vibration_intensity", value)

func _set_silhouette(value: float) -> void:
	if shader_material:
		shader_material.set_shader_parameter("silhouette_reveal", value)

func _set_fog_density(value: float) -> void:
	if shader_material:
		shader_material.set_shader_parameter("fog_density", value)

func _set_heat_distortion(value: float) -> void:
	if shader_material:
		shader_material.set_shader_parameter("heat_distortion", value)

func _set_scale_pressure(value: float) -> void:
	if shader_material:
		shader_material.set_shader_parameter("scale_pressure", value)

func _set_vignette(value: float) -> void:
	if shader_material:
		shader_material.set_shader_parameter("vignette_strength", value)

# --- Ground Shake Effect ---

var _shake_tween: Tween

func _start_ground_shake(intensity: float) -> void:
	if _shake_tween:
		_shake_tween.kill()
	
	_shake_tween = create_tween()
	_shake_tween.set_loops()
	
	var shake_duration := 0.05
	var shake_amount := intensity * 0.005
	
	for i in range(20):
		var offset_x := randf_range(-shake_amount, shake_amount)
		var offset_y := randf_range(-shake_amount, shake_amount)
		
		_shake_tween.tween_method(_set_shake_offset, offset_x, offset_y, shake_duration)

func _set_shake_offset(x: float, y: float) -> void:
	if shader_material:
		shader_material.set_shader_parameter("shake_offset_x", x)
		shader_material.set_shader_parameter("shake_offset_y", y)

# --- Energy Flash Effect ---

var _flash_timer: Timer

func _start_energy_flashes(frequent: bool = false) -> void:
	if _flash_timer:
		_flash_timer.queue_free()
	
	_flash_timer = Timer.new()
	add_child(_flash_timer)
	_flash_timer.wait_time = 2.0 if not frequent else 0.8
	_flash_timer.timeout.connect(_do_energy_flash)
	_flash_timer.start()

func _do_energy_flash() -> void:
	if not shader_material:
		return
	
	var tween := create_tween()
	# Flash up
	tween.tween_method(_set_flash_intensity, 0.0, randf_range(0.6, 1.0), 0.1)
	# Flash down
	tween.tween_method(_set_flash_intensity, randf_range(0.6, 1.0), 0.0, 0.3)

func _set_flash_intensity(value: float) -> void:
	if shader_material:
		shader_material.set_shader_parameter("flash_intensity", value)

# --- Public API for Timeline Control ---

func trigger_vibration() -> void:
	_set_phase(Phase.VIBRATION)

func trigger_something_big() -> void:
	_set_phase(Phase.SOMETHING_BIG)

func trigger_silhouette() -> void:
	_set_phase(Phase.SILHOUETTE)

func trigger_retreat() -> void:
	_set_phase(Phase.RETREAT)

func trigger_panic() -> void:
	_set_phase(Phase.PANIC)

func reset_to_calm() -> void:
	_set_phase(Phase.CALM)
	if _flash_timer:
		_flash_timer.queue_free()
		_flash_timer = null
	if _shake_tween:
		_shake_tween.kill()
		_shake_tween = null
