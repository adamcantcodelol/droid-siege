extends Node
## Global autoload: save data, upgrades, networking, RPC relay, generated sounds, test harness.

const SAVE_PATH := "user://droid_siege_save.json"
const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const MAX_LEVEL := 5
const GRENADE_COST := 60
const MAX_GRENADES := 6
const MENU_SCENE := "res://scenes/main_menu.tscn"
const WORLD_SCENE := "res://scenes/world.tscn"

const UPGRADES := {
	"dmg": {"label": "Blaster Damage", "desc": "+6 damage per bolt"},
	"rate": {"label": "Fire Rate", "desc": "12% faster firing"},
	"mag": {"label": "Power Cell", "desc": "+8 shots per magazine"},
	"armor": {"label": "Armor Plating", "desc": "+25 max health"},
}

var MAPS: Array = [
	{"name": "Geonosis Outpost", "posts": [Vector3(0, 0, -30), Vector3(50, 0, 10), Vector3(-45, 0, 35)],
		"lz": Vector3(0, 0, 72), "ground": Color(0.76, 0.55, 0.36), "cliff": Color(0.55, 0.36, 0.24),
		"rock": Color(0.6, 0.42, 0.3), "sky_top": Color(0.55, 0.35, 0.22), "sky_hor": Color(0.95, 0.7, 0.45),
		"fog": Color(0.85, 0.6, 0.4), "fog_density": 0.006, "sun": Color(1.0, 0.9, 0.75), "sun_energy": 1.2,
		"ambient": 0.8, "rocks": 70, "pillar_ratio": 0.35},
	{"name": "Felucia Night Raid", "posts": [Vector3(-50, 0, -40), Vector3(40, 0, -45), Vector3(10, 0, 20)],
		"lz": Vector3(60, 0, 70), "ground": Color(0.2, 0.33, 0.22), "cliff": Color(0.18, 0.22, 0.2),
		"rock": Color(0.42, 0.28, 0.52), "sky_top": Color(0.03, 0.06, 0.12), "sky_hor": Color(0.15, 0.3, 0.3),
		"fog": Color(0.15, 0.3, 0.28), "fog_density": 0.014, "sun": Color(0.6, 0.75, 1.0), "sun_energy": 0.45,
		"ambient": 0.6, "rocks": 95, "pillar_ratio": 0.7},
]
var DIFFICULTIES: Array = [
	{"name": "Recruit", "hp": 0.75, "dmg": 0.6, "cap": -1, "credits": 0.75},
	{"name": "Veteran", "hp": 1.0, "dmg": 1.0, "cap": 0, "credits": 1.0},
	{"name": "Commando", "hp": 1.3, "dmg": 1.4, "cap": 3, "credits": 1.5},
]

signal lobby_changed
signal net_status(msg: String)

var save := {}
var player_name := "Trooper"
var players := {}          # peer_id -> {"name": String}
var online := false
var in_mission := false
var dedicated := false          # this process is a headless dedicated server (no local player)
var server_is_dedicated := false # (clients) the server we joined is dedicated: any trooper can start
const DEFAULT_WS_PORT := 8080
var mission_seed := 1
var settings := {"map": 0, "diff": 1}
var world: Node = null
var test_mode := ""
var sounds := {}
var menu_message := ""
var mouse_sensitivity := 0.0025
var control_mode := 0      # 0 = mouse + keyboard, 1 = trackpad / keyboard only
var turn_speed := 2.6      # radians per second for keyboard turning
var auto_fire := false
var aim_assist := true
const CONTROL_MODES := ["Mouse + Keyboard", "Trackpad / Keyboard Only"]
var _test_start_ms := 0
var _test_done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_save()
	_make_sounds()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var ded_port := int(OS.get_environment("PORT")) if OS.get_environment("PORT") != "" else DEFAULT_WS_PORT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			test_mode = a.substr(7)
		elif a == "--server":
			dedicated = true
		elif a.begins_with("--port="):
			ded_port = int(a.substr(7))
	if dedicated:
		call_deferred("_start_dedicated", ded_port)
	if test_mode != "":
		print("[test] mode=", test_mode)
		_test_start_ms = Time.get_ticks_msec()
		call_deferred("_start_test")


func controls_help() -> String:
	if control_mode == 1:
		return "TRACKPAD / KEYBOARD: WASD move, Arrows or J/L turn + I/K look, F or Ctrl fire (trackpad tap also fires), Q or Alt toggle aim, Shift sprint, Space jump, R reload, G grenade, E (hold) revive, Esc pause. Aim assist pulls toward droids near the crosshair%s." % (", auto-fire ON" if auto_fire else "")
	return "MOUSE + KEYBOARD: WASD move, Mouse look, Left click fire, Right click aim, Shift sprint, Space jump, R reload, G grenade, E (hold) revive, Esc pause."


## Adds the Controls selector (+ turn speed, aim assist, auto-fire) to a menu box.
func build_control_options(box: Control) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = "Controls:"
	row.add_child(l)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in CONTROL_MODES:
		opt.add_item(m)
	opt.selected = control_mode
	row.add_child(opt)
	box.add_child(row)
	var extra := VBoxContainer.new()
	box.add_child(extra)
	var tl := Label.new()
	tl.text = "Keyboard turn speed"
	extra.add_child(tl)
	var ts := HSlider.new()
	ts.min_value = 0.8
	ts.max_value = 6.0
	ts.step = 0.1
	ts.value = turn_speed
	ts.value_changed.connect(func(v): turn_speed = v; write_save())
	extra.add_child(ts)
	var aa := CheckBox.new()
	aa.text = "Aim assist (pulls toward droids near the crosshair)"
	aa.button_pressed = aim_assist
	aa.toggled.connect(func(on): aim_assist = on; write_save())
	extra.add_child(aa)
	var af := CheckBox.new()
	af.text = "Auto-fire when the crosshair is on a droid"
	af.button_pressed = auto_fire
	af.toggled.connect(func(on): auto_fire = on; write_save())
	extra.add_child(af)
	extra.visible = control_mode == 1
	opt.item_selected.connect(func(i): control_mode = i; extra.visible = i == 1; write_save())


func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


# ---------------------------------------------------------------- input
func _setup_input() -> void:
	_bind("move_forward", [KEY_W])
	_bind("move_back", [KEY_S])
	_bind("move_left", [KEY_A])
	_bind("move_right", [KEY_D])
	# Keyboard / trackpad mode (only used when control_mode == 1)
	_bind("turn_left", [KEY_LEFT, KEY_J])
	_bind("turn_right", [KEY_RIGHT, KEY_L])
	_bind("look_up", [KEY_UP, KEY_I])
	_bind("look_down", [KEY_DOWN, KEY_K])
	_bind("kb_fire", [KEY_F, KEY_CTRL])
	_bind("kb_aim", [KEY_Q, KEY_ALT])
	_bind("sprint", [KEY_SHIFT])
	_bind("jump", [KEY_SPACE])
	_bind("reload", [KEY_R])
	_bind("grenade", [KEY_G])
	_bind("interact", [KEY_E])
	_bind("pause", [KEY_ESCAPE])
	_bind("fire", [], MOUSE_BUTTON_LEFT)
	_bind("aim", [], MOUSE_BUTTON_RIGHT)


func _bind(action: String, keys: Array, mouse_button: int = 0) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	if mouse_button != 0:
		var m := InputEventMouseButton.new()
		m.button_index = mouse_button
		InputMap.action_add_event(action, m)


# ---------------------------------------------------------------- save / upgrades
func default_save() -> Dictionary:
	return {"credits": 0, "dmg": 0, "rate": 0, "mag": 0, "armor": 0, "grenades": 2,
		"missions": 0, "wins": 0, "name": "Trooper", "sens": 0.0025, "map": 0, "diff": 1, "controls": 0, "turn_speed": 2.6, "auto_fire": false, "aim_assist": true, "ws_url": ""}


func load_save() -> void:
	save = default_save()
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				for k in d.keys():
					if save.has(k):
						save[k] = d[k]
	for k in ["credits", "dmg", "rate", "mag", "armor", "grenades", "missions", "wins"]:
		save[k] = int(save[k])
	player_name = str(save["name"])
	settings = {"map": int(save["map"]), "diff": int(save["diff"])}
	mouse_sensitivity = float(save["sens"])
	control_mode = int(save["controls"])
	turn_speed = float(save["turn_speed"])
	auto_fire = bool(save["auto_fire"])
	aim_assist = bool(save["aim_assist"])


func write_save() -> void:
	save["name"] = player_name
	save["sens"] = mouse_sensitivity
	save["controls"] = control_mode
	save["turn_speed"] = turn_speed
	save["auto_fire"] = auto_fire
	save["aim_assist"] = aim_assist
	save["map"] = int(settings["map"])
	save["diff"] = int(settings["diff"])
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save, "\t"))


func upgrade_cost(key: String) -> int:
	return int(150.0 * pow(1.7, int(save[key])))


func buy_upgrade(key: String) -> bool:
	if int(save[key]) >= MAX_LEVEL:
		return false
	var c := upgrade_cost(key)
	if int(save["credits"]) < c:
		return false
	save["credits"] = int(save["credits"]) - c
	save[key] = int(save[key]) + 1
	write_save()
	return true


func buy_grenade() -> bool:
	if int(save["grenades"]) >= MAX_GRENADES or int(save["credits"]) < GRENADE_COST:
		return false
	save["credits"] = int(save["credits"]) - GRENADE_COST
	save["grenades"] = int(save["grenades"]) + 1
	write_save()
	return true


func weapon_damage() -> float:
	return 20.0 + 6.0 * int(save["dmg"])


func fire_interval() -> float:
	return 0.16 * pow(0.88, int(save["rate"]))


func mag_size() -> int:
	return 24 + 8 * int(save["mag"])


func max_health() -> float:
	return 100.0 + 25.0 * int(save["armor"])


# ---------------------------------------------------------------- sounds (generated tones)
func _make_sounds() -> void:
	sounds = {
		"blaster": _tone(1500.0, 260.0, 0.18, 0.45, 0.08),
		"enemy_blaster": _tone(950.0, 170.0, 0.2, 0.4, 0.15),
		"explosion": _tone(110.0, 35.0, 0.9, 0.9, 0.85),
		"hit": _tone(1900.0, 1700.0, 0.05, 0.3, 0.0),
		"capture": _tone(660.0, 990.0, 0.4, 0.4, 0.0),
		"down": _tone(420.0, 90.0, 0.7, 0.5, 0.1),
		"reload": _tone(300.0, 520.0, 0.15, 0.3, 0.3),
		"hurt": _tone(220.0, 160.0, 0.12, 0.4, 0.5),
	}


func _tone(f0: float, f1: float, dur: float, vol: float, noise: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var t := float(i) / float(n)
		ph += TAU * lerpf(f0, f1, t) / rate
		var env := (1.0 - t) * minf(1.0, float(i) / (rate * 0.004))
		var v := sin(ph) * (1.0 - noise) + randf_range(-1.0, 1.0) * noise
		data.encode_s16(i * 2, int(clampf(v * env * env * vol, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func play_sfx(sname: String, pos = null, vol_db: float = 0.0) -> void:
	if is_headless() or not sounds.has(sname):
		return
	if pos is Vector3 and world != null:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = sounds[sname]
		p3.volume_db = vol_db
		p3.unit_size = 14.0
		world.add_child(p3)
		p3.global_position = pos
		p3.finished.connect(p3.queue_free)
		p3.play()
	else:
		var p := AudioStreamPlayer.new()
		p.stream = sounds[sname]
		p.volume_db = vol_db
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()


# ---------------------------------------------------------------- networking
func host_game(port: int) -> String:
	leave_network()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return "Could not host on port %d (error %d). Is it already in use?" % [port, err]
	multiplayer.multiplayer_peer = peer
	online = true
	players = {1: {"name": player_name}}
	lobby_changed.emit()
	return ""


## Dedicated WebSocket server (for browsers / school networks). Runs headless, no local player.
func _start_dedicated(port: int) -> void:
	leave_network()
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		push_error("Dedicated server: cannot listen on %d (error %d)" % [port, err])
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	online = true
	dedicated = true
	players = {}
	print("[server] Droid Siege dedicated WebSocket server listening on port %d" % port)


func is_web() -> bool:
	return OS.has_feature("web")


## Join a dedicated server over WebSocket. Accepts wss://host, ws://host:port, or a bare host name.
func join_ws(url: String) -> String:
	leave_network()
	var u := url.strip_edges()
	if not (u.begins_with("ws://") or u.begins_with("wss://")):
		u = "wss://" + u
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(u)
	if err != OK:
		return "Could not open WebSocket to %s (error %d)" % [u, err]
	multiplayer.multiplayer_peer = peer
	online = true
	players = {}
	return ""


func join_game(ip: String, port: int) -> String:
	leave_network()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), port)
	if err != OK:
		return "Could not start connection (error %d)" % err
	multiplayer.multiplayer_peer = peer
	online = true
	players = {}
	return ""


func leave_network() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	players = {}


func start_singleplayer() -> void:
	leave_network()
	players = {1: {"name": player_name}}
	start_mission()


func start_mission() -> void:
	if not multiplayer.is_server():
		if server_is_dedicated and is_connected_online():
			rpc_id(1, "request_start", settings)
		return
	if dedicated and players.is_empty():
		return
	write_save()
	net_all("rpc_start_mission", [players, randi(), settings])


func return_to_menu(message: String = "") -> void:
	if dedicated:
		in_mission = false
		get_tree().change_scene_to_file(MENU_SCENE)
		return
	leave_network()
	in_mission = false
	menu_message = message
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func is_connected_online() -> bool:
	return online and multiplayer.multiplayer_peer != null \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Call method locally (optional) and on every remote peer.
func net_all(method: String, args: Array = [], include_self: bool = true) -> void:
	if include_self:
		callv(method, args)
	if is_connected_online():
		callv("rpc", [method] + args)


## Call method on the server (directly if we are the server).
func net_server(method: String, args: Array = []) -> void:
	if multiplayer.is_server():
		callv(method, args)
	elif is_connected_online():
		callv("rpc_id", [1, method] + args)


## Call method on one peer (directly if that peer is us).
func net_peer(pid: int, method: String, args: Array = []) -> void:
	if pid == multiplayer.get_unique_id():
		callv(method, args)
	elif is_connected_online():
		callv("rpc_id", [pid, method] + args)


func _sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return s if s != 0 else multiplayer.get_unique_id()


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		var mission_over: bool = world != null and world.ended
		if players.size() >= MAX_PLAYERS or mission_over:
			print("Rejecting peer %d (squad full or mission over)" % id)
			multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
	var pname := str(players[id]["name"]) if players.has(id) else "A trooper"
	players.erase(id)
	if world != null:
		world.remove_player(id)
		world.show_message("%s left the game" % pname)
	if multiplayer.is_server():
		_broadcast_lobby()
		if dedicated and players.is_empty() and in_mission:
			print("[server] squad empty, back to lobby")
			return_to_menu()
	if test_mode in ["server", "server_late"] and not _test_done:
		_test_done = true
		var ok: bool = world != null and world.started and world.server_enemy_count_max > 0
		print("[test] SERVER %s: client left; enemies spawned max=%d" % ["OK" if ok else "FAIL", world.server_enemy_count_max if world else -1])
		get_tree().quit(0 if ok else 1)


func _on_connected() -> void:
	net_status.emit("Connected! Waiting for the host to start the mission...")
	rpc_id(1, "register_player", player_name)


func _on_connection_failed() -> void:
	leave_network()
	net_status.emit("Could not connect. For direct IP: check the IP/port and that the host's firewall allows UDP. For online servers: check the wss:// address and that the server is awake (free hosts can take ~1 minute to wake up).")


func _on_server_disconnected() -> void:
	return_to_menu("Lost connection to the host.")


func _broadcast_lobby() -> void:
	if is_connected_online():
		rpc("sync_lobby", players, dedicated)
	lobby_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func register_player(pname: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var clean := pname.strip_edges().substr(0, 16)
	if clean == "":
		clean = "Trooper %d" % (players.size() + 1)
	players[id] = {"name": clean}
	_broadcast_lobby()
	if in_mission:
		# Drop-in: send the late joiner straight into the running mission.
		rpc_id(id, "rpc_start_mission", players, mission_seed, settings)
		if world != null:
			world.sync_players()
			world.ready_peers[id] = true
			net_all("announce", ["%s dropped in to reinforce the squad!" % clean])


@rpc("authority", "call_remote", "reliable")
func sync_lobby(p: Dictionary, ded: bool) -> void:
	players = p
	server_is_dedicated = ded
	lobby_changed.emit()
	if world != null:
		world.sync_players()


@rpc("any_peer", "call_remote", "reliable")
func request_start(sett: Dictionary) -> void:
	# Dedicated server: any connected trooper may start (or restart) the mission.
	if not (multiplayer.is_server() and dedicated):
		return
	if world != null and not world.ended:
		return
	settings = {"map": int(sett.get("map", 0)), "diff": int(sett.get("diff", 1))}
	print("[server] mission start requested by %d settings=%s" % [multiplayer.get_remote_sender_id(), settings])
	start_mission()


@rpc("authority", "call_remote", "reliable")
func rpc_start_mission(p: Dictionary, mseed: int, sett: Dictionary) -> void:
	players = p
	settings = sett
	mission_seed = mseed
	in_mission = true
	get_tree().paused = false
	get_tree().change_scene_to_file(WORLD_SCENE)


# ---------------------------------------------------------------- mission RPC relay (forwarded to world)
@rpc("any_peer", "call_remote", "reliable")
func client_world_ready() -> void:
	if world != null and multiplayer.is_server():
		world.on_peer_ready(_sender())


@rpc("any_peer", "call_remote", "unreliable_ordered")
func player_state(pos: Vector3, ry: float, pitch: float, hp: float, st: int) -> void:
	if world != null:
		world.apply_player_state(_sender(), pos, ry, pitch, hp, st)


@rpc("any_peer", "call_remote", "unreliable")
func bolt_fx(from: Vector3, to: Vector3, kind: int) -> void:
	if world != null:
		world.spawn_bolt(from, to, kind)


@rpc("any_peer", "call_remote", "reliable")
func req_damage(eid: int, dmg: float, from: Vector3) -> void:
	if world != null and multiplayer.is_server():
		world.damage_enemy(eid, clampf(dmg, 0.0, 200.0), from, _sender(), false)


@rpc("any_peer", "call_remote", "reliable")
func req_explode(pos: Vector3) -> void:
	if world != null and multiplayer.is_server():
		world.explode(pos, _sender())


@rpc("any_peer", "call_remote", "reliable")
func grenade_fx(pos: Vector3, vel: Vector3) -> void:
	if world != null:
		world.spawn_grenade(pos, vel, false)


@rpc("authority", "call_remote", "reliable")
func explosion_fx(pos: Vector3) -> void:
	if world != null:
		world.spawn_explosion(pos)


@rpc("authority", "call_remote", "unreliable_ordered")
func enemy_states(data: PackedFloat32Array) -> void:
	if world != null:
		world.apply_enemy_states(data)


@rpc("authority", "call_remote", "reliable")
func enemy_died(eid: int, pos: Vector3, killer: int, etype: int) -> void:
	if world != null:
		world.on_enemy_died(eid, pos, killer, etype)


@rpc("authority", "call_remote", "reliable")
func hit_player(dmg: float, from: Vector3) -> void:
	if world != null:
		var lp = world.local_player()
		if lp != null:
			lp.take_damage(dmg, from)


@rpc("any_peer", "call_remote", "reliable")
func get_revived() -> void:
	if world != null:
		var lp = world.local_player()
		if lp != null:
			var by := _sender()
			lp.revive()
			if players.has(by) and by != multiplayer.get_unique_id():
				world.show_message("Revived by %s!" % players[by]["name"])


@rpc("authority", "call_remote", "unreliable_ordered")
func objective_state(ph: int, prog: Vector3, cap_mask: int, con_mask: int, t: float, k: int, ne: int, earned: int) -> void:
	if world != null:
		world.apply_objective(ph, prog, cap_mask, con_mask, t, k, ne, earned)


@rpc("authority", "call_remote", "reliable")
func announce(text: String) -> void:
	if world != null:
		world.show_message(text)


@rpc("authority", "call_remote", "reliable")
func mission_end(win: bool, credits: int, kills: int) -> void:
	if world != null:
		world.on_mission_end(win, credits, kills)


# ---------------------------------------------------------------- headless test harness
func _start_test() -> void:
	match test_mode:
		"smoke", "smoke2", "smokefail", "walkcap", "kbtest":
			player_name = "SmokeTester"
			control_mode = 1 if test_mode == "kbtest" else 0
			aim_assist = true
			settings = {"map": 1, "diff": 2} if test_mode == "smoke2" else {"map": 0, "diff": 1}
			start_singleplayer()
		"server", "server_late":
			player_name = "TestHost"
			var e := host_game(DEFAULT_PORT + 1)
			print("[test] server hosting on %d err='%s'" % [DEFAULT_PORT + 1, e])
		"client_ws":
			player_name = "WebTester"
			var e3 := join_ws("ws://127.0.0.1:%d" % (DEFAULT_WS_PORT + 1))
			print("[test] ws client joining err='%s'" % e3)
		"client":
			player_name = "TestClient"
			var e2 := join_game("127.0.0.1", DEFAULT_PORT + 1)
			print("[test] client joining err='%s'" % e2)
		"menu":
			pass
		"shot":
			await get_tree().create_timer(2.5).timeout
			await _save_shot("/tmp/ds_menu.png")
			settings = {"map": 1, "diff": 1}
			start_singleplayer()
			await get_tree().create_timer(9.0).timeout
			_save_shot("/tmp/ds_game.png")
			get_tree().quit(0)


func _process(_delta: float) -> void:
	if test_mode == "" or _test_done:
		return
	var elapsed := (Time.get_ticks_msec() - _test_start_ms) / 1000.0
	match test_mode:
		"menu":
			if elapsed > 2.0:
				_test_done = true
				var scene := get_tree().current_scene
				print("[test] MENU OK scene=", scene.name if scene else "none")
				get_tree().quit(0)
		"server", "server_late":
			if test_mode == "server_late" and not in_mission:
				print("[test] server_late: starting mission solo before client joins")
				start_mission()
			if not in_mission and players.size() >= 2:
				print("[test] server: client registered, starting mission. players=", players)
				start_mission()
			if elapsed > 90.0:
				_test_done = true
				print("[test] SERVER FAIL timeout")
				get_tree().quit(1)
		"client_ws":
			if not in_mission and server_is_dedicated and players.size() >= 1 and elapsed > 1.0:
				start_mission()  # any trooper can start on a dedicated server
			if world != null and world.enemy_state_packets > 30 and world.enemies.size() > 0 \
					and world.players.size() == players.size() and not players.has(1):
				_test_done = true
				print("[test] WS CLIENT OK: dedicated=%s players=%d enemies=%d enemy_packets=%d" % [
					server_is_dedicated, world.players.size(), world.enemies.size(), world.enemy_state_packets])
				net_server("req_damage", [int(world.enemies.keys()[0]), 5.0, Vector3.ZERO])
				await get_tree().create_timer(0.5).timeout
				leave_network()
				get_tree().quit(0)
			elif elapsed > 80.0:
				_test_done = true
				print("[test] WS CLIENT FAIL timeout")
				get_tree().quit(1)
		"client":
			if world != null and world.enemy_state_packets > 30 and world.players.size() == 2 \
					and world.enemies.size() > 0 and world.remote_state_packets > 10:
				_test_done = true
				print("[test] CLIENT OK: players=%d enemies=%d enemy_packets=%d player_packets=%d phase=%d" % [
					world.players.size(), world.enemies.size(), world.enemy_state_packets,
					world.remote_state_packets, world.phase])
				# shoot one bolt request at an enemy to exercise client->server damage
				var eid: int = world.enemies.keys()[0]
				net_server("req_damage", [eid, 5.0, Vector3.ZERO])
				await get_tree().create_timer(0.5).timeout
				leave_network()
				get_tree().quit(0)
			elif elapsed > 80.0:
				_test_done = true
				print("[test] CLIENT FAIL timeout world=%s" % [world != null])
				get_tree().quit(1)
		"smoke", "smoke2", "smokefail", "walkcap", "kbtest":
			if elapsed > 150.0:
				_test_done = true
				print("[test] SMOKE FAIL timeout phase=", world.phase if world else -1)
				get_tree().quit(1)


func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[test] saved ", path)


func finish_test(ok: bool, text: String) -> void:
	if _test_done:
		return
	_test_done = true
	print("[test] %s %s" % ["OK" if ok else "FAIL", text])
	get_tree().quit(0 if ok else 1)
