extends Node2D
class_name OverworldRadar

@export var label_font: Font
@export var label_font_size: int = 12
@export var label_alpha: float = 0.20

signal mission_requested(node_id: int, node_type: int, difficulty: float)

var current_node_id: int = -1
var hovered_node_id: int = -1
@export var restrict_to_neighbors := true

# ✅ Fade-in settings
@export var fade_in_enabled := true
@export var fade_in_duration := 1

# -------------------------
# SETTINGS
# -------------------------
@export var grid_size: int = 9                 # 9x9
@export var spacing: float = 64.0              # pixels between lattice points
var origin: Vector2

@export var remove_ratio: float = 0.33         # % nodes removed (voids)
@export var extra_links_chance: float = 0.0   # add a few diagonals sometimes
@export var seed_value: int = 0                # 0 = random

# Radar look
@export var ring_count: int = 5
@export var sweep_speed: float = 1.2           # radians/sec
@export var sweep_width: float = 0.22          # radians (wedge width)
@export var sweep_falloff: float = 0.9         # brightness drop across wedge

# Node look
@export var node_radius: float = 7.0
@export var boss_radius: float = 12.0
@export var pulse_speed: float = 3.0
@export var jitter_px: float = 0.8             # CRT jitter
@export var draw_labels: bool = true           # shows tiny labels

# Packets (little dots moving along edges)
@export var packets_enabled: bool = true
@export var packet_count: int = 18
@export var packet_speed: float = 0.35         # edge fraction per second

signal node_selected(node_id: int)
signal node_enter_requested(node_id: int)

@export var squad_title_text := "CURRENT SQUAD"
@export var squad_title_font_size := 32
@export var squad_title_font: Font
@export var title_scene_path: String = "res://scenes/title_screen.tscn"
@export var squad_scene_path: String = "res://scenes/squad_deploy_screen.tscn"
@export var back_button_text := "Back"

@export var back_button_font_size := 16
@export var back_button_font: Font

@export var elite_node_count: int = 2          # how many ELITE nodes total
@export var elite_min_difficulty: float = 0.70 # only place ELITEs late in the route
@export var elite_min_bfs_gap: int = 2         # keep ELITEs from clustering

var elite_ids: Array[int] = []                # optional: for debugging / reference

# -------------------------
# DATA
# -------------------------
enum NodeType { START, COMBAT, SUPPLY, ELITE, EVENT, BOSS }

class NodeData:
	var id: int
	var gx: int
	var gy: int
	var pos: Vector2
	var neighbors: Array[int] = []
	var difficulty: float = 0.0 # 0..1
	var ntype: int = NodeType.COMBAT
	var cleared: bool = false

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var alive: Array[bool] = []                 # bool array size N
var nodes: Array[NodeData] = []
var edges: Array[Vector2i] = []             # (a,b) where a<b

var start_id: int = -1
var boss_id: int = -1

var sweep_angle: float = 0.0
var time_sec: float = 0.0

# Packet dict: {"a":int, "b":int, "t":float, "dir":int}
var packets: Array[Dictionary] = []

var _font: Font = null

# -------------------------
# SQUAD HUD (top-left)
# -------------------------
@export var squad_hud_enabled := true
@export var squad_hud_padding := Vector2(16, 16)
@export var squad_chip_size := Vector2(44, 44)
@export var squad_portrait_size := Vector2(40, 40)
@export var squad_thumb_size := Vector2(18, 18)
@export var squad_show_names := false
@export var squad_name_font_size := 12
@export var squad_name_font: Font

var _hud_layer: CanvasLayer = null
var _hud_panel: PanelContainer = null
var _hud_row: HBoxContainer = null

@export var boss_node_count: int = 3          # total boss nodes including the farthest one
@export var boss_min_difficulty: float = 0.70 # only place bosses late in the route
@export var boss_min_bfs_gap: int = 2         # keep bosses from clustering

@export var cheat_event_key_enabled := true

const LINEAR_ROUTE := [
	NodeType.START,
	NodeType.COMBAT,
	NodeType.EVENT,
	NodeType.COMBAT,
	NodeType.SUPPLY,
	NodeType.COMBAT,
	NodeType.ELITE,
	NodeType.COMBAT,
	NodeType.BOSS,
]

# -------------------------
# LIFECYCLE
# -------------------------
func _ready() -> void:
	# ✅ Start invisible if fade-in enabled
	if fade_in_enabled:
		modulate = Color(1, 1, 1, 0)
	
	set_process_input(true)
	set_process_unhandled_input(true)
		
	var rs: Node = _rs()

	# --- seed ---Current node highlight
	if rs != null:
		if int(rs.overworld_seed) == 0:
			rs.overworld_seed = int(Time.get_unix_time_from_system()) ^ randi()
		rng.seed = int(rs.overworld_seed)
	else:
		rng.randomize()

	origin = get_viewport_rect().size * 0.5
	_font = label_font if label_font != null else ThemeDB.fallback_font

	_generate_world()

	# --- restore state ---
	if rs != null:
		# cleared nodes
		for k in rs.overworld_cleared.keys():
			var id: int = int(k)
			if id >= 0 and id < nodes.size():
				nodes[id].cleared = true

		# current node (or default to start)
		var saved_id: int = int(rs.overworld_current_node_id)
		if saved_id >= 0 and saved_id < nodes.size():
			current_node_id = saved_id
		else:
			current_node_id = start_id
			rs.overworld_current_node_id = current_node_id
	else:
		current_node_id = start_id

	_debug_counts()
	_ensure_current_is_alive(rs)
	_build_packets()
	queue_redraw()

	if squad_hud_enabled:
		_build_squad_hud()
		await _refresh_squad_hud()  # ✅ Add await here
	
	# ✅ Fade in after everything is set up
	if fade_in_enabled:
		await _fade_in()

func _fade_in() -> void:
	var tween := create_tween()
	tween.set_parallel(true)  # Fade all elements together
	
	# Fade in the radar (this node)
	tween.tween_property(self, "modulate:a", 1.0, fade_in_duration)
	
	# Fade in the squad HUD panel
	if _hud_panel != null and is_instance_valid(_hud_panel):
		tween.tween_property(_hud_panel, "modulate:a", 1.0, fade_in_duration)
	
	# ✅ Fade in each squad chip
	if _hud_row != null and is_instance_valid(_hud_row):
		for chip in _hud_row.get_children():
			if is_instance_valid(chip):
				tween.tween_property(chip, "modulate:a", 1.0, fade_in_duration)
	
	await tween.finished

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B:
			_cheat_clear_path_to_nearest_boss()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E:
			_cheat_clear_path_to_nearest_elite()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_S:
			_cheat_clear_path_to_nearest_supply()
			get_viewport().set_input_as_handled()

func _rs() -> Node:
	var rs := get_tree().root.get_node_or_null("RunStateNode")
	if rs != null:
		return rs
	return get_tree().root.get_node_or_null("RunState") # fallback only

func _process(delta: float) -> void:
	time_sec += delta
	sweep_angle = fposmod(sweep_angle + sweep_speed * delta, TAU)

	# Move packets
	if packets_enabled and packets.size() > 0:
		for p in packets:
			p["t"] = float(p.get("t", 0.0)) + packet_speed * delta * float(int(p.get("dir", 1)))
			var tt: float = float(p["t"])
			if tt >= 1.0:
				p["t"] = 1.0
				p["dir"] = -1
			elif tt <= 0.0:
				p["t"] = 0.0
				p["dir"] = 1

	queue_redraw()

func _input(event: InputEvent) -> void:
	if not cheat_event_key_enabled:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_V:
			_cheat_clear_path_to_nearest_event()
				
	if event is InputEventMouseMotion:
		var hit := _pick_node(get_global_mouse_position())
		hovered_node_id = hit if _can_click_node(hit) else -1
		return

	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit: int = _pick_node(get_global_mouse_position())
		if hit < 0:
			return
		if not _can_click_node(hit):
			return

		if hit == current_node_id and not nodes[current_node_id].cleared:
			var rs := _rs()
			if rs != null:
				rs.mission_node_id = hit
				rs.mission_difficulty = nodes[hit].difficulty
				rs.mission_node_type = StringName(_type_name(nodes[hit].ntype).to_lower())
				rs.boss_mode_enabled_next_mission = (nodes[hit].ntype == NodeType.BOSS)
				rs.overworld_current_node_id = hit
			emit_signal("mission_requested", hit, nodes[hit].ntype, nodes[hit].difficulty)
			return

		_move_to_node(hit)
		return

	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if current_node_id >= 0 and not nodes[current_node_id].cleared:
				var rs := _rs()
				if rs != null:
					rs.mission_node_id = current_node_id
					rs.mission_difficulty = nodes[current_node_id].difficulty
					rs.mission_node_type = StringName(_type_name(nodes[current_node_id].ntype).to_lower())
					rs.boss_mode_enabled_next_mission = (nodes[current_node_id].ntype == NodeType.BOSS)
					rs.overworld_current_node_id = current_node_id

				emit_signal("mission_requested", current_node_id, nodes[current_node_id].ntype, nodes[current_node_id].difficulty)
				return

func _cheat_clear_path_to_nearest_elite() -> void:
	if current_node_id < 0 or current_node_id >= nodes.size():
		return

	# Find nearest elite and a parent map from BFS
	var result := _bfs_to_nearest_elite(current_node_id)
	var elite_target: int = int(result.get("elite", -1))
	var parent: Dictionary = result.get("parent", {})

	if elite_target < 0:
		print("CHEAT: No reachable uncleared ELITE found.")
		return

	# Reconstruct path from elite back to current node
	var path: Array[int] = []
	var cur := elite_target
	while cur != current_node_id and parent.has(cur):
		path.append(cur)
		cur = int(parent[cur])
	path.append(current_node_id)
	path.reverse() # now current -> ... -> elite

	# Clear everything along the path EXCEPT the elite node itself
	var rs := _rs()
	for id in path:
		if id == elite_target:
			continue
		if id < 0 or id >= nodes.size():
			continue
		nodes[id].cleared = true
		if rs != null and ("overworld_cleared" in rs):
			rs.overworld_cleared[str(id)] = true

	# Jump current selection onto the elite node (leave it uncleared so it can launch)
	current_node_id = elite_target
	hovered_node_id = -1

	if rs != null:
		rs.overworld_current_node_id = current_node_id

	print("CHEAT: Cleared path to elite node ", elite_target)

	_build_packets()
	queue_redraw()

	if squad_hud_enabled:
		_refresh_squad_hud()

func _cheat_clear_path_to_nearest_event() -> void:
	if current_node_id < 0 or current_node_id >= nodes.size():
		return

	# Find nearest event and a parent map from BFS
	var result := _bfs_to_nearest_event(current_node_id)
	var event_target: int = int(result.get("event", -1))
	var parent: Dictionary = result.get("parent", {})

	if event_target < 0:
		print("CHEAT: No reachable uncleared EVENT found.")
		return

	# Reconstruct path from event back to current node
	var path: Array[int] = []
	var cur := event_target
	while cur != current_node_id and parent.has(cur):
		path.append(cur)
		cur = int(parent[cur])
	path.append(current_node_id)
	path.reverse() # now current -> ... -> event

	# Clear everything along the path EXCEPT the event node itself
	var rs := _rs()
	for id in path:
		if id == event_target:
			continue
		if id < 0 or id >= nodes.size():
			continue
		nodes[id].cleared = true
		if rs != null and ("overworld_cleared" in rs):
			rs.overworld_cleared[str(id)] = true

	# Jump current selection onto the event node (leave it uncleared so it can launch)
	current_node_id = event_target
	hovered_node_id = -1

	if rs != null:
		rs.overworld_current_node_id = current_node_id

	print("CHEAT: Cleared path to event node ", event_target)

	_build_packets()
	queue_redraw()

	if squad_hud_enabled:
		_refresh_squad_hud()

func _bfs_to_nearest_event(start_id: int) -> Dictionary:
	var q: Array[int] = []
	var visited: Dictionary = {}
	var parent: Dictionary = {}

	q.append(start_id)
	visited[start_id] = true

	while not q.is_empty():
		var cur = q.pop_front()

		# ✅ target: reachable + uncleared + EVENT
		if cur != start_id and cur >= 0 and cur < nodes.size():
			if (not nodes[cur].cleared) and (nodes[cur].ntype == OverworldRadar.NodeType.EVENT):
				return {"event": cur, "parent": parent}

		# Explore neighbors (this is your adjacency list)
		if cur < 0 or cur >= nodes.size():
			continue

		for nxt in nodes[cur].neighbors:
			var ni := int(nxt)
			if visited.has(ni):
				continue

			if ni < 0 or ni >= nodes.size():
				continue
			if nodes[ni].cleared:
				continue

			visited[ni] = true
			parent[ni] = cur
			q.append(ni)

	return {"event": -1, "parent": parent}

func _bfs_to_nearest_elite(src: int) -> Dictionary:
	var parent: Dictionary = {}
	var seen: Dictionary = {}
	var q: Array[int] = []

	seen[src] = true
	q.append(src)

	while not q.is_empty():
		var cur: int = q.pop_front()

		# Found nearest reachable uncleared elite
		if nodes[cur].ntype == NodeType.ELITE and not nodes[cur].cleared:
			return {"elite": cur, "parent": parent}

		for nb in nodes[cur].neighbors:
			if nb < 0 or nb >= nodes.size():
				continue
			if not alive[nb]:
				continue
			# allow traversing cleared nodes
			if seen.has(nb):
				continue

			seen[nb] = true
			parent[nb] = cur
			q.append(nb)

	return {"elite": -1, "parent": parent}
				
func _cheat_clear_path_to_nearest_boss() -> void:
	if current_node_id < 0 or current_node_id >= nodes.size():
		return

	print("CHEAT DEBUG current=", current_node_id,
		" alive=", (current_node_id >= 0 and current_node_id < alive.size() and alive[current_node_id]),
		" type=", _type_name(nodes[current_node_id].ntype),
		" cleared=", nodes[current_node_id].cleared)


	# Find nearest boss and a parent map from BFS
	var result := _bfs_to_nearest_boss(current_node_id)
	var boss_target: int = int(result.get("boss", -1))
	var parent: Dictionary = result.get("parent", {})

	if boss_target < 0:
		print("CHEAT: No reachable uncleared boss found.")
		return

	# Reconstruct path from boss back to start node
	var path: Array[int] = []
	var cur := boss_target
	while cur != current_node_id and parent.has(cur):
		path.append(cur)
		cur = int(parent[cur])
	path.append(current_node_id)
	path.reverse() # now current -> ... -> boss

	# Clear everything along the path EXCEPT the boss node itself
	var rs := _rs()
	for id in path:
		if id == boss_target:
			continue
		if id < 0 or id >= nodes.size():
			continue
		nodes[id].cleared = true
		if rs != null and ("overworld_cleared" in rs):
			rs.overworld_cleared[str(id)] = true

	# Jump current selection onto the boss node (leave it uncleared so it can launch)
	current_node_id = boss_target
	hovered_node_id = -1

	if rs != null:
		rs.overworld_current_node_id = current_node_id

	print("CHEAT: Cleared path to boss node ", boss_target)

	_build_packets()
	queue_redraw()

	if squad_hud_enabled:
		_refresh_squad_hud()

func _bfs_to_nearest_boss(src: int) -> Dictionary:
	var parent: Dictionary = {}
	var seen: Dictionary = {}
	var q: Array[int] = []

	seen[src] = true
	q.append(src)

	while not q.is_empty():
		var cur: int = q.pop_front()

		# Found nearest reachable uncleared boss
		if nodes[cur].ntype == NodeType.BOSS and not nodes[cur].cleared:
			return {"boss": cur, "parent": parent}

		for nb in nodes[cur].neighbors:
			if nb < 0 or nb >= nodes.size():
				continue
			if not alive[nb]:
				continue
			if nodes[nb].cleared:
				# still allow traversing cleared nodes (path should include them)
				pass
			if seen.has(nb):
				continue

			seen[nb] = true
			parent[nb] = cur
			q.append(nb)

	return {"boss": -1, "parent": parent}

func _can_click_node(id: int) -> bool:
	if id < 0 or id >= nodes.size():
		return false
	if not alive[id]:
		return false
	if current_node_id < 0 or current_node_id >= nodes.size():
		return false

	# If current node NOT cleared: only it is clickable (launch)
	if not nodes[current_node_id].cleared:
		return id == current_node_id

	# Current node IS cleared: normally, only neighbors are clickable (move)
	if _has_uncleared_neighbor(current_node_id):
		# allow moving onto cleared neighbors too (so you can backtrack)
		return nodes[current_node_id].neighbors.has(id)

	# DEAD END CASE:
	# no uncleared neighbors — let the player click ANY reachable uncleared node
	return _is_reachable_uncleared(current_node_id, id)

func _move_to_node(id: int) -> void:
	if id == current_node_id:
		return

	current_node_id = id

	var rs: Node = _rs()
	if rs != null:
		rs.overworld_current_node_id = current_node_id


# -------------------------
# GENERATION
# -------------------------
func _generate_world() -> void:
	nodes.clear()
	edges.clear()

	var n: int = grid_size * grid_size
	alive.resize(n)
	for i in range(n):
		alive[i] = true

	# Create node positions
	for gy in range(grid_size):
		for gx in range(grid_size):
			var id: int = gy * grid_size + gx
			var nd: NodeData = NodeData.new()
			nd.id = id
			nd.gx = gx
			nd.gy = gy
			nd.pos = origin + Vector2((float(gx) - float(grid_size - 1) * 0.5) * spacing,
									  (float(gy) - float(grid_size - 1) * 0.5) * spacing)
			nodes.append(nd)

	# Carve voids but keep connectivity
	_carve_voids_connected()

	# Build adjacency (4-neighbor)
	_rebuild_graph()

	# Choose start (prefer top-left-ish)
	start_id = _find_nearest_alive()
	if start_id < 0:
		start_id = _find_any_alive()

	# Boss = farthest reachable from start
	boss_id = _farthest_from(start_id)

	# ✅ Keep only ONE constellation: the start->boss route
	var path := _path_start_to_boss()
	if not path.is_empty():
		# If you want EXACTLY your sequence length, trim:
		if path.size() > LINEAR_ROUTE.size():
			path = path.slice(0, LINEAR_ROUTE.size())
			boss_id = int(path[path.size() - 1])
		_keep_only_path_constellation(path)

	# Recompute difficulty on the constellation
	_assign_difficulty_from(start_id)

	# Apply your linear route types on that path
	_assign_linear_route_types()

	current_node_id = start_id

func _carve_voids_connected() -> void:
	var n: int = grid_size * grid_size
	var target_remove: int = int(round(float(n) * remove_ratio))

	# Never remove too many: keep at least ~half
	target_remove = clampi(target_remove, 0, n - int(float(n) * 0.55))

	var candidates: Array[int] = []
	candidates.resize(n)
	for id in range(n):
		candidates[id] = id

	# IMPORTANT: don't use candidates.shuffle() (global RNG)
	_rng_shuffle_int(candidates)

	var removed: int = 0
	for id in candidates:
		if removed >= target_remove:
			break

		alive[id] = false

		# Keep a minimum number of nodes
		if _count_alive() < 8:
			alive[id] = true
			continue

		# Only accept this removal if graph stays connected
		if _is_connected():
			removed += 1
		else:
			alive[id] = true

func _rebuild_graph() -> void:
	edges.clear() # ✅ IMPORTANT: clear edges so _add_edge can repopulate neighbors

	for nd in nodes:
		nd.neighbors.clear()

	# Add edges (4-neighbor)
	for gy in range(grid_size):
		for gx in range(grid_size):
			var a: int = gy * grid_size + gx
			if not alive[a]:
				continue

			_try_link(a, gx + 1, gy) # right
			_try_link(a, gx, gy + 1) # down

	# Optional extra diagonal links
	for gy in range(grid_size - 1):
		for gx in range(grid_size - 1):
			if rng.randf() > extra_links_chance:
				continue
			var a: int = gy * grid_size + gx
			var b: int = (gy + 1) * grid_size + (gx + 1)
			if alive[a] and alive[b]:
				_add_edge(a, b)

func _try_link(a: int, gx: int, gy: int) -> void:
	if gx < 0 or gy < 0 or gx >= grid_size or gy >= grid_size:
		return
	var b: int = gy * grid_size + gx
	if not alive[b]:
		return
	_add_edge(a, b)

func _add_edge(a: int, b: int) -> void:
	if a == b:
		return
	var lo: int = min(a, b)
	var hi: int = max(a, b)
	var e: Vector2i = Vector2i(lo, hi)
	if edges.has(e):
		return
	edges.append(e)
	nodes[lo].neighbors.append(hi)
	nodes[hi].neighbors.append(lo)

func _count_alive() -> int:
	var c: int = 0
	for v in alive:
		if v:
			c += 1
	return c

func _find_any_alive() -> int:
	for i in range(alive.size()):
		if alive[i]:
			return i
	return -1

func _find_nearest_alive() -> int:
	var best: int = -1
	var best_score: int = 1_000_000
	for nd in nodes:
		if not alive[nd.id]:
			continue
		var score: int = nd.gx + nd.gy
		if score < best_score:
			best_score = score
			best = nd.id
	return best

func _is_connected() -> bool:
	var start: int = _find_any_alive()
	if start < 0:
		return true

	var seen: Dictionary = {}
	var q: Array[int] = [start]
	seen[start] = true

	while not q.is_empty():
		var cur: int = q.pop_front()
		var gx: int = cur % grid_size
		var gy: int = int(cur / grid_size)

		var neigh: Array[Vector2i] = [
			Vector2i(gx + 1, gy), Vector2i(gx - 1, gy),
			Vector2i(gx, gy + 1), Vector2i(gx, gy - 1)
		]

		for p in neigh:
			if p.x < 0 or p.y < 0 or p.x >= grid_size or p.y >= grid_size:
				continue
			var nid: int = p.y * grid_size + p.x
			if not alive[nid]:
				continue
			if not seen.has(nid):
				seen[nid] = true
				q.append(nid)

	return seen.size() == _count_alive()

func _farthest_from(src: int) -> int:
	var dist: Dictionary = _bfs_dist(src)
	var best: int = src
	var best_d: int = -1
	for k in dist.keys():
		var d: int = int(dist[k])
		if d > best_d:
			best_d = d
			best = int(k)
	return best

func _assign_difficulty_from(src: int) -> void:
	var dist: Dictionary = _bfs_dist(src)
	var max_d: int = 1
	for k in dist.keys():
		max_d = max(max_d, int(dist[k]))

	for nd in nodes:
		if not alive[nd.id]:
			nd.difficulty = -1.0
			continue
		var d: int = int(dist.get(nd.id, 0))
		nd.difficulty = clamp(float(d) / float(max_d), 0.0, 1.0)

func _bfs_dist(src: int) -> Dictionary:
	var dist: Dictionary = {}
	if src < 0 or not alive[src]:
		return dist

	var q: Array[int] = [src]
	dist[src] = 0

	while not q.is_empty():
		var cur: int = q.pop_front()
		var cd: int = int(dist[cur])

		for nb in nodes[cur].neighbors:
			if not alive[nb]:
				continue
			if not dist.has(nb):
				dist[nb] = cd + 1
				q.append(nb)

	return dist

func _assign_types() -> void:
	# baseline
	for nd in nodes:
		if not alive[nd.id]:
			continue
		nd.ntype = NodeType.COMBAT

	# Force start/boss
	if start_id >= 0:
		nodes[start_id].ntype = NodeType.START
	if boss_id >= 0:
		nodes[boss_id].ntype = NodeType.BOSS

	for nd in nodes:
		if not alive[nd.id]:
			continue
		if nd.id == start_id:
			continue
		if nd.id == boss_id:
			continue
		if nd.ntype == NodeType.BOSS:
			continue

		var d := clampf(nd.difficulty, 0.0, 1.0)

		# -------------------------
		# Difficulty-gated weights
		# -------------------------
		# early: lots of SUPPLY, few ELITE, some EVENT
		# mid:   more EVENT, some ELITE, some SUPPLY
		# late:  more ELITE, fewer SUPPLY/EVENT
		var w_supply := lerpf(0.30, 0.08, d)  # 30% -> 8%
		var w_event  := lerpf(0.10, 0.14, d)  # 10% -> 14% (slightly more mid/late)
		var w_elite  := lerpf(0.04, 0.28, d)  # 4%  -> 28%

		# Optional: avoid upgrades right next to the boss (feels weird)
		if d > 0.85:
			w_supply *= 0.35
			w_event  *= 0.50

		# Remaining probability becomes COMBAT
		var w_combat = max(0.0, 1.0 - (w_supply + w_event + w_elite))

		# -------------------------
		# Roll
		# -------------------------
		var r := rng.randf()
		if r < w_supply:
			nd.ntype = NodeType.SUPPLY
		elif r < w_supply + w_event:
			nd.ntype = NodeType.EVENT
		elif r < w_supply + w_event + w_elite:
			nd.ntype = NodeType.ELITE
		else:
			nd.ntype = NodeType.COMBAT

# -------------------------
# PACKETS
# -------------------------
func _build_packets() -> void:
	packets.clear()
	if not packets_enabled:
		return
	if edges.is_empty():
		return

	for i in range(packet_count):
		var e: Vector2i = edges[rng.randi_range(0, edges.size() - 1)]
		var d: int = 1
		if rng.randf() < 0.5:
			d = -1

		packets.append({
			"a": int(e.x),
			"b": int(e.y),
			"t": rng.randf(),
			"dir": d
		})

# -------------------------
# DRAWING
# -------------------------
func _draw() -> void:
	# CRT jitter
	var jx: float = rng.randf_range(-jitter_px, jitter_px)
	var jy: float = rng.randf_range(-jitter_px, jitter_px)
	var jitter: Vector2 = Vector2(jx, jy)

	_draw_radar_background(jitter)
	_draw_edges(jitter)
	_draw_packets(jitter)
	_draw_nodes(jitter)

func _draw_radar_background(jitter: Vector2) -> void:
	var rmax: float = spacing * float(grid_size) * 0.55

	# rings
	for i in range(1, ring_count + 1):
		var rr: float = rmax * float(i) / float(ring_count)
		draw_arc(origin + jitter, rr, 0.0, TAU, 96, Color(0.2, 1.0, 0.2, 0.10), 2.0)

	# crosshair
	draw_line(origin + jitter + Vector2(-rmax, 0), origin + jitter + Vector2(rmax, 0), Color(0.2, 1.0, 0.2, 0.10), 2.0)
	draw_line(origin + jitter + Vector2(0, -rmax), origin + jitter + Vector2(0, rmax), Color(0.2, 1.0, 0.2, 0.10), 2.0)

	# sweep wedge (fan lines)
	var steps: int = 26
	for s in range(steps):
		var tt: float = float(s) / float(max(1, steps - 1))
		var ang: float = sweep_angle - sweep_width * 0.5 + sweep_width * tt
		var alpha: float = 0.22 * pow(1.0 - abs(tt - 0.5) * 2.0, sweep_falloff)
		var col: Color = Color(0.3, 1.0, 0.3, alpha)
		var endp: Vector2 = origin + jitter + Vector2(cos(ang), sin(ang)) * rmax
		draw_line(origin + jitter, endp, col, 2.0)

func _draw_edges(jitter: Vector2) -> void:
	for e in edges:
		var a: int = int(e.x)
		var b: int = int(e.y)
		if not alive[a] or not alive[b]:
			continue

		var pa: Vector2 = nodes[a].pos + jitter
		var pb: Vector2 = nodes[b].pos + jitter
		var mid: Vector2 = (pa + pb) * 0.5
		var ang: float = (mid - (origin + jitter)).angle()
		var glow: float = _sweep_glow(ang)

		var base: float = 0.08
		var col: Color = Color(0.2, 1.0, 0.2, base + 0.22 * glow)
		draw_line(pa, pb, col, 2.0)

func _draw_packets(jitter: Vector2) -> void:
	if not packets_enabled:
		return

	for p in packets:
		var a: int = int(p.get("a", -1))
		var b: int = int(p.get("b", -1))
		if a < 0 or b < 0:
			continue
		if not alive[a] or not alive[b]:
			continue

		var tt: float = float(p.get("t", 0.0))
		var pos: Vector2 = nodes[a].pos.lerp(nodes[b].pos, tt) + jitter

		var ang: float = (pos - (origin + jitter)).angle()
		var glow: float = _sweep_glow(ang)
		var col: Color = Color(0.4, 1.0, 0.4, 0.20 + 0.55 * glow)

		draw_circle(pos, 3.0, col)

func _draw_nodes(jitter: Vector2) -> void:
	var pulse: float = 0.5 + 0.5 * sin(time_sec * pulse_speed)

	# draw in enum order
	for t in [NodeType.START, NodeType.COMBAT, NodeType.SUPPLY, NodeType.ELITE, NodeType.EVENT, NodeType.BOSS]:
		for nd in nodes:
			if not alive[nd.id]:
				continue
			if nd.ntype != t:
				continue

			var pos: Vector2 = nd.pos + jitter
			var ang: float = (pos - (origin + jitter)).angle()
			var glow: float = _sweep_glow(ang)

			var r: float = node_radius
			var col: Color = Color(0.2, 1.0, 0.2, 0.18 + 0.32 * glow)

			match nd.ntype:
				NodeType.START:
					r = node_radius + 2.0
					col = Color(0.4, 1.0, 0.4, 0.30 + 0.45 * glow)
				NodeType.SUPPLY:
					col = Color(0.4, 1.0, 0.4, 0.14 + 0.38 * glow)
				NodeType.EVENT:
					col = Color(0.3, 1.0, 0.8, 0.14 + 0.38 * glow)
				NodeType.ELITE:
					col = Color(1.0, 0.7, 0.2, 0.14 + 0.38 * glow)
				NodeType.BOSS:
					r = boss_radius
					col = Color(1.0, 0.3, 0.3, 0.16 + 0.55 * glow)
				_:
					pass

			if nd.ntype != NodeType.BOSS and nd.ntype != NodeType.START:
				col.a += 0.10 * nd.difficulty

			# Cleared nodes: dim + hollow + pure white X
			if nd.cleared:
				col.a *= 0.35
				draw_circle(pos, r + 2.0, Color(col.r, col.g, col.b, col.a * 0.40))
				draw_circle(pos, r - 1.0, Color(0.0, 0.0, 0.0, col.a * 0.22))
				var xx := r * 0.85
				var xcol := Color(1.0, 1.0, 1.0, 1.0)
				draw_line(pos + Vector2(-xx, -xx), pos + Vector2(xx, xx), xcol, 2.0)
				draw_line(pos + Vector2(-xx, xx),  pos + Vector2(xx, -xx), xcol, 2.0)

			# Current node highlight
			if nd.id == current_node_id:
				draw_circle(pos, r + 6.0, Color(0.6, 1.0, 0.6, 0.20 + 0.35 * glow))

			# Hover highlight (only if allowed)
			if nd.id == hovered_node_id and _can_click_node(nd.id):
				draw_circle(pos, r + 4.0, Color(1.0, 1.0, 1.0, 0.10 + 0.20 * glow))

			draw_circle(pos, r, col)
			draw_circle(pos, max(2.0, r * 0.35), Color(col.r, col.g, col.b, 0.10 + 0.18 * pulse))

			if draw_labels and _font != null:
				draw_string(
					_font,
					pos + Vector2(r + 4, -r - 4),
					"%s %s" % [
						_type_name(nd.ntype),
						_difficulty_tier_name(nd.difficulty)
					],
					HORIZONTAL_ALIGNMENT_LEFT, -1,
					label_font_size,
					Color(0.2, 1.0, 0.2, label_alpha)
				)


func _difficulty_tier_name(d: float) -> String:
	if d < 0.25:
		return "I"
	elif d < 0.50:
		return "II"
	elif d < 0.75:
		return "III"
	else:
		return "IV"

func _sweep_glow(angle: float) -> float:
	var d: float = abs(wrapf(angle - sweep_angle, -PI, PI))
	var half: float = sweep_width * 0.5
	if d > half:
		return 0.0
	return pow(1.0 - (d / max(0.0001, half)), 1.6)

# -------------------------
# PICKING
# -------------------------
func _pick_node(world_pos: Vector2) -> int:
	var best: int = -1
	var best_d: float = 999999.0

	for nd in nodes:
		if not alive[nd.id]:
			continue

		var d: float = world_pos.distance_to(nd.pos)

		var rr: float = node_radius
		if nd.id == boss_id:
			rr = boss_radius

		if d <= rr + 6.0 and d < best_d:
			best_d = d
			best = nd.id

	return best

func _type_name(t: int) -> String:
	match t:
		NodeType.START:
			return "START"
		NodeType.COMBAT:
			return "COMBAT"
		NodeType.SUPPLY:
			return "SUPPLY"
		NodeType.ELITE:
			return "ELITE"
		NodeType.EVENT:
			return "EVENT"
		NodeType.BOSS:
			return "BOSS"
	return "?"

func _rng_shuffle_int(arr: Array[int]) -> void:
	# Fisher–Yates shuffle using THIS radar's rng (deterministic with rng.seed)
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

func _build_squad_hud() -> void:
	# Kill old if reloading
	if _hud_layer != null and is_instance_valid(_hud_layer):
		_hud_layer.queue_free()
	_hud_layer = null
	_hud_panel = null
	_hud_row = null

	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "SquadHUD"
	add_child(_hud_layer)

	_hud_panel = PanelContainer.new()
	_hud_panel.name = "Panel"
	_hud_layer.add_child(_hud_panel)

	# anchor top-left with padding
	_hud_panel.anchor_left = 0.0
	_hud_panel.anchor_top = 0.0
	_hud_panel.anchor_right = 0.0
	_hud_panel.anchor_bottom = 0.0
	_hud_panel.position = squad_hud_padding

	var margin := MarginContainer.new()
	margin.name = "Margin"
	_hud_panel.add_child(margin)

	# padding inside panel
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)

	# ✅ stack: title -> chips row -> back button
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.name = "Title"
	title.text = squad_title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_font_size_override("font_size", squad_title_font_size)

	# choose font (prefer explicit title font, else squad_name_font, else label_font)
	if squad_title_font != null:
		title.add_theme_font_override("font", squad_title_font)
	elif squad_name_font != null:
		title.add_theme_font_override("font", squad_name_font)
	elif label_font != null:
		title.add_theme_font_override("font", label_font)

	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	vbox.add_child(title)

	# Chips row
	_hud_row = HBoxContainer.new()
	_hud_row.name = "Row"
	_hud_row.add_theme_constant_override("separation", 8)
	vbox.add_child(_hud_row)

	# Back button
	var back := Button.new()
	back.add_theme_font_size_override("font_size", back_button_font_size)

	if back_button_font != null:
		back.add_theme_font_override("font", back_button_font)
	elif squad_name_font != null:
		back.add_theme_font_override("font", squad_name_font)
	elif label_font != null:
		back.add_theme_font_override("font", label_font)
	
	back.name = "BackButton"
	back.text = back_button_text
	back.pressed.connect(_on_back_pressed)
	vbox.add_child(back)

func _on_back_pressed() -> void:
	if squad_scene_path == "" or not ResourceLoader.exists(squad_scene_path):
		push_warning("OverworldRadar: squad_scene_path missing or invalid: " + squad_scene_path)
		return
	get_tree().change_scene_to_file(squad_scene_path)

func _refresh_squad_hud() -> void:
	if _hud_row == null or not is_instance_valid(_hud_row):
		return

	for ch in _hud_row.get_children():
		ch.queue_free()
	await get_tree().process_frame

	var rs := _rs()
	if rs == null:
		print("HUD: rs is null")
		return

	# ✅ always try to read squad_scene_paths safely
	var raw := _get_array_prop(rs, &"squad_scene_paths")

	print("HUD: squad_scene_paths size=", raw.size(), " value=", raw)

	var paths: Array[String] = []
	for p_any in raw:
		var p := ""
		if p_any is PackedScene:
			p = (p_any as PackedScene).resource_path
		else:
			p = str(p_any)

		if p != "" and ResourceLoader.exists(p):
			paths.append(p)

	if paths.is_empty():
		print("HUD: no valid paths after filtering (missing files or empty array)")
		return

	for p in paths:
		var chip := await _make_squad_chip(p)
		if fade_in_enabled:
			chip.modulate = Color(1, 1, 1, 0)
		_hud_row.add_child(chip)
	
func _make_squad_chip(scene_path: String) -> Control:
	var chip := VBoxContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_constant_override("separation", 4)
	chip.alignment = BoxContainer.ALIGNMENT_CENTER

	var psize: Vector2 = squad_portrait_size * 2.0
	var tsize: Vector2 = squad_thumb_size * 2.0

	# --- Portrait ---
	var portrait := TextureRect.new()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = psize
	chip.add_child(portrait)

	# --- Thumb under portrait ---
	var thumb := TextureRect.new()
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.custom_minimum_size = tsize
	chip.add_child(thumb)

	# --- Display name under thumb ---
	if squad_show_names:
		var name_label := Label.new()
		name_label.name = "NameLabel"
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		# Apply chosen font if provided
		if squad_name_font != null:
			name_label.add_theme_font_override("font", squad_name_font)

		name_label.add_theme_font_size_override("font_size", squad_name_font_size)

		# default radar-green tint (still editable later)
		name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))

		chip.add_child(name_label)


	# --- Load visuals from unit scene ---
	var vis := await _read_unit_visuals(scene_path)
	portrait.texture = vis.get("portrait", null)
	thumb.texture = vis.get("thumb", null)

	if squad_show_names:
		var nl := chip.get_node("NameLabel") as Label
		if nl:
			nl.text = str(vis.get("name", ""))

	return chip

func _read_unit_visuals(scene_path: String) -> Dictionary:
	var out := {"portrait": null, "thumb": null, "name": ""}

	if scene_path == "" or not ResourceLoader.exists(scene_path):
		return out

	var ps := load(scene_path) as PackedScene
	if ps == null:
		return out

	var inst := ps.instantiate()
	if inst == null:
		return out

	var u := _find_unit_in_tree(inst)
	if u == null:
		u = inst  # fallback

	# Prefer your Unit getters if present
	if u.has_method("get_portrait_texture"):
		out["portrait"] = u.call("get_portrait_texture")
	else:
		out["portrait"] = _get_prop_if_exists(u, "portrait_tex")

	if u.has_method("get_thumbnail_texture"):
		out["thumb"] = u.call("get_thumbnail_texture")
	else:
		out["thumb"] = _get_prop_if_exists(u, "thumbnail")

	if u.has_method("get_display_name"):
		out["name"] = str(u.call("get_display_name"))
	else:
		out["name"] = str(_get_prop_if_exists(u, "display_name"))

	# Meta fallback
	if out["portrait"] == null and u.has_meta("portrait_tex"):
		out["portrait"] = u.get_meta("portrait_tex")
	if out["thumb"] == null and u.has_meta("thumbnail"):
		out["thumb"] = u.get_meta("thumbnail")
	if (out["name"] == null or str(out["name"]) == "") and u.has_meta("display_name"):
		out["name"] = str(u.get_meta("display_name"))

	if out["name"] == null or str(out["name"]) == "":
		out["name"] = u.name

	inst.queue_free()
	return out

func _find_unit_in_tree(n: Node) -> Node:
	if n == null:
		return null
	# your Unit tends to have these
	if n.has_method("get_display_name") and n.has_method("get_portrait_texture"):
		return n
	if ("hp" in n) and ("max_hp" in n) and n.has_method("take_damage"):
		return n
	for ch in n.get_children():
		var u := _find_unit_in_tree(ch)
		if u != null:
			return u
	return null

func _get_prop_if_exists(obj: Object, prop: StringName) -> Variant:
	# Checks actual properties (includes exported vars)
	for p in obj.get_property_list():
		# p is a Dictionary; "name" key exists
		if StringName(p.get("name", "")) == prop:
			return obj.get(prop)
	return null

func _bfs_distance_between(a: int, b: int) -> int:
	if a == b:
		return 0
	if a < 0 or b < 0:
		return -1
	if a >= nodes.size() or b >= nodes.size():
		return -1
	if not alive[a] or not alive[b]:
		return -1

	var q: Array[int] = [a]
	var dist: Dictionary = {}
	dist[a] = 0

	while not q.is_empty():
		var cur: int = q.pop_front()
		var cd: int = int(dist[cur])

		for nb in nodes[cur].neighbors:
			if not alive[nb]:
				continue
			if dist.has(nb):
				continue
			dist[nb] = cd + 1
			if nb == b:
				return cd + 1
			q.append(nb)

	return -1

func _ensure_current_is_alive(rs: Node) -> void:
	# If current is invalid or dead, fall back to start if alive, else any alive node.
	if current_node_id < 0 or current_node_id >= nodes.size() or not alive[current_node_id]:
		if start_id >= 0 and start_id < nodes.size() and alive[start_id]:
			current_node_id = start_id
		else:
			current_node_id = _find_any_alive()

		if rs != null:
			rs.overworld_current_node_id = current_node_id

func _debug_counts() -> void:
	var bosses_total := 0
	var bosses_uncleared := 0
	var elites_total := 0
	var elites_uncleared := 0

	for nd in nodes:
		if not alive[nd.id]:
			continue

		if nd.ntype == NodeType.BOSS:
			bosses_total += 1
			if not nd.cleared:
				bosses_uncleared += 1

		if nd.ntype == NodeType.ELITE:
			elites_total += 1
			if not nd.cleared:
				elites_uncleared += 1

	print("DEBUG bosses total=", bosses_total, " uncleared=", bosses_uncleared,
		" | elites total=", elites_total, " uncleared=", elites_uncleared)

func _cheat_clear_path_to_nearest_supply() -> void:
	if current_node_id < 0 or current_node_id >= nodes.size():
		return

	var result := _bfs_to_nearest_supply(current_node_id)
	var supply_target: int = int(result.get("supply", -1))
	var parent: Dictionary = result.get("parent", {})

	if supply_target < 0:
		print("CHEAT: No reachable uncleared SUPPLY found.")
		return

	# Reconstruct path from supply back to current
	var path: Array[int] = []
	var cur := supply_target
	while cur != current_node_id and parent.has(cur):
		path.append(cur)
		cur = int(parent[cur])
	path.append(current_node_id)
	path.reverse() # current -> ... -> supply

	# Clear everything along the path EXCEPT the supply node itself
	var rs := _rs()
	for id in path:
		if id == supply_target:
			continue
		if id < 0 or id >= nodes.size():
			continue
		nodes[id].cleared = true
		if rs != null and ("overworld_cleared" in rs):
			rs.overworld_cleared[str(id)] = true

	# Jump onto the supply node (leave it uncleared so it can be clicked)
	current_node_id = supply_target
	hovered_node_id = -1

	if rs != null:
		rs.overworld_current_node_id = current_node_id
		if rs.has_method("save_to_disk"):
			rs.call("save_to_disk")

	print("CHEAT: Cleared path to supply node ", supply_target)

	_build_packets()
	queue_redraw()

	if squad_hud_enabled:
		_refresh_squad_hud()


func _bfs_to_nearest_supply(start_id: int) -> Dictionary:
	var q: Array[int] = []
	var visited: Dictionary = {}
	var parent: Dictionary = {}

	q.append(start_id)
	visited[start_id] = true

	while not q.is_empty():
		var cur: int = q.pop_front()

		# ✅ target: reachable + uncleared + SUPPLY (not the starting node)
		if cur != start_id and cur >= 0 and cur < nodes.size():
			if (not nodes[cur].cleared) and (nodes[cur].ntype == NodeType.SUPPLY):
				return {"supply": cur, "parent": parent}

		if cur < 0 or cur >= nodes.size():
			continue

		for nxt in nodes[cur].neighbors:
			var ni := int(nxt)
			if visited.has(ni):
				continue
			if ni < 0 or ni >= nodes.size():
				continue
			if not alive[ni]:
				continue

			# NOTE: unlike your event BFS, we allow walking through cleared nodes
			# (because the whole point is to clear a path quickly)
			visited[ni] = true
			parent[ni] = cur
			q.append(ni)

	return {"supply": -1, "parent": parent}

func _path_start_to_boss() -> Array[int]:
	var parent: Dictionary = {}
	var q: Array[int] = [start_id]
	parent[start_id] = -1

	while not q.is_empty():
		var cur: int = q.pop_front()
		if cur == boss_id:
			break
		for nb in nodes[cur].neighbors:
			if not alive[nb]:
				continue
			if parent.has(nb):
				continue
			parent[nb] = cur
			q.append(nb)

	if not parent.has(boss_id):
		return []

	# reconstruct
	var path: Array[int] = []
	var cur := boss_id
	while cur != -1:
		path.append(cur)
		cur = int(parent[cur])
	path.reverse()
	return path

func _has_uncleared_neighbor(from_id: int) -> bool:
	if from_id < 0 or from_id >= nodes.size():
		return false
	for nb in nodes[from_id].neighbors:
		if nb < 0 or nb >= nodes.size():
			continue
		if not alive[nb]:
			continue
		if not nodes[nb].cleared:
			return true
	return false


func _is_reachable_uncleared(src: int, target: int) -> bool:
	# BFS that can traverse alive nodes (cleared or not),
	# but target must be alive + uncleared.
	if src < 0 or src >= nodes.size():
		return false
	if target < 0 or target >= nodes.size():
		return false
	if not alive[target]:
		return false
	if nodes[target].cleared:
		return false

	var q: Array[int] = [src]
	var seen: Dictionary = {}
	seen[src] = true

	while not q.is_empty():
		var cur = q.pop_front()
		if cur == target:
			return true

		for nb in nodes[cur].neighbors:
			if nb < 0 or nb >= nodes.size():
				continue
			if not alive[nb]:
				continue
			if seen.has(nb):
				continue
			# allow walking through cleared nodes to escape dead ends
			seen[nb] = true
			q.append(nb)

	return false

func get_center_world() -> Vector2:
	# origin is in radar-local coordinates; convert to world
	return to_global(origin)

func get_node_world_pos(id: int) -> Vector2:
	if id < 0 or id >= nodes.size():
		return get_center_world()
	return to_global(nodes[id].pos)

func _assign_linear_route_types() -> void:
	# Baseline everything to COMBAT (alive only)
	for nd in nodes:
		if not alive[nd.id]:
			continue
		nd.ntype = NodeType.COMBAT

	# Ensure start/boss exist
	if start_id >= 0 and start_id < nodes.size() and alive[start_id]:
		nodes[start_id].ntype = NodeType.START
	if boss_id >= 0 and boss_id < nodes.size() and alive[boss_id]:
		nodes[boss_id].ntype = NodeType.BOSS

	# Get path start -> boss
	var path := _path_start_to_boss()
	if path.is_empty():
		return

	# Apply pattern along the path (truncate if path shorter)
	var L = min(path.size(), LINEAR_ROUTE.size())

	for i in range(L):
		var id := path[i]
		if id < 0 or id >= nodes.size():
			continue
		if not alive[id]:
			continue
		nodes[id].ntype = LINEAR_ROUTE[i]

	# Force the final to be BOSS if we reached the end of the path
	var last := path[path.size() - 1]
	if last >= 0 and last < nodes.size() and alive[last]:
		nodes[last].ntype = NodeType.BOSS

func _keep_only_path_constellation(path: Array[int]) -> void:
	# Mark which ids to keep
	var keep: Dictionary = {}
	for id in path:
		keep[int(id)] = true

	# Kill everything else
	for i in range(alive.size()):
		alive[i] = keep.has(i)

	# Rebuild graph based on the remaining alive nodes
	_rebuild_graph()

func _has_prop(obj: Object, prop: StringName) -> bool:
	if obj == null:
		return false
	for p in obj.get_property_list():
		if StringName(p.get("name","")) == prop:
			return true
	return false

func _get_array_prop(obj: Object, key: StringName) -> Array:
	if obj == null or not is_instance_valid(obj):
		return []

	# 1) Real property (declared var / exported var)
	if (key in obj):
		var v = obj.get(String(key))
		if v is Array:
			return v

	# 2) Meta fallback (what your SquadDeploy sometimes writes)
	if obj.has_meta(key):
		var m = obj.get_meta(key)
		if m is Array:
			return m

	return []
