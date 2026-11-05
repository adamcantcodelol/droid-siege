extends SceneTree
const RelayPeer = preload("res://scripts/relay_peer.gd")
var peer
var code := ""
func _init():
	peer = RelayPeer.new()
	peer.room_ready.connect(func(c): code=c; print("[live] HOSTED code=", c); FileAccess.open("/tmp/live_code.txt", FileAccess.WRITE).store_string(c))
	peer.relay_error.connect(func(m): print("[live] HOST ERR ", m); quit(1))
	var err = peer.start_host("wss://droid-siege.moeller-basil.workers.dev/ws")
	print("[live] host start err=", err)
func _process(_d):
	if peer: peer.poll()
