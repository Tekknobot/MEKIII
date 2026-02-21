extends Node
class_name NetworkManager

# ------------------------------------------------------------
# Minimal 2-player co-op over WebSockets (host + 1 client)
#
# - Host runs a WebSocket server (native builds).
# - Client connects via ws://HOST_IP:PORT
# - 2 peers max.
#
# NOTE: HTML5 exports cannot host a server, but they CAN join.
# ------------------------------------------------------------

signal coop_enabled_changed(enabled: bool)
signal peer_list_changed()
signal squad_picks_changed()
signal mission_settings_ready()

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

func is_coop() -> bool:
	return coop_enabled and multiplayer != null and multiplayer.has_multiplayer_peer()

func local_peer_id() -> int:
	return multiplayer.get_unique_id() if multiplayer != null else 1

func start_host(port := 8910) -> bool:
	stop()
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		push_warning("COOP: failed to host WebSocket server (err=%s)" % [err])
		return false

	multiplayer.multiplayer_peer = peer
	coop_enabled = true
	is_host = true
	host_port = port
	shared_seed = int(Time.get_ticks_msec())
	_bind_signals()
	picks_by_peer.clear()
	picks_by_peer[host_peer_id] = []
	emit_signal("coop_enabled_changed", true)
	emit_signal("peer_list_changed")
	return true

func start_client(url: String) -> bool:
	stop()
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		push_warning("COOP: failed to connect (err=%s) url=%s" % [err, url])
		return false

	multiplayer.multiplayer_peer = peer
	coop_enabled = true
	is_host = false
	connect_url = url
	_bind_signals()
	picks_by_peer.clear()
	emit_signal("coop_enabled_changed", true)
	emit_signal("peer_list_changed")
	return true

func stop() -> void:
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null
	coop_enabled = false
	is_host = false
	client_peer_id = -1
	has_mission_settings = false
	shared_seed = 0
	mission_seed = 0
	picked_season = -1
	picked_weather = -1
	picks_by_peer.clear()
	emit_signal("coop_enabled_changed", false)
	emit_signal("peer_list_changed")

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

func _on_connected_to_server() -> void:
	# client: ask host for seed + mission settings
	_rpc_request_session_state.rpc_id(1)

func _on_connection_failed() -> void:
	push_warning("COOP: connection failed")
	stop()

func _on_server_disconnected() -> void:
	push_warning("COOP: disconnected")
	stop()

func _on_peer_connected(id: int) -> void:
	if is_host:
		client_peer_id = id
		if not picks_by_peer.has(id):
			picks_by_peer[id] = []
		emit_signal("peer_list_changed")

func _on_peer_disconnected(id: int) -> void:
	if is_host and id == client_peer_id:
		client_peer_id = -1
	if picks_by_peer.has(id):
		picks_by_peer.erase(id)
	emit_signal("peer_list_changed")
	emit_signal("squad_picks_changed")

func peer_count() -> int:
	if multiplayer == null or not multiplayer.has_multiplayer_peer():
		return 1
	return multiplayer.get_peers().size() + 1

func both_players_present() -> bool:
	return is_host and client_peer_id != -1

# ------------------------------------------------------------
# Session state sync
# ------------------------------------------------------------

@rpc("any_peer", "reliable")
func _rpc_request_session_state() -> void:
	if not is_host:
		return
	_rpc_receive_session_state.rpc_id(multiplayer.get_remote_sender_id(), shared_seed, mission_seed, picked_season, picked_weather)

@rpc("authority", "reliable")
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
	if is_host and client_peer_id == -1:
		return false
	var a = picks_by_peer.get(host_peer_id, [])
	var b = picks_by_peer.get(client_peer_id, [])
	return (a is Array and b is Array and a.size() >= per_player and b.size() >= per_player)
