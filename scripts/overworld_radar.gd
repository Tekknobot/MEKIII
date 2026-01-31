extends Node2D
class_name OverworldRadar

@export var label_font: Font
@export var label_font_size: int = 12
@export var label_alpha: float = 0.20

signal mission_requested(node_id: int, node_type: int, difficulty: float)

var current_node_id: int = -1
var hovered_node_id: int = -1
@export var restrict_to_neighbors := true

# -------------------------
# SETTINGS
# -------------------------
@export var grid_size: int = 9                 # 9x9
@export var spacing: float = 64.0              # pixels between lattice points
var origin: Vector2

@export var remove_ratio: float = 0.33         # % nodes removed (voids)
@export var extra_links_chance: float = 0.10   # add a few diagonals sometimes
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

# -------------------------
# LIFECYCLE
# -------------------------
func _ready() -> void:
	var rs: Node = _rs()

	# --- seed ---
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

	_build_packets()
	queue_redraw()

	if squad_hud_enabled:
		_build_squad_hud()
		_refresh_squad_hud()

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
				
	if event is InputEventKey and event.pressed:
		# DEBUG CHEAT: clear path to nearest boss
		if event.keycode == KEY_B:
			_cheat_clear_path_to_nearest_boss()
			return

	if event is InputEventKey and event.pressed:
		# DEBUG CHEAT: clear path to nearest elite
		if event.keycode == KEY_E:
			_cheat_clear_path_to_nearest_elite()
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
	if nodes[id].cleared:
		return false
	if current_node_id < 0:
		return false

	# If the current node is NOT cleared yet: only it is clickable (launch)
	if not nodes[current_node_id].cleared:
		return id == current_node_id

	# If the current node IS cleared: only its neighbors are clickable (move)
	return nodes[current_node_id].neighbors.has(id)


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

	# Difficulty gradient = normalized BFS distance from start
	_assign_difficulty_from(start_id)

	# Assign node types
	_assign_types()
	_assign_extra_boss_nodes()
	_assign_extra_elite_nodes()
	_line_up_events()
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
	for nd in nodes:
		if not alive[nd.id]:
			continue
		nd.ntype = NodeType.COMBAT

	# Force start/boss
	if start_id >= 0:
		nodes[start_id].ntype = NodeType.START
	if boss_id >= 0:
		nodes[boss_id].ntype = NodeType.BOSS

	# Sprinkle types by difficulty (equalized odds)
	for nd in nodes:
		if not alive[nd.id]:
			continue
		if nd.id == start_id or nd.id == boss_id:
			continue

		var r := rng.randf()

		# Same probabilities everywhere
		if r < 0.22:
			nd.ntype = NodeType.SUPPLY
		elif r < 0.22 + 0.15:
			nd.ntype = NodeType.EVENT
		elif r < 0.22 + 0.15 + 0.35:
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
				draw_string(_font, pos + Vector2(r + 4, -r - 2),
					"%s" % _type_name(nd.ntype),
					HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size,
					Color(0.2, 1.0, 0.2, label_alpha))

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
	if title_scene_path == "" or not ResourceLoader.exists(title_scene_path):
		push_warning("OverworldRadar: title_scene_path missing or invalid: " + title_scene_path)
		return
	get_tree().change_scene_to_file(title_scene_path)

func _refresh_squad_hud() -> void:
	if _hud_row == null or not is_instance_valid(_hud_row):
		return

	# clear
	for ch in _hud_row.get_children():
		ch.queue_free()

	var rs := _rs()
	if rs == null:
		return
	if not ("squad_scene_paths" in rs):
		return

	var paths: Array = rs.squad_scene_paths
	for p in paths:
		var path := str(p)
		if path == "":
			continue
		_hud_row.add_child(await _make_squad_chip(path))

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

	# Exports (properties)
	out["portrait"] = _get_prop_if_exists(inst, "portrait_tex")
	out["thumb"] = _get_prop_if_exists(inst, "thumbnail")
	out["name"] = _get_prop_if_exists(inst, "display_name")

	# Meta fallback (only if you still have legacy units using meta)
	if out["portrait"] == null and inst.has_meta("portrait_tex"):
		out["portrait"] = inst.get_meta("portrait_tex")
	if out["thumb"] == null and inst.has_meta("thumbnail"):
		out["thumb"] = inst.get_meta("thumbnail")
	if (out["name"] == null or str(out["name"]) == "") and inst.has_meta("display_name"):
		out["name"] = inst.get_meta("display_name")

	if out["name"] == null or str(out["name"]) == "":
		out["name"] = inst.name
	else:
		out["name"] = str(out["name"])

	inst.queue_free()
	return out

func _get_prop_if_exists(obj: Object, prop: StringName) -> Variant:
	# Checks actual properties (includes exported vars)
	for p in obj.get_property_list():
		# p is a Dictionary; "name" key exists
		if StringName(p.get("name", "")) == prop:
			return obj.get(prop)
	return null

func _assign_extra_boss_nodes() -> void:
	# Ensure at least 1 boss (your farthest node)
	if boss_id < 0:
		return

	# Clamp desired count
	var desired = max(1, boss_node_count)

	# Already have 1 boss via _assign_types()
	var remaining = desired - 1
	if remaining <= 0:
		return

	# Distances from start so we can prefer late nodes
	var dist := _bfs_dist(start_id)

	# Candidates: alive, not cleared, not start, not existing boss_id, high difficulty
	var candidates: Array[int] = []
	for nd in nodes:
		if not alive[nd.id]:
			continue
		if nd.id == start_id:
			continue
		if nd.id == boss_id:
			continue
		if nd.difficulty < boss_min_difficulty:
			continue
		candidates.append(nd.id)

	# Shuffle deterministically
	_rng_shuffle_int(candidates)

	# Keep bosses spaced out by BFS distance between them
	var chosen: Array[int] = [boss_id]

	for id in candidates:
		if remaining <= 0:
			break

		# spacing check: BFS gap between this id and all chosen bosses
		var ok := true
		for b in chosen:
			var gap := _bfs_distance_between(id, b)
			if gap >= 0 and gap < boss_min_bfs_gap:
				ok = false
				break
		if not ok:
			continue

		# Promote to boss
		nodes[id].ntype = NodeType.BOSS
		chosen.append(id)
		remaining -= 1

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

func _assign_extra_elite_nodes() -> void:
	elite_ids.clear()

	# Clamp desired count
	var desired = max(0, elite_node_count)
	if desired <= 0:
		return

	# Candidates: alive, not cleared, not start, not boss, late difficulty
	var candidates: Array[int] = []
	for nd in nodes:
		if not alive[nd.id]:
			continue
		if nd.id == start_id:
			continue
		if nd.ntype == NodeType.BOSS:
			continue
		if nd.difficulty < elite_min_difficulty:
			continue

		# Don’t steal other special nodes unless you want to allow it
		# (If you DO want elites to overwrite COMBAT/EVENT/SUPPLY, remove this check.)
		if nd.ntype != NodeType.COMBAT:
			continue

		candidates.append(nd.id)

	_rng_shuffle_int(candidates)

	# Keep ELITEs spaced out
	var chosen: Array[int] = []

	for id in candidates:
		if chosen.size() >= desired:
			break

		var ok := true

		# keep away from other elites
		for e in chosen:
			var gap := _bfs_distance_between(id, e)
			if gap >= 0 and gap < elite_min_bfs_gap:
				ok = false
				break
		if not ok:
			continue

		# optional: also keep away from bosses a bit
		# (uncomment if you want)
		# if boss_id >= 0:
		# 	var gb := _bfs_distance_between(id, boss_id)
		# 	if gb >= 0 and gb < elite_min_bfs_gap:
		# 		continue

		nodes[id].ntype = NodeType.ELITE
		chosen.append(id)

	elite_ids = chosen

func _line_up_events() -> void:
	# Gather event nodes
	var ev: Array[NodeData] = []
	for nd in nodes:
		if alive[nd.id] and nd.ntype == NodeType.EVENT:
			ev.append(nd)
	if ev.size() <= 1:
		return

	# Sort by difficulty so they "read" left-to-right early->late
	ev.sort_custom(func(a: NodeData, b: NodeData) -> bool:
		return a.difficulty < b.difficulty
	)

	# Choose a row: the median event's current row (keeps it "somewhere" sensible)
	var row := ev[int(ev.size() * 0.5)].gy
	row = clampi(row, 0, grid_size - 1)

	# Get all alive nodes in that row, excluding start/boss, sorted by gx
	var slots: Array[NodeData] = []
	for nd in nodes:
		if not alive[nd.id]:
			continue
		if nd.id == start_id or nd.id == boss_id:
			continue
		if nd.gy != row:
			continue
		slots.append(nd)

	slots.sort_custom(func(a: NodeData, b: NodeData) -> bool:
		return a.gx < b.gx
	)

	if slots.size() == 0:
		return

	# If not enough slots in that row, fall back to the fullest row
	if slots.size() < ev.size():
		var best_row := row
		var best_count := slots.size()
		for y in range(grid_size):
			var c := 0
			for nd in nodes:
				if alive[nd.id] and nd.id != start_id and nd.id != boss_id and nd.gy == y:
					c += 1
			if c > best_count:
				best_count = c
				best_row = y
		row = best_row

		# rebuild slots for chosen row
		slots.clear()
		for nd in nodes:
			if not alive[nd.id]:
				continue
			if nd.id == start_id or nd.id == boss_id:
				continue
			if nd.gy != row:
				continue
			slots.append(nd)
		slots.sort_custom(func(a: NodeData, b: NodeData) -> bool:
			return a.gx < b.gx
		)

		if slots.size() < ev.size():
			# not enough space anywhere; give up safely
			return

	# Move event types onto that row by swapping types with the slot nodes
	for i in range(ev.size()):
		var a := ev[i]
		var b := slots[i]
		if a.id == b.id:
			continue
		var tmp := a.ntype
		a.ntype = b.ntype
		b.ntype = tmp

	# After changing types, rebuild graph/difficulty if you want them consistent
	_rebuild_graph()
	_assign_difficulty_from(start_id)
