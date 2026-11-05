extends SceneTree
const RelayPeer = preload("res://scripts/relay_peer.gd")
var peer
var got_peer := false
var got_pkt := false
func _init():
	await_code()
func await_code():
	var t0 = Time.get_ticks_msec()
	while not FileAccess.file_exists("/tmp/live_code.txt") and Time.get_ticks_msec()-t0 < 8000:
		await create_timer(0.1).timeout
	if not FileAccess.file_exists("/tmp/live_code.txt"):
		print("[live] CLIENT no code file"); quit(1); return
	var code = FileAccess.get_file_as_string("/tmp/live_code.txt").strip_edges()
	print("[live] CLIENT joining ", code)
	peer = RelayPeer.new()
	peer.relay_error.connect(func(m): print("[live] CLIENT ERR ", m); quit(1))
	peer.peer_connected.connect(func(id): print("[live] CLIENT peer_connected ", id); got_peer=true; _send())
	var err = peer.start_join("wss://droid-siege.moeller-basil.workers.dev/ws", code)
	print("[live] client start err=", err)
func _send():
	peer.set_target_peer(1)
	peer.put_packet(PackedByteArray([1,2,3,4,5]))
	print("[live] CLIENT sent packet")
func _process(_d):
	if peer: peer.poll()
	if peer and peer.get_available_packet_count() > 0:
		var p = peer.get_packet()
		print("[live] CLIENT got packet size=", p.size(), " from=", peer.get_packet_peer())
		got_pkt = true
		print("[live] OK client got_peer=", got_peer, " got_pkt=", got_pkt)
		quit(0)
