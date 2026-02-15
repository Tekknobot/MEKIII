extends Node2D
class_name Unit

enum Team { ALLY, ENEMY }

signal quirk_triggered(quirk_id: StringName, label: String, color: Color)

# --- Specials base plumbing ---
var special_cd: Dictionary = {} # String -> int turns remaining

@export var display_name: String = ""

@export var team: Team = Team.ALLY
@export var footprint_size: Vector2i = Vector2i(1, 1)

@export var move_range: int = 3
@export var attack_range: int = 3
@export var attack_damage: int = 1

@export var chill_move_penalty: int = 2

@export var tnt_throw_range: int = 0

@export var max_hp: int = 3
@export var hp: int = 3

var cell: Vector2i = Vector2i.ZERO

@export var z_base: int = 1
@export var z_per_cell: int = 1

@export var sprite_path: NodePath = NodePath("Sprite2D")
@onready var spr: Sprite2D = get_node_or_null(sprite_path) as Sprite2D

var _dying := false

@export var sfx_hurt := &"unit_hurt"
@export var sfx_death := &"unit_death"

var _terrain_ref: TileMap = null
@export var death_fx_offset := Vector2.ZERO  # tweak per-unit if needed

var floppy_parts: int = 0
signal died(u: Unit)

@export var visual_offset: Vector2 = Vector2.ZERO

const BLOOD_FX_SCENE := preload("res://scenes/blood_particles.tscn")

func _ready() -> void:
	hp = clamp(hp, 0, max_hp)
	_update_depth()

func set_cell(c: Vector2i, terrain: TileMap) -> void:
	var old := cell
	cell = c
	_terrain_ref = terrain
	if terrain and is_instance_valid(terrain):
		global_position = terrain.to_global(terrain.map_to_local(c))
	_update_depth()
	_apply_visual_offset()

	# ✅ NEW: tell subclasses we teleported/moved cells
	if old != cell and has_method("_on_cell_changed"):
		call("_on_cell_changed")


func _update_depth() -> void:
	z_as_relative = false
	z_index = 1 + (cell.x + cell.y) * z_per_cell

func set_selected(on: bool) -> void:
	if spr:
		spr.modulate = (Color(1, 1, 1) if not on else Color(1.25, 1.25, 1.25))

func take_damage(dmg: int) -> void:
	if _dying:
		return

	if has_meta(&"quirks"):
		var qs: Array = get_meta(&"quirks", [])
		if qs.has(&"reinforced_frame"):
			emit_signal("quirk_triggered", &"reinforced_frame", "ARMOR", QuirkDB.get_color(&"reinforced_frame"))

	hp = max(hp - dmg, 0)	

	# ✅ Hurt sound if still alive
	if hp > 0:
		_play_sfx(sfx_hurt)

	if hp <= 0:
		_die()

func can_use_special(id: String) -> bool:
	return int(special_cd.get(id, 0)) <= 0


func mark_special_used(id: String, cd_turns: int = 1) -> void:
	special_cd[id] = max(0, cd_turns)


func tick_special_cooldowns() -> void:
	for k in special_cd.keys():
		special_cd[k] = max(0, int(special_cd[k]) - 1)

func await_die() -> void:
	# If already dying, just wait a bounded number of frames
	if _dying:
		for i in range(120): # ~2 seconds at 60fps
			if not is_instance_valid(self):
				return
			await get_tree().process_frame
		return

	# Force death, then wait a bounded number of frames
	hp = 0
	_die()

	for i in range(120):
		if not is_instance_valid(self):
			return
		await get_tree().process_frame

func _die() -> void:
	if _dying:
		return
	_dying = true

	_play_sfx(sfx_death)
	emit_signal("died", self)

	# --------------------------------------------------------------------
	# ✅ CRITICAL FIX:
	# If MapController is awaiting a special coroutine on this unit,
	# queue_free() during that await can stall MapController forever.
	# So: play death visuals, cleanup board occupancy, mark pending_free,
	# and let MapController free us safely once the special resolves.
	# --------------------------------------------------------------------
	if has_meta(&"special_lock") and bool(get_meta(&"special_lock")):
		_spawn_blood_fx()

		var a := _get_anim_sprite()
		if a != null and a.sprite_frames != null and a.sprite_frames.has_animation("death"):
			a.sprite_frames.set_animation_loop("death", false)
			a.stop()

			var apply_offset := not (self is Zombie) and not (self is Human) and not (self is HumanTwo)
			var prev_pos := a.position
			if apply_offset:
				a.position = prev_pos + Vector2(0, -16)

			a.play("death")
			await a.animation_finished

			if apply_offset and is_instance_valid(a):
				a.position = prev_pos
		else:
			await _play_death_anim_fallback()

		var MC := get_tree().get_first_node_in_group("MapController")
		if MC != null and MC.has_method("_cleanup_dead_at"):
			MC.call("_cleanup_dead_at", cell)

		set_meta(&"pending_free", true)
		return

	# ✅ EliteMech: custom death sequence (wait, then free)
	if self is EliteMech and has_method("play_death_anim"):
		# Remove from board occupancy immediately (but DO NOT free yet)
		var M := get_tree().get_first_node_in_group("MapController")
		if M != null and M.has_method("_cleanup_dead_at"):
			M.call("_cleanup_dead_at", cell)

		# Run custom anim + wait for finish signal
		call("play_death_anim")
		if has_signal("death_anim_finished"):
			await self.death_anim_finished

		# Now it's safe to actually free
		if is_instance_valid(self):
			queue_free()
		return

	# --- Everyone else ---
	_spawn_blood_fx()

	var a2 := _get_anim_sprite()
	if a2 != null and a2.sprite_frames != null and a2.sprite_frames.has_animation("death"):
		a2.sprite_frames.set_animation_loop("death", false)
		a2.stop()

		var apply_offset2 := not (self is Zombie) and not (self is Human) and not (self is HumanTwo)
		var prev_pos2 := a2.position
		if apply_offset2:
			a2.position = prev_pos2 + Vector2(0, -16)

		a2.play("death")
		await a2.animation_finished

		if apply_offset2:
			a2.position = prev_pos2

		queue_free()
		return

	await _play_death_anim_fallback()

	var MC2 := get_tree().get_first_node_in_group("MapController")
	if MC2 != null and MC2.has_method("_cleanup_dead_at"):
		MC2.call("_cleanup_dead_at", cell)

	queue_free()

func _play_death_anim_fallback() -> void:
	var ci: CanvasItem = null

	if spr != null:
		ci = spr
	else:
		# grab any CanvasItem child (Sprite2D, AnimatedSprite2D, etc.)
		for ch in get_children():
			if ch is CanvasItem:
				ci = ch as CanvasItem
				break

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD)
	tw.set_ease(Tween.EASE_OUT)

	# Fade (if we found a CanvasItem)
	if ci != null:
		var m := ci.modulate
		tw.tween_property(ci, "modulate", Color(m.r, m.g, m.b, 0.0), 0.18)

	# Shrink the node slightly
	tw.parallel().tween_property(self, "scale", scale * 0.85, 0.18)

	await tw.finished

func get_special_range(id: String) -> int:
	return 0

func _play_sfx(cue: StringName) -> void:
	var tree := get_tree()
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return

	var M := tree.get_first_node_in_group("MapController")
	if M == null:
		return
	if not M.has_method("_sfx"):
		return

	M.call("_sfx", cue, 1.0, randf_range(0.95, 1.05), global_position)

func get_move_range() -> int:
	var r := move_range

	# Stim bonus
	if has_meta(&"stim_turns") and int(get_meta(&"stim_turns", 0)) > 0:
		r += int(get_meta(&"stim_move_bonus", 0))

	# Chill penalty (default to 1 if not set)
	var chilled := int(get_meta(&"chilled_turns", 0))
	if chilled > 0:
		var pen := int(get_meta(&"chill_move_penalty", chill_move_penalty))
		r -= pen

	return max(1, r)


func get_attack_damage() -> int:
	var d: int = int(attack_damage)

	# turns
	var turns := 0
	if has_meta("stim_turns"):
		var t = get_meta("stim_turns")
		if t != null and (typeof(t) == TYPE_INT or typeof(t) == TYPE_FLOAT or typeof(t) == TYPE_STRING):
			turns = int(t)

	if turns > 0:
		# bonus
		var bonus := 0
		if has_meta("stim_damage_bonus"):
			var b = get_meta("stim_damage_bonus")
			if b != null and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT or typeof(b) == TYPE_STRING):
				bonus = int(b)

		d += bonus

	return d

func get_tile_world_pos() -> Vector2:
	if _terrain_ref != null and is_instance_valid(_terrain_ref):
		return _terrain_ref.to_global(_terrain_ref.map_to_local(cell))
	return global_position

func get_display_name() -> String:
	if display_name.strip_edges() != "":
		return display_name
	if has_meta("display_name"):
		var m = get_meta("display_name")
		if m != null and str(m).strip_edges() != "":
			return str(m)
	return name

func get_portrait_texture() -> Texture2D:
	# 1) Try exported var on subclasses (safe even if missing)
	var v = get("portrait_tex")
	if v is Texture2D:
		return v

	# 2) Meta fallback
	var m = get_meta("portrait_tex") if has_meta("portrait_tex") else null
	if m is Texture2D:
		return m

	# 3) Optional: fallback to thumbnail
	var t = get("thumbnail")
	if t is Texture2D:
		return t

	return null

func get_thumbnail_texture() -> Texture2D:
	# 1) exported var on subclasses
	if "thumbnail" in self:
		var v = get("thumbnail")
		if v is Texture2D:
			return v

	# 2) meta fallback
	if has_meta("thumbnail"):
		var m = get_meta("thumbnail")
		if m is Texture2D:
			return m

	# 3) fallback to portrait
	return get_portrait_texture()

func _get_render_canvas_item() -> CanvasItem:
	# Try common names first
	var spr := get_node_or_null("Sprite2D")
	if spr is CanvasItem:
		return spr
	var anim := get_node_or_null("AnimatedSprite2D")
	if anim is CanvasItem:
		return anim

	# Fallback: first CanvasItem child
	for ch in get_children():
		if ch is CanvasItem:
			return ch
	return null

func _apply_visual_offset() -> void:
	var ci: CanvasItem = _get_render_canvas_item()
	if ci != null and is_instance_valid(ci):
		ci.position = visual_offset

func _spawn_blood_fx() -> void:
	# Only enemies bleed (change if you want allies to bleed too)
	if team != Team.ENEMY:
		return

	# ✅ EliteMech should NOT spawn blood puff / small explosion
	if self is EliteMech:
		return

	if BLOOD_FX_SCENE == null:
		return
		
	var fx := BLOOD_FX_SCENE.instantiate() as Node2D
	if fx == null:
		return

	# Iso "feet" position
	fx.global_position = global_position + death_fx_offset + Vector2(0, -16)

	# Add to same parent so depth sorting feels right
	if get_parent() != null:
		get_parent().add_child(fx)
	else:
		get_tree().current_scene.add_child(fx)

	# Slightly above the unit
	fx.z_index = z_index + 1

func _get_anim_sprite() -> AnimatedSprite2D:
	# Common names you’ve used
	for p in ["AnimatedSprite2D", "Animate", "Aniamte"]:
		var n := get_node_or_null(p)
		if n is AnimatedSprite2D:
			return n as AnimatedSprite2D

	# Otherwise find the first AnimatedSprite2D anywhere under this unit
	var found := find_child("", true, false)
	# (find_child can’t filter by type directly; we scan)
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var cur = stack.pop_back()
		for ch in cur.get_children():
			if ch is AnimatedSprite2D:
				return ch as AnimatedSprite2D
			if ch is Node:
				stack.append(ch)
	return null

func _get_map_controller() -> Node:
	return get_tree().get_first_node_in_group("MapController")

func get_quirk_ids() -> Array[StringName]:
	# Quirks are stored as metadata by QuirkDB.apply_to_unit()
	var qs: Array = get_meta(&"quirks", []) if has_meta(&"quirks") else []
	var out: Array[StringName] = []
	for q in qs:
		if q == null:
			continue
		out.append(StringName(str(q)))
	return out

func has_quirks() -> bool:
	return get_quirk_ids().size() > 0

func get_quirks_text() -> String:
	var qs := get_quirk_ids()
	if qs.is_empty():
		return ""
	return QuirkDB.describe_list(qs)

func get_hud_extras() -> Dictionary:
	var d := {}
	var qs: Array = get_meta(&"quirks", []) if has_meta(&"quirks") else []
	if qs.size() > 0:
		d["Quirks"] = QuirkDB.describe_list(qs)
	return d
