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
# LIFECYCLE
# -------------------------
func _ready() -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	_font = label_font
	if _font == null:
		_font = ThemeDB.fallback_font

	_generate_world()
	_build_packets()
	queue_redraw()

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
		hovered_node_id = _pick_node(get_global_mouse_position())
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit: int = _pick_node(get_global_mouse_position())
		if hit < 0:
			return
		if not _can_click_node(hit):
			return

		# clicking current node = launch mission
		if hit == current_node_id:
			emit_signal("mission_requested", hit, nodes[hit].ntype, nodes[hit].difficulty)
			return

		# otherwise move
		_move_to_node(hit)
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if current_node_id >= 0:
				emit_signal("mission_requested", current_node_id, nodes[current_node_id].ntype, nodes[current_node_id].difficulty)

func _can_click_node(id: int) -> bool:
	if id < 0:
		return false
	if not alive[id]:
		return false
	if current_node_id < 0:
		return true
	if not restrict_to_neighbors:
		return true
	if id == current_node_id:
		return true
	return nodes[current_node_id].neighbors.has(id)

func _move_to_node(id: int) -> void:
	if id == current_node_id:
		return

	# mark current as cleared (optional)
	if current_node_id >= 0:
		nodes[current_node_id].cleared = true

	current_node_id = id

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

	current_node_id = start_id


func _carve_voids_connected() -> void:
	var n: int = grid_size * grid_size
	var target_remove: int = int(round(float(n) * remove_ratio))

	# Never remove too many: keep at least ~half
	target_remove = clampi(target_remove, 0, n - int(float(n) * 0.55))

	var candidates: Array[int] = []
	for id in range(n):
		candidates.append(id)
	candidates.shuffle()

	var removed: int = 0
	for id in candidates:
		if removed >= target_remove:
			break

		alive[id] = false
		if _count_alive() < 8:
			alive[id] = true
			continue

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

	# Sprinkle types by difficulty
	for nd in nodes:
		if not alive[nd.id]:
			continue
		if nd.id == start_id or nd.id == boss_id:
			continue

		var r: float = rng.randf()

		if nd.difficulty < 0.30:
			if r < 0.22:
				nd.ntype = NodeType.SUPPLY
			else:
				nd.ntype = NodeType.COMBAT
		elif nd.difficulty < 0.65:
			if r < 0.15:
				nd.ntype = NodeType.EVENT
			else:
				nd.ntype = NodeType.COMBAT
		else:
			if r < 0.35:
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

	for nd in nodes:
		if not alive[nd.id]:
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

		# Cleared nodes dim
		if nd.cleared:
			col.a *= 0.45

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
				"%s %.2f" % [_type_name(nd.ntype), nd.difficulty],
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
