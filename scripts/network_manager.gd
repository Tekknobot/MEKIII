extends Node
class_name NetworkManager

# ------------------------------------------------------------
# Minimal 2-player co-op over WebSockets (host + 1 client)
#
# + LAN Auto-Join (native builds): host broadcasts via UDP, clients listen & auto-connect
# + Copy Invite URL helper
# + Connection success indicator (state + message)
# + Peer ready status for lobby
#
# NOTES:
# - HTML5 exports: cannot host a WebSocket server, and UDP broadcast discovery won't work.
#   (Browser sandbox blocks UDP.) HTML5 can still join via manual invite URL.
# ------------------------------------------------------------

# ------------------------------------------------------------
# Signals
# ------------------------------------------------------------
signal coop_enabled_changed(enabled: bool)
signal peer_list_changed()
signal squad_picks_changed()
signal mission_settings_ready()

signal connection_state_changed(state: int, message: String)
signal ready_state_changed()

# ------------------------------------------------------------
# Connection state enum
# ------------------------------------------------------------
enum ConnState { OFFLINE, HOSTING, CONNECTING, CONNECTED, FAILED }

var connection_state: int = ConnState.OFFLINE
var connection_message: String = ""

# ------------------------------------------------------------
# Core state
# ------------------------------------------------------------
var coop_enabled: bool = false
var is_host: bool = false

var host_port: int = 8910
var connect_url: String = ""

var host_peer_id: int = 1 # Godot server id
var client_peer_id: int = -1

# Shared run seed + mission settings (host decides, clients mirror)
var shared_seed: int = 0
var mission_seed: int = 0
var picked_season: int = -1
var picked_weather: int = -1
var has_mission_settings: bool = false

# Squad picks (paths) per peer
var picks_by_peer: Dictionary = {} # peer_id -> Array[String]

# Ready status per peer
var ready_by_peer: Dictionary = {} # peer_id -> bool

# ------------------------------------------------------------
# LAN discovery (UDP broadcast)
# ------------------------------------------------------------
var lan_enabled: bool = true

var _udp: PacketPeerUDP = PacketPeerUDP.new()
var _lan_listen_port: int = 8911              # discovery port (NOT websocket port)
var _lan_broadcast_interval: float = 0.35
var _lan_broadcast_timer: float = 0.0
var _lan_magic: String = "ZMCOOP"
var _auto_join_in_progress: bool = false

# ------------------------------------------------------------
# Snapshot request gating (prevents client crash / infinite loop)
# ------------------------------------------------------------
var _requested_snapshot: bool = false
var _snapshot_task_running: bool = false

# Prevent double-start spam / races
var _connecting: bool = false

# ------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------
func _ready() -> void:
	_lan_start_listening()

func _process(delta: float) -> void:
	# IMPORTANT: drive websocket networking
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		var p := multiplayer.multiplayer_peer
		if p != null:
			p.poll()

	# Host: broadcast presence regularly
	if lan_enabled and coop_enabled and is_host:
		_lan_broadcast_timer += delta
		if _lan_broadcast_timer >= _lan_broadcast_interval:
			_lan_broadcast_timer = 0.0
			_lan_broadcast()

	# Client: listen and auto-join if not connected
	if lan_enabled and (not coop_enabled):
		_lan_poll_for_hosts_and_autojoin()

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
func _set_conn_state(s: int, msg: String = "") -> void:
	connection_state = s
	connection_message = msg
	emit_signal("connection_state_changed", connection_state, connection_message)

func is_coop() -> bool:
	return coop_enabled and multiplayer != null and multiplayer.has_multiplayer_peer()

func local_peer_id() -> int:
	return multiplayer.get_unique_id() if multiplayer != null else 1

func get_host_lan_ip() -> String:
	# Auto-detect a shareable LAN IPv4 for co-op invites.
	# Prefer private ranges (192.168/10/172.16-31), skip loopback/IPv6/APIPA.
	var addrs := IP.get_local_addresses()
	var best_ip := ""
	var best_score := -999

	for ip in addrs:
		# Skip IPv6
		if ip.find(":") != -1:
			continue
		# Skip loopback / invalid
		if ip == "127.0.0.1" or ip == "0.0.0.0" or ip == "":
			continue

		var score := 0

		# De-prioritize APIPA (usually means no real LAN)
		if ip.begins_with("169.254."):
			score -= 50

		# Prefer common private LAN ranges
		if ip.begins_with("192.168."):
			score += 100
		elif ip.begins_with("10."):
			score += 90
		elif ip.begins_with("172."):
			# Only 172.16.0.0 – 172.31.255.255 are private
			for n in range(16, 32):
				if ip.begins_with("172.%d." % n):
					score += 80
					break

		# Small bonus for "normal looking" IPv4 that isn't loopback/apipa
		score += 5

		if score > best_score:
			best_score = score
			best_ip = ip

	# If we found any non-loopback IPv4, return the best candidate.
	if best_ip != "":
		return best_ip

	# Last resort
	return "127.0.0.1"

func get_invite_url() -> String:
	return "ws://%s:%d" % [get_host_lan_ip(), host_port]

func peer_count() -> int:
	if multiplayer == null or not multiplayer.has_multiplayer_peer():
		return 1
	return multiplayer.get_peers().size() + 1

func both_players_present() -> bool:
	return is_host and client_peer_id != -1

# ------------------------------------------------------------
# Start / Stop (WITH PRINTS)
# ------------------------------------------------------------
func start_host(port := 8910) -> bool:
	print("COOP(HOST): start_host port=", port)

	stop()

	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port, "0.0.0.0")
	print("COOP(HOST): create_server err=", err)
	print("COOP(HOST): local_addrs=", IP.get_local_addresses())
	print("COOP(HOST): lan_ip=", get_host_lan_ip())
	
	if err != OK:
		push_warning("COOP: failed to host WebSocket server (err=%s)" % [err])
		_set_conn_state(ConnState.FAILED, "Host failed (err=%s)" % [err])
		return false

	multiplayer.multiplayer_peer = peer
	print("COOP(HOST): multiplayer_peer set. has_peer=", multiplayer.has_multiplayer_peer())

	coop_enabled = true
	is_host = true
	host_port = port
	_connecting = false

	shared_seed = int(Time.get_ticks_msec())
	print("COOP(HOST): shared_seed=", shared_seed)

	_bind_signals()
	print("COOP(HOST): signals bound")

	picks_by_peer.clear()
	ready_by_peer.clear()

	picks_by_peer[host_peer_id] = []
	ready_by_peer[host_peer_id] = false

	_auto_join_in_progress = false
	_lan_broadcast_timer = 0.0

	_requested_snapshot = false
	_snapshot_task_running = false

	print("COOP(HOST): invite_url=", get_invite_url())
	_set_conn_state(ConnState.HOSTING, "Hosting on %s" % get_invite_url())

	emit_signal("coop_enabled_changed", true)
	emit_signal("peer_list_changed")
	emit_signal("ready_state_changed")

	print("COOP(HOST): start_host OK. peers=", multiplayer.get_peers(), " unique_id=", multiplayer.get_unique_id())
	return true

func start_client(url: String) -> bool:
	print("COOP(CLIENT): start_client url=", url)

	# ✅ prevent double-click / double-start races
	if _connecting:
		print("COOP(CLIENT): start_client ignored (already connecting)")
		return false
	_connecting = true

	stop()

	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	print("COOP(CLIENT): create_client err=", err)

	if err != OK:
		_connecting = false
		push_warning("COOP: failed to connect (err=%s) url=%s" % [err, url])
		_set_conn_state(ConnState.FAILED, "Connect failed (err=%s)" % [err])
		_auto_join_in_progress = false
		return false

	multiplayer.multiplayer_peer = peer
	print("COOP(CLIENT): multiplayer_peer set. has_peer=", multiplayer.has_multiplayer_peer())

	coop_enabled = true
	is_host = false
	connect_url = url

	_bind_signals()
	print("COOP(CLIENT): signals bound")

	picks_by_peer.clear()
	ready_by_peer.clear()

	_requested_snapshot = false
	_snapshot_task_running = false

	_set_conn_state(ConnState.CONNECTING, "Connecting to %s" % url)

	emit_signal("coop_enabled_changed", true)
	emit_signal("peer_list_changed")
	emit_signal("ready_state_changed")

	_auto_join_in_progress = false

	print("COOP(CLIENT): start_client OK. unique_id=", multiplayer.get_unique_id())
	return true

func stop() -> void:
	print("COOP: stop() called. had_peer=", (multiplayer != null and multiplayer.has_multiplayer_peer()))

	# ✅ stop any “wait for snapshot” coroutine from doing work after teardown
	_requested_snapshot = false
	_snapshot_task_running = false
	_connecting = false

	# ✅ disconnect signals (prevents duplicate callbacks after reconnect)
	_unbind_signals()

	if multiplayer != null and multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null
		print("COOP: multiplayer_peer cleared")

	coop_enabled = false
	is_host = false
	client_peer_id = -1

	has_mission_settings = false
	shared_seed = 0
	mission_seed = 0
	picked_season = -1
	picked_weather = -1

	picks_by_peer.clear()
	ready_by_peer.clear()

	_auto_join_in_progress = false

	_set_conn_state(ConnState.OFFLINE, "")

	emit_signal("coop_enabled_changed", false)
	emit_signal("peer_list_changed")
	emit_signal("squad_picks_changed")
	emit_signal("ready_state_changed")

	print("COOP: stopped. coop_enabled=", coop_enabled, " is_host=", is_host, " client_peer_id=", client_peer_id)

# ------------------------------------------------------------
# Multiplayer signals
# ------------------------------------------------------------
func _bind_signals() -> void:
	if multiplayer == null:
		return

	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func _unbind_signals() -> void:
	if multiplayer == null:
		return

	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)

func _on_connection_failed() -> void:
	print("COOP(CLIENT): connection_failed fired")
	_connecting = false
	push_warning("COOP: connection failed")

	_set_conn_state(ConnState.FAILED, "Connection failed")
	stop()

func _on_server_disconnected() -> void:
	_connecting = false
	push_warning("COOP: disconnected")
	_set_conn_state(ConnState.FAILED, "Disconnected")
	stop()

func _on_connected_to_server() -> void:
	print("COOP(CLIENT): connected_to_server fired")
	_connecting = false

	# ✅ request session state immediately (your existing state sync)
	print("COOP(CLIENT): requesting session state from host")
	_rpc_request_session_state.rpc_id(host_peer_id)

func _on_peer_connected(id: int) -> void:
	print("COOP: peer_connected id=", id, " is_host=", is_host)

	if is_host:
		client_peer_id = id
		# if Game exists, push snapshot immediately too
		var game := get_tree().get_first_node_in_group("Game")
		if game != null and game.has_method("_send_snapshot_to_peer"):
			game.call("_send_snapshot_to_peer", id)
			
		if not picks_by_peer.has(id):
			picks_by_peer[id] = []
		if not ready_by_peer.has(id):
			ready_by_peer[id] = false
		if not ready_by_peer.has(host_peer_id):
			ready_by_peer[host_peer_id] = false

		print("COOP(HOST): client connected ->", id)
		print("COOP(HOST): total peers=", multiplayer.get_peers())

	emit_signal("peer_list_changed")
	emit_signal("ready_state_changed")

func _on_peer_disconnected(id: int) -> void:
	print("COOP: peer_disconnected id=", id, " is_host=", is_host)

	if is_host and id == client_peer_id:
		client_peer_id = -1
		print("COOP(HOST): client disconnected")

	if picks_by_peer.has(id):
		picks_by_peer.erase(id)
	if ready_by_peer.has(id):
		ready_by_peer.erase(id)

	emit_signal("peer_list_changed")
	emit_signal("squad_picks_changed")
	emit_signal("ready_state_changed")

# ------------------------------------------------------------
# Snapshot request (CLIENT) - safe + bounded
# ------------------------------------------------------------
func _request_snapshot_when_game_ready() -> void:
	# Don’t block the main thread; bounded retries (prevents infinite call_deferred loops).
	_call_request_snapshot_async()

func _call_request_snapshot_async() -> void:
	# Fire-and-forget coroutine pattern (Godot allows awaits inside this function).
	_request_snapshot_async()

func _find_game_instance() -> Node:
	# Prefer a group if you add it in game.gd: add_to_group("Game")
	var g := get_tree().get_first_node_in_group("GameMap")
	if g != null:
		return g
	# Fallback: current scene
	return get_tree().current_scene

	var net := get_tree().root.get_node_or_null("Network") as NetworkManager
	if net != null and net.is_coop() and not net.is_host:
		net.request_snapshot_now()

func _request_snapshot_async() -> void:
	# Wait up to ~60 frames (~1 sec at 60fps) for Game to exist + have the RPC method.
	var tries := 60
	while tries > 0:
		tries -= 1

		# Stop trying if we’re no longer connected/active
		if not is_coop() or is_host:
			_snapshot_task_running = false
			return

		if multiplayer == null or multiplayer.multiplayer_peer == null:
			await get_tree().process_frame
			continue

		# Unique id is 0 for a moment right after connect; wait until it becomes real
		if multiplayer.get_unique_id() == 0:
			await get_tree().process_frame
			continue

		var game_instance := _find_game_instance()
		if game_instance != null and game_instance.has_method("_rpc_request_snapshot") and not _requested_snapshot:
			_requested_snapshot = true
			print("COOP(CLIENT): requesting snapshot now")
			_rpc_request_snapshot.rpc_id(host_peer_id)
			_snapshot_task_running = false
			return

		await get_tree().process_frame

	# Give up quietly (prevents hard crash / infinite loop)
	print("COOP(CLIENT): snapshot request skipped (Game not ready in time)")
	_snapshot_task_running = false

# ------------------------------------------------------------
# Session state sync
# ------------------------------------------------------------
@rpc("any_peer", "reliable")
func _rpc_request_session_state() -> void:
	if not is_host:
		return
	var target := multiplayer.get_remote_sender_id()
	_rpc_receive_session_state.rpc_id(target, shared_seed, mission_seed, picked_season, picked_weather)

@rpc("any_peer", "reliable")
func _rpc_receive_session_state(seed: int, mseed: int, season: int, weather: int) -> void:
	shared_seed = seed
	mission_seed = mseed
	picked_season = season
	picked_weather = weather

	has_mission_settings = (mseed != 0 and season >= 0 and weather >= 0)
	if has_mission_settings:
		emit_signal("mission_settings_ready")

func set_mission_settings(seed: int, season: int, weather: int) -> void:
	# host-only helper
	if not is_host:
		return

	mission_seed = seed
	picked_season = season
	picked_weather = weather
	has_mission_settings = true

	_rpc_receive_session_state.rpc(shared_seed, mission_seed, picked_season, picked_weather)
	emit_signal("mission_settings_ready")

# ------------------------------------------------------------
# Squad picks
# ------------------------------------------------------------
func submit_local_picks(paths: Array[String]) -> void:
	if not is_coop():
		return
	var pid := local_peer_id()
	picks_by_peer[pid] = paths.duplicate()
	emit_signal("squad_picks_changed")
	_rpc_submit_picks.rpc(pid, paths)

@rpc("any_peer", "reliable")
func _rpc_submit_picks(peer_id: int, paths: Array) -> void:
	if not is_coop():
		return
	var arr: Array[String] = []
	for p in paths:
		arr.append(str(p))
	picks_by_peer[peer_id] = arr
	emit_signal("squad_picks_changed")

func are_both_picks_ready(per_player := 2) -> bool:
	if not is_coop():
		return false

	var other_id := -1
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		var peers := multiplayer.get_peers()
		if peers.size() > 0:
			other_id = int(peers[0])

	if other_id == -1:
		return false

	var my_id := local_peer_id()

	var a = picks_by_peer.get(my_id, [])
	var b = picks_by_peer.get(other_id, [])

	return (a is Array and b is Array and a.size() >= per_player and b.size() >= per_player)

# ------------------------------------------------------------
# Ready status (lobby)
# ------------------------------------------------------------
func set_local_ready(is_ready: bool) -> void:
	if not is_coop():
		return
	var pid := local_peer_id()
	ready_by_peer[pid] = is_ready
	emit_signal("ready_state_changed")
	_rpc_set_ready.rpc(pid, is_ready)

@rpc("any_peer", "reliable")
func _rpc_set_ready(peer_id: int, is_ready: bool) -> void:
	ready_by_peer[peer_id] = is_ready
	emit_signal("ready_state_changed")

func is_peer_ready(peer_id: int) -> bool:
	return bool(ready_by_peer.get(peer_id, false))

func both_ready() -> bool:
	if not is_coop():
		return false

	var other_id := -1
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		var peers := multiplayer.get_peers()
		if peers.size() > 0:
			other_id = int(peers[0])

	if other_id == -1:
		return false

	var my_id := local_peer_id()
	return is_peer_ready(my_id) and is_peer_ready(other_id)

# ------------------------------------------------------------
# LAN discovery (UDP)
# ------------------------------------------------------------
func _lan_start_listening() -> void:
	if not lan_enabled:
		return

	_udp.close()
	var err := _udp.bind(_lan_listen_port, "0.0.0.0")
	if err != OK:
		push_warning("LAN: UDP bind failed err=%s" % [err])
		return

	_udp.set_broadcast_enabled(true)

func _lan_broadcast() -> void:
	if not lan_enabled:
		return

	# Packet format: ZMCOOP|port|shared_seed
	var msg := "%s|%d|%d" % [_lan_magic, host_port, shared_seed]

	_udp.set_broadcast_enabled(true)
	_udp.set_dest_address("255.255.255.255", _lan_listen_port)
	_udp.put_packet(msg.to_utf8_buffer())

func _lan_poll_for_hosts_and_autojoin() -> void:
	if not lan_enabled:
		return

	if _udp.get_available_packet_count() <= 0:
		return

	var pkt := _udp.get_packet()
	var from_ip := _udp.get_packet_ip()
	var text := pkt.get_string_from_utf8()

	# Expect: ZMCOOP|port|seed
	var parts := text.split("|")
	if parts.size() < 2:
		return
	if parts[0] != _lan_magic:
		return

	var port := int(parts[1])
	if port <= 0:
		return

	# Ignore self
	var my_ip := get_host_lan_ip()
	if from_ip == my_ip:
		return

	# Already connected / connecting?
	if is_coop() or _auto_join_in_progress or _connecting:
		return

	_auto_join_in_progress = true
	var url := "ws://%s:%d" % [from_ip, port]
	start_client(url)

func request_snapshot_now() -> void:
	if not is_coop() or is_host:
		return
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return
	if multiplayer.get_unique_id() == 0:
		return

	_requested_snapshot = false
	if not _snapshot_task_running:
		_snapshot_task_running = true
		_request_snapshot_when_game_ready()

@rpc("any_peer", "reliable")
func _rpc_request_snapshot() -> void:
	# Host only
	if not is_host:
		return

	var to_id := multiplayer.get_remote_sender_id()

	# Find the host's Game node (must exist to build snapshot)
	var game := get_tree().current_scene
	if game == null or not game.has_method("_build_snapshot"):
		game = get_tree().get_first_node_in_group("Game")
	if game == null or not game.has_method("_build_snapshot"):
		print("COOP(HOST): snapshot requested but Game not ready")
		return

	var snap = game.call("_build_snapshot")
	_rpc_receive_snapshot.rpc_id(to_id, snap)


@rpc("any_peer", "reliable")
func _rpc_receive_snapshot(snap: Dictionary) -> void:
	# Client receives snapshot and applies it locally
	var game := get_tree().current_scene
	if game == null or not game.has_method("_apply_snapshot"):
		game = get_tree().get_first_node_in_group("Game")
	if game == null or not game.has_method("_apply_snapshot"):
		print("COOP(CLIENT): got snapshot but Game not ready yet")
		return

	game.call("_apply_snapshot", snap)
