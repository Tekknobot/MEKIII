extends Node
## SIGNAL 7 / STORY MODE
## Reveal the REAL campaign's isometric TileMaps. Keep the campaign's units,
## z-layering, UI, selection, special buttons, and alternating combat turns.
## The underlying GridData is generated once for navigation, but its graphics
## stream in as the squad physically enters newly explored cells.

const REVEAL_RADIUS := 5
const SECTOR_SIZE := 6
const REVEAL_FADE_SECONDS := 0.26
const REVEAL_DROP_SECONDS := 0.30
const ZOMBIE_FADE_SECONDS := 0.50
const MAX_STORY_ENEMIES := 16
const RESCUE_SCENES: Array[PackedScene] = [
	preload("res://scenes/units/allies/M1.tscn"),
	preload("res://scenes/units/allies/R1.tscn"),
	preload("res://scenes/units/allies/M2.tscn"),
	preload("res://scenes/units/allies/humantwo.tscn"),
	preload("res://scenes/units/allies/R2.tscn")
]

var game: Game
var board: MapController
var terrain: TileMap
var battle_camera: Camera2D
var protagonist: Unit
var ready_to_explore := false
var discovered: Dictionary = {}
# Only normal squad exploration activates road segments; road-supported tiles
# must not trigger the next road and reveal the whole map in a chain reaction.
var explored_by_squad: Dictionary = {}
var last_ally_cells: Dictionary = {}
var cleared_sectors: Dictionary = {}
var saved_map_cells: Dictionary = {} # TileMap -> {Vector2i: source, atlas, alt}
var road_support_cells: Dictionary = {} # TileMap -> {road cell: all terrain cells under visible road pixels}
var drop_layers: Dictionary = {} # TileMap -> stable-depth container for animated reveal sprites
var hidden_structures: Array[Node2D] = []
var rescue_markers: Dictionary = {} # Vector2i -> {sprite, scene, index, revealed}
var rescued_count := 0
var story_text: Label
var info_text: Label
var story_panel: PanelContainer
var story_notice_time := 0.0
var manual_camera_pan := false
var landed_terrain_cells: Dictionary = {} # Terrain tile has fully finished its reveal animation.

func _ready() -> void:
	game = get_parent() as Game
	board = game.get_node("MapController") as MapController
	terrain = game.get_node("Terrain") as TileMap
	battle_camera = game.get_node("Camera2D") as Camera2D
	# Camera drag is player-driven; don't restore automatic following
	# until a different ally is deliberately selected or F is pressed.
	if battle_camera != null and battle_camera.has_signal("story_manual_pan_started"):
		battle_camera.connect("story_manual_pan_started", Callable(self, "_on_manual_camera_pan"))
	if board != null:
		board.selection_changed.connect(_on_story_selection_changed)

func _on_manual_camera_pan() -> void:
	manual_camera_pan = true

func _on_story_selection_changed(unit: Unit) -> void:
	if unit != null and is_instance_valid(unit) and unit.team == Unit.Team.ALLY:
		manual_camera_pan = false

func _input(event: InputEvent) -> void:
	# Optional deliberate return to the selected squad member.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		manual_camera_pan = false

func prepare_world() -> void:
	# Keep the original campaign TileMaps and source IDs intact. Store the
	# cells before hiding them; Story Mode fades them back in as explored.
	var maps: Array[TileMap] = [terrain, game.roads_dl, game.roads_dr, game.roads_x]
	for tm in maps:
		var original: Dictionary = {}
		for c in tm.get_used_cells(0):
			var id := tm.get_cell_source_id(0, c)
			if id < 0:
				continue
			original[c] = {
				"source": id,
				"atlas": tm.get_cell_atlas_coords(0, c),
				"alternative": tm.get_cell_alternative_tile(0, c)
			}
		saved_map_cells[tm] = original
		if tm != terrain:
			# A 64-pixel road diamond spans MANY 32x16 isometric cells.
			# Check the visible texture footprint, not only its center cell.
			var support_lookup: Dictionary = {}
			for c in original.keys():
				support_lookup[c] = _road_terrain_footprint(tm, c, original[c])
			road_support_cells[tm] = support_lookup
		tm.clear_layer(0)
		_make_drop_layer(tm)

	for child in game.structures_root.get_children():
		if child is Node2D:
			var building := child as Node2D
			building.visible = false
			building.modulate.a = 0.0
			hidden_structures.append(building)

	_build_story_overlay()
	_prepare_rescue_sites()

func _make_drop_layer(tm: TileMap) -> Node2D:
	var existing: Node2D = drop_layers.get(tm) as Node2D
	if existing != null and is_instance_valid(existing):
		return existing
	var layer := Node2D.new()
	layer.name = "StoryTileDrops"
	# Draw behind the TileMap's already-landed cells so a falling tile does
	# not cover terrain that is physically in front of it.
	layer.show_behind_parent = true
	# Sort by the permanent landing anchors, not the animated sprite's Y.
	layer.y_sort_enabled = true
	tm.add_child(layer)
	drop_layers[tm] = layer
	return layer

func _road_terrain_footprint(tm: TileMap, cell: Vector2i, data: Dictionary) -> Dictionary:
	var support: Dictionary = {}
	var source := tm.tile_set.get_source(int(data["source"])) as TileSetAtlasSource
	if source == null or source.texture == null:
		return support
	var image := source.texture.get_image()
	if image == null:
		return support
	var region: Rect2i = source.get_tile_texture_region(data["atlas"])
	var center := Vector2(region.size) * 0.5
	var local_center := tm.map_to_local(cell)
	# Sample the alpha shape of the ORIGINAL road tile, including its tips.
	# Sampling the full 64x64 rectangle instead would needlessly suppress
	# neighboring roads because most of that rectangle is transparent.
	for py in range(0, region.size.y, 3):
		for px in range(0, region.size.x, 3):
			var ix := region.position.x + px
			var iy := region.position.y + py
			if ix < 0 or iy < 0 or ix >= image.get_width() or iy >= image.get_height():
				continue
			if image.get_pixel(ix, iy).a <= 0.05:
				continue
			var sample_world := tm.to_global(local_center + Vector2(float(px) + 0.5, float(py) + 0.5) - center)
			var ground_cell := terrain.local_to_map(terrain.to_local(sample_world))
			# Include out-of-bounds cells in the support set. That keeps road
			# sprites which protrude past the map border hidden in Story Mode.
			support[ground_cell] = true
	return support

func _reveal_supported_roads() -> void:
	# If a road wants terrain that is still hidden, reveal those ground tiles
	# first, then reveal the road after the support has physically landed.
	var pending_terrain: Dictionary = saved_map_cells.get(terrain, {})
	for tm in [game.roads_dl, game.roads_dr, game.roads_x]:
		var pending: Dictionary = saved_map_cells.get(tm, {})
		var footprints: Dictionary = road_support_cells.get(tm, {})
		for road_cell in pending.keys():
			var footprint: Dictionary = footprints.get(road_cell, {})
			if footprint.is_empty():
				continue
			# Do not build faraway roads until the squad has explored a cell
			# within the road's own opaque footprint.
			var near_exploration := false
			for ground_cell in footprint.keys():
				if explored_by_squad.has(ground_cell):
					near_exploration = true
					break
			if not near_exploration:
				continue
			var fully_supported := true
			for ground_cell in footprint.keys():
				# Border roads are allowed to extend beyond the discovered map edge.
				# Only require support terrain for cells that are actually in bounds.
				if not game.grid.in_bounds(ground_cell):
					continue
				if landed_terrain_cells.has(ground_cell):
					continue
				fully_supported = false
				if pending_terrain.has(ground_cell):
					discovered[ground_cell] = true
					_drop_cell(terrain, ground_cell, 0.01)
			if fully_supported:
				_drop_cell(tm, road_cell, 0.04)

func start_story(leader: Unit) -> void:
	protagonist = leader
	if battle_camera != null:
		if battle_camera.has_method("set_follow_enabled"):
			battle_camera.call("set_follow_enabled", false)
		battle_camera.global_position = leader.global_position
	# The starting area is actually uncovered, not a square-tile overlay.
	_reveal_around(leader.cell)
	_show_nearby_structures()
	_show_nearby_rescues(leader.cell)
	last_ally_cells[leader] = leader.cell
	cleared_sectors[_sector_of(leader.cell)] = true
	ready_to_explore = true
	_update_story_overlay()

func _process(delta: float) -> void:
	if not ready_to_explore or board == null:
		return

	# Keep the existing camera and input. Camera focus glides toward the
	# selected ally, rather than the middle of a massive 30x30 map.
	if battle_camera != null and not manual_camera_pan and not bool(battle_camera.get("_enemy_cinematic_active")):
		var subject: Unit = board.selected
		if subject == null or not is_instance_valid(subject) or subject.team != Unit.Team.ALLY:
			subject = protagonist
		if subject != null and is_instance_valid(subject):
			var factor := 1.0 - exp(-7.0 * delta)
			battle_camera.global_position = battle_camera.global_position.lerp(subject.global_position, factor)

	for unit in board.get_all_units():
		if unit == null or not is_instance_valid(unit) or unit.team != Unit.Team.ALLY or unit.hp <= 0:
			continue
		if not last_ally_cells.has(unit) or last_ally_cells[unit] != unit.cell:
			last_ally_cells[unit] = unit.cell
			_reveal_around(unit.cell)
			_show_nearby_structures()
			_show_nearby_rescues(unit.cell)
			_try_rescue(unit.cell)
			_try_spawn_sector_encounter(unit.cell)
	if story_notice_time > 0.0:
		story_notice_time -= delta
		if story_notice_time <= 0.0 and info_text != null:
			info_text.text = "FIND THE LOST UNITS"
			_position_story_panel()
	_update_story_overlay()

func _reveal_around(origin: Vector2i) -> void:
	var reveal_now: Array[Vector2i] = []
	for dy in range(-REVEAL_RADIUS, REVEAL_RADIUS + 1):
		for dx in range(-REVEAL_RADIUS, REVEAL_RADIUS + 1):
			var cell := origin + Vector2i(dx, dy)
			if not game.grid.in_bounds(cell):
				continue
			explored_by_squad[cell] = true
			if discovered.has(cell):
				continue
			discovered[cell] = true
			reveal_now.append(cell)

	# Diamond wave: the closest tiles fade in first, more distant tiles follow.
	reveal_now.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return abs(a.x - origin.x) + abs(a.y - origin.y) < abs(b.x - origin.x) + abs(b.y - origin.y)
	)
	for c in reveal_now:
		var manhattan = abs(c.x - origin.x) + abs(c.y - origin.y)
		_drop_cell(terrain, c, float(manhattan) * 0.025)

	# A newly explored location can activate a road even if all its ground
	# had already been uncovered to support a neighboring road section.
	_reveal_supported_roads()

func _drop_cell(tm: TileMap, cell: Vector2i, delay: float) -> void:
	var originals: Dictionary = saved_map_cells.get(tm, {})
	if not originals.has(cell):
		return
	var data: Dictionary = originals[cell]
	originals.erase(cell)
	var source_id: int = int(data["source"])
	var atlas_cell: Vector2i = data["atlas"]
	var alternative: int = int(data["alternative"])
	var source := tm.tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null:
		tm.set_cell(0, cell, source_id, atlas_cell, alternative)
		if tm == terrain:
			_on_terrain_landed(cell)
		return

	# Anchor at the final isometric grid coordinate for consistent Y-sorting.
	# Story Mode now fades tiles in place instead of dropping them from above.
	var anchor := Node2D.new()
	anchor.position = tm.map_to_local(cell)
	_make_drop_layer(tm).add_child(anchor)

	var sprite := Sprite2D.new()
	sprite.texture = source.texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(source.get_tile_texture_region(atlas_cell))
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.modulate = tm.get_layer_modulate(0)
	sprite.modulate.a = 0.0
	anchor.add_child(sprite)

	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(sprite, "modulate:a", tm.get_layer_modulate(0).a, REVEAL_FADE_SECONDS)
	tw.tween_callback(func() -> void:
		if is_instance_valid(tm):
			tm.set_cell(0, cell, source_id, atlas_cell, alternative)
			if tm == terrain:
				_on_terrain_landed(cell)
		if is_instance_valid(anchor):
			anchor.queue_free()
	)

func _on_terrain_landed(cell: Vector2i) -> void:
	landed_terrain_cells[cell] = true
	_show_nearby_structures()
	_reveal_supported_roads()

func _is_building_ground_complete(building: Node2D) -> bool:
	# set_origin() records the actual terrain footprint. Do not use the tall
	# building sprite's visible center or its screen bounds for this check.
	var base: Vector2i = building.get_meta("origin_cell", Vector2i(-1, -1))
	if not game.grid.in_bounds(base):
		return false
	var footprint: Vector2i = game.building_footprint
	# Require a one-cell shoulder of solid revealed terrain around the
	# footprint, so the base can't hang off the edge of a streaming island.
	for dx in range(-1, footprint.x + 1):
		for dy in range(-1, footprint.y + 1):
			var c := base + Vector2i(dx, dy)
			if not game.grid.in_bounds(c):
				continue
			if not landed_terrain_cells.has(c):
				return false
	return true

func _show_nearby_structures() -> void:
	for building in hidden_structures.duplicate():
		if not is_instance_valid(building):
			hidden_structures.erase(building)
			continue
		if not _is_building_ground_complete(building):
			continue
		hidden_structures.erase(building)
		# Place it at the same original isometric anchor as the campaign;
		# only the opacity animates after the underlying tiles have landed.
		building.visible = true
		building.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(building, "modulate:a", 1.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _prepare_rescue_sites() -> void:
	var center := Vector2i(game.map_width / 2, game.map_height / 2)
	var offsets := [Vector2i(8, 1), Vector2i(-7, 8), Vector2i(-9, -6), Vector2i(7, -8), Vector2i(12, 10)]
	for i in range(mini(RESCUE_SCENES.size(), offsets.size())):
		var base: Vector2i = center + offsets[i]
		base.x = clampi(base.x, 1, game.map_width - 2)
		base.y = clampi(base.y, 1, game.map_height - 2)
		var cell: Vector2i = board._find_nearest_open_walkable(base, {}, 14)
		if cell.x < 0 or rescue_markers.has(cell):
			continue
		var preview := RESCUE_SCENES[i].instantiate() as Unit
		if preview == null:
			continue
		var display := preview.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		var marker := Sprite2D.new()
		if display != null and display.sprite_frames != null:
			var anim := &"idle"
			if not display.sprite_frames.has_animation(anim):
				anim = display.sprite_frames.get_animation_names()[0]
			marker.texture = display.sprite_frames.get_frame_texture(anim, 0)
			marker.position = terrain.map_to_local(cell) + display.position
		else:
			marker.texture = preload("res://sprites/Humans/soldier/idle/soldier_idle1.png")
			marker.position = terrain.map_to_local(cell)
		preview.free()
		marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		marker.z_as_relative = false
		marker.z_index = 1 + cell.x + cell.y
		marker.visible = false
		marker.modulate = Color(0.70, 0.90, 1.0, 0.0)
		game.units_root.add_child(marker)
		rescue_markers[cell] = {"marker": marker, "scene": RESCUE_SCENES[i], "index": i, "revealed": false}

func _show_nearby_rescues(origin: Vector2i) -> void:
	for cell in rescue_markers.keys():
		var entry: Dictionary = rescue_markers[cell]
		if bool(entry["revealed"]):
			continue
		if maxi(abs(cell.x - origin.x), abs(cell.y - origin.y)) > REVEAL_RADIUS:
			continue
		entry["revealed"] = true
		rescue_markers[cell] = entry
		var marker: Sprite2D = entry["marker"]
		marker.visible = true
		var tw := create_tween()
		tw.tween_interval(0.42)
		tw.tween_property(marker, "modulate:a", 1.0, 0.46)

func _try_rescue(origin: Vector2i) -> void:
	for c in rescue_markers.keys():
		var cell: Vector2i = c
		if maxi(abs(cell.x - origin.x), abs(cell.y - origin.y)) > 1:
			continue
		var entry: Dictionary = rescue_markers[cell]
		var marker: Sprite2D = entry["marker"]
		if is_instance_valid(marker):
			marker.queue_free()
		rescue_markers.erase(cell)
		board._spawn_specific_ally(cell, entry["scene"])
		var ally: Unit = board.units_by_cell.get(cell) as Unit
		if ally != null:
			ally.modulate.a = 0.0
			create_tween().tween_property(ally, "modulate:a", 1.0, 0.45)
		rescued_count += 1
		_announce("UNIT %d OF %d RECOVERED" % [rescued_count, RESCUE_SCENES.size()])
		if rescued_count >= RESCUE_SCENES.size():
			_announce("ALL UNITS RECOVERED")

func _sector_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / SECTOR_SIZE), floori(float(cell.y) / SECTOR_SIZE))

func _try_spawn_sector_encounter(origin: Vector2i) -> void:
	var sector := _sector_of(origin)
	if cleared_sectors.has(sector):
		return
	cleared_sectors[sector] = true
	var current_enemies := 0
	for u in board.get_all_units():
		if u != null and is_instance_valid(u) and u.team == Unit.Team.ENEMY and u.hp > 0:
			current_enemies += 1
	if current_enemies >= MAX_STORY_ENEMIES:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(10019 + sector.x * 8917 + sector.y * 13007)
	var candidates: Array[Vector2i] = []
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			var test := origin + Vector2i(dx, dy)
			var distance := maxi(abs(dx), abs(dy))
			if distance < 3 or distance > REVEAL_RADIUS:
				continue
			if not game.grid.in_bounds(test) or not board._is_walkable(test) or board.units_by_cell.has(test):
				continue
			if rescue_markers.has(test):
				continue
			candidates.append(test)
	var count := mini(2 + int(rng.randi() % 2), MAX_STORY_ENEMIES - current_enemies)
	for i in range(count):
		if candidates.is_empty():
			break
		var choice_index := rng.randi_range(0, candidates.size() - 1)
		var cell: Vector2i = candidates[choice_index]
		candidates.remove_at(choice_index)
		if not board._spawn_unit_walkable(cell, Unit.Team.ENEMY):
			continue
		var zombie: Unit = board.units_by_cell.get(cell) as Unit
		if zombie == null:
			continue
		zombie.modulate.a = 0.0
		zombie.set_meta("story_revealing", true)
		# Unit comes in only AFTER its isometric terrain has landed.
		var tw := create_tween()
		tw.tween_interval(0.55 + 0.14 * i)
		tw.tween_property(zombie, "modulate:a", 1.0, ZOMBIE_FADE_SECONDS)
		tw.tween_callback(func() -> void:
			if is_instance_valid(zombie):
				zombie.set_meta("story_revealing", false)
		)

func _build_story_overlay() -> void:
	# Keep the campaign's turn buttons, unit card and enemy HUD. Story-only
	# information gets one compact card at top right, below the MENU button.
	var overlay := CanvasLayer.new()
	overlay.name = "StoryObjectives"
	overlay.layer = 20
	game.add_child(overlay)

	var panel := PanelContainer.new()
	panel.name = "StoryObjectiveCard"
	# No fixed offsets for width/height; PanelContainer derives both
	# dimensions from the text and padding.
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(panel)
	story_panel = panel

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.045, 0.90)
	style.border_color = Color(0.22, 0.31, 0.25, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)

	var padding := MarginContainer.new()
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padding.add_theme_constant_override("margin_left", 16)
	padding.add_theme_constant_override("margin_right", 16)
	padding.add_theme_constant_override("margin_top", 12)
	padding.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(padding)

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 6)
	padding.add_child(stack)

	var font: Font = preload("res://fonts/magofonts/mago2.ttf")
	var heading := Label.new()
	heading.text = "SIGNAL 7"
	heading.add_theme_font_override("font", font)
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Color(0.80, 0.95, 0.80))
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(heading)

	story_text = Label.new()
	story_text.add_theme_font_override("font", font)
	story_text.add_theme_font_size_override("font_size", 20)
	story_text.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	story_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(story_text)

	info_text = Label.new()
	info_text.text = "FIND THE LOST UNITS"
	info_text.add_theme_font_override("font", font)
	info_text.add_theme_font_size_override("font_size", 18)
	info_text.add_theme_color_override("font_color", Color(0.68, 0.78, 0.74))
	info_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(info_text)

	# Re-anchor whenever text content or the viewport changes.
	_position_story_panel()
	get_viewport().size_changed.connect(_position_story_panel)

	# Campaign floppy progression is not Story's win condition; retain the
	# zombie counter while hiding those unrelated meters and tutorial toasts.
	if game.turn_manager != null and is_instance_valid(game.turn_manager):
		var infection: InfestationHUD = game.turn_manager.infestation_hud
		if infection != null and is_instance_valid(infection):
			infection.set_story_mode_ui(true)

func _position_story_panel() -> void:
	if story_panel == null or not is_instance_valid(story_panel):
		return
	story_panel.reset_size()
	var viewport_width := get_viewport().get_visible_rect().size.x
	story_panel.position = Vector2(maxf(8.0, viewport_width - story_panel.size.x - 20.0), 70.0)

func _update_story_overlay() -> void:
	if story_text == null:
		return
	var updated := "SURVIVORS %d OF %d    TILES %d" % [rescued_count, RESCUE_SCENES.size(), discovered.size()]
	if story_text.text != updated:
		story_text.text = updated
		_position_story_panel()

func is_cell_revealed(cell: Vector2i) -> bool:
	return discovered.has(cell)

func is_cell_landed(cell: Vector2i) -> bool:
	return landed_terrain_cells.has(cell)

func is_cell_overlay_visible(cell: Vector2i) -> bool:
	return landed_terrain_cells.has(cell)

func _announce(content: String) -> void:
	if info_text != null:
		info_text.text = content
		story_notice_time = 5.0
		_position_story_panel()
