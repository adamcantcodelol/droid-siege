extends Node3D
## Mission scene. Builds the level procedurally, owns players/enemies, runs the
## server-authoritative mission logic (objectives, waves, enemy AI).

const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const BoltScript = preload("res://scripts/bolt.gd")
const GrenadeScript = preload("res://scripts/grenade.gd")
const HudScript = preload("res://scripts/hud.gd")

var M: Dictionary = {}
var DIFF: Dictionary = {}
var POSTS: Array = []
const POST_NAMES := ["ALPHA", "BRAVO", "CHARLIE"]
var LZ := Vector3(0, 0, 72)
const CAPTURE_RADIUS := 7.0
const EXTRACT_TIME := 120.0
const MAP_HALF := 95.0

var players := {}       # peer_id -> player node
var enemies := {}       # enemy id -> enemy node
var next_enemy_id := 1
var phase := 0          # 0..2 = capturing post N, 3 = extraction, 4 = over
var progress := 0.0      # progress of the post most recently worked on (legacy/HUD)
var post_progress := [0.0, 0.0, 0.0]
var post_captured := [false, false, false]
var post_contested := [false, false, false]
var timer := EXTRACT_TIME
var kills := 0
var earned := 0
var enemy_count := 0
var ended := false
var started := false
var ready_peers := {}
var start_wait := 0.0
var spawn_cd := 4.0
var sync_cd := 0.0
var obj_cd := 0.0
var last_phase := 0
var rng := RandomNumberGenerator.new()
var hud
var players_root: Node3D
var enemies_root: Node3D
var fx_root: Node3D
var post_visuals := []
var gunship: Node3D
var nav_region: NavigationRegion3D
var nav_polys := 0
var test_speed := 1.0
var versus := false
var ffa := false
var pvp_scores := {}        # peer_id -> Vector2i(kills, deaths)
var team_scores := Vector2i.ZERO
var last_attacker := {}
var pvp_time := 480.0
var pvp_target := 15
var pvp_cd := 0.0
var _pvp_respawns := 0
var _pvp_saw_dead := false
var test_cd := 0.0
var test_elapsed := 0.0
var enemy_state_packets := 0
var remote_state_packets := 0
var server_enemy_count_max := 0


func _ready() -> void:
	Game.world = self
	rng.seed = Game.mission_seed
	M = Game.MAPS[clampi(int(Game.settings["map"]), 0, Game.MAPS.size() - 1)]
	DIFF = Game.DIFFICULTIES[clampi(int(Game.settings["diff"]), 0, Game.DIFFICULTIES.size() - 1)]
	POSTS = M["posts"]
	versus = int(Game.settings.get("mode", 0)) > 0
	ffa = int(Game.settings.get("mode", 0)) == 2
	pvp_target = 10 if ffa else 15
	LZ = M["lz"]
	if Game.test_mode in ["smoke", "smoke2", "smokefail", "walkcap", "kbtest"]:
		test_speed = 4.0
		Engine.time_scale = 3.0
	players_root = _child_node("Players")
	enemies_root = _child_node("Enemies")
	fx_root = _child_node("FX")
	_build_level()
	if multiplayer.is_server():
		_bake_nav()
	var keys := Game.players.keys()
	keys.sort()
	for i in keys.size():
		_add_player(int(keys[i]), i)
	if not players.has(multiplayer.get_unique_id()) and not Game.dedicated:
		# Safety: make sure we always have a local player.
		_add_player(multiplayer.get_unique_id(), players.size())
	hud = HudScript.new()
	add_child(hud)
	if not Game.is_headless():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if multiplayer.is_server():
		if not Game.dedicated:
			on_peer_ready(1)
	else:
		Game.rpc_id(1, "client_world_ready")
	show_message("%s (%s): squad deployed! Head for Command Post ALPHA." % [M["name"], DIFF["name"]])


func _exit_tree() -> void:
	if Game.world == self:
		Game.world = null
	Engine.time_scale = 1.0


func _child_node(n: String) -> Node3D:
	var node := Node3D.new()
	node.name = n
	add_child(node)
	return node


# ------------------------------------------------------------------ level
func _mat(c: Color, rough: float = 0.9, emit: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _add_box(pos: Vector3, size: Vector3, color: Color, rot_y: float = 0.0) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(color)
	mi.mesh = bm
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	b.position = pos
	b.rotation.y = rot_y
	nav_region.add_child(b)
	return b


func _add_pillar(pos: Vector3, radius: float, height: float, color: Color) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.7
	cm.bottom_radius = radius
	cm.height = height
	cm.material = _mat(color)
	mi.mesh = cm
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = height
	cs.shape = sh
	b.add_child(cs)
	b.position = pos + Vector3(0, height / 2.0, 0)
	nav_region.add_child(b)


func _build_level() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Level"
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.cell_size = 0.4
	nm.cell_height = 0.2
	nm.agent_radius = 0.8
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.4
	nav_region.navigation_mesh = nm
	add_child(nav_region)
	# Sky / environment (Geonosis-style dusty orange planet)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = M["sky_top"]
	sm.sky_horizon_color = M["sky_hor"]
	sm.ground_horizon_color = Color(0.8, 0.55, 0.35)
	sm.ground_bottom_color = Color(0.35, 0.22, 0.14)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = M["ambient"]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = M["fog"]
	env.fog_density = M["fog_density"]
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_color = M["sun"]
	sun.light_energy = M["sun_energy"]
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)

	# Ground
	var g := _add_box(Vector3(0, -0.5, 0), Vector3(240, 1, 240), M["ground"])
	g.name = "Ground"
	# Boundary cliffs
	for i in 4:
		var horizontal := i < 2
		var s := 1.0 if i % 2 == 0 else -1.0
		var pos := Vector3(0, 6, s * (MAP_HALF + 6)) if horizontal else Vector3(s * (MAP_HALF + 6), 6, 0)
		var size := Vector3(220, 12, 8) if horizontal else Vector3(8, 12, 220)
		_add_box(pos, size, M["cliff"])
	# Random rock cover (deterministic from mission seed so all peers match)
	var placed := 0
	var tries := 0
	while placed < int(M["rocks"]) and tries < 600:
		tries += 1
		var p := Vector3(rng.randf_range(-MAP_HALF + 5, MAP_HALF - 5), 0, rng.randf_range(-MAP_HALF + 5, MAP_HALF - 5))
		var blocked := p.distance_to(LZ) < 14.0
		for post in POSTS:
			if p.distance_to(post) < CAPTURE_RADIUS + 5.0:
				blocked = true
		if blocked:
			continue
		placed += 1
		var shade := rng.randf_range(0.8, 1.1)
		var rc: Color = M["rock"]
		var col := Color(rc.r * shade, rc.g * shade, rc.b * shade)
		if rng.randf() < float(M["pillar_ratio"]):
			_add_pillar(p, rng.randf_range(1.0, 2.5), rng.randf_range(4.0, 14.0), col)
		else:
			var sz := Vector3(rng.randf_range(1.5, 6.0), rng.randf_range(1.2, 3.0), rng.randf_range(1.0, 3.0))
			_add_box(p + Vector3(0, sz.y / 2.0, 0), sz, col, rng.randf_range(0, PI))

	# Command posts: CSG ring wall with doorways + flag pole + capture ring
	for i in POSTS.size():
		_build_post(i)

	# Landing zone pad
	var pad := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 8.0
	pm.bottom_radius = 8.0
	pm.height = 0.1
	pm.material = _mat(Color(0.35, 0.35, 0.4), 0.6)
	pad.mesh = pm
	pad.position = LZ + Vector3(0, 0.05, 0)
	add_child(pad)
	_add_box(LZ + Vector3(-6, 0.6, -6), Vector3(3, 1.2, 1), Color(0.4, 0.4, 0.45))
	_add_box(LZ + Vector3(6, 0.6, -6), Vector3(3, 1.2, 1), Color(0.4, 0.4, 0.45))

	gunship = _build_gunship()
	gunship.position = LZ + Vector3(0, 80, 0)
	gunship.visible = false
	add_child(gunship)


func _bake_nav() -> void:
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, 0.4)
	NavigationServer3D.map_set_cell_height(map, 0.2)
	nav_region.bake_navigation_mesh(false)
	nav_polys = nav_region.navigation_mesh.get_polygon_count()
	print("[nav] baked polygons=", nav_polys)


func nav_path_length(a: Vector3, b: Vector3) -> int:
	return NavigationServer3D.map_get_path(get_world_3d().navigation_map, a, b, true).size()


func _build_post(i: int) -> void:
	var center: Vector3 = POSTS[i]
	var csg := CSGCombiner3D.new()
	csg.use_collision = true
	csg.collision_layer = 1
	csg.collision_mask = 0
	csg.position = center
	var outer := CSGCylinder3D.new()
	outer.radius = CAPTURE_RADIUS + 1.6
	outer.height = 1.3
	outer.sides = 24
	outer.position.y = 0.65
	outer.material = _mat(Color(0.65, 0.65, 0.7), 0.5)
	csg.add_child(outer)
	var inner := CSGCylinder3D.new()
	inner.operation = CSGShape3D.OPERATION_SUBTRACTION
	inner.radius = CAPTURE_RADIUS + 1.0
	inner.height = 2.0
	inner.sides = 24
	inner.position.y = 0.65
	csg.add_child(inner)
	for d in 4:
		var door := CSGBox3D.new()
		door.operation = CSGShape3D.OPERATION_SUBTRACTION
		door.size = Vector3(3.2, 3, 4)
		door.position = Vector3(0, 0.65, 0)
		door.rotation.y = d * PI / 2.0
		door.position = Vector3(sin(d * PI / 2.0), 0, cos(d * PI / 2.0)) * (CAPTURE_RADIUS + 1.3) + Vector3(0, 0.65, 0)
		csg.add_child(door)
	nav_region.add_child(csg)
	# Capture ring (visual)
	var ring := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = CAPTURE_RADIUS
	rm.bottom_radius = CAPTURE_RADIUS
	rm.height = 0.06
	var ring_mat := _mat(Color(0.8, 0.2, 0.15), 0.5, 0.6)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color.a = 0.45
	rm.material = ring_mat
	ring.mesh = rm
	ring.position = center + Vector3(0, 0.04, 0)
	add_child(ring)
	# Flag pole + flag
	_add_box(center + Vector3(0, 4, 0), Vector3(0.2, 8, 0.2), Color(0.3, 0.3, 0.3))
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.05, 1.2, 2.0)
	var flag_mat := _mat(Color(0.8, 0.2, 0.15), 0.5, 0.4)
	fm.material = flag_mat
	flag.mesh = fm
	flag.position = center + Vector3(0, 1.5, 1.05)
	add_child(flag)
	# Label
	var lbl := Label3D.new()
	lbl.text = "POST " + POST_NAMES[i]
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 96
	lbl.outline_size = 16
	lbl.no_depth_test = true
	lbl.fixed_size = false
	lbl.pixel_size = 0.02
	lbl.position = center + Vector3(0, 10, 0)
	add_child(lbl)
	# Ammo/supply crates as cover inside
	_add_box(center + Vector3(3, 0.5, 2), Vector3(1.2, 1.0, 1.2), Color(0.3, 0.35, 0.5))
	_add_box(center + Vector3(-3, 0.5, -2), Vector3(1.2, 1.0, 1.2), Color(0.3, 0.35, 0.5))
	post_visuals.append({"ring_mat": ring_mat, "flag": flag, "flag_mat": flag_mat, "label": lbl, "center": center})


func _build_gunship() -> Node3D:
	var root := Node3D.new()
	root.name = "Gunship"
	var hull_col := Color(0.82, 0.84, 0.78)
	var green := Color(0.35, 0.45, 0.3)
	var parts := [
		[Vector3(0, 0, 0), Vector3(3.5, 2.6, 9), hull_col],
		[Vector3(0, 0.3, -5.5), Vector3(2.6, 2.0, 3), hull_col],
		[Vector3(0, 0.6, -6.6), Vector3(2.0, 1.0, 1.0), Color(0.15, 0.2, 0.3)],
		[Vector3(0, 1.5, 0), Vector3(12, 0.3, 3), green],
		[Vector3(0, 1.0, 5), Vector3(1.0, 2.5, 2.5), green],
		[Vector3(5.5, 1.0, 0.5), Vector3(1.2, 1.2, 2.5), Color(0.3, 0.3, 0.3)],
		[Vector3(-5.5, 1.0, 0.5), Vector3(1.2, 1.2, 2.5), Color(0.3, 0.3, 0.3)],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[1]
		bm.material = _mat(p[2], 0.6)
		mi.mesh = bm
		mi.position = p[0]
		root.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.3, 0.2)
	light.omni_range = 12
	light.position = Vector3(0, -2, 0)
	root.add_child(light)
	return root


# ------------------------------------------------------------------ players
func _add_player(pid: int, index: int) -> void:
	if players.has(pid):
		return
	var p := PlayerScript.new()
	p.peer_id = pid
	p.color_index = index
	p.display_name = str(Game.players[pid]["name"]) if Game.players.has(pid) else "Trooper"
	p.name = "P%d" % pid
	p.position = LZ + Vector3((index - 1.5) * 2.5, 1.0, 0)
	if versus:
		p.team = index if ffa else _balanced_team()
		p.position = _spawn_for(p.team, index)
	players_root.add_child(p)
	players[pid] = p
	if not pvp_scores.has(pid):
		pvp_scores[pid] = Vector2i.ZERO


func _balanced_team() -> int:
	var c := [0, 0]
	for q in players.values():
		c[clampi(q.team, 0, 1)] += 1
	return 0 if c[0] <= c[1] else 1


func _spawn_for(team: int, salt: int) -> Vector3:
	var r := RandomNumberGenerator.new()
	r.randomize()
	if not ffa:
		var base := Vector3(0, 1.0, 78.0 if team == 0 else -78.0)
		return base + Vector3(r.randf_range(-12, 12) + salt * 0.0, 0, r.randf_range(-3, 3))
	var ang := r.randf() * TAU
	return Vector3(cos(ang) * 60.0, 1.0, sin(ang) * 60.0)


## Respawn position for a versus player (team spawn or random FFA spot).
func spawn_point(pid: int) -> Vector3:
	var p = players.get(pid)
	return _spawn_for(p.team if p != null else 0, 0)


func is_hostile(a: int, b: int) -> bool:
	if not versus or a == b:
		return false
	if ffa:
		return true
	var pa = players.get(a)
	var pb = players.get(b)
	return pa != null and pb != null and pa.team != pb.team


func assist_candidates(me) -> Array:
	var out: Array = enemies.values()
	if versus:
		out = []
		for p in players.values():
			if p != me and p.state == 0 and is_hostile(me.peer_id, p.peer_id):
				out.append(p)
	return out


func sync_players() -> void:
	for pid in Game.players.keys():
		if not players.has(pid):
			_add_player(int(pid), players.size())


func remove_player(pid: int) -> void:
	if players.has(pid):
		players[pid].queue_free()
		players.erase(pid)
	ready_peers.erase(pid)


func local_player():
	return players.get(multiplayer.get_unique_id())


func apply_player_state(pid: int, pos: Vector3, ry: float, pitch: float, hp: float, st: int) -> void:
	if pid == multiplayer.get_unique_id():
		return
	if not players.has(pid) and Game.players.has(pid):
		_add_player(pid, players.size())
	if players.has(pid):
		var prev: int = players[pid].state
		players[pid].net_update(pos, ry, pitch, hp, st)
		if prev == 0 and st == 1 and hud != null:
			hud.add_feed("%s is DOWN! Revive them (E)" % players[pid].display_name, Color(1, 0.4, 0.3))
		remote_state_packets += 1


func nearest_alive_player(pos: Vector3):
	var best = null
	var bd := INF
	for p in players.values():
		if p.state != 0:
			continue
		var d: float = p.global_position.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = p
	return best


func has_los(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# ------------------------------------------------------------------ server mission loop
func on_peer_ready(pid: int) -> void:
	ready_peers[pid] = true
	_check_start()


func _check_start() -> void:
	if started:
		return
	for pid in Game.players.keys():
		if not ready_peers.has(pid):
			return
	if Game.players.is_empty():
		return
	started = true
	Game.net_all("announce", ["All troopers on the ground. Capture Command Post ALPHA!"])


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		if not started:
			start_wait += delta
			if start_wait > 15.0:
				started = true  # don't wait forever for a slow client
		elif not ended:
			_server_tick(delta)
			_test_autopilot(delta)
	_update_visuals(delta)


func _server_tick(delta: float) -> void:
	if versus:
		_pvp_tick(delta)
		return
	# Fail check: everyone downed or dead
	var alive := 0
	for p in players.values():
		if p.state == 0:
			alive += 1
	if players.size() > 0 and alive == 0:
		_end_mission(false)
		return

	# Objectives: every uncaptured post can be captured, in any order. Plain distance
	# checks against every alive player (no Area3D/collision layers involved).
	if phase < 3:
		for i in POSTS.size():
			if post_captured[i]:
				continue
			var center: Vector3 = POSTS[i]
			var pin := 0
			for p in players.values():
				if p.state == 0 and _flat_dist(p.global_position, center) < CAPTURE_RADIUS:
					pin += 1
			var ein := 0
			for e in enemies.values():
				if is_instance_valid(e) and e.hp > 0.0 and _flat_dist(e.global_position, center) < CAPTURE_RADIUS:
					ein += 1
			post_contested[i] = pin > 0 and ein > pin
			if pin > 0 and ein <= pin:
				post_progress[i] = minf(1.0, post_progress[i] + delta * (0.05 + 0.018 * (pin - 1)) * test_speed)
				progress = post_progress[i]
			elif pin == 0:
				post_progress[i] = maxf(0.0, post_progress[i] - delta * 0.01)
			if post_progress[i] >= 1.0:
				post_captured[i] = true
				post_contested[i] = false
				earned += int(150 * float(DIFF["credits"]))
				phase += 1
				if phase == 3:
					timer = EXTRACT_TIME
					Game.net_all("announce", ["All command posts captured! Survive until the gunship arrives!"])
				else:
					Game.net_all("announce", ["Post %s captured! %d to go." % [POST_NAMES[i], 3 - phase]])
	elif phase == 3:
		timer -= delta * test_speed
		if timer <= 0.0:
			timer = 0.0
			earned += int(500 * float(DIFF["credits"]))
			_end_mission(true)
			return

	# Enemy AI
	for e in enemies.values():
		e.server_tick(delta, self)

	# Waves
	var n := players.size()
	var cap := 4 + phase * 2 + 2 * (n - 1) + int(DIFF["cap"])
	var interval := 3.5 - phase * 0.5
	if phase == 3:
		cap = 10 + 3 * (n - 1) + int(DIFF["cap"])
		interval = 1.6
	spawn_cd -= delta
	if spawn_cd <= 0.0 and enemies.size() < cap:
		spawn_cd = interval
		_spawn_enemy()
		if phase == 3 and rng.randf() < 0.5 and enemies.size() < cap:
			_spawn_enemy()
	server_enemy_count_max = maxi(server_enemy_count_max, enemies.size())

	# Sync
	sync_cd -= delta
	if sync_cd <= 0.0:
		sync_cd = 0.05
		var data := PackedFloat32Array()
		for e in enemies.values():
			data.append_array(e.pack_state())
		if Game.is_connected_online():
			Game.rpc("enemy_states", data)
	obj_cd -= delta
	if obj_cd <= 0.0:
		obj_cd = 0.2
		var cap_mask := 0
		var con_mask := 0
		for i in 3:
			if post_captured[i]:
				cap_mask |= 1 << i
			if post_contested[i]:
				con_mask |= 1 << i
		Game.net_all("objective_state", [phase, Vector3(post_progress[0], post_progress[1], post_progress[2]),
			cap_mask, con_mask, timer, kills, enemies.size(), earned])


func post_at(pos: Vector3) -> int:
	for i in POSTS.size():
		if _flat_dist(pos, POSTS[i]) < CAPTURE_RADIUS:
			return i
	return -1


func nearest_open_post(pos: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in POSTS.size():
		if post_captured[i]:
			continue
		var d := _flat_dist(pos, POSTS[i])
		if d < bd:
			bd = d
			best = i
	return best


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _pick_type() -> int:
	var r := rng.randf()
	match phase:
		0:
			return 0 if r < 0.85 else 1
		1:
			return 0 if r < 0.65 else (1 if r < 0.85 else 2)
		2:
			return 0 if r < 0.55 else (1 if r < 0.8 else 2)
		_:
			return 0 if r < 0.5 else (1 if r < 0.78 else 2)


func _spawn_enemy() -> void:
	var focus: Vector3 = LZ
	if phase < 3:
		var lp0 = players.values()[0] if players.size() > 0 else null
		var np := nearest_open_post(lp0.global_position if lp0 != null else LZ)
		focus = POSTS[maxi(np, 0)]
	var pos := Vector3.ZERO
	for attempt in 12:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(45.0, 65.0)
		pos = focus + Vector3(cos(ang), 0, sin(ang)) * dist
		pos.x = clampf(pos.x, -MAP_HALF + 3, MAP_HALF - 3)
		pos.z = clampf(pos.z, -MAP_HALF + 3, MAP_HALF - 3)
		var ok := true
		for p in players.values():
			if p.global_position.distance_to(pos) < 25.0:
				ok = false
		if ok:
			break
	pos.y = 0.5
	var id := next_enemy_id
	next_enemy_id += 1
	_create_enemy(id, _pick_type(), pos)


func _create_enemy(id: int, etype: int, pos: Vector3):
	var e := EnemyScript.new()
	e.eid = id
	e.etype = etype
	e.name = "E%d" % id
	e.position = pos
	enemies_root.add_child(e)
	enemies[id] = e
	return e


func enemy_fire(e, target, dist: float) -> void:
	var from: Vector3 = e.muzzle_position()
	var aim: Vector3 = target.global_position + Vector3(0, 1.2, 0)
	var chance: float = e.stats["acc"] * clampf(1.3 - dist / e.stats["range"], 0.35, 1.0)
	if target.is_sprinting:
		chance *= 0.6
	var hit := rng.randf() < chance
	var to := aim
	if not hit:
		var off := Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(-0.6, 1.4), rng.randf_range(-1.6, 1.6))
		to = from + ((aim + off) - from).normalized() * (dist + 20.0)
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		var res := get_world_3d().direct_space_state.intersect_ray(q)
		if not res.is_empty():
			to = res["position"]
	Game.net_all("bolt_fx", [from, to, 1])
	if hit:
		var solo := 0.8 if players.size() == 1 else 1.0
		Game.net_peer(target.peer_id, "hit_player", [float(e.stats["dmg"]) * solo, from])


func damage_enemy(eid: int, dmg: float, from: Vector3, shooter: int, explosive: bool) -> void:
	if not enemies.has(eid) or ended:
		return
	var e = enemies[eid]
	if e.apply_damage(dmg, from, explosive):
		kills += 1
		earned += int(round(float(e.stats["credits"]) * float(DIFF["credits"])))
		Game.net_all("enemy_died", [eid, e.global_position, shooter, e.etype])


func explode(pos: Vector3, shooter: int) -> void:
	Game.net_all("explosion_fx", [pos])
	if versus:
		for p in players.values():
			var dp: float = p.global_position.distance_to(pos)
			if dp < 7.0:
				pvp_damage(shooter, p.peer_id, 120.0 * (1.0 - dp / 7.0) + 20.0, pos)
	for e in enemies.values().duplicate():
		var d: float = e.global_position.distance_to(pos)
		if d < 7.0:
			damage_enemy(e.eid, 160.0 * (1.0 - d / 7.0) + 40.0, pos, shooter, true)


# ------------------------------------------------------------------ versus (host-authoritative)
func _pvp_tick(delta: float) -> void:
	pvp_time -= delta
	pvp_cd -= delta
	if pvp_cd <= 0.0:
		pvp_cd = 0.25
		Game.net_all("pvp_state", [pvp_scores, team_scores, pvp_time])
	if pvp_time <= 0.0:
		_pvp_finish()


func pvp_damage(shooter: int, target: int, dmg: float, from: Vector3) -> void:
	if ended or not is_hostile(shooter, target):
		return  # friendly fire and self damage are off
	var t = players.get(target)
	if t == null or t.state != 0:
		return
	last_attacker[target] = shooter
	Game.net_peer(target, "hit_player", [dmg, from])


func on_pvp_died(victim: int) -> void:
	if ended:
		return
	var killer: int = last_attacker.get(victim, 0)
	last_attacker.erase(victim)
	var vs: Vector2i = pvp_scores.get(victim, Vector2i.ZERO)
	pvp_scores[victim] = Vector2i(vs.x, vs.y + 1)
	var vname := _pname(victim)
	if killer != 0 and killer != victim and players.has(killer):
		var ks: Vector2i = pvp_scores.get(killer, Vector2i.ZERO)
		pvp_scores[killer] = Vector2i(ks.x + 1, ks.y)
		if not ffa:
			if players[killer].team == 0:
				team_scores.x += 1
			else:
				team_scores.y += 1
		Game.net_all("feed", ["%s  >  %s" % [_pname(killer), vname]])
	else:
		Game.net_all("feed", ["%s went down" % vname])
	Game.net_all("pvp_state", [pvp_scores, team_scores, pvp_time])
	if ffa:
		for pid in pvp_scores.keys():
			if pvp_scores[pid].x >= pvp_target:
				_pvp_finish()
				return
	elif team_scores.x >= pvp_target or team_scores.y >= pvp_target:
		_pvp_finish()


func _pname(pid: int) -> String:
	return players[pid].display_name if players.has(pid) else "Trooper"


func _pvp_finish() -> void:
	if ended:
		return
	if ffa:
		var best := -1
		var bk := -1
		for pid in pvp_scores.keys():
			if pvp_scores[pid].x > bk:
				bk = pvp_scores[pid].x
				best = pid
		Game.net_all("pvp_end", ["%s wins the Free-for-All with %d kills!" % [_pname(best), bk], -1, best])
	else:
		var wt := 0 if team_scores.x > team_scores.y else (1 if team_scores.y > team_scores.x else -1)
		var text := "RED TEAM WINS!" if wt == 0 else ("BLUE TEAM WINS!" if wt == 1 else "DRAW!")
		Game.net_all("pvp_end", ["%s  %d - %d" % [text, team_scores.x, team_scores.y], wt, 0])


func apply_pvp(scores: Dictionary, teams: Vector2i, t: float) -> void:
	pvp_scores = scores
	team_scores = teams
	pvp_time = t


func on_pvp_end(text: String, win_team: int, win_id: int) -> void:
	if ended:
		return
	ended = true
	var me := multiplayer.get_unique_id()
	var lp = local_player()
	var my_kills: int = pvp_scores.get(me, Vector2i.ZERO).x
	var won := false
	if lp != null:
		won = (win_id == me) if ffa else (win_team == lp.team)
	var credits := my_kills * 10 + (100 if won else 25)
	Game.save["credits"] = int(Game.save["credits"]) + credits
	Game.write_save()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_pvp_end(text, won, credits, my_kills)


func _end_mission(win: bool) -> void:
	if ended:
		return
	var credits := earned if win else int(earned * 0.5)
	Game.net_all("mission_end", [win, credits, kills])


# ------------------------------------------------------------------ client-side sync
func apply_enemy_states(data: PackedFloat32Array) -> void:
	if multiplayer.is_server():
		return
	enemy_state_packets += 1
	var seen := {}
	var stride: int = EnemyScript.STATE_SIZE
	var i := 0
	while i + stride <= data.size():
		var id := int(data[i])
		seen[id] = true
		var e = enemies.get(id)
		if e == null:
			e = _create_enemy(id, int(data[i + 1]), Vector3(data[i + 2], data[i + 3], data[i + 4]))
		e.apply_state(data, i)
		i += stride
	for id in enemies.keys():
		if not seen.has(id):
			enemies[id].queue_free()
			enemies.erase(id)


func on_enemy_died(eid: int, pos: Vector3, killer: int = 0, etype: int = 0) -> void:
	if enemies.has(eid):
		enemies[eid].queue_free()
		enemies.erase(eid)
	spawn_explosion(pos + Vector3(0, 1, 0), 0.5)
	_spawn_debris(pos + Vector3(0, 1, 0), etype)
	var kname := "Squad"
	if Game.players.has(killer):
		kname = str(Game.players[killer]["name"])
	if hud != null:
		hud.add_feed("%s  >  %s" % [kname, EnemyScript.TYPES[etype]["name"]],
			Color(0.5, 0.8, 1.0) if killer == multiplayer.get_unique_id() else Color(0.9, 0.9, 0.9))


func _spawn_debris(pos: Vector3, etype: int) -> void:
	var col: Color = [Color(0.78, 0.68, 0.48), Color(0.3, 0.33, 0.4), Color(0.55, 0.4, 0.25)][clampi(etype, 0, 2)]
	for i in 7:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(0.1, 0.3), randf_range(0.1, 0.3), randf_range(0.1, 0.4))
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		bm.material = m
		mi.mesh = bm
		fx_root.add_child(mi)
		mi.global_position = pos
		var dest := pos + Vector3(randf_range(-2.5, 2.5), randf_range(-0.9, 1.5), randf_range(-2.5, 2.5))
		dest.y = maxf(dest.y, 0.1)
		var tw := mi.create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "global_position", dest, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(mi, "rotation", Vector3(randf() * 6, randf() * 6, randf() * 6), 0.5)
		tw.chain().tween_interval(2.0)
		tw.chain().tween_property(mi, "scale", Vector3.ZERO, 0.4)
		tw.chain().tween_callback(mi.queue_free)


func apply_objective(ph: int, prog: Vector3, cap_mask: int, con_mask: int, t: float, k: int, ne: int, e: int) -> void:
	if ph != last_phase and ph > last_phase:
		Game.play_sfx("capture")
	last_phase = ph
	phase = ph
	for i in 3:
		post_progress[i] = prog[i]
		post_captured[i] = (cap_mask & (1 << i)) != 0
		post_contested[i] = (con_mask & (1 << i)) != 0
	timer = t
	kills = k
	enemy_count = ne
	earned = e


func on_mission_end(win: bool, credits: int, k: int) -> void:
	if ended:
		return
	ended = true
	kills = k
	Game.save["credits"] = int(Game.save["credits"]) + credits
	Game.save["missions"] = int(Game.save["missions"]) + 1
	if win:
		Game.save["wins"] = int(Game.save["wins"]) + 1
	Game.write_save()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_end(win, credits, k)
	if Game.test_mode in ["smoke", "smoke2"]:
		var plen := nav_path_length(LZ, POSTS[0])
		print("[test] map=%s diff=%s nav polys=%d path_points LZ->ALPHA=%d" % [M["name"], DIFF["name"], nav_polys, plen])
		print("[test] kill feed entries=%d" % hud.feed_box.get_child_count())
		Game.finish_test(win and nav_polys > 0 and plen >= 2 and hud.feed_box.get_child_count() > 0, "SMOKE win=%s credits=%d kills=%d total_credits=%d" % [win, credits, k, Game.save["credits"]])
	elif Game.test_mode == "smokefail":
		print("[test] damage indicator active=%s" % (hud.dmg_time > 0.0))
		Game.finish_test(not win and hud.dmg_time > 0.0, "SMOKEFAIL win=%s credits=%d kills=%d" % [win, credits, k])


# ------------------------------------------------------------------ fx
func spawn_bolt(from: Vector3, to: Vector3, kind: int) -> void:
	var b := BoltScript.new()
	b.from = from
	b.to = to
	b.kind = kind
	fx_root.add_child(b)
	_muzzle_flash(from, kind)
	Game.play_sfx("blaster" if kind == 0 else "enemy_blaster", from, -4.0 if kind == 0 else -8.0)


func _muzzle_flash(pos: Vector3, kind: int) -> void:
	var c := Color(0.5, 0.75, 1.0) if kind == 0 else Color(1.0, 0.35, 0.2)
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = 2.5
	l.omni_range = 4.0
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	sm.material = m
	mi.mesh = sm
	l.add_child(mi)
	fx_root.add_child(l)
	l.global_position = pos
	get_tree().create_timer(0.06).timeout.connect(l.queue_free)


func spawn_grenade(pos: Vector3, vel: Vector3, owned: bool) -> void:
	var g := GrenadeScript.new()
	g.velocity = vel
	g.owned = owned
	g.position = pos
	fx_root.add_child(g)


func spawn_explosion(pos: Vector3, scale_mul: float = 1.0) -> void:
	var root := Node3D.new()
	fx_root.add_child(root)
	root.global_position = pos
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.6, 0.2, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = m
	mi.mesh = sm
	mi.scale = Vector3.ONE * 0.3 * scale_mul
	root.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.6, 0.3)
	light.light_energy = 4.0 * scale_mul
	light.omni_range = 10.0 * scale_mul
	root.add_child(light)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 4.0 * scale_mul, 0.45)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.tween_property(light, "light_energy", 0.0, 0.45)
	tw.chain().tween_callback(root.queue_free)
	Game.play_sfx("explosion", pos, -2.0 if scale_mul >= 1.0 else -10.0)


func show_message(text: String) -> void:
	if hud != null:
		hud.show_message(text)


func _update_visuals(delta: float) -> void:
	for i in post_visuals.size():
		var v: Dictionary = post_visuals[i]
		var col := Color(0.8, 0.2, 0.15)
		var h := 1.5
		var target_h := 1.5 + float(post_progress[i]) * 5.5
		if post_captured[i]:
			col = Color(0.2, 0.45, 1.0)
			target_h = 7.0
		elif post_contested[i]:
			col = Color(1.0, 0.45, 0.1) if int(Time.get_ticks_msec() / 250) % 2 == 0 else Color(0.8, 0.2, 0.15)
		elif post_progress[i] > 0.0:
			col = Color(1.0, 0.75, 0.2)
		var cur: Vector3 = v["flag"].position
		h = lerpf(cur.y - float(v["center"].y), target_h, minf(1.0, delta * 6.0))
		v["ring_mat"].albedo_color = Color(col.r, col.g, col.b, 0.45)
		v["ring_mat"].emission = col
		v["flag_mat"].albedo_color = col
		v["flag_mat"].emission = col
		var c: Vector3 = v["center"]
		v["flag"].position = c + Vector3(0, h, 1.05)
	# Gunship arrives during the last 25 seconds of extraction
	if phase >= 3:
		var t := clampf(timer / 25.0, 0.0, 1.0)
		gunship.visible = timer < 25.0 or ended
		var target_y := 6.0 + 74.0 * t
		gunship.position.y = lerpf(gunship.position.y, target_y, minf(1.0, delta * 2.0))
		gunship.rotation.y += delta * 0.05 * t


# ------------------------------------------------------------------ headless test autopilot
func _test_autopilot(delta: float) -> void:
	if Game.test_mode == "pvp_server":
		_test_pvp_server(delta)
		return
	if Game.test_mode not in ["smoke", "smoke2", "smokefail", "walkcap", "kbtest"]:
		return
	test_elapsed += delta
	var lp = local_player()
	if lp == null:
		return
	if Game.test_mode == "walkcap":
		_test_walkcap(delta, lp)
		return
	if Game.test_mode == "kbtest":
		_test_keyboard(delta, lp)
		return
	if Game.test_mode in ["smoke", "smoke2"]:
		lp.god = true
		if phase < 3:
			lp.global_position = POSTS[nearest_open_post(lp.global_position)] + Vector3(1, 0.5, 1)
			lp.velocity = Vector3.ZERO
		test_cd -= delta
		if test_cd <= 0.0 and enemies.size() > 0:
			test_cd = 0.35
			var eid: int = enemies.keys()[0]
			damage_enemy(eid, 9999.0, lp.global_position, 1, false)
		# also exercise a grenade once
		if test_elapsed > 2.0 and test_elapsed < 2.0 + delta * 1.5:
			explode(lp.global_position + Vector3(0, 0, -3), 1)
	elif Game.test_mode == "smokefail" and test_elapsed > 3.0 and lp.state == 0:
		lp.take_damage(99999.0, lp.global_position + Vector3(5, 0, 0))


var _t_start := Vector3.ZERO
var _t_stage := 0
var _t_val := 0.0
var _t_mark := 0.0
var _t_enemy = null


## Walk (real physics, real input action) from outside BRAVO's wall, through the doorway, into the ring.
func _test_walkcap(_delta: float, lp) -> void:
	lp.god = true
	var post := 1
	var center: Vector3 = POSTS[post]
	if _t_stage == 0:
		lp.global_position = center + Vector3(0, 0.5, 11.5)
		lp.rotation.y = 0.0
		lp.velocity = Vector3.ZERO
		_t_start = lp.global_position
		_t_stage = 1
		return
	for e in enemies.values().duplicate():
		if _flat_dist(e.global_position, center) < 20.0:
			damage_enemy(e.eid, 9999.0, center, 1, false)
	var d := _flat_dist(lp.global_position, center)
	if d > 2.5:
		Input.action_press("move_forward")
	else:
		Input.action_release("move_forward")
	var flag_h: float = post_visuals[post]["flag"].position.y - center.y
	if post_progress[post] > 0.25:
		Input.action_release("move_forward")
		var walked := _flat_dist(_t_start, lp.global_position)
		print("[test] walkcap: walked %.1fm, in ring dist %.1fm, BRAVO progress %.2f, flag height %.2f, contested=%s" % [walked, d, post_progress[post], flag_h, post_contested[post]])
		Game.finish_test(walked > 7.0 and flag_h > 2.0, "WALKCAP progress rises from real movement")
	elif test_elapsed > 40.0:
		print("[test] walkcap: stuck at dist %.1f progress %.2f pos %s" % [d, post_progress[post], lp.global_position])
		Game.finish_test(false, "WALKCAP timeout")


## Keyboard-only controls: turn with the turn action, fire with kb_fire, and aim assist pulls toward a droid.
func _test_keyboard(_delta: float, lp) -> void:
	lp.god = true
	match _t_stage:
		0:
			_t_val = lp.rotation.y
			Input.action_press("turn_right")
			_t_mark = test_elapsed
			_t_stage = 1
		1:
			if test_elapsed - _t_mark > 0.5:
				Input.action_release("turn_right")
				var turned := absf(angle_difference(_t_val, lp.rotation.y))
				print("[test] kbtest: turned %.2f rad" % turned)
				if turned < 0.3:
					Game.finish_test(false, "KBTEST turning")
					return
				_t_val = float(lp.mag)
				Input.action_press("kb_fire")
				_t_mark = test_elapsed
				_t_stage = 2
		2:
			if test_elapsed - _t_mark > 0.4:
				Input.action_release("kb_fire")
				print("[test] kbtest: mag %d -> %d" % [int(_t_val), lp.mag])
				if lp.mag >= int(_t_val):
					Game.finish_test(false, "KBTEST firing")
					return
				# put a droid 6 degrees off the crosshair, 15 m away, on open ground
				for e in enemies.values().duplicate():
					damage_enemy(e.eid, 9999.0, Vector3.ZERO, 1, false)
				spawn_cd = 999.0
				lp.global_position = Vector3(0, 0.5, LZ.z - 2.0)
				lp.rotation.y = 0.0
				lp.pitch = 0.0
				var dir := Vector3(sin(deg_to_rad(-6.0)), 0, -cos(deg_to_rad(6.0)))
				_t_enemy = _create_enemy(next_enemy_id, 0, lp.global_position + dir * 15.0)
				next_enemy_id += 1
				_t_enemy.fire_cd = 999.0
				_t_mark = test_elapsed
				_t_stage = 3
		3:
			if test_elapsed - _t_mark > 0.25 and _t_val >= 0.0:
				_t_val = -1.0
				_t_mark = test_elapsed
				_t_start = Vector3(_cam_angle_to(lp, _t_enemy), 0, 0)
			elif _t_val < 0.0 and test_elapsed - _t_mark > 1.0:
				var after := _cam_angle_to(lp, _t_enemy)
				print("[test] kbtest: aim assist angle %.1f deg -> %.1f deg" % [rad_to_deg(_t_start.x), rad_to_deg(after)])
				Game.finish_test(after < _t_start.x * 0.7 or after < deg_to_rad(1.5), "KBTEST turn+fire+aim-assist")


func _cam_angle_to(lp, e) -> float:
	if e == null or not is_instance_valid(e):
		return 0.0
	var d: Vector3 = e.global_position + Vector3(0, 1.2, 0) - lp.cam.global_position
	return (-lp.cam.global_transform.basis.z).angle_to(d)


## Host repeatedly "shoots" the client through the real authoritative path; the client must
## die, report its death, respawn after 5 s and die again (2 kills credited to the host).
func _test_pvp_server(delta: float) -> void:
	test_elapsed += delta
	test_cd -= delta
	pvp_damage(1, 1, 9999.0, Vector3.ZERO)  # self damage must be ignored
	if players.has(1) and players[1].state != 0:
		Game.finish_test(false, "PVP self-damage applied")
		return
	for pid in players.keys():
		if pid != 1 and test_cd <= 0.0 and players[pid].state == 0:
			test_cd = 0.5
			pvp_damage(1, pid, 9999.0, players[1].global_position)
	var k: int = pvp_scores.get(1, Vector2i.ZERO).x
	if k >= 2 and _t_mark == 0.0:
		_t_mark = test_elapsed
	if k >= 2 and not ended and test_elapsed > _t_mark + 7.0:
		print("[test] pvp server: host kills=%d team score=%s client deaths=%s" % [k, team_scores, pvp_scores])
		Game.finish_test(team_scores.x >= 2 or team_scores.y >= 2, "PVP SERVER kills+respawn+team score")


func _process(_delta: float) -> void:
	if Game.test_mode != "pvp_client":
		return
	var lp = local_player()
	if lp == null:
		return
	if lp.state == 2:
		_pvp_saw_dead = true
	elif _pvp_saw_dead and lp.state == 0:
		_pvp_saw_dead = false
		_pvp_respawns += 1
		print("[test] pvp client: respawned at %s (team %d)" % [lp.global_position, lp.team])
		if _pvp_respawns >= 2:
			Game.finish_test(versus and not ffa, "PVP CLIENT died and respawned")
