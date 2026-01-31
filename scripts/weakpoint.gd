extends Unit
class_name Weakpoint

signal took_hit(dmg: int)

# -------------------------
# Hurt flash (on hit)
# -------------------------
@export var hurt_flash_time := 0.10
@export var hurt_flash_color := Color(1, 0.25, 0.25, 1)

var _hurt_tw: Tween = null
var _base_modulate: Color = Color(1, 1, 1, 1)

# -------------------------
# Suppress FX (twitch + flash while suppress_turns > 0)
# -------------------------
@export var suppress_twitch_strength := 0.6
@export var suppress_twitch_interval := 0.016
@export var suppress_flash_strength := 1.35

var _suppress_tw: Tween = null
var _suppress_base_pos: Vector2
var _suppress_base_modulate: Color = Color(1, 1, 1, 1)
var _suppress_active := false

# --- add near the top (with your other vars) ---
var _removed_from_grid := false

func _ready() -> void:
	# Identity (metas used by your UI)
	if not has_meta("display_name"):
		set_meta("display_name", "Boss Zombie")
	if not has_meta("portrait_tex"):
		set_meta("portrait_tex", preload("res://sprites/Portraits/zombie_port.png"))

	# ✅ behave like an enemy / zombie in your systems
	team = Unit.Team.ENEMY

	# ✅ vision used by your TurnManager vision check
	if not has_meta("vision"):
		set_meta("vision", 8) # tweak

	footprint_size = Vector2i(1, 1)
	move_range = 4
	attack_range = 1
	attack_damage = 1

	max_hp = max(1, max_hp)
	hp = clamp(hp, 0, max_hp)

	super._ready()

	# Cache base visuals for flashes + suppress restore
	_suppress_base_pos = global_position
	var ci := _get_render_item()
	if ci != null:
		_base_modulate = ci.modulate
		_suppress_base_modulate = ci.modulate
	else:
		_base_modulate = Color(1, 1, 1, 1)
		_suppress_base_modulate = Color(1, 1, 1, 1)


func take_damage(amount: int) -> void:
	super.take_damage(amount)

	emit_signal("took_hit", amount)

	if hp > 0:
		_flash_hurt()
	else:
		# If we died, notify boss (ONCE)
		_notify_boss_once()

		# ✅ remove occupancy from MapController grid
		_remove_from_grid()

		# Optional: if Unit doesn't already queue_free on death, do it here
		# queue_free()


# -------------------------
# Grid removal
# -------------------------
func _remove_from_grid() -> void:
	if _removed_from_grid:
		return
	_removed_from_grid = true

	# Try to find MapController
	var M := _find_map_controller()
	if M == null or not is_instance_valid(M):
		return

	# If MapController stores units by cell, clear only if it's actually us
	# (prevents nuking another unit that moved into the cell)
	if M.units_by_cell.has(cell) and M.units_by_cell[cell] == self:
		M.units_by_cell.erase(cell)

	# Optional: if you have other occupancy dicts, clear here too
	# e.g. M._bubble_by_unit.erase(self) etc.


func _find_map_controller() -> Node:
	# 1) If you already stash it somewhere, use that first (best)
	# if M != null: return M

	# 2) Group-based lookup (recommend: put MapController in group "MapController")
	var mc := get_tree().get_first_node_in_group("MapController")
	if mc != null:
		return mc

	# 3) Fallback: walk up parents until we find one named "MapController"
	var p := get_parent()
	while p != null:
		if p is Node and p.get_class() == "MapController":
			return p
		p = p.get_parent()

	return null

func _process(delta: float) -> void:
	# Only twitch while suppressed
	var turns := 0
	if has_meta("suppress_turns"):
		turns = int(get_meta("suppress_turns"))

	var want := turns > 0

	if want and not _suppress_active:
		_suppress_active = true
		_start_suppress_twitch()
	elif (not want) and _suppress_active:
		_suppress_active = false
		_stop_suppress_twitch()

	# keep base position updated when NOT suppressed (so movement doesn't fight twitch)
	if not _suppress_active:
		_suppress_base_pos = global_position

# -------------------------
# Boss notify
# -------------------------
func _notify_boss_once() -> void:
	if has_meta("boss_notified_dead") and bool(get_meta("boss_notified_dead")):
		return
	set_meta("boss_notified_dead", true)

	# Only notify if this is actually marked as boss part
	if not (has_meta("is_boss_part") and bool(get_meta("is_boss_part"))):
		return

	var part_id: StringName = get_meta("boss_part_id", &"") as StringName
	var boss_dmg: int = int(get_meta("boss_damage_on_destroy", 0))

	# Find BossController via group (simple + reliable)
	var boss := get_tree().get_first_node_in_group("BossController")
	if boss != null and is_instance_valid(boss) and boss.has_method("on_weakpoint_destroyed"):
		boss.call("on_weakpoint_destroyed", part_id, boss_dmg)

# -------------------------
# Hurt flash FX
# -------------------------
func _flash_hurt() -> void:
	var ci := _get_render_item()
	if ci == null:
		return

	if _hurt_tw != null and is_instance_valid(_hurt_tw):
		_hurt_tw.kill()

	_hurt_tw = create_tween()
	_hurt_tw.tween_property(ci, "modulate", hurt_flash_color, hurt_flash_time * 0.5)
	_hurt_tw.tween_property(ci, "modulate", _base_modulate, hurt_flash_time * 0.5)

# -------------------------
# Suppress twitch FX
# -------------------------
func _start_suppress_twitch() -> void:
	_stop_suppress_twitch() # safety

	_suppress_base_pos = global_position

	var ci := _get_render_item()
	if ci != null:
		_suppress_base_modulate = ci.modulate
	else:
		_suppress_base_modulate = Color(1, 1, 1, 1)

	_suppress_tw = create_tween()
	_suppress_tw.set_loops() # infinite
	_suppress_tw.set_trans(Tween.TRANS_SINE)
	_suppress_tw.set_ease(Tween.EASE_IN_OUT)

	var step = max(0.04, suppress_twitch_interval)

	# jitter + brighten
	_suppress_tw.tween_callback(func():
		if not is_instance_valid(self): return

		global_position = _suppress_base_pos + Vector2(
			randf_range(-suppress_twitch_strength, suppress_twitch_strength),
			randf_range(-suppress_twitch_strength, suppress_twitch_strength)
		)

		var cii := _get_render_item()
		if cii != null and is_instance_valid(cii):
			var base := _suppress_base_modulate
			cii.modulate = Color(
				min(base.r * suppress_flash_strength, 2.0),
				min(base.g * suppress_flash_strength, 2.0),
				min(base.b * suppress_flash_strength, 2.0),
				base.a
			)
	)

	_suppress_tw.tween_interval(step * 0.5)

	# return to base + restore color
	_suppress_tw.tween_callback(func():
		if not is_instance_valid(self): return
		global_position = _suppress_base_pos

		var cii := _get_render_item()
		if cii != null and is_instance_valid(cii):
			cii.modulate = _suppress_base_modulate
	)

	_suppress_tw.tween_interval(step * 0.5)

func _stop_suppress_twitch() -> void:
	if _suppress_tw != null and is_instance_valid(_suppress_tw):
		_suppress_tw.kill()
	_suppress_tw = null

	# restore
	global_position = _suppress_base_pos
	var ci := _get_render_item()
	if ci != null and is_instance_valid(ci):
		ci.modulate = _suppress_base_modulate

# -------------------------
# Render item helper
# -------------------------
func _get_render_item() -> CanvasItem:
	# Try common names first, then any CanvasItem child
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	if spr != null:
		return spr
	var anim := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim != null:
		return anim
	for ch in get_children():
		if ch is CanvasItem:
			return ch as CanvasItem
	return null

func _on_cell_changed() -> void:
	# re-anchor twitch to current cell position
	_suppress_base_pos = global_position

	# if currently suppressed, restart tween so it jitters around the NEW cell
	if _suppress_active:
		_start_suppress_twitch()
