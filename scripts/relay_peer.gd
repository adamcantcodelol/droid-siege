extends MultiplayerPeerExtension
## MultiplayerPeer that tunnels Godot's high-level multiplayer through the room-code
## WebSocket relay (relay/relay.js). Works on desktop and in browsers (wss on port 443),
## so it gets through school/office networks that block UDP or direct IPs.
## Topology mirrors ENet: joiners only talk to the host (peer 1); Godot's server relay
## forwards client-to-client RPCs through the host.

signal room_ready(code: String)
signal relay_error(msg: String)

var ws := WebSocketPeer.new()
var url := ""
var want_host := false
var join_code := ""
var room_code := ""
var my_id := 0
var status: int = MultiplayerPeer.CONNECTION_DISCONNECTED
var hello_sent := false
var target := 0
var incoming: Array = []   # [from_id, PackedByteArray]
var peers := {}
var t_mode: int = MultiplayerPeer.TRANSFER_MODE_RELIABLE
var t_channel := 0
var refusing := false


func start_host(relay_url: String) -> int:
	want_host = true
	return _open(relay_url)


func start_join(relay_url: String, code: String) -> int:
	want_host = false
	join_code = code.strip_edges().to_upper()
	return _open(relay_url)


func _open(relay_url: String) -> int:
	url = relay_url.strip_edges()
	if not (url.begins_with("ws://") or url.begins_with("wss://")):
		url = "wss://" + url
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 20
	var err := ws.connect_to_url(url)
	if err == OK:
		status = MultiplayerPeer.CONNECTION_CONNECTING
	return err


func _poll() -> void:
	if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not hello_sent:
			hello_sent = true
			if want_host:
				ws.send_text(JSON.stringify({"op": "host"}))
			else:
				ws.send_text(JSON.stringify({"op": "join", "code": join_code}))
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			if ws.was_string_packet():
				_control(pkt.get_string_from_utf8())
			elif pkt.size() >= 4:
				incoming.append([pkt.decode_s32(0), pkt.slice(4)])
	elif st == WebSocketPeer.STATE_CLOSED:
		_drop("Connection to the relay closed (code %d)." % ws.get_close_code())


func _drop(msg: String) -> void:
	if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	var was_connected := status == MultiplayerPeer.CONNECTION_CONNECTED
	status = MultiplayerPeer.CONNECTION_DISCONNECTED
	for id in peers.keys():
		peer_disconnected.emit(id)
	peers.clear()
	if not was_connected:
		relay_error.emit(msg)


func _control(text: String) -> void:
	var m = JSON.parse_string(text)
	if not (m is Dictionary):
		return
	match str(m.get("op", "")):
		"hosted":
			my_id = 1
			room_code = str(m["code"])
			status = MultiplayerPeer.CONNECTION_CONNECTED
			room_ready.emit(room_code)
		"joined":
			my_id = int(m["id"])
			room_code = str(m["code"])
			status = MultiplayerPeer.CONNECTION_CONNECTED
			peers[1] = true
			peer_connected.emit(1)
		"peer_connected":
			var id := int(m["id"])
			if refusing:
				ws.send_text(JSON.stringify({"op": "kick", "id": id}))
				return
			peers[id] = true
			peer_connected.emit(id)
		"peer_disconnected":
			var id2 := int(m["id"])
			if peers.erase(id2):
				peer_disconnected.emit(id2)
		"error":
			relay_error.emit(str(m.get("msg", "Relay error")))
			ws.close()
			_drop(str(m.get("msg", "Relay error")))


func _get_available_packet_count() -> int:
	return incoming.size()


func _get_packet_script() -> PackedByteArray:
	if incoming.is_empty():
		return PackedByteArray()
	return incoming.pop_front()[1]


func _get_packet_peer() -> int:
	return incoming[0][0] if not incoming.is_empty() else 0


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	var out := PackedByteArray()
	out.resize(4)
	out.encode_s32(0, target)
	out.append_array(buffer)
	return ws.send(out)


func _get_max_packet_size() -> int:
	return 1 << 20


func _get_packet_channel() -> int:
	return 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _set_transfer_channel(channel: int) -> void:
	t_channel = channel


func _get_transfer_channel() -> int:
	return t_channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	t_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return t_mode


func _set_target_peer(peer: int) -> void:
	target = peer


func _is_server() -> bool:
	return my_id == 1


func _close() -> void:
	ws.close()
	status = MultiplayerPeer.CONNECTION_DISCONNECTED
	peers.clear()
	incoming.clear()


func _disconnect_peer(peer: int, _force: bool) -> void:
	if my_id == 1:
		ws.send_text(JSON.stringify({"op": "kick", "id": peer}))
		if peers.erase(peer):
			peer_disconnected.emit(peer)


func _get_unique_id() -> int:
	return my_id


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return status


func _is_server_relay_supported() -> bool:
	return true


func _set_refuse_new_connections(enable: bool) -> void:
	refusing = enable


func _is_refusing_new_connections() -> bool:
	return refusing
