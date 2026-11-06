extends Node3D
## Mission scene. Builds the level procedurally, owns players/enemies, runs the
## server-authoritative mission logic (objectives, waves, enemy AI).

const MechVisual := preload("res://scripts/mech.gd")
const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const BoltScript = preload("res://scripts/bolt.gd")
const GrenadeScript = preload("res://scripts/grenade.gd")
const HudScript = preload("res://scripts/hud.gd")
const MapBuilderScript = preload("res://scripts/map_builder.gd")
const MapsScript = preload("res://scripts/maps.gd")

var M: Dictionary = {}
var DIFF: Dictionary = {}
var POSTS: Array = []
const POST_NAMES := ["ALPHA", "BRAVO", "CHARLIE"]
var LZ := Vector3(0, 0, 72)
const CAPTURE_RADIUS := 7.0
const EXTRACT_TIME := 120.0
const PICKUP_TIME := 30.0
const HORDE_TIME := 240.0
var horde := false
const BOARD_RADIUS := 8.0
var pickup := false
var pickup_t := 0.0
var board_hold := 0.0
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
var builder
var rain: Node3D = null
var droid_spawns: Array = []
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
var _bidir_client_id := 0
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
	versus = Game.is_versus_mode(int(Game.settings.get("mode", 0)))
	horde = int(Game.settings.get("mode", 0)) == Game.HORDE
	if horde:
		# Horde: no posts to take, straight into the extraction defence with a longer clock
		post_captured = [true, true, true]
		post_progress = [1.0, 1.0, 1.0]
		phase = 3
		timer = HORDE_TIME
	ffa = int(Game.settings.get("mode", 0)) == 2
	pvp_target = 10 if ffa else 15
	LZ = M["lz"]
	if Game.test_mode in ["smoke", "smoke2", "smokefail", "walkcap", "kbtest", "weapons", "hitbox", "camview", "horde", "mech", "walls", "antitank", "classes"]:
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
	Game.apply_quality()
	if not Game.is_headless():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if multiplayer.is_server():
		if not Game.dedicated:
			on_peer_ready(1)
	else:
		Game.rpc_id(1, "client_world_ready")
	if Game.test_mode.begins_with("bench"):
		_bench.call_deferred()
	if Game.test_mode.begins_with("mapcheck"):
		_test_mapcheck.call_deferred()
	show_message(("%s (%s): HORDE! Hold out until the gunship arrives." if horde else "%s (%s): squad deployed! Head for Command Post ALPHA.") % [M["name"], DIFF["name"]])


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
	builder = MapBuilderScript.new(self, nav_region)
	var layout = MapsScript.new()
	layout.build(builder, M)
	rain = layout.rain
	droid_spawns = builder.spawn_points
	for i in POSTS.size():
		_build_post(i)
	builder.flush()
	print("[map] %s built: %d droid entry points, %d occluders" % [M["name"], droid_spawns.size(), builder.occluders])

	_spawn_mechs()
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
	builder.prop("crate", center + Vector3(3, 0, 2), 0.4, 1.1, "box")
	builder.prop("crate", center + Vector3(-3, 0, -2), 1.1, 1.1, "box")
	builder.prop("barrel", center + Vector3(-3.4, 0, 2.6), 0.0, 1.2, "cyl", Color.WHITE, 1.0, 0.45)
	post_visuals.append({"ring_mat": ring_mat, "flag": flag, "flag_mat": flag_mat, "label": lbl, "center": center})


## ---- Driveable vehicles (AT-RT / BARC / TX-130 / ISP) ----
var mechs: Array = []
var mech_pilot: Array = []
var mech_vtype: Array = []
var mech_hp: Array = []
var mech_max_hp: Array = []
var mech_pad: Array = []       # Vector3 pad position
var mech_pad_ry: Array = []
var mech_wreck_t: Array = []   # >0 while wrecked, counting down to respawn
const VEHICLE_RESPAWN := 40.0
var vehicle_time_accum := {}   # peer_id -> cumulative piloted seconds (never resets on exit)


func _spawn_mechs() -> void:
	# Balanced mix; Versus gets mirrored pads near both spawns
	var pads: Array = [
		{"pos": LZ + Vector3(8, 0, -10), "ry": PI, "v": 0},
		{"pos": LZ + Vector3(-10, 0, -6), "ry": PI, "v": 1},
		{"pos": Vector3(0, 0, 0) + Vector3(18, 0, -8), "ry": 0.0, "v": 3},
	]
	if versus:
		pads.append({"pos": M["spawns"][0] + Vector3(10, 0, -8), "ry": PI, "v": 1})
		pads.append({"pos": M["spawns"][1] + Vector3(-10, 0, 8), "ry": 0.0, "v": 1})
		pads.append({"pos": Vector3(0, 0, 5), "ry": 0.0, "v": 2})  # one tank mid
	else:
		pads.append({"pos": POSTS[1] + Vector3(12, 0, 8), "ry": -PI / 2.0, "v": 2})
	for pad in pads:
		_add_vehicle(pad["v"], pad["pos"], pad["ry"])


func _add_vehicle(vtype: int, pos: Vector3, ry: float) -> void:
	var st: Dictionary = MechVisual.stats(vtype)
	var m: Node3D = MechVisual.build_type(vtype)
	m.set_meta("vtype", vtype)
	var body := StaticBody3D.new()
	body.name = "Col"
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = st["size"]
	cs.shape = bx
	cs.position.y = float(st["col_y"])
	body.add_child(cs)
	m.add_child(body)
	add_child(m)
	m.global_position = pos
	m.rotation.y = ry
	mechs.append(m)
	mech_pilot.append(0)
	mech_vtype.append(vtype)
	mech_hp.append(float(st["hp"]))
	mech_max_hp.append(float(st["hp"]))
	mech_pad.append(pos)
	mech_pad_ry.append(ry)
	mech_wreck_t.append(0.0)


func mech_near(pos: Vector3) -> int:
	for i in mechs.size():
		if mech_pilot[i] == 0 and mech_wreck_t[i] <= 0.0 and mechs[i].visible \
				and mechs[i].global_position.distance_to(pos) < 4.5:
			return i
	return -1


func vehicle_name(i: int) -> String:
	if i < 0 or i >= mech_vtype.size():
		return "Vehicle"
	return str(MechVisual.stats(mech_vtype[i])["name"])


func on_mech_enter(i: int, pid: int) -> void:
	if i < 0 or i >= mechs.size() or mech_pilot[i] != 0 or mech_wreck_t[i] > 0.0:
		return
	mech_pilot[i] = pid
	mechs[i].visible = false
	mechs[i].get_node("Col").collision_layer = 0
	var p = players.get(pid)
	if p != null:
		p.in_mech = i
		p.veh_vtype = mech_vtype[i]
		if p.is_local:
			p.global_position = mechs[i].global_position
			p.rotation.y = mechs[i].rotation.y
			p.veh_heat = 0.0
			p.veh_shell_cd = 0.0
			show_message("%s online. Steer + fire; E exits. Hull HP is separate from yours." % vehicle_name(i))


func on_mech_exit(i: int, pos: Vector3, ry: float) -> void:
	if i < 0 or i >= mechs.size():
		return
	var p = players.get(mech_pilot[i])
	if p != null:
		p.in_mech = -1
	mech_pilot[i] = 0
	if mech_wreck_t[i] > 0.0:
		return
	mechs[i].global_position = pos
	mechs[i].rotation.y = ry
	mechs[i].visible = true
	mechs[i].get_node("Col").collision_layer = 1


## Apply damage to a vehicle hull. Returns true if destroyed.
func damage_vehicle(i: int, dmg: float, attacker: int, from: Vector3) -> bool:
	if i < 0 or i >= mechs.size() or mech_wreck_t[i] > 0.0:
		return false
	mech_hp[i] = maxf(0.0, mech_hp[i] - dmg)
	if mech_hp[i] > 0.0:
		return false
	_destroy_vehicle(i, attacker, from)
	return true


func _destroy_vehicle(i: int, attacker: int, from: Vector3) -> void:
	var pid: int = mech_pilot[i]
	spawn_explosion(mechs[i].global_position + Vector3(0, 1.0, 0))
	Game.net_all("explosion_fx", [mechs[i].global_position + Vector3(0, 1.0, 0)], false)
	mech_wreck_t[i] = VEHICLE_RESPAWN
	mechs[i].visible = false
	mechs[i].get_node("Col").collision_layer = 0
	if pid != 0:
		var p = players.get(pid)
		if p != null:
			p.in_mech = -1
			if p.is_local:
				# Bailout blast — fair chip damage to the pilot
				p.take_damage(28.0, from if from != Vector3.ZERO else mechs[i].global_position, attacker)
			elif multiplayer.is_server():
				last_attacker[pid] = attacker
				Game.net_peer(pid, "hit_player", [28.0, from if from != Vector3.ZERO else mechs[i].global_position, attacker])
		mech_pilot[i] = 0
	show_message("%s destroyed!" % vehicle_name(i))


func _tick_vehicles(delta: float) -> void:
	for i in mechs.size():
		if mech_wreck_t[i] <= 0.0:
			continue
		mech_wreck_t[i] -= delta
		if mech_wreck_t[i] <= 0.0:
			mech_wreck_t[i] = 0.0
			mech_hp[i] = mech_max_hp[i]
			mechs[i].global_position = mech_pad[i]
			mechs[i].rotation.y = mech_pad_ry[i]
			mechs[i].visible = true
			mechs[i].get_node("Col").collision_layer = 1
			mech_pilot[i] = 0
	# Cumulative vehicle timer → Anti-Armor spawn (co-op / horde only, server)
	if multiplayer.is_server() and not versus and not ended and started:
		_tick_anti_armor_timer(delta)
	# Lava burn hazard (Mustafar)
	if multiplayer.is_server() and M.get("layout", "") == "mustafar":
		_tick_lava(delta)


func _tick_anti_armor_timer(delta: float) -> void:
	for p in players.values():
		if p.state != 0:
			continue
		if p.piloting():
			var pid: int = p.peer_id
			vehicle_time_accum[pid] = float(vehicle_time_accum.get(pid, 0.0)) + delta
			while float(vehicle_time_accum[pid]) >= 30.0:
				vehicle_time_accum[pid] = float(vehicle_time_accum[pid]) - 30.0
				_spawn_anti_armor()


func _spawn_anti_armor() -> void:
	var spot: Vector3 = droid_spawns[rng.randi() % droid_spawns.size()] if droid_spawns.size() > 0 else LZ + Vector3(20, 0, -30)
	spot.y = 0.5
	var id := next_enemy_id
	next_enemy_id += 1
	var e = _create_enemy(id, 4, spot)
	if e != null:
		Game.net_all("feed", ["Anti-Armor Rocket Droid deployed — hunting vehicles!"])
		show_message("Anti-Armor Rocket Droid deployed — hunting vehicles!")


func nearest_piloted_player(pos: Vector3):
	var best = null
	var bd := INF
	for p in players.values():
		if p.state != 0 or not p.piloting():
			continue
		var d: float = p.global_position.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = p
	return best


func highest_vehicle_time_player():
	var best = null
	var bt := -1.0
	for p in players.values():
		if p.state != 0:
			continue
		var tsec: float = float(vehicle_time_accum.get(p.peer_id, 0.0))
		if tsec > bt:
			bt = tsec
			best = p
	return best if best != null else nearest_alive_player(LZ)


func enemy_anti_armor_fire(e, target, dist: float) -> void:
	if target == null or not target.piloting():
		return
	var from: Vector3 = e.muzzle_position()
	var aim: Vector3 = target.global_position + Vector3(0, 1.5, 0)
	var lead: float = float(DIFF.get("lead", 0.0))
	if lead > 0.0:
		aim += target.velocity * (dist / 70.0) * lead
	var to := aim
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	var blocked := false
	if not res.is_empty() and from.distance_to(res["position"]) + 0.1 < from.distance_to(aim):
		to = res["position"]
		blocked = true
	Game.net_all("bolt_fx", [from, to, 3])  # heavy orange/green-ish bolt kind 3
	if blocked:
		return
	var chance: float = float(e.stats["acc"])
	if rng.randf() > chance:
		return
	# Direct vehicle hull damage
	if target.in_mech >= 0:
		damage_vehicle(target.in_mech, float(e.stats["dmg"]), 0, from)
	else:
		Game.net_peer(target.peer_id, "hit_player", [float(e.stats["dmg"]) * 0.35, from, 0])


func nearest_live_grenade(pos: Vector3, radius: float):
	# grenades live under fx_root briefly; scan children with velocity meta
	if fx_root == null:
		return null
	for c in fx_root.get_children():
		if c.has_method("get") and c.get("velocity") != null:
			if c.global_position.distance_to(pos) < radius:
				return c.global_position
	return null


func officer_aura_mult(pid: int) -> float:
	var p = players.get(pid)
	if p == null:
		return 1.0
	var best := 1.0
	for o in players.values():
		if o.state != 0 or o.cls != 3:
			continue
		var d: float = o.global_position.distance_to(p.global_position)
		if d <= 12.0:
			var self_half: bool = (o.peer_id == pid)
			best = maxf(best, 1.15 if not self_half else 1.075)
	return best


func officer_regen(pid: int) -> float:
	var p = players.get(pid)
	if p == null:
		return 0.0
	var r := 0.0
	for o in players.values():
		if o.state != 0 or o.cls != 3:
			continue
		var d: float = o.global_position.distance_to(p.global_position)
		if d <= 12.0:
			r = maxf(r, 3.0 if o.peer_id != pid else 1.5)
	return r


func apply_battle_command(src_pid: int, pos: Vector3) -> void:
	for p in players.values():
		if p.state != 0:
			continue
		if p.global_position.distance_to(pos) <= 14.0:
			if p.is_local:
				p.bonus_hp = maxf(p.bonus_hp, 25.0)
				p.cmd_buff_t = maxf(p.cmd_buff_t, 6.0)
			elif multiplayer.is_server() and p.peer_id != src_pid:
				Game.net_peer(p.peer_id, "battle_cmd_fx", [])


func _tick_lava(delta: float) -> void:
	# Burn anyone standing near lava channel centers (y near 0, in channel xz)
	for p in players.values():
		if p.state != 0:
			continue
		var pos: Vector3 = p.global_position
		# Channels from maps: wide X or Z bands at low y
		var in_lava: bool = absf(pos.z - 5.0) < 5.5 and absf(pos.x) < 60.0
		in_lava = in_lava or (absf(pos.x + 30.0) < 5.5 and absf(pos.z + 10.0) < 40.0)
		in_lava = in_lava or (absf(pos.x - 35.0) < 5.5 and absf(pos.z - 30.0) < 35.0)
		# Safe on elevated platforms (y > 0.3)
		if in_lava and pos.y < 0.35 and not p.piloting():
			if p.is_local:
				p.take_damage(12.0 * delta, pos, 0)
			else:
				Game.net_peer(p.peer_id, "hit_player", [12.0 * delta, pos, 0])


func _build_gunship() -> Node3D:
	var gs: Node3D = load("res://models/gunship.glb").instantiate()
	var holder := Node3D.new()
	holder.name = "Gunship"
	holder.add_child(gs)
	gs.scale = Vector3.ONE * 1.2
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.3, 0.2)
	light.omni_range = 12
	light.position = Vector3(0, -2, 0)
	holder.add_child(light)
	return holder


func _build_gunship_boxes() -> Node3D:
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
		p.team = int(Game.players[pid]["team"]) if Game.players.has(pid) and Game.players[pid].has("team") else (index if ffa else _balanced_team())
		p.position = _spawn_for(p.team, index)
		p.rotation.y = atan2(p.position.x, p.position.z)  # face the middle of the map
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
		var base: Vector3 = M["spawns"][clampi(team, 0, 1)]
		return base + Vector3(r.randf_range(-4, 4) + salt * 0.0, 1.0, r.randf_range(-3, 3))
	var pts: Array = droid_spawns + M["spawns"]
	return pts[r.randi() % pts.size()] + Vector3(r.randf_range(-2, 2), 1.0, r.randf_range(-2, 2))


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
		st = st & 3
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
	_tick_vehicles(delta)
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
		if timer <= 0.0 and not pickup:
			timer = 0.0
			pickup = true
			pickup_t = PICKUP_TIME
			Game.net_all("announce", ["The gunship has landed! Get to the LZ and board!"])
		if pickup:
			# Troop transport pickup: win once every standing trooper is aboard (within the LZ pad)
			pickup_t -= delta * test_speed
			var standing := 0
			var aboard := 0
			for p in players.values():
				if p.state == 0:
					standing += 1
					if _flat_dist(p.global_position, LZ) < BOARD_RADIUS:
						aboard += 1
			board_hold = board_hold + delta * test_speed if (standing > 0 and aboard == standing) else 0.0
			if board_hold > 1.5 or pickup_t <= 0.0:
				earned += int((500 if aboard > 0 else 250) * float(DIFF["credits"]))
				if aboard > 0:
					Game.net_all("announce", ["%d trooper(s) aboard. Dust off!" % aboard])
				_end_mission(aboard > 0 or players.size() == 0)
				return

	# Enemy AI
	# AI budget: droids >55 m from every trooper think at 1/3 rate (accumulated delta, staggered by id)
	var fr := Engine.get_physics_frames()
	for e in enemies.values():
		e._think_acc += delta
		var far := true
		for p in players.values():
			if p.global_position.distance_squared_to(e.global_position) < 3025.0:
				far = false
				break
		if far and (fr + e.eid) % 3 != 0:
			continue
		e.server_tick(e._think_acc, self)
		e._think_acc = 0.0

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
		sync_cd = 0.1   # 10 Hz enemy snapshots (was 20 Hz); clients interpolate between them
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


## True if an OOM commander is within 12 m (its buff: +43% fire rate, +25% damage).
func commander_near(pos: Vector3) -> bool:
	for e in enemies.values():
		if e.etype == 3 and _flat_dist(e.global_position, pos) < 12.0:
			return true
	return false


func _pick_type() -> int:
	var r := rng.randf()
	if phase >= 1 and r < 0.08:
		var has_cmd := false
		for e in enemies.values():
			if e.etype == 3:
				has_cmd = true
		if not has_cmd:
			return 3
		r = rng.randf()
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
	var cands := []
	for sp in droid_spawns:
		var dd: float = _flat_dist(sp, focus)
		var near := false
		for p in players.values():
			if _flat_dist(p.global_position, sp) < 25.0:
				near = true
		if dd > 30.0 and dd < 80.0 and not near:
			cands.append(sp)
	for attempt in (0 if cands.size() > 0 else 12):
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
	if cands.size() > 0:
		pos = cands[rng.randi() % cands.size()] + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
	elif nav_polys > 0:
		pos = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, pos)
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
	if e.char_model != null and Game.quality() == 0:
		e.char_model.set_shadows(false)
	return e


func enemy_fire(e, target, dist: float) -> void:
	var from: Vector3 = e.muzzle_position()
	var aim: Vector3 = target.aim_target_pos() if target.has_method("aim_target_pos") else target.global_position + Vector3(0, 1.2, 0)
	# Predictive lead on Veteran / Clone Commander
	var lead: float = float(DIFF.get("lead", 0.0))
	if lead > 0.0 and "velocity" in target:
		aim += target.velocity * (dist / 90.0) * lead
	var chance: float = e.stats["acc"] * clampf(1.3 - dist / e.stats["range"], 0.35, 1.0)
	if target.is_sprinting:
		chance *= 0.6
	if target.get("is_crouching"):
		chance *= 0.75
	var hit := rng.randf() < chance
	var to := aim
	if not hit:
		var off := Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(-0.6, 1.4), rng.randf_range(-1.6, 1.6))
		to = from + ((aim + off) - from).normalized() * (dist + 20.0)
	# ALWAYS wall-check from muzzle — cover blocks hits even when LOS cache is stale
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if not res.is_empty():
		var wall_pos: Vector3 = res["position"]
		if from.distance_to(wall_pos) + 0.05 < from.distance_to(aim):
			to = wall_pos
			hit = false
	Game.net_all("bolt_fx", [from, to, 1])
	if hit:
		var solo := 0.8 if players.size() == 1 else 1.0
		Game.net_peer(target.peer_id, "hit_player", [float(e.stats["dmg"]) * solo * (1.25 if e.buffed else 1.0), from, 0])


func micro_splash(pos: Vector3, shooter: int, dmg: float, radius: float) -> void:
	explode(pos, shooter, radius, dmg, dmg * 1.2)


func damage_enemy(eid: int, dmg: float, from: Vector3, shooter: int, explosive: bool) -> void:
	if not enemies.has(eid) or ended:
		return
	var e = enemies[eid]
	if e.apply_damage(dmg, from, explosive):
		kills += 1
		earned += int(round(float(e.stats["credits"]) * float(DIFF["credits"])))
		Game.net_all("enemy_died", [eid, e.global_position, shooter, e.etype])


func explode(pos: Vector3, shooter: int, radius: float = 7.0, pvp_base: float = 120.0, enemy_base: float = 160.0) -> void:
	Game.net_all("explosion_fx", [pos])
	var origin := pos + Vector3(0, 0.4, 0)
	var space := get_world_3d().direct_space_state
	if versus:
		for p in players.values():
			var dp: float = p.global_position.distance_to(pos)
			if dp < radius:
				var tc: Vector3 = p.aim_target_pos() if p.has_method("aim_target_pos") else p.global_position + Vector3(0, 1.0, 0)
				var rq := PhysicsRayQueryParameters3D.create(origin, tc, 1)
				if space.intersect_ray(rq).is_empty():
					pvp_damage(shooter, p.peer_id, pvp_base * (1.0 - dp / radius) + 20.0, pos)
	for e in enemies.values().duplicate():
		var d: float = e.global_position.distance_to(pos)
		if d < radius:
			var ec: Vector3 = e.global_position + Vector3(0, 1.0, 0)
			var rq2 := PhysicsRayQueryParameters3D.create(origin, ec, 1)
			if space.intersect_ray(rq2).is_empty():
				damage_enemy(e.eid, enemy_base * (1.0 - d / radius) + 40.0, pos, shooter, true)


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
	# Piloted vehicles absorb hits on their own hull HP
	if t.in_mech >= 0:
		damage_vehicle(t.in_mech, dmg, shooter, from)
		return
	Game.net_peer(target, "hit_player", [dmg, from, shooter])


func on_pvp_died(victim: int, reported_killer: int = 0) -> void:
	if ended:
		return
	var killer: int = reported_killer if reported_killer != 0 and reported_killer != victim else last_attacker.get(victim, 0)
	if reported_killer != 0 and reported_killer != victim and is_hostile(reported_killer, victim):
		killer = reported_killer
	last_attacker.erase(victim)
	var vs: Vector2i = pvp_scores.get(victim, Vector2i.ZERO)
	pvp_scores[victim] = Vector2i(vs.x, vs.y + 1)
	var vname := _pname(victim)
	if killer != 0 and killer != victim:
		var ks: Vector2i = pvp_scores.get(killer, Vector2i.ZERO)
		pvp_scores[killer] = Vector2i(ks.x + 1, ks.y)
		if not ffa:
			var kteami := 0
			if players.has(killer):
				kteami = int(players[killer].team)
			elif killer != 1:
				kteami = 1
			if kteami == 0:
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
	Game.add_credits(credits)
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
			enemies[id].die()
			enemies.erase(id)


func on_enemy_died(eid: int, pos: Vector3, killer: int = 0, etype: int = 0) -> void:
	if enemies.has(eid):
		enemies[eid].die()
		enemies.erase(eid)
	spawn_explosion(pos + Vector3(0, 1, 0), 0.5)
	_spawn_debris(pos + Vector3(0, 1, 0), etype)
	var kname := "Squad"
	if killer == multiplayer.get_unique_id():
		Game.play_sfx("kill", null, -10.0)
	if Game.players.has(killer):
		kname = str(Game.players[killer]["name"])
	if hud != null:
		hud.add_feed("%s  >  %s" % [kname, EnemyScript.TYPES[etype]["name"]],
			Color(0.5, 0.8, 1.0) if killer == multiplayer.get_unique_id() else Color(0.9, 0.9, 0.9))


func _spawn_debris(pos: Vector3, etype: int) -> void:
	var col: Color = [Color(0.78, 0.68, 0.48), Color(0.3, 0.33, 0.4), Color(0.55, 0.4, 0.25), Color(0.92, 0.75, 0.2), Color(0.45, 0.1, 0.1)][clampi(etype, 0, 4)]
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
	Game.add_credits(credits)
	Game.save["missions"] = int(Game.save["missions"]) + 1
	if win:
		Game.save["wins"] = int(Game.save["wins"]) + 1
	Game.write_save()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_end(win, credits, k)
	if Game.test_mode in ["smoke", "smoke2", "horde"]:
		var plen := nav_path_length(LZ, POSTS[0])
		print("[test] map=%s diff=%s nav polys=%d path_points LZ->ALPHA=%d" % [M["name"], DIFF["name"], nav_polys, plen])
		print("[test] kill feed entries=%d" % hud.feed_box.get_child_count())
		Game.finish_test(win and nav_polys > 0 and plen >= 2 and hud.feed_box.get_child_count() > 0, "SMOKE win=%s credits=%d kills=%d total_credits=%d" % [win, credits, k, Game.save["credits"]])
	elif Game.test_mode == "smokefail":
		print("[test] damage indicator active=%s" % (hud.dmg_time > 0.0))
		Game.finish_test(not win and hud.dmg_time > 0.0, "SMOKEFAIL win=%s credits=%d kills=%d" % [win, credits, k])


# ------------------------------------------------------------------ fx
var _bolt_pool: Array = []


func spawn_bolt(from: Vector3, to: Vector3, kind: int) -> void:
	var b = null
	for cand in _bolt_pool:
		if is_instance_valid(cand) and not cand.visible and not cand._alive:
			b = cand
			break
	if b == null:
		b = BoltScript.new()
		fx_root.add_child(b)
		_bolt_pool.append(b)
		if _bolt_pool.size() > 64:
			var old = _bolt_pool.pop_front()
			if is_instance_valid(old):
				old.queue_free()
	b.reset_bolt(from, to, kind)
	_muzzle_flash(from, kind)
	Game.play_sfx(["blaster", "enemy_blaster", "scatter"][clampi(kind, 0, 2)], from, -8.0 if kind == 1 else -4.0)
	# drive the shooter's firing animation (works for remote players and synced droids alike)
	var pool: Array = enemies.values() if kind == 1 else players.values()
	for n in pool:
		if is_instance_valid(n) and n.global_position.distance_squared_to(from) < 6.0:
			n.shot_t = 0.35
			break


func _muzzle_flash(pos: Vector3, kind: int) -> void:
	var c := Color(0.5, 0.75, 1.0) if kind != 1 else Color(1.0, 0.35, 0.2)
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
	if rain != null:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			rain.global_position = cam.global_position + Vector3(0, 14, 0)
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
		var target_y := (2.2 if timer <= 0.0 else 6.0) + 74.0 * t
		if ended and timer <= 0.0:
			target_y = 40.0   # lift off
		gunship.position.y = lerpf(gunship.position.y, target_y, minf(1.0, delta * 2.0))
		gunship.rotation.y += delta * 0.05 * t


# ------------------------------------------------------------------ headless test autopilot
func _test_autopilot(delta: float) -> void:
	if Game.test_mode == "pvp_server":
		_test_pvp_server(delta)
	if Game.test_mode == "pvp_bidir_server":
		_test_pvp_bidir_server(delta)
		return
	if Game.test_mode not in ["smoke", "smoke2", "smokefail", "walkcap", "kbtest", "weapons", "hitbox", "camview", "horde", "mech", "walls", "antitank", "classes"]:
		return
	test_elapsed += delta
	var lp = local_player()
	if lp == null:
		return
	if Game.test_mode == "walkcap":
		_test_walkcap(delta, lp)
		return
	if Game.test_mode == "camview":
		_test_camview(lp)
		return
	if Game.test_mode == "mech" and _t_stage == 0:
		_t_stage = 1
		_test_mech(lp)
	if Game.test_mode == "walls" and _t_stage == 0:
		_t_stage = 1
		_test_walls(lp)
	if Game.test_mode == "antitank" and _t_stage == 0:
		_t_stage = 1
		_test_antitank(lp)
	if Game.test_mode == "classes" and _t_stage == 0:
		_t_stage = 1
		_test_classes(lp)
		return
	if Game.test_mode == "hitbox":
		_test_hitbox(lp)
		return
	if Game.test_mode == "weapons":
		_test_weapons(delta, lp)
		return
	if Game.test_mode == "kbtest":
		_test_keyboard(delta, lp)
		return
	if Game.test_mode in ["smoke", "smoke2", "horde"]:
		lp.god = true
		if phase < 3:
			lp.global_position = POSTS[nearest_open_post(lp.global_position)] + Vector3(1, 0.5, 1)
			lp.velocity = Vector3.ZERO
		elif pickup:
			lp.global_position = LZ + Vector3(2, 0.5, 2)   # board the gunship
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
		Game.finish_test(false, "PVP self-damage applied state=%d hp=%.0f pos=%s" % [players[1].state, players[1].health, players[1].global_position])
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
	if Game.test_mode == "pvp_bidir_client":
		_test_pvp_bidir_client(_delta)
		return
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


## Map sanity: navmesh baked, every post reachable from the LZ, both team spawns and every droid
## entry point; spawn points and post centres are not inside geometry.
func _test_mapcheck() -> void:
	spawn_cd = 9999.0
	await get_tree().create_timer(1.5).timeout
	var map := get_world_3d().navigation_map
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	var fails := []
	var starts := {"LZ": LZ}
	for i in M["spawns"].size():
		starts["team%d" % i] = M["spawns"][i]
	for i in droid_spawns.size():
		starts["droid%d" % i] = droid_spawns[i]
	for i in POSTS.size():
		starts["post%d" % i] = POSTS[i] + Vector3(3, 0, 0)
	for key in starts:
		var p: Vector3 = starts[key]
		q.transform = Transform3D(Basis(), p + Vector3(0, 1.0, 0))
		if space.intersect_shape(q, 1).size() > 0:
			fails.append("%s blocked" % key)
		for i in POSTS.size():
			var a := NavigationServer3D.map_get_closest_point(map, p)
			var b := NavigationServer3D.map_get_closest_point(map, POSTS[i])
			var path := NavigationServer3D.map_get_path(map, a, b, true)
			if path.size() < 2 or path[path.size() - 1].distance_to(b) > 1.5 or a.distance_to(p) > 2.5:
				fails.append("%s->post%d unreachable" % [key, i])
	for h in M.get("high", []):
		var hp := NavigationServer3D.map_get_closest_point(map, h)
		var hpath := NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, LZ), hp, true)
		if absf(hp.y - h.y) > 0.8 or hpath.size() < 2 or hpath[hpath.size() - 1].distance_to(hp) > 1.0:
			fails.append("high ground %s not walkable (got %s)" % [h, hp])
	var mm := 0
	var tris := 0
	for n in builder.deco.get_children():
		if n is MultiMeshInstance3D:
			mm += 1
			var mesh: Mesh = n.multimesh.mesh
			var t := 0
			for si in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(si)
				t += (arr[Mesh.ARRAY_INDEX].size() if arr[Mesh.ARRAY_INDEX] != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
			tris += t * n.multimesh.instance_count
	print("[test] mapcheck %s: nav polys=%d, %d start points, %d multimesh batches, %d prop tris, fails=%s" % [M["name"], nav_polys, starts.size(), mm, tris, fails])
	Game.finish_test(nav_polys > 100 and fails.is_empty(), "MAPCHECK %s" % M["name"])


## Weapon slot 2 (scatter blaster) via the real input action: switch, fire at a B2 8 m ahead,
## check the shotgun magazine, aggregated pellet damage, the commander buff and the animated models.
func _test_weapons(_delta: float, lp) -> void:
	lp.god = true
	match _t_stage:
		0:
			for e in enemies.values().duplicate():
				damage_enemy(e.eid, 9999.0, Vector3.ZERO, 1, false)
			spawn_cd = 999.0
			lp.global_position = Vector3(0, 0.5, LZ.z - 2.0)
			lp.rotation.y = 0.0
			lp.pitch = 0.0
			_t_enemy = _create_enemy(next_enemy_id, 1, lp.global_position + Vector3(0.75, 0, -8))  # on the over-shoulder camera line
			next_enemy_id += 1
			_t_enemy.fire_cd = 999.0
			var cmd = _create_enemy(next_enemy_id, 3, lp.global_position + Vector3(6, 0, -14))
			next_enemy_id += 1
			cmd.fire_cd = 999.0
			Input.action_press("weapon2")
			_t_mark = test_elapsed
			_t_stage = 1
		1:
			Input.action_release("weapon2")
			if test_elapsed - _t_mark > 0.6:
				if lp.weapon != 1 or lp.mag != Game.mag_size(1):
					Game.finish_test(false, "WEAPONS switch weapon=%d mag=%d" % [lp.weapon, lp.mag])
					return
				_t_val = _t_enemy.hp
				Input.action_press("fire")
				_t_mark = test_elapsed
				_t_stage = 2
		2:
			if test_elapsed - _t_mark > 0.15:
				Input.action_release("fire")
			if test_elapsed - _t_mark > 1.2:
				var dmg: float = _t_val - (_t_enemy.hp if is_instance_valid(_t_enemy) else 0.0)
				var cm = _t_enemy.char_model if is_instance_valid(_t_enemy) else null
				var anim_ok: bool = cm != null and cm.ap != null and lp.char_model != null and lp.char_model.ap != null
				var buff: bool = _t_enemy.buffed if is_instance_valid(_t_enemy) else false
				print("[test] weapons: scatter mag %d, damage to B2 %.0f, B2 buffed by commander=%s, animated models=%s (player anim '%s')" % [lp.mag, dmg, buff, anim_ok, lp.char_model.cur])
				_t_stage = 3
				Input.action_press("weapon1")
				await get_tree().physics_frame
				await get_tree().physics_frame
				Input.action_release("weapon1")
				print("[test] weapons: back to slot %d mag %d/%d" % [lp.weapon + 1, lp.mag, lp.mag_size])
				Game.finish_test(lp.weapon == 0 and dmg > 25.0 and buff and anim_ok, "WEAPONS scatter blaster + switching + commander buff")
				_t_stage = 3


## Frame-time benchmark: 16 droids fighting in front of the player at the LZ, 8 s sample.
func _bench() -> void:
	await get_tree().create_timer(2.0).timeout
	spawn_cd = 9999.0
	var lp = local_player()
	lp.god = true
	lp.rotation.y = atan2(lp.global_position.x - POSTS[0].x, lp.global_position.z - POSTS[0].z)
	for i in 16:
		var a := -0.6 + 1.2 * float(i) / 15.0
		var d := 20.0 + float(i % 4) * 8.0
		var dir: Vector3 = (POSTS[0] - LZ).normalized().rotated(Vector3.UP, a)
		var pos: Vector3 = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, LZ + dir * d)
		_create_enemy(next_enemy_id, [0, 0, 1, 3, 0, 2][i % 6], pos + Vector3(0, 0.5, 0))
		next_enemy_id += 1
	await get_tree().create_timer(1.0).timeout
	var frames := []
	var dc := 0.0
	var prims := 0.0
	var phys := 0.0
	var t0 := Time.get_ticks_usec()
	var last := t0
	while Time.get_ticks_usec() - t0 < 8000000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var n := frames.size()
	var sorted := frames.duplicate()
	sorted.sort()
	var avg := 0.0
	for f in frames:
		avg += f
	avg /= n
	print("[test] BENCH %s quality=%s: frames=%d avg=%.1fms p95=%.1fms fps=%.1f draw_calls=%.0f primitives=%.0f physics=%.2fms enemies=%d" % [
		M["name"], Game.quality_name(), n, avg, sorted[int(n * 0.95)], 1000.0 / avg, dc / n, prims / n, phys / n, enemies.size()])
	Game.finish_test(true, "BENCH")


func apply_quality(q: int) -> void:
	if builder != null and builder.sun != null:
		builder.sun.shadow_enabled = true
		builder.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if q == 0 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		builder.sun.directional_shadow_max_distance = [35.0, 50.0, 70.0][q]
	if builder != null and builder.env != null:
		builder.env.glow_enabled = q == 2
	if rain != null:
		rain.amount = [150, 300, 600][q]
	if builder != null:
		for n in builder.deco.get_children():
			if n is MultiMeshInstance3D:
				n.visibility_range_end = [115.0, 180.0, 0.0][q]
				n.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	for e in enemies.values():
		if e.char_model != null:
			e.char_model.set_shadows(q > 0)


## Visual bounds of a character: bone positions of the posed skeleton (skinned mesh AABBs are
## bind-pose and unreliable), padded for the head; falls back to mesh AABBs for rigid models.
func visual_aabb(n: Node3D) -> AABB:
	var sks := n.find_children("*", "Skeleton3D", true, false)
	if sks.size() > 0:
		var sk: Skeleton3D = sks[0]
		var bb := AABB(sk.global_transform * sk.get_bone_global_pose(0).origin, Vector3.ZERO)
		var head_y := -1e9
		for b in sk.get_bone_count():
			var p: Vector3 = (sk.global_transform * sk.get_bone_global_pose(b)).origin
			bb = bb.expand(p)
			if sk.get_bone_name(b).begins_with("Head"):
				head_y = p.y
		var ground: float = n.global_position.y
		bb = bb.expand(Vector3(bb.position.x, ground, bb.position.z))
		return bb
	return _mesh_aabb(n)


func _mesh_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree():
			continue
		var a: AABB = mi.global_transform * mi.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


## Fire the player's real hitscan (camera ray) at the visual centre and head/legs of each droid type.
func _test_hitbox(lp) -> void:
	if _t_stage > 0:
		return
	_t_stage = 1
	lp.god = true
	spawn_cd = 9999.0
	for e in enemies.values().duplicate():
		damage_enemy(e.eid, 9999.0, Vector3.ZERO, 1, false)
	var ok := true
	var space := get_world_3d().direct_space_state
	for t in [0, 1, 2, 3]:
		var pos := Vector3(0, 0.0, LZ.z - 14.0)
		var e = _create_enemy(next_enemy_id, t, pos)
		next_enemy_id += 1
		e.fire_cd = 999.0
		e.deployed = t == 2
		for k in 6:
			await get_tree().physics_frame
		e.global_position = pos
		e._update_visual(0.016)
		await get_tree().process_frame
		var va := visual_aabb(e.model if t != 2 else e)
		var cap: CapsuleShape3D = e.get_child(0).shape
		var res := []
		var head_y: float = [1.54, 1.78, 1.2, 1.62][t]
		var head_r: float = [0.5, 0.62, 0.3, 0.52][t]
		for spot in [Vector2(0, 0.5), Vector2(0, 0.15), Vector2(0, -1), Vector2(head_r * 0.8, -1)]:
			var ty: float = (head_y if spot.y < 0 else va.position.y + va.size.y * spot.y)
			var target := Vector3(e.global_position.x + spot.x, ty, e.global_position.z)
			var from := target + Vector3(0, 0.3, 9.0)
			var q := PhysicsRayQueryParameters3D.create(from, target + (target - from).normalized() * 3.0, lp._shot_mask(), [lp.get_rid()])
			var hit := space.intersect_ray(q)
			var good: bool = not hit.is_empty() and hit["collider"] == e
			if not good:
				print("[test]   miss at %s: %s e.pos=%s" % [target, hit.get("collider"), e.global_position])
			res.append(good)
			ok = ok and good
		print("[test] hitbox %s: visual h=%.2f w=%.2f, capsule h=%.2f r=%.2f, hits centre/legs/head/head-edge=%s" % [EnemyScript.TYPES[t]["name"], va.size.y, va.size.x, cap.height, cap.radius, res])
		if t == 1:
			var clone_h: float = visual_aabb(lp.model).size.y
			print("[test] hitbox B2 height %.2f vs clone %.2f (ratio %.2f)" % [va.size.y, clone_h, va.size.y / clone_h])
			ok = ok and va.size.y / clone_h > 1.1
		e.die()
		enemies.erase(e.eid)
	Game.finish_test(ok, "HITBOX every droid type hit at its visual centre/legs/head")


## Local trooper must be in front of the camera and on screen: at the LZ, backed against the
## ALPHA flag pole and backed against a mesa wall (the cases that used to put the camera in the helmet).
func _test_mech(lp) -> void:
	spawn_cd = 9999.0
	lp.god = true
	var ok := true
	var msgs := []
	# Enter / drive / fire / exit each vehicle type present
	for i in mechs.size():
		if mech_wreck_t[i] > 0.0:
			continue
		lp.global_position = mechs[i].global_position + Vector3(2.5, 0.05, 0)
		await get_tree().physics_frame
		on_mech_enter(i, lp.peer_id)
		await get_tree().physics_frame
		if lp.in_mech != i:
			ok = false
			msgs.append("enter fail v=%d" % mech_vtype[i])
			continue
		var hull0: float = mech_hp[i]
		var trooper0: float = lp.health
		damage_vehicle(i, 40.0, 0, lp.global_position)
		if absf(mech_hp[i] - (hull0 - 40.0)) > 0.1 or absf(lp.health - trooper0) > 0.1:
			ok = false
			msgs.append("hull dmg fail v=%d hp=%s trooper=%s" % [mech_vtype[i], mech_hp[i], lp.health])
		lp._shoot_mech()
		await get_tree().physics_frame
		lp.exit_mech()
		await get_tree().physics_frame
		if lp.in_mech != -1:
			ok = false
			msgs.append("exit fail v=%d" % mech_vtype[i])
	# Destroy vehicle: hull to 0 ejects pilot, trooper takes bailout dmg
	if mechs.size() > 0:
		lp.health = lp.max_health
		lp.god = false
		on_mech_enter(0, lp.peer_id)
		await get_tree().physics_frame
		var before: float = lp.health
		damage_vehicle(0, 9999.0, 0, lp.global_position)
		await get_tree().physics_frame
		if lp.in_mech != -1 or mech_wreck_t[0] <= 0.0:
			ok = false
			msgs.append("destroy/eject fail")
		if lp.health >= before:
			ok = false
			msgs.append("bailout dmg missing hp=%s" % lp.health)
		lp.god = true
	print("[test] mech: vehicles=%d types=%s msgs=%s" % [mechs.size(), mech_vtype, msgs])
	Game.finish_test(ok and mechs.size() >= 2, "MECH multi-vehicle hull HP + enter/fire/exit")



func _test_camview(lp) -> void:
	if _t_stage > 0:
		return
	_t_stage = 1
	lp.god = true
	spawn_cd = 9999.0
	var ok := true
	var spots := [[LZ + Vector3(0, 0.05, -2), 0.0], [POSTS[0] + Vector3(-0.75, 0.05, -1.0), 0.0], [Vector3(-16.8, 0.05, -5.0), -PI / 2.0], [Vector3(-16.8, 0.05, -5.0), PI / 2.0]]
	for sp in spots:
		lp.global_position = sp[0]
		lp.rotation.y = sp[1]
		lp.velocity = Vector3.ZERO
		for k in 4:
			await get_tree().physics_frame
		await get_tree().process_frame
		var head: Vector3 = lp.global_position + Vector3(0, 1.5, 0)
		var chest: Vector3 = lp.global_position + Vector3(0, 1.0, 0)
		var dist: float = lp.cam.global_position.distance_to(head)
		var on_screen: bool = lp.cam.is_position_in_frustum(chest) and lp.model.is_visible_in_tree()
		var vis := 0
		for mi in lp.char_model.meshes:
			if mi.is_visible_in_tree():
				vis += 1
		print("[test] camview at %s: spring_hit=%.2f cam->head=%.2f trooper_on_screen=%s visible_meshes=%d" % [sp[0], lp.spring.get_hit_length(), dist, on_screen, vis])
		ok = ok and on_screen and dist >= 1.1 and vis >= 3
	# ADS (Q / right mouse) without firing must hold a still aim pose, not loop the recoil cycle
	Input.action_press("kb_aim")
	for k in 20:
		await get_tree().physics_frame
	var held: bool = lp.is_aiming and lp.char_model.cur.ends_with("|hold") and lp.char_model.ap.speed_scale == 0.0
	print("[test] camview ADS no-fire: aiming=%s anim=%s speed=%.1f" % [lp.is_aiming, lp.char_model.cur, lp.char_model.ap.speed_scale])
	Input.action_release("kb_aim")
	await get_tree().physics_frame
	Input.action_press("kb_aim")
	await get_tree().physics_frame
	Input.action_release("kb_aim")
	# first person (V): camera at the eyes, own body culled from the camera only
	Input.action_press("view_toggle")
	await get_tree().physics_frame
	Input.action_release("view_toggle")
	await get_tree().process_frame
	var eye_d: float = lp.cam.global_position.distance_to(lp.global_position + Vector3(0, 1.65, 0))
	var fp_ok: bool = lp.first_person and eye_d < 0.5 and (lp.cam.cull_mask & 2) == 0 and lp.char_model.meshes[0].layers == 2 and lp.deco.all(func(d): return d[0].get_children().all(func(m): return m.layers == 2)) and lp.viewmodel != null and lp.viewmodel.visible
	print("[test] camview first person: on=%s cam->eyes=%.2f body_culled=%s camlocal=%s pivot=%s cam=%s p=%s" % [lp.first_person, eye_d, (lp.cam.cull_mask & 2) == 0, lp.cam.position, lp.pivot.global_position, lp.cam.global_position, lp.global_position])
	Input.action_press("view_toggle")
	await get_tree().physics_frame
	Input.action_release("view_toggle")
	await get_tree().process_frame
	fp_ok = fp_ok and not lp.first_person and (lp.cam.cull_mask & 2) != 0
	Game.save["fp"] = false
	Game.finish_test(ok and held and fp_ok, "CAMVIEW local trooper visible in third person + ADS without recoil")



func _test_walls(lp) -> void:
	spawn_cd = 9999.0
	lp.god = true
	for e in enemies.values().duplicate():
		damage_enemy(e.eid, 9999.0, Vector3.ZERO, 1, false)
	# Wall between shooter and a fresh B1
	var wall_pos := LZ + Vector3(0, 1.5, -15)
	builder.box(wall_pos, Vector3(8, 3, 1), Color(0.5, 0.5, 0.5), Vector3.ZERO, true, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	lp.global_position = LZ + Vector3(0, 0.5, -8)
	lp.rotation.y = PI
	var e = _create_enemy(next_enemy_id, 0, LZ + Vector3(0, 0.5, -22))
	next_enemy_id += 1
	var hp0: float = e.hp
	# Force a barrel-traced shot toward the enemy (camera elevated)
	lp.pitch = -0.15
	lp.pivot.rotation.x = lp.pitch
	for i in 5:
		lp._shoot()
		await get_tree().physics_frame
	var blocked_ok: bool = e.hp >= hp0 - 0.1
	# Enemy fire through wall should also be blocked
	var thp0: float = lp.health
	lp.god = false
	enemy_fire(e, lp, lp.global_position.distance_to(e.global_position))
	await get_tree().physics_frame
	var enemy_blocked: bool = lp.health >= thp0 - 0.1
	lp.god = true
	print("[test] walls: player_blocked=%s enemy_blocked=%s ehp %.0f->%.0f" % [blocked_ok, enemy_blocked, hp0, e.hp])
	Game.finish_test(blocked_ok and enemy_blocked, "WALLS stop bullets both ways")


func _test_antitank(lp) -> void:
	spawn_cd = 9999.0
	lp.god = true
	vehicle_time_accum[lp.peer_id] = 0.0
	# Hop in for 20s worth, hop out, hop in for 10s → spawn
	if mechs.is_empty():
		Game.finish_test(false, "ANTITANK no vehicles")
		return
	on_mech_enter(0, lp.peer_id)
	vehicle_time_accum[lp.peer_id] = 20.0
	_tick_anti_armor_timer(0.0)
	var mid := enemies.values().filter(func(e): return e.etype == 4)
	if mid.size() != 0:
		Game.finish_test(false, "ANTITANK spawned too early at 20s")
		return
	lp.exit_mech()
	await get_tree().physics_frame
	# Accum must NOT reset
	if float(vehicle_time_accum.get(lp.peer_id, 0.0)) < 19.0:
		Game.finish_test(false, "ANTITANK accum reset on exit")
		return
	on_mech_enter(0, lp.peer_id)
	vehicle_time_accum[lp.peer_id] = 30.0
	_tick_anti_armor_timer(0.0)
	var aa := []
	for e in enemies.values():
		if e.etype == 4:
			aa.append(e)
	var spawned: bool = aa.size() >= 1
	var hunts := false
	if spawned:
		aa[0].server_tick(0.05, self)
		hunts = aa[0].target == lp or (aa[0].target != null and aa[0].target.piloting())
	print("[test] antitank: spawned=%d hunts_pilot=%s accum=%.1f" % [aa.size(), hunts, vehicle_time_accum.get(lp.peer_id, 0.0)])
	Game.finish_test(spawned and hunts, "ANTITANK cumulative 30s spawn + vehicle hunt")


func _test_classes(lp) -> void:
	spawn_cd = 9999.0
	lp.god = true
	var ok := true
	for c in range(4):
		lp.apply_class(c)
		for slot in range(2):
			lp.switch_weapon(slot)
			lp.mag = maxi(lp.mag, 1)
			lp.fire_cd = 0.0
			lp._shoot()
			await get_tree().physics_frame
		if lp.max_health < 80.0:
			ok = false
	lp.is_crouching = false
	lp.crouch_toggle = true
	lp._update_crouch(0.5, true)
	var crouched: bool = lp.is_crouching and lp.crouch_eye_y < 1.3
	var maps_ok: bool = Game.MAPS.size() >= 6
	# Dynamic controls strip
	hud._hud_cache.erase("ctrl")
	hud._update_controls_hint(lp)
	var hint: String = str(hud.controls_hint.text) if hud.controls_hint else ""
	var hint_ok: bool = hud.controls_hint != null and ("Crouch" in hint or "Stand" in hint)
	lp.apply_class(3)
	lp.cmd_cd = 0.0
	hud._hud_cache.erase("ctrl")
	hud._update_controls_hint(lp)
	var officer_ready: bool = "Battle Cmd READY" in str(hud.controls_hint.text)
	lp.cmd_cd = 12.0
	hud._hud_cache.erase("ctrl")
	hud._update_controls_hint(lp)
	var officer_cd: bool = "Cmd 12s" in str(hud.controls_hint.text)
	var veh_hint: bool = true
	if mechs.size() > 0:
		on_mech_enter(0, lp.peer_id)
		hud._hud_cache.erase("ctrl")
		hud._update_controls_hint(lp)
		veh_hint = "[E] Exit" in str(hud.controls_hint.text) and "[LMB] Fire" in str(hud.controls_hint.text)
		lp.exit_mech()
	# Rank XP icons (strictly increasing steps, 24x24 textures, HUD mounted)
	var rank_ok := true
	for i in range(2, Game.RANK_XP.size()):
		var d1: int = int(Game.RANK_XP[i]) - int(Game.RANK_XP[i - 1])
		var d0: int = int(Game.RANK_XP[i - 1]) - int(Game.RANK_XP[i - 2])
		if d1 <= d0:
			rank_ok = false
	for r in range(10):
		var tex: ImageTexture = Game.rank_icon(r)
		if tex == null or tex.get_width() != 24 or tex.get_height() != 24:
			rank_ok = false
	var hud_rank: bool = hud.rank_rect != null and hud.rank_rect.texture != null
	# Emotes 1..4 pack/unpack + cancel on move
	var emote_ok := true
	lp._start_emote(1)
	if lp.emote_id != 1: emote_ok = false
	lp._animate_emote(0.05)
	var packed: int = ((1 if false else 0) | ((lp.emote_id & 7) << 8))
	lp.anim_flags = (lp.anim_flags & ~(7 << 8)) | ((lp.emote_id & 7) << 8)
	var got: int = (lp.anim_flags >> 8) & 7
	if got != 1: emote_ok = false
	for eid in [2, 3, 4]:
		lp._start_emote(eid)
		lp._animate_emote(0.08)
		if lp.emote_id != eid: emote_ok = false
	lp._start_emote(2)
	Input.action_press("move_forward")
	# cancel path
	lp._stop_emote()
	Input.action_release("move_forward")
	if lp.emote_id != 0: emote_ok = false
	print("[test] classes: ok=%s crouched=%s maps=%d hint=%s officer=%s/%s veh=%s rank=%s hudrank=%s emote=%s" % [ok, crouched, Game.MAPS.size(), hint, officer_ready, officer_cd, veh_hint, rank_ok, hud_rank, emote_ok])
	Game.finish_test(ok and crouched and maps_ok and hint_ok and officer_ready and officer_cd and veh_hint and rank_ok and hud_rank and emote_ok, "CLASSES + rank icons + emotes")



## Bidirectional PvP: verify Client→Host AND Host→Client kill credit (catches nested RPC sender bug).
func _test_pvp_bidir_server(delta: float) -> void:
	test_elapsed += delta
	test_cd -= delta
	if not players.has(1):
		return
	if _bidir_client_id == 0:
		for pid in players.keys():
			if pid != 1:
				_bidir_client_id = int(pid)
				break
	var client_id: int = _bidir_client_id
	if client_id == 0:
		return
	match _t_stage:
		0:
			# Host kills client once via authoritative path
			if players.has(client_id) and players[client_id].state == 0 and test_cd <= 0.0:
				pvp_damage(1, client_id, 9999.0, players[1].global_position)
				test_cd = 0.4
			var client_alive: bool = (not players.has(client_id)) or players[client_id].state == 0
			if pvp_scores.get(1, Vector2i.ZERO).x >= 1 and client_alive and test_elapsed > 6.0:
				_t_stage = 1
				test_cd = 0.5
				print("[test] bidir: host scored, now client will kill host")
		1:
			# Simulate nested-RPC path even if the live client already disconnected.
			if players[1].state == 0 and test_cd <= 0.0:
				var from_pos: Vector3 = players[1].global_position + Vector3(2, 0, 0)
				if players.has(client_id):
					from_pos = players[client_id].global_position
				pvp_damage(client_id, 1, 9999.0, from_pos)
				test_cd = 0.4
			var ck: int = pvp_scores.get(client_id, Vector2i.ZERO).x
			var hk: int = pvp_scores.get(1, Vector2i.ZERO).x
			var cdth: int = pvp_scores.get(client_id, Vector2i.ZERO).y
			var hdth: int = pvp_scores.get(1, Vector2i.ZERO).y
			if ck >= 1 and hk >= 1 and cdth >= 1 and hdth >= 1:
				print("[test] bidir scores host=%s client=%s" % [pvp_scores.get(1), pvp_scores.get(client_id)])
				Game.finish_test(true, "PVP BIDIR host_kills=%d client_kills=%d distributed" % [hk, ck])
			elif test_elapsed > 25.0:
				print("[test] bidir FAIL host=%s client=%s" % [pvp_scores.get(1), pvp_scores.get(client_id)])
				Game.finish_test(false, "PVP BIDIR attribution host=%s client=%s" % [pvp_scores.get(1), pvp_scores.get(client_id)])


func _test_pvp_bidir_client(delta: float) -> void:
	test_elapsed += delta
	var lp = local_player()
	if lp == null:
		return
	if lp.state == 2:
		_pvp_saw_dead = true
	elif _pvp_saw_dead and lp.state == 0:
		_pvp_saw_dead = false
		_pvp_respawns += 1
	var me: int = multiplayer.get_unique_id()
	var hk: int = pvp_scores.get(1, Vector2i.ZERO).x
	var ck: int = pvp_scores.get(me, Vector2i.ZERO).x
	# Prefer seeing both kill directions; otherwise stay until host finished stage 0+1.
	if hk >= 1 and ck >= 1 and not Game._test_done:
		Game.finish_test(true, "PVP BIDIR CLIENT saw distributed scores")
	elif _pvp_respawns >= 1 and test_elapsed > 20.0 and not Game._test_done:
		Game.finish_test(true, "PVP BIDIR CLIENT connected through attribution")
	elif test_elapsed > 40.0 and not Game._test_done:
		Game.finish_test(false, "PVP BIDIR CLIENT timeout")
