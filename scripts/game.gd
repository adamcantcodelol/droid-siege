extends Node
const TrooperClass = preload("res://scripts/trooper_class.gd")
## Global autoload: save data, upgrades, networking, RPC relay, generated sounds, test harness.

const SAVE_PATH := "user://droid_siege_save.json"
const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const GAME_VERSION := "1.3.1"
const MAX_LEVEL := 5
const GRENADE_COST := 100
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
	{"name": "Geonosis Canyon Outpost", "layout": "geonosis",
		"posts": [Vector3(0, 0, -30), Vector3(50, 0, 10), Vector3(-45, 0, 35)],
		"lz": Vector3(0, 0, 72), "spawns": [Vector3(0, 0, 80), Vector3(-8, 0, -82)],
		"ground": Color(0.6, 0.4, 0.25), "cliff": Color(0.62, 0.4, 0.26), "rock": Color(0.66, 0.44, 0.3),
		"sky_top": Color(0.42, 0.3, 0.24), "sky_hor": Color(0.95, 0.68, 0.42),
		"fog": Color(0.88, 0.62, 0.4), "fog_density": 0.006, "sun": Color(1.0, 0.88, 0.7), "sun_energy": 1.1,
		"ambient": 0.5, "sun_rot": Vector3(-42, 30, 0), "post_col": Color(0.6, 0.55, 0.5), "high": [Vector3(-24, 5, 0), Vector3(24, 5, 38), Vector3(-24, 5, -45)]},
	{"name": "Felucia Jungle Ruins", "layout": "felucia",
		"posts": [Vector3(-50, 0, -40), Vector3(40, 0, -45), Vector3(10, 0, 20)],
		"lz": Vector3(60, 0, 70), "spawns": [Vector3(60, 0, 82), Vector3(-60, 0, -82)],
		"ground": Color(0.22, 0.36, 0.22), "cliff": Color(0.18, 0.22, 0.2), "rock": Color(0.42, 0.28, 0.52),
		"sky_top": Color(0.05, 0.1, 0.16), "sky_hor": Color(0.2, 0.38, 0.34),
		"fog": Color(0.2, 0.36, 0.32), "fog_density": 0.013, "sun": Color(0.7, 0.85, 1.0), "sun_energy": 0.55,
		"ambient": 0.7, "sun_rot": Vector3(-60, -40, 0), "post_col": Color(0.45, 0.5, 0.44), "lz_glow": Color(0.4, 1.0, 0.8), "high": [Vector3(-5, 3, -54), Vector3(-5, 6, -64)]},
	{"name": "Kamino Storm Platform", "layout": "kamino",
		"posts": [Vector3(-40, 0, -35), Vector3(45, 0, -20), Vector3(0, 0, 30)],
		"lz": Vector3(0, 0, 72), "spawns": [Vector3(0, 0, 84), Vector3(0, 0, -84)],
		"ground": Color(0.3, 0.33, 0.37), "cliff": Color(0.3, 0.32, 0.36), "rock": Color(0.5, 0.52, 0.56),
		"sky_top": Color(0.12, 0.15, 0.2), "sky_hor": Color(0.35, 0.42, 0.5),
		"fog": Color(0.36, 0.42, 0.5), "fog_density": 0.011, "sun": Color(0.75, 0.82, 1.0), "sun_energy": 0.6,
		"ambient": 0.5, "sun_rot": Vector3(-65, 20, 0), "post_col": Color(0.75, 0.78, 0.82), "lz_glow": Color(0.5, 0.8, 1.0), "high": [Vector3(0, 3, -5)]},
	{"name": "Umbara Shadow Airbase", "layout": "umbara",
		"posts": [Vector3(-35, 0, -25), Vector3(40, 0, -30), Vector3(5, 0, 25)],
		"lz": Vector3(0, 0, 75), "spawns": [Vector3(0, 0, 84), Vector3(0, 0, -84)],
		"ground": Color(0.08, 0.06, 0.14), "cliff": Color(0.12, 0.08, 0.2), "rock": Color(0.18, 0.12, 0.3),
		"sky_top": Color(0.02, 0.02, 0.08), "sky_hor": Color(0.18, 0.08, 0.35),
		"fog": Color(0.12, 0.06, 0.22), "fog_density": 0.014, "sun": Color(0.55, 0.7, 1.0), "sun_energy": 0.35,
		"ambient": 0.55, "sun_rot": Vector3(-55, -20, 0), "post_col": Color(0.35, 0.55, 0.7), "lz_glow": Color(0.3, 1.0, 0.95), "high": [Vector3(0, 6.05, -5)]},
	{"name": "Christophsis Crystal Plaza", "layout": "christophsis",
		"posts": [Vector3(-40, 0, -20), Vector3(45, 0, -25), Vector3(0, 0, 30)],
		"lz": Vector3(55, 0, 70), "spawns": [Vector3(60, 0, 82), Vector3(-60, 0, -82)],
		"ground": Color(0.22, 0.32, 0.4), "cliff": Color(0.18, 0.28, 0.38), "rock": Color(0.25, 0.55, 0.65),
		"sky_top": Color(0.08, 0.16, 0.28), "sky_hor": Color(0.35, 0.65, 0.75),
		"fog": Color(0.3, 0.55, 0.65), "fog_density": 0.008, "sun": Color(0.7, 0.9, 1.0), "sun_energy": 0.85,
		"ambient": 0.6, "sun_rot": Vector3(-48, 40, 0), "post_col": Color(0.45, 0.75, 0.85), "lz_glow": Color(0.4, 0.95, 1.0), "high": []},
	{"name": "Mustafar Lava Refinery", "layout": "mustafar",
		"posts": [Vector3(-30, 0, -35), Vector3(35, 0, -20), Vector3(0, 0, 25)],
		"lz": Vector3(0, 0, 72), "spawns": [Vector3(-8, 0, 82), Vector3(8, 0, -82)],
		"ground": Color(0.18, 0.1, 0.08), "cliff": Color(0.12, 0.08, 0.07), "rock": Color(0.25, 0.12, 0.08),
		"sky_top": Color(0.15, 0.05, 0.02), "sky_hor": Color(0.55, 0.2, 0.08),
		"fog": Color(0.45, 0.18, 0.08), "fog_density": 0.012, "sun": Color(1.0, 0.55, 0.25), "sun_energy": 0.9,
		"ambient": 0.45, "sun_rot": Vector3(-35, 10, 0), "post_col": Color(0.55, 0.35, 0.25), "lz_glow": Color(1.0, 0.45, 0.15), "high": [Vector3(0, 1.0, 5)],
		"lava": [Vector3(0, -0.4, 0), Vector3(50, -0.4, 40), Vector3(-45, -0.4, -20)]},
]
var DIFFICULTIES: Array = [
	{"name": "Cadet", "hp": 0.75, "dmg": 0.55, "cap": -1, "credits": 0.7, "react": 0.55, "lead": 0.0, "ai": 0},
	{"name": "Trooper", "hp": 1.0, "dmg": 1.0, "cap": 0, "credits": 1.0, "react": 0.30, "lead": 0.0, "ai": 1},
	{"name": "Veteran", "hp": 1.2, "dmg": 1.25, "cap": 2, "credits": 1.35, "react": 0.14, "lead": 0.55, "ai": 2},
	{"name": "Clone Commander", "hp": 1.4, "dmg": 1.5, "cap": 4, "credits": 1.7, "react": 0.05, "lead": 0.9, "ai": 3},
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
## Room-code relay (relay/relay.js). Paste your deployed relay address here before exporting,
## e.g. "wss://droid-siege-relay.onrender.com". Players can also override it under Advanced.
const RELAY_URL := "wss://droid-siege.moeller-basil.workers.dev/ws"
## Free Render backup (auto-fallback when Cloudflare is blocked / room not found there).
const BACKUP_RELAY_URL := "wss://droid-siege-relay.onrender.com"
const RelayPeerScript = preload("res://scripts/relay_peer.gd")
var room_code := ""
var _pending_relay = null
var mission_seed := 1
var settings := {"map": 0, "diff": 1, "mode": 0}
var world: Node = null
var test_mode := ""
var sounds := {}
var menu_message := ""
var mouse_sensitivity := 0.0025
var control_mode := 0      # 0 = mouse + keyboard, 1 = trackpad / keyboard only
var turn_speed := 2.6      # radians per second for keyboard turning
var auto_fire := false
var aim_assist := true
const GAME_MODES := ["Co-op: Droid Siege (capture 3 posts)", "Versus: Team Deathmatch (1v1-2v2)", "Versus: Free-for-All", "Co-op: Horde Survival (4 min)",
	"Versus: King of the Hill (hold the zone)", "Versus: Capture the Flag (first to 3)", "Co-op: Hold the Line (defend one post)"]
const HORDE := 3
const KOTH := 4
const CTF := 5
const HOLD := 6


func is_versus_mode(m: int) -> bool:
	return m in [1, 2, KOTH, CTF]


## Rpc: the gunship lifts off with the listed troopers aboard (cinematic on every peer).
@rpc("authority", "call_remote", "reliable")
func extract_liftoff(ids: Array) -> void:
	if world != null:
		world.on_extract_liftoff(ids)


## Rpc: CTF flag state. carriers = [red flag carrier pid, blue flag carrier pid] (0 = none),
## positions of both flags (home or dropped).
@rpc("authority", "call_remote", "unreliable_ordered")
func flag_state(carriers: Vector2i, red_pos: Vector3, blue_pos: Vector3, koth_owner: int, koth_mask: int) -> void:
	if world != null:
		world.apply_flag_state(carriers, red_pos, blue_pos, koth_owner, koth_mask)
const CONTROL_MODES := ["Mouse + Keyboard", "Trackpad / Keyboard Only"]
var _test_start_ms := 0
var _test_done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.size_changed.connect(_refresh_render_scale)
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
		return "TRACKPAD / KEYBOARD: WASD move, Arrows or J/L turn + I/K look, F or Ctrl fire (trackpad tap also fires), Q or Alt toggle aim, Shift sprint, Space jump, C crouch / Z toggle, R reload, G grenade, E (hold) revive, X battle command (Officer), Esc/P/M or Menu button pause. Aim assist pulls toward droids near the crosshair%s." % (", auto-fire ON" if auto_fire else "")
	return "MOUSE + KEYBOARD: WASD move, Mouse look, Left click fire, Right click aim, Shift sprint, Space jump, C crouch / Z toggle, R reload, G grenade, E (hold) revive, X battle command (Officer), Esc/P/M or Menu button pause. On the web Esc unlocks the mouse and opens pause — click Resume to recapture."


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
	var qrow := HBoxContainer.new()
	var ql := Label.new()
	ql.text = "Graphics:"
	qrow.add_child(ql)
	var qo := OptionButton.new()
	qo.add_item("Auto (%s)" % QUALITY_NAMES[quality() if int(save.get("quality", -1)) < 0 else 0])
	for n in QUALITY_NAMES:
		qo.add_item(n)
	qo.selected = int(save.get("quality", -1)) + 1
	qo.item_selected.connect(func(i): save["quality"] = i - 1; write_save(); apply_quality())
	qrow.add_child(qo)
	box.add_child(qrow)


const QUALITY_NAMES := ["Low", "Medium", "High"]


## Effective graphics quality: saved choice, or auto (Low on web / integrated GPUs, High on discrete).
func quality() -> int:
	var q := int(save.get("quality", -1))
	if q >= 0:
		return clampi(q, 0, 2)
	if OS.has_feature("web"):
		return 0
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	for k in ["nvidia", "geforce", "rtx", "radeon rx"]:
		if k in gpu:
			return 2
	return 0


func quality_name() -> String:
	return QUALITY_NAMES[quality()]


## Apply the preset to the running world (render scale, shadows, glow, MSAA, rain, anim LOD).
func apply_quality() -> void:
	var q := quality()
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = render_scale(q) * dyn_scale
	vp.msaa_3d = Viewport.MSAA_2X if q == 2 else Viewport.MSAA_DISABLED
	vp.mesh_lod_threshold = [6.0, 2.0, 1.0][q]   # v1.3: lean on automatic mesh LODs on Low
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096][q], true)
	var CM = load("res://scripts/char_model.gd")
	CM.anim_lod_far = [20.0, 35.0, 60.0][q]
	CM.anim_lod_every = [4, 3, 2][q]
	CM.cull_dist = [85.0, 120.0, 0.0][q]
	var cam := vp.get_camera_3d()
	if cam != null:
		cam.far = [140.0, 220.0, 400.0][q]
	if world != null:
		world.apply_quality(q)


## 3D render scale. High-DPI screens (Surface Pro: 2880x1920 at 200%) make the browser canvas
## huge, so Low/Medium target a fixed 3D pixel budget instead of a flat percentage.
func render_scale(q: int) -> float:
	var sz := Vector2(get_viewport().size)
	var px := maxf(sz.x * sz.y, 1.0)
	var budget: float = [640.0 * 400.0 * 1.6, 1280.0 * 720.0, 1920.0 * 1080.0][q]
	var cap: float = [0.75, 0.9, 1.0][q]
	return clampf(sqrt(budget / px), 0.35, cap)


## Dynamic resolution on Low: if the frame rate sits under ~28 fps the 3D render scale steps down
## (to 60 % of the Low preset at most); it creeps back up when there is headroom.
var dyn_scale := 1.0
var _dyn_t := 0.0
var _dyn_frames := 0


func _dynamic_resolution(delta: float) -> void:
	if world == null or is_headless() or quality() != 0:
		dyn_scale = 1.0
		return
	_dyn_t += delta
	_dyn_frames += 1
	if _dyn_t < 2.0:
		return
	var fps := _dyn_frames / _dyn_t
	_dyn_t = 0.0
	_dyn_frames = 0
	var old := dyn_scale
	if fps < 28.0:
		dyn_scale = maxf(0.6, dyn_scale * 0.9)
	elif fps > 50.0:
		dyn_scale = minf(1.0, dyn_scale * 1.05)
	if absf(old - dyn_scale) > 0.001:
		_refresh_render_scale()


func _refresh_render_scale() -> void:
	if world != null:
		get_viewport().scaling_3d_scale = maxf(0.25, render_scale(quality()) * dyn_scale)


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
	_bind("pause", [KEY_ESCAPE, KEY_P, KEY_M])
	_bind("scoreboard", [KEY_TAB])
	_bind("weapon1", [KEY_1])
	_bind("view_toggle", [KEY_V])
	_bind("weapon2", [KEY_2])
	_bind("weapon_next", [KEY_3])
	_bind("crouch", [KEY_C])
	_bind("crouch_toggle", [KEY_Z])
	_bind("battle_cmd", [KEY_X])
	_bind("emote", [KEY_B])
	_bind("emote1", [KEY_5])
	_bind("emote2", [KEY_6])
	_bind("emote3", [KEY_7])
	_bind("emote4", [KEY_8])
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
		"missions": 0, "wins": 0, "name": "Trooper", "sens": 0.0025, "map": 0, "diff": 1, "controls": 0, "turn_speed": 2.6, "auto_fire": false, "aim_assist": true, "ws_url": "", "relay_url": "", "relay_pref": 0, "mode": 0, "quality": -1, "fp": false, "cls": 0, "xp": 0}


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
	save["grenades"] = maxi(2, int(save["grenades"]))   # grenade tier (old saves may have been drained)
	save["xp"] = maxi(int(save.get("xp", 0)), int(save.get("credits", 0)))
	player_name = str(save["name"])
	settings = {"map": int(save["map"]), "diff": int(save["diff"]), "mode": int(save["mode"])}
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
	save["mode"] = int(settings.get("mode", 0))
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save, "\t"))


const UPGRADE_COSTS := [150, 300, 500, 800, 1200]


func upgrade_cost(key: String) -> int:
	return UPGRADE_COSTS[clampi(int(save[key]), 0, UPGRADE_COSTS.size() - 1)]


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


func trooper_cls() -> int:
	return TrooperClass.clamp_id(int(save.get("cls", 0)))


func class_def() -> Dictionary:
	return TrooperClass.def(trooper_cls())


func class_weapon(slot: int = -1) -> Dictionary:
	var lp = world.local_player() if world != null else null
	var s: int = slot if slot >= 0 else (lp.weapon if lp != null else 0)
	return TrooperClass.weapon(trooper_cls(), s)


func weapon_damage(slot: int = -1) -> float:
	var w := class_weapon(slot)
	var base: float = float(w.get("dmg", 20.0))
	var mult := 1.0 + 0.06 * int(save["dmg"])  # armory still scales
	# Officer aura (self half) applied by caller when relevant
	return base * mult


func fire_interval(slot: int = -1) -> float:
	var w := class_weapon(slot)
	var base: float = float(w.get("interval", 0.16))
	return base * pow(0.92, int(save["rate"]))


func mag_size(slot: int = -1) -> int:
	var w := class_weapon(slot)
	return int(w.get("mag", 24)) + 8 * int(save["mag"])


func max_health() -> float:
	var base: float = float(class_def().get("hp", 100.0))
	return base + 25.0 * int(save["armor"])


func class_speed_mult() -> float:
	return float(class_def().get("speed", 1.0))


const RANK_XP := [0, 200, 500, 900, 1500, 2300, 3300, 4600, 6200, 8200]
var _rank_icons := {}


func add_credits(amount: int) -> void:
	if amount <= 0:
		return
	save["credits"] = int(save.get("credits", 0)) + amount
	save["xp"] = int(save.get("xp", 0)) + amount
	write_save()


func rank_for_xp(xp: int) -> int:
	var r := 0
	for i in RANK_XP.size():
		if xp >= int(RANK_XP[i]):
			r = i
	return r


func local_rank() -> int:
	return rank_for_xp(int(save.get("xp", 0)))


func peer_rank(pid: int) -> int:
	if players.has(pid) and players[pid].has("rank"):
		return clampi(int(players[pid]["rank"]), 0, RANK_XP.size() - 1)
	if pid == multiplayer.get_unique_id():
		return local_rank()
	return 0


func xp_progress() -> Dictionary:
	var xp := int(save.get("xp", 0))
	var r := rank_for_xp(xp)
	var cur := int(RANK_XP[r])
	var nxt := int(RANK_XP[mini(r + 1, RANK_XP.size() - 1)])
	var frac := 1.0 if r >= RANK_XP.size() - 1 else clampf(float(xp - cur) / float(maxi(nxt - cur, 1)), 0.0, 1.0)
	return {"rank": r, "xp": xp, "cur_floor": cur, "next_ceil": nxt, "frac": frac}


## Procedural 24x24 military rank badge (icon only — no text titles).
func rank_icon(rank: int) -> ImageTexture:
	rank = clampi(rank, 0, 9)
	if _rank_icons.has(rank):
		return _rank_icons[rank]
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var plate := Color(0.12, 0.14, 0.18, 0.95)
	var edge := Color(0.55, 0.58, 0.62, 1.0)
	var mark := Color(0.85, 0.88, 0.92, 1.0)
	if rank >= 7:
		mark = Color(1.0, 0.85, 0.25, 1.0)
	elif rank >= 5:
		mark = Color(0.75, 0.82, 0.95, 1.0)
	elif rank >= 9:
		mark = Color(1.0, 0.45, 0.2, 1.0)
	if rank >= 9:
		mark = Color(1.0, 0.55, 0.15, 1.0)
	# plate + border
	for y in range(2, 22):
		for x in range(2, 22):
			var border := x == 2 or x == 21 or y == 2 or y == 21
			img.set_pixel(x, y, edge if border else plate)
	# draw chevrons / pips by rank
	var draw_chev := func(cy: int, col: Color):
		for i in 7:
			var x0 := 12 - i
			var x1 := 12 + i
			var yy := cy + i
			if yy < 22:
				if x0 >= 3: img.set_pixel(x0, yy, col)
				if x1 <= 20: img.set_pixel(x1, yy, col)
				if x0 + 1 >= 3 and x0 + 1 <= 20: img.set_pixel(x0 + 1, yy, col)
				if x1 - 1 >= 3: img.set_pixel(x1 - 1, yy, col)
	var draw_rocker := func(cy: int, col: Color):
		for i in 8:
			var x0 := 5 + i
			var yy := cy + int((i - 3.5) * (i - 3.5) * 0.15)
			if x0 <= 18 and yy >= 3 and yy <= 20:
				img.set_pixel(x0, yy, col)
				img.set_pixel(x0, yy + 1, col)
	var draw_diamond := func(cx: int, cy: int, col: Color):
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if abs(dx) + abs(dy) <= 3:
					var xx := cx + dx
					var yy := cy + dy
					if xx >= 3 and xx <= 20 and yy >= 3 and yy <= 20:
						img.set_pixel(xx, yy, col)
	var draw_star := func(cx: int, cy: int, col: Color):
		for a in 5:
			var ang := -PI / 2.0 + a * TAU / 5.0
			for s in range(0, 5):
				var xx := cx + int(cos(ang) * s * 0.7)
				var yy := cy + int(sin(ang) * s * 0.7)
				if xx >= 3 and xx <= 20 and yy >= 3 and yy <= 20:
					img.set_pixel(xx, yy, col)
		img.set_pixel(cx, cy, col)
	match rank:
		0:
			img.set_pixel(12, 12, mark)
			img.set_pixel(11, 12, mark)
			img.set_pixel(13, 12, mark)
		1:
			draw_chev.call(8, mark)
		2:
			draw_chev.call(6, mark)
			draw_chev.call(10, mark)
		3:
			draw_chev.call(5, mark)
			draw_chev.call(8, mark)
			draw_chev.call(11, mark)
		4:
			draw_chev.call(5, mark)
			draw_chev.call(8, mark)
			draw_chev.call(11, mark)
			draw_rocker.call(16, mark)
		5:
			draw_chev.call(6, mark)
			draw_chev.call(9, mark)
			draw_rocker.call(14, mark)
			draw_rocker.call(17, mark)
		6:
			draw_diamond.call(12, 11, mark)
		7:
			draw_star.call(12, 11, mark)
		8:
			draw_star.call(8, 11, mark)
			draw_star.call(16, 11, mark)
		9:
			draw_star.call(12, 8, mark)
			draw_diamond.call(12, 15, Color(1.0, 0.35, 0.15, 1.0))
			draw_rocker.call(18, mark)
	var tex := ImageTexture.create_from_image(img)
	_rank_icons[rank] = tex
	return tex




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
		"scatter": _tone(700.0, 90.0, 0.32, 0.6, 0.55),
		"switch": _tone(900.0, 1300.0, 0.06, 0.25, 0.2),
		"kill": _tone(1200.0, 1800.0, 0.09, 0.25, 0.0),
		"step": _tone(140.0, 90.0, 0.05, 0.18, 0.7),
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
	players = {1: {"name": player_name, "rank": local_rank(), "cls": trooper_cls()}}
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


func relay_url() -> String:
	var u := str(save.get("relay_url", "")).strip_edges()
	return u if u != "" else primary_relay()


func primary_relay() -> String:
	return BACKUP_RELAY_URL if int(save.get("relay_pref", 0)) == 1 else RELAY_URL


func backup_relay() -> String:
	return RELAY_URL if int(save.get("relay_pref", 0)) == 1 else BACKUP_RELAY_URL


## Ordered relay candidates. Custom Advanced URL disables dual-fallback.
func relay_candidates() -> Array:
	var custom := str(save.get("relay_url", "")).strip_edges()
	if custom != "":
		return [custom]
	var a := primary_relay()
	var b := backup_relay()
	var out: Array = []
	if a != "":
		out.append(a)
	if b != "" and b != a:
		out.append(b)
	return out


func _wake_backup_relay() -> void:
	if BACKUP_RELAY_URL == "":
		return
	var http := HTTPRequest.new()
	http.timeout = 25.0
	add_child(http)
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	var u := BACKUP_RELAY_URL.replace("wss://", "https://").replace("ws://", "http://")
	if u.ends_with("/ws"):
		u = u.substr(0, u.length() - 3)
	http.request(u + "/")


var _relay_attempt_id := 0
var _relay_using_backup := false


## Host through the relay: the relay hands back a short room code for friends to type.
## Tries Primary then Backup (~3.5s / ~15s) unless a custom Advanced URL is set.
func host_room() -> String:
	leave_network()
	var urls: Array = relay_candidates()
	if urls.is_empty():
		return "No relay server set. Open Advanced and paste the relay address (see README), or use Direct IP."
	_relay_attempt_id += 1
	_try_host(urls, 0, _relay_attempt_id)
	net_status.emit("Contacting relay for a room code...")
	return ""


func _try_host(urls: Array, idx: int, attempt: int) -> void:
	if attempt != _relay_attempt_id:
		return
	if idx >= urls.size():
		_pending_relay = null
		net_status.emit("Could not reach any relay. Check your network, or try Relay: Backup (Render) / Advanced.")
		return
	var url: String = urls[idx]
	_relay_using_backup = (BACKUP_RELAY_URL != "" and url.find("onrender.com") >= 0)
	var peer = RelayPeerScript.new()
	var err: int = peer.start_host(url)
	if err != OK:
		_try_host(urls, idx + 1, attempt)
		return
	var done := {"v": false}
	peer.room_ready.connect(func(code):
		if done["v"] or attempt != _relay_attempt_id:
			return
		done["v"] = true
		_on_room_ready(code, peer)
	)
	peer.relay_error.connect(func(msg):
		if done["v"] or attempt != _relay_attempt_id:
			return
		done["v"] = true
		if peer == _pending_relay:
			_pending_relay = null
		peer.close()
		net_status.emit("Relay busy/unreachable — trying backup..." if idx + 1 < urls.size() else msg)
		_try_host(urls, idx + 1, attempt)
	)
	_pending_relay = peer
	var wait := 15.0 if _relay_using_backup else 3.5
	net_status.emit(("Contacting backup relay (Render may need ~15s to wake)..." if _relay_using_backup else "Contacting relay for a room code...") )
	get_tree().create_timer(wait).timeout.connect(func():
		if done["v"] or attempt != _relay_attempt_id:
			return
		done["v"] = true
		if peer == _pending_relay:
			_pending_relay = null
		peer.close()
		net_status.emit("Relay timed out — trying backup..." if idx + 1 < urls.size() else "Relay timed out.")
		_try_host(urls, idx + 1, attempt)
	)


func _on_room_ready(code: String, peer) -> void:
	_pending_relay = null
	room_code = code
	multiplayer.multiplayer_peer = peer
	online = true
	players = {1: {"name": player_name, "rank": local_rank(), "cls": trooper_cls()}}
	print("[relay] hosting room ", code, " backup=" , _relay_using_backup)
	var tag := " (Backup)" if _relay_using_backup else ""
	net_status.emit("Room code: %s%s  -  tell your squad to type it in Join with Code." % [code, tag])
	lobby_changed.emit()


## Join by room code. Tries Primary then Backup; also switches relays if the first
## answers "No room with code" (host may have landed on the other free relay).
func join_room(code: String) -> String:
	leave_network()
	var urls: Array = relay_candidates()
	if urls.is_empty():
		return "No relay server set. Open Advanced and paste the relay address (see README), or use Direct IP."
	var clean := code.strip_edges().to_upper()
	if clean.length() < 4:
		return "Type the room code your host sees (5 letters/numbers)."
	_relay_attempt_id += 1
	room_code = clean
	_try_join(urls, 0, clean, _relay_attempt_id)
	net_status.emit("Joining room %s ..." % clean)
	return ""


func _try_join(urls: Array, idx: int, clean: String, attempt: int) -> void:
	if attempt != _relay_attempt_id:
		return
	if idx >= urls.size():
		_pending_relay = null
		net_status.emit("No room with code %s on Primary or Backup. Check the code with your host." % clean)
		return
	var url: String = urls[idx]
	_relay_using_backup = (BACKUP_RELAY_URL != "" and url.find("onrender.com") >= 0)
	var peer = RelayPeerScript.new()
	var err: int = peer.start_join(url, clean)
	if err != OK:
		_try_join(urls, idx + 1, clean, attempt)
		return
	# Assign early so MultiplayerAPI sees connected_to_server / register_player (same as pre-fallback).
	multiplayer.multiplayer_peer = peer
	online = true
	players = {}
	_pending_relay = peer
	var done := {"v": false}
	peer.peer_connected.connect(func(id):
		if id != 1 or done["v"] or attempt != _relay_attempt_id:
			return
		done["v"] = true
		_pending_relay = null
		print("[relay] joined room ", clean, " via ", url)
		var tag := " (Backup)" if _relay_using_backup else ""
		net_status.emit("Joined room %s%s." % [clean, tag])
		lobby_changed.emit()
	)
	peer.relay_error.connect(func(msg):
		if done["v"] or attempt != _relay_attempt_id:
			return
		done["v"] = true
		_pending_relay = null
		# Tear down this attempt without clearing the attempt id, then retry other relay.
		if multiplayer.multiplayer_peer == peer:
			peer.close()
			multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
			online = false
		var no_room: bool = str(msg).begins_with("No room with code")
		if idx + 1 < urls.size():
			net_status.emit("Trying the other relay for code %s..." % clean)
			_try_join(urls, idx + 1, clean, attempt)
		else:
			net_status.emit(msg if no_room else str(msg))
	)
	var wait := 15.0 if _relay_using_backup else 3.5
	get_tree().create_timer(wait).timeout.connect(func():
		if done["v"] or attempt != _relay_attempt_id:
			return
		done["v"] = true
		_pending_relay = null
		if multiplayer.multiplayer_peer == peer:
			peer.close()
			multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
			online = false
		if idx + 1 < urls.size():
			net_status.emit("Trying the other relay for code %s..." % clean)
			_try_join(urls, idx + 1, clean, attempt)
		else:
			net_status.emit("Could not join room %s (timed out)." % clean)
	)



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
	if _pending_relay != null:
		_pending_relay.close()
		_pending_relay = null
	room_code = ""
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	players = {}


func start_singleplayer() -> void:
	leave_network()
	players = {1: {"name": player_name, "rank": local_rank(), "cls": trooper_cls()}}
	if is_versus_mode(int(settings.get("mode", 0))):
		settings["mode"] = 0   # versus needs other players; solo falls back to co-op
	start_mission()


func start_mission() -> void:
	if not multiplayer.is_server():
		if server_is_dedicated and is_connected_online():
			rpc_id(1, "request_start", settings)
		return
	if dedicated and players.is_empty():
		return
	write_save()
	_assign_teams()
	net_all("rpc_start_mission", [players, randi(), settings])


## Host decides teams so every peer (including late joiners) agrees.
func _assign_teams() -> void:
	var keys := players.keys()
	keys.sort()
	for i in keys.size():
		players[keys[i]]["team"] = i if int(settings.get("mode", 0)) == 2 else i % 2


func _team_for_new_player() -> int:
	if int(settings.get("mode", 0)) == 2:
		return players.size()
	var c := [0, 0]
	for v in players.values():
		if v.has("team"):
			c[clampi(int(v["team"]), 0, 1)] += 1
	return 0 if c[0] <= c[1] else 1


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


## Tracks nested synchronous callv during local net_* so _sender() stays correct for PvP.
var _local_rpc_depth := 0


func _local_callv(method: String, args: Array) -> void:
	_local_rpc_depth += 1
	callv(method, args)
	_local_rpc_depth -= 1


## Call method locally (optional) and on every remote peer.
func net_all(method: String, args: Array = [], include_self: bool = true) -> void:
	if include_self:
		_local_callv(method, args)
	if is_connected_online():
		callv("rpc", [method] + args)


## Call method on the server (directly if we are the server).
func net_server(method: String, args: Array = []) -> void:
	if multiplayer.is_server():
		_local_callv(method, args)
	elif is_connected_online():
		callv("rpc_id", [1, method] + args)


## Call method on one peer (directly if that peer is us).
func net_peer(pid: int, method: String, args: Array = []) -> void:
	if pid == multiplayer.get_unique_id():
		_local_callv(method, args)
	elif is_connected_online():
		callv("rpc_id", [pid, method] + args)


func _sender() -> int:
	# Nested local callv keeps the outer remote sender id; return our id instead.
	if _local_rpc_depth > 0:
		return multiplayer.get_unique_id()
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
	rpc_id(1, "register_player", player_name, local_rank(), trooper_cls())


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
func register_player(pname: String, prank: int = 0, pcls: int = 0) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var clean := pname.strip_edges().substr(0, 16)
	if clean == "":
		clean = "Trooper %d" % (players.size() + 1)
	players[id] = {"name": clean, "rank": clampi(prank, 0, 9), "cls": TrooperClass.clamp_id(pcls)}
	if in_mission:
		players[id]["team"] = _team_for_new_player()
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
	settings = {"map": int(sett.get("map", 0)), "diff": int(sett.get("diff", 1)), "mode": int(sett.get("mode", 0))}
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


@rpc("any_peer", "call_remote", "reliable")
func mech_enter(i: int, pid: int) -> void:
	if world != null:
		world.on_mech_enter(i, pid)


@rpc("any_peer", "call_remote", "reliable")
func mech_exit(i: int, pos: Vector3, ry: float) -> void:
	if world != null:
		world.on_mech_exit(i, pos, ry)


@rpc("any_peer", "call_remote", "unreliable")
func bolt_fx(from: Vector3, to: Vector3, kind: int) -> void:
	if world != null:
		world.spawn_bolt(from, to, kind)
		if kind != 1 and kind != 3:
			world.player_bolt(from, to)


@rpc("any_peer", "call_remote", "reliable")
func req_damage(eid: int, dmg: float, from: Vector3) -> void:
	if world != null and multiplayer.is_server():
		world.damage_enemy(eid, clampf(dmg, 0.0, 200.0), from, _sender(), false)


@rpc("any_peer", "call_remote", "reliable")
func req_explode(pos: Vector3) -> void:
	if world != null and multiplayer.is_server():
		world.explode(pos, _sender())


@rpc("any_peer", "call_remote", "reliable")
func req_micro_splash(pos: Vector3, dmg: float, radius: float) -> void:
	if world != null and multiplayer.is_server():
		world.micro_splash(pos, _sender(), clampf(dmg, 0.0, 120.0), clampf(radius, 0.5, 8.0))


@rpc("authority", "call_remote", "reliable")
func battle_cmd_fx() -> void:
	if world != null:
		var lp = world.local_player()
		if lp != null:
			lp.bonus_hp = maxf(lp.bonus_hp, 25.0)
			lp.cmd_buff_t = maxf(lp.cmd_buff_t, 6.0)


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
func hit_player(dmg: float, from: Vector3, attacker_id: int = 0) -> void:
	if world != null:
		var lp = world.local_player()
		if lp != null:
			lp.take_damage(dmg, from, attacker_id)


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


@rpc("any_peer", "call_remote", "reliable")
func req_pvp_damage(target: int, dmg: float, from: Vector3) -> void:
	if world != null and multiplayer.is_server():
		world.pvp_damage(_sender(), target, clampf(dmg, 0.0, 200.0), from)


@rpc("any_peer", "call_remote", "reliable")
func pvp_died(killer_id: int = 0) -> void:
	if world != null and multiplayer.is_server():
		world.on_pvp_died(_sender(), killer_id)


@rpc("authority", "call_remote", "unreliable_ordered")
func pvp_state(scores: Dictionary, teams: Vector2i, t: float) -> void:
	if world != null:
		world.apply_pvp(scores, teams, t)


@rpc("authority", "call_remote", "reliable")
func pvp_end(text: String, win_team: int, win_id: int) -> void:
	if world != null:
		world.on_pvp_end(text, win_team, win_id)


@rpc("authority", "call_remote", "reliable")
func feed(text: String) -> void:
	if world != null and world.hud != null:
		world.hud.add_feed(text, Color(1, 0.85, 0.5))


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
		"smoke", "smoke2", "smokefail", "walkcap", "kbtest", "weapons", "hitbox", "camview", "horde", "mech", "walls", "antitank", "classes", "commando":
			player_name = "SmokeTester"
			control_mode = 1 if test_mode == "kbtest" else 0
			aim_assist = true
			settings = {"map": 1, "diff": 2, "mode": 0} if test_mode == "smoke2" else {"map": 0, "diff": 1, "mode": 0}
			if test_mode == "horde":
				settings = {"map": 2, "diff": 1, "mode": HORDE}
			if test_mode == "commando":
				settings = {"map": 0, "diff": 3, "mode": 0}
			start_singleplayer()
		"hold":
			player_name = "HoldTester"
			settings = {"map": 0, "diff": 1, "mode": HOLD}
			start_singleplayer()
		"koth", "ctf":
			player_name = "ModeTester"
			settings = {"map": 0, "diff": 1, "mode": KOTH if test_mode == "koth" else CTF}
			leave_network()
			players = {1: {"name": player_name, "rank": 0, "cls": 0, "team": 0}}
			start_mission()
		"bench0", "bench1", "bench2", "bench3", "bench4", "bench5":
			player_name = "Bench"
			settings = {"map": int(test_mode.right(1)), "diff": 1, "mode": 0}
			start_singleplayer()
		"mapcheck0", "mapcheck1", "mapcheck2", "mapcheck3", "mapcheck4", "mapcheck5":
			player_name = "MapTester"
			settings = {"map": int(test_mode.right(1)), "diff": 1, "mode": 0}
			start_singleplayer()
		"server", "server_late":
			player_name = "TestHost"
			var e := host_game(DEFAULT_PORT + 1)
			print("[test] server hosting on %d err='%s'" % [DEFAULT_PORT + 1, e])
		"pvp_server":
			player_name = "RedHost"
			settings = {"map": 0, "diff": 1, "mode": 1}
			print("[test] pvp server err='%s'" % host_game(DEFAULT_PORT + 2))
		"pvp_client":
			player_name = "BlueClient"
			print("[test] pvp client err='%s'" % join_game("127.0.0.1", DEFAULT_PORT + 2))
		"pvp_bidir_server":
			player_name = "RedHost"
			settings = {"map": 0, "diff": 1, "mode": 1}
			print("[test] pvp bidir server err='%s'" % host_game(DEFAULT_PORT + 3))
		"pvp_bidir_client":
			player_name = "BlueClient"
			print("[test] pvp bidir client err='%s'" % join_game("127.0.0.1", DEFAULT_PORT + 3))
		"live_backup_host":
			player_name = "BackupHost"
			settings = {"map": 0, "diff": 1, "mode": 0}
			save["relay_url"] = ""
			save["relay_pref"] = 1
			print("[test] live backup host err='%s'" % host_room())
		"live_relay_host":
			player_name = "LiveHost"
			settings = {"map": 0, "diff": 1, "mode": 0}
			save["relay_url"] = "wss://droid-siege.moeller-basil.workers.dev/ws"
			print("[test] live relay host err='%s'" % host_room())
		"live_relay_client":
			player_name = "LiveClient"
			settings = {"map": 0, "diff": 1, "mode": 0}
			save["relay_url"] = "wss://droid-siege.moeller-basil.workers.dev/ws"
			var code2 := ""
			for i in 50:
				await get_tree().create_timer(0.1).timeout
				if FileAccess.file_exists("/tmp/ds_live_code.txt"):
					code2 = FileAccess.get_file_as_string("/tmp/ds_live_code.txt").strip_edges()
					break
			print("[test] live relay client joining code=%s err='%s'" % [code2, join_room(code2)])
		"relay_host":
			player_name = "RelayHost"
			save["relay_url"] = "ws://127.0.0.1:9081"
			print("[test] relay host err='%s'" % host_room())
		"relay_client":
			player_name = "RelayClient"
			save["relay_url"] = "ws://127.0.0.1:9081"
			var code := FileAccess.get_file_as_string("/tmp/ds_room_code.txt").strip_edges()
			print("[test] relay client joining code=%s err='%s'" % [code, join_room(code)])
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
		"shot", "shot0", "shot1", "shot2":
			await get_tree().create_timer(2.5).timeout
			await _save_shot("/tmp/ds_menu.png")
			settings = {"map": 1 if test_mode == "shot" else int(test_mode.right(1)), "diff": 1, "mode": 0}
			start_singleplayer()
			await get_tree().create_timer(9.0).timeout
			var lp = world.local_player() if world else null
			if OS.get_environment("DS_GRID") != "":
				var short := 0
				var tot := 0
				var nm = world.get_world_3d().navigation_map
				for gx in range(-80, 81, 10):
					for gz in range(-80, 81, 10):
						var p3: Vector3 = NavigationServer3D.map_get_closest_point(nm, Vector3(gx, 0, gz))
						lp.global_position = p3 + Vector3(0, 0.05, 0)
						lp.rotation.y = randf() * TAU
						await get_tree().physics_frame
						await get_tree().physics_frame
						tot += 1
						if lp.spring.get_hit_length() < 1.2:
							short += 1
							if short <= 6:
								print("[diag] short spring %.2f at %s" % [lp.spring.get_hit_length(), p3])
				print("[diag] spring short at %d / %d spots" % [short, tot])
			if OS.get_environment("DS_RUN") != "":
				Input.action_press("move_forward")
				Input.action_press("fire")
				for k in 8:
					await get_tree().create_timer(0.4).timeout
					var sk0 = lp.char_model.find_children("*", "Skeleton3D", true, false)[0]
					print("[diag] t=%d pos=%s root=%s hips=%s anim=%s" % [k, lp.global_position, (sk0.global_transform * sk0.get_bone_global_pose(0)).origin, (sk0.global_transform * sk0.get_bone_global_pose(3)).origin, lp.char_model.cur])
				Input.action_release("fire")
			if lp != null:
				var cm = lp.char_model
				var vis := 0
				for mi in cm.meshes:
					if mi.is_visible_in_tree():
						vis += 1
				var sk = cm.find_children("*", "Skeleton3D", true, false)
				print("[diag] renderer=%s player=%s cam=%s spring_hit=%.2f model_vis=%s meshes_vis=%d/%d model_gscale=%s cm_scale=%s bone0=%s cam_cull=%d anim=%s" % [
					RenderingServer.get_current_rendering_method(), lp.global_position, lp.cam.global_position, lp.spring.get_hit_length(),
					lp.model.is_visible_in_tree(), vis, cm.meshes.size(), lp.model.global_transform.basis.get_scale(), cm.scale,
					(sk[0].global_transform * sk[0].get_bone_global_pose(0)).origin if sk.size() > 0 else null, lp.cam.cull_mask, cm.cur])
			var view := OS.get_environment("DS_VIEW")
			if lp != null and view != "":
				lp.god = true
				world.spawn_cd = 9999.0
				if view.begins_with("mech"):
					lp.global_position = world.mechs[0].global_position + Vector3(2, 0, 0)
					world.on_mech_enter(0, lp.peer_id)
					if view == "mechwalk":
						Input.action_press("move_forward")
				if view == "fp":
					lp.set_first_person(true)
					if OS.get_environment("DS_FIRE") != "":
						Input.action_press("fire")
				await get_tree().create_timer(1.2).timeout
				if view in ["front", "mechfront", "mechwalk"]:
					var c := Camera3D.new()
					world.add_child(c)
					var h := 4.5 if view.begins_with("mech") else 1.4
					var d := 5.5 if view.begins_with("mech") else 2.0
					var fwd: Vector3 = -lp.global_transform.basis.z
					var side: Vector3 = lp.global_transform.basis.x
					c.global_position = lp.global_position + fwd * d + side * d * 0.6 + Vector3(0, h * 0.8, 0)
					c.look_at(lp.global_position + Vector3(0, h * 0.55, 0))
					c.current = true
					await get_tree().create_timer(0.3).timeout
				if lp.deco.size() > 0:
					print("[diag] player=%s head_deco=%s headbone=%s in_mech=%s" % [lp.global_position, lp.deco[0][0].global_position, (lp._skel.global_transform * lp._skel.get_bone_global_pose(lp.deco[0][1])).origin, lp.in_mech])
				test_mode = test_mode + "_" + view
			_save_shot("/tmp/ds_game_%s.png" % test_mode)
			get_tree().quit(0)


func _process(_delta: float) -> void:
	if _pending_relay != null:
		_pending_relay.poll()
	_dynamic_resolution(_delta)
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
		"pvp_server", "pvp_bidir_server":
			if not in_mission and players.size() >= 2:
				start_mission()
			if elapsed > 80.0 and not _test_done:
				_test_done = true
				print("[test] PVP SERVER FAIL timeout")
				get_tree().quit(1)
		"pvp_client", "pvp_bidir_client":
			if elapsed > 80.0 and not _test_done:
				_test_done = true
				print("[test] PVP CLIENT FAIL timeout")
				get_tree().quit(1)
		"relay_host", "live_relay_host", "live_backup_host":
			if room_code != "":
				var rpath := "/tmp/ds_live_code.txt" if test_mode in ["live_relay_host", "live_backup_host"] else "/tmp/ds_room_code.txt"
				if not FileAccess.file_exists(rpath):
					var f := FileAccess.open(rpath, FileAccess.WRITE)
					f.store_string(room_code)
					f.close()
			if not in_mission and players.size() >= 2:
				print("[test] relay host: client joined via code, starting mission")
				start_mission()
			if in_mission and world != null and world.remote_state_packets > 10 and world.server_enemy_count_max > 0 and not _test_done:
				_test_done = true
				print("[test] RELAY HOST OK code=%s remote_packets=%d" % [room_code, world.remote_state_packets])
				await get_tree().create_timer(2.0).timeout
				get_tree().quit(0)
			if elapsed > 90.0 and not _test_done:
				_test_done = true
				print("[test] RELAY HOST FAIL timeout")
				get_tree().quit(1)
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
		"client", "relay_client", "live_relay_client":
			if world != null and world.enemy_state_packets > 30 and world.players.size() == 2 \
					and world.enemies.size() > 0 and world.remote_state_packets > 10:
				_test_done = true
				var host = world.players.get(1)
				var e0 = world.enemies.values()[0]
				var anim_ok: bool = host != null and host.state == 0 and host.char_model != null and host.char_model.cur != "" \
					and e0.char_model != null and e0.char_model.cur != ""
				print("[test] CLIENT OK: players=%d enemies=%d enemy_packets=%d player_packets=%d phase=%d host_state=%d host_anim=%s droid_anim=%s" % [
					world.players.size(), world.enemies.size(), world.enemy_state_packets,
					world.remote_state_packets, world.phase, host.state if host else -1,
					host.char_model.cur if host and host.char_model else "none", e0.char_model.cur if e0.char_model else "none"])
				if not anim_ok:
					print("[test] CLIENT FAIL animation sync")
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
	if OS.get_environment("DS_SHOT_DIR") != "":
		path = OS.get_environment("DS_SHOT_DIR").path_join(path.get_file())
	get_viewport().get_texture().get_image().save_png(path)
	print("[test] saved ", path)


func finish_test(ok: bool, text: String) -> void:
	if _test_done:
		return
	_test_done = true
	print("[test] %s %s" % ["OK" if ok else "FAIL", text])
	get_tree().quit(0 if ok else 1)
