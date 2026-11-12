extends CharacterBody3D
## Separatist droid. AI runs only on the server; clients interpolate synced state.

const STATE_SIZE := 9  # id, type, x, y, z, rot_y, hp, shield, deployed
const TYPES := {
	0: {"name": "B1 Battle Droid", "hp": 60.0, "speed": 3.4, "range": 26.0, "dmg": 6.0, "rof": 1.3, "acc": 0.4, "credits": 10, "shield": 0.0},
	1: {"name": "B2 Super Droid", "hp": 240.0, "speed": 2.3, "range": 22.0, "dmg": 9.0, "rof": 0.55, "acc": 0.4, "credits": 25, "shield": 0.0},
	3: {"name": "OOM Commander", "hp": 170.0, "speed": 2.8, "range": 30.0, "dmg": 7.0, "rof": 0.9, "acc": 0.45, "credits": 50, "shield": 0.0},
	2: {"name": "Droideka", "hp": 130.0, "speed": 7.0, "range": 20.0, "dmg": 7.0, "rof": 0.35, "acc": 0.35, "credits": 40, "shield": 220.0},
	4: {"name": "B2-HA Anti-Armor", "hp": 280.0, "speed": 2.6, "range": 42.0, "dmg": 75.0, "rof": 3.5, "acc": 0.85, "credits": 60, "shield": 0.0, "anti_armor": true},
	# Clone Commander difficulty only. Sprints, leaps, dodges aimed fire, flanks, vibroblade melee, brief cloak.
	5: {"name": "BX Commando Droid", "hp": 107.0, "speed": 12.0, "range": 34.0, "dmg": 13.0, "rof": 0.45, "acc": 0.9, "credits": 100, "shield": 40.0, "melee": 40.0},
}
const COMMANDO := 5
enum Act { NONE, ROLL, FLIP, LEAP, MELEE, SIDESTEP }
const COMMANDO_ANIMS := {"_raw_h": 4.62, "idle": "RobotArmature|Robot_Idle", "run": "RobotArmature|Robot_Running",
	"shoot": "RobotArmature|Robot_Idle", "death": "RobotArmature|Robot_Death", "jump": "RobotArmature|Robot_Jump",
	"punch": "RobotArmature|Robot_Punch"}
# Commando state (server drives it; act/cloak/side ride in the synced flags float).
var act := 0
var act_t := 0.0
var act_side := 1.0
var dodge_cd := 0.0
var melee_cd := 0.0
var leap_cd := 0.0
var wallhop_cd := 0.0
var cloak_t := 0.0
var cloak_used := false
var threat := 0.0
var melee_done := false
var dodges := 0
var _vis_act := 0
var _vis_t := 0.0

var eid := 0
var etype := 0
var stats: Dictionary = {}
var hp := 60.0
var shield := 0.0
var max_shield := 0.0
var shield_cd := 0.0
var fire_cd := 1.5
var deployed := false
var target = null
var retarget := 0.0
var strafe_dir := 1.0
var strafe_t := 0.0
var net_pos := Vector3.ZERO
var net_rot := 0.0
var agent: NavigationAgent3D
var repath := 0.0
var los_cd := 0.0
var los_cache := true
var _think_acc := 0.0
var react_t := -1.0          # reaction delay before first shot after acquiring LOS
var cover_t := 0.0           # droideka: time target stayed behind cover
var _grenade_fear := 0.0

var model: Node3D
var ball: MeshInstance3D
var shield_mesh: MeshInstance3D
var shield_mat: StandardMaterial3D
var muzzle: Node3D
var hp_label: Label3D
var char_model = null
var shot_t := 0.0
var buffed := false
var dead := false
var aura: MeshInstance3D
var _last_pos := Vector3.ZERO
var _speed := 0.0
const CharModel = preload("res://scripts/char_model.gd")
const ROBOT_ANIMS := {"_raw_h": 4.62, "idle": "RobotArmature|Robot_Idle", "run": "RobotArmature|Robot_Walking",
	"shoot": "RobotArmature|Robot_Idle", "death": "RobotArmature|Robot_Death"}
const MECH_ANIMS := {"_raw_h": 7.71, "idle": "CharacterArmature|Idle", "run": "CharacterArmature|Walk",
	"shoot": "CharacterArmature|Shoot", "death": "CharacterArmature|Death"}


func get_enemy_id() -> int:
	return eid


func _ready() -> void:
	stats = TYPES[etype].duplicate()
	if Game.world != null:
		stats["hp"] = float(stats["hp"]) * float(Game.world.DIFF["hp"])
		stats["dmg"] = float(stats["dmg"]) * float(Game.world.DIFF["dmg"])
		if stats.has("melee"):
			stats["melee"] = float(stats["melee"]) * float(Game.world.DIFF["dmg"])
	hp = stats["hp"]
	max_shield = stats["shield"]
	shield = max_shield
	strafe_dir = 1.0 if (eid % 2) == 0 else -1.0
	collision_layer = 4
	collision_mask = 1 | 4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	var _rad := [0.4, 0.6, 0.7, 0.4, 0.65, 0.36]
	var _hgt := [1.9, 2.2, 1.6, 2.0, 2.3, 1.95]
	cap.radius = _rad[clampi(etype, 0, 5)]
	cap.height = _hgt[clampi(etype, 0, 5)]
	cs.shape = cap
	cs.position.y = cap.height / 2.0
	add_child(cs)
	# The robot models have big round heads wider than the body capsule: give them their own hurt sphere.
	if etype != 2:
		var hs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		var _hr := [0.5, 0.62, 0, 0.52, 0.6, 0.42]
		var _hy := [1.54, 1.78, 0, 1.62, 1.85, 1.6]
		sp.radius = _hr[clampi(etype, 0, 5)]
		hs.shape = sp
		hs.position.y = _hy[clampi(etype, 0, 5)]
		add_child(hs)
	_build_model()
	if multiplayer.is_server():
		agent = NavigationAgent3D.new()
		agent.radius = cap.radius
		agent.height = cap.height
		agent.path_desired_distance = 1.0
		agent.target_desired_distance = 1.5
		add_child(agent)
	net_pos = position
	net_rot = rotation.y


static var _mats := {}


func _mat(c: Color, metal: float = 0.3) -> StandardMaterial3D:
	var key := "%s|%.2f" % [c.to_html(), metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.5
	_mats[key] = m
	return m


func _box(size: Vector3, pos: Vector3, c: Color, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(c)
	mi.position = pos
	(parent if parent != null else model).add_child(mi)
	return mi


func _build_model() -> void:
	model = Node3D.new()
	add_child(model)
	muzzle = Node3D.new()
	match etype:
		0:  # B1: tan battle droid
			char_model = CharModel.new()
			char_model.setup("res://models/robot.glb", 1.95, {"Main": Color(0.78, 0.68, 0.48), "Grey": Color(0.55, 0.48, 0.34)}, ROBOT_ANIMS)
			model.add_child(char_model)
			_box(Vector3(0.07, 0.1, 0.6), Vector3(0.3, 1.15, -0.35), Color(0.15, 0.15, 0.15))
			muzzle.position = Vector3(0.3, 1.15, -0.7)
		1:  # B2: bulky gunmetal super droid
			char_model = CharModel.new()
			# Upright bulked-up robot (the old mech asset was a low quadruped crawler): ~1.2x clone height, wide.
			char_model.setup("res://models/robot.glb", 2.25, {"Main": Color(0.3, 0.34, 0.42), "Grey": Color(0.22, 0.24, 0.3)}, ROBOT_ANIMS)
			char_model.scale *= Vector3(1.45, 1.0, 1.3)
			model.add_child(char_model)
			_box(Vector3(0.22, 0.22, 0.5), Vector3(-0.55, 1.25, -0.35), Color(0.15, 0.15, 0.18))
			_box(Vector3(0.22, 0.22, 0.5), Vector3(0.55, 1.25, -0.35), Color(0.15, 0.15, 0.18))
			muzzle.position = Vector3(0.55, 1.25, -0.65)
		3:  # OOM commander: yellow-marked droid that buffs nearby droids
			char_model = CharModel.new()
			char_model.setup("res://models/robot.glb", 2.05, {"Main": Color(0.92, 0.75, 0.2), "Grey": Color(0.85, 0.82, 0.75)}, ROBOT_ANIMS)
			model.add_child(char_model)
			_box(Vector3(0.07, 0.1, 0.5), Vector3(0.3, 1.2, -0.3), Color(0.15, 0.15, 0.15))
			muzzle.position = Vector3(0.3, 1.2, -0.6)
			aura = MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 12.0
			cm.bottom_radius = 12.0
			cm.height = 0.03
			cm.radial_segments = 32
			cm.rings = 1
			var am := StandardMaterial3D.new()
			am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			am.albedo_color = Color(1.0, 0.8, 0.2, 0.12)
			cm.material = am
			aura.mesh = cm
			aura.position.y = 0.06
			aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(aura)
		2:  # Droideka: rolls as a ball, deploys with a shield
			var bronze := Color(0.55, 0.4, 0.25)
			_box(Vector3(0.6, 0.5, 0.7), Vector3(0, 1.0, 0), bronze)
			_box(Vector3(0.35, 0.3, 0.45), Vector3(0, 1.35, -0.3), bronze)
			for i in 3:
				var a := i * TAU / 3.0
				_box(Vector3(0.08, 1.0, 0.08), Vector3(sin(a) * 0.45, 0.45, cos(a) * 0.45), bronze)
			_box(Vector3(0.1, 0.1, 0.7), Vector3(-0.35, 1.0, -0.4), Color(0.2, 0.2, 0.2))
			_box(Vector3(0.1, 0.1, 0.7), Vector3(0.35, 1.0, -0.4), Color(0.2, 0.2, 0.2))
			muzzle.position = Vector3(0.35, 1.0, -0.8)
			ball = MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.6
			sm.height = 1.2
			ball.mesh = sm
			ball.material_override = _mat(bronze, 0.6)
			ball.position.y = 0.6
			add_child(ball)
			shield_mesh = MeshInstance3D.new()
			var ss := SphereMesh.new()
			ss.radius = 1.35
			ss.height = 2.7
			shield_mesh.mesh = ss
			shield_mat = StandardMaterial3D.new()
			shield_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			shield_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			shield_mat.albedo_color = Color(0.3, 0.6, 1.0, 0.25)
			shield_mesh.material_override = shield_mat
			shield_mesh.position.y = 1.0
			add_child(shield_mesh)
		4:  # B2-HA Anti-Armor rocket droid
			char_model = CharModel.new()
			char_model.setup("res://models/robot.glb", 2.35, {"Main": Color(0.22, 0.18, 0.2), "Grey": Color(0.45, 0.1, 0.1)}, ROBOT_ANIMS)
			char_model.scale *= Vector3(1.5, 1.05, 1.35)
			model.add_child(char_model)
			_box(Vector3(0.28, 0.28, 0.85), Vector3(0.7, 1.55, -0.15), Color(0.55, 0.18, 0.08))  # rocket tube
			_box(Vector3(0.18, 0.18, 0.4), Vector3(0.7, 1.55, -0.7), Color(0.2, 0.2, 0.22))
			_box(Vector3(0.12, 0.12, 0.12), Vector3(0.0, 1.9, -0.35), Color(1.0, 0.15, 0.1))  # optic
			muzzle.position = Vector3(0.7, 1.55, -0.95)
		5:  # BX commando: slim dark-tan droid with orange markings, rifle + vibroblade (2 extra mats)
			char_model = CharModel.new()
			char_model.setup("res://models/robot.glb", 2.0, {"Main": Color(0.42, 0.36, 0.26), "Grey": Color(0.16, 0.15, 0.14)}, COMMANDO_ANIMS)
			char_model.scale *= Vector3(0.78, 1.0, 0.8)
			model.add_child(char_model)
			var orange := Color(0.95, 0.45, 0.1)
			var dark := Color(0.1, 0.1, 0.11)
			_box(Vector3(0.5, 0.06, 0.08), Vector3(0, 1.72, -0.36), orange)    # visor stripe
			_box(Vector3(0.12, 0.06, 0.3), Vector3(-0.33, 1.38, 0.0), orange)  # shoulder flashes
			_box(Vector3(0.12, 0.06, 0.3), Vector3(0.33, 1.38, 0.0), orange)
			_box(Vector3(0.08, 0.36, 0.06), Vector3(0, 1.1, -0.2), orange)     # chest mark
			_box(Vector3(0.06, 0.09, 0.62), Vector3(0.26, 1.12, -0.38), dark)   # E-5 rifle
			_box(Vector3(0.03, 0.05, 0.55), Vector3(-0.28, 0.95, -0.4), dark)   # vibroblade
			muzzle.position = Vector3(0.26, 1.12, -0.72)
	model.add_child(muzzle)
	load("res://scripts/mech.gd").merge_meshes(model)
	if etype == 4:
		hp_label = Label3D.new()
		hp_label.text = "ANTI-ARMOR"
		hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		hp_label.font_size = 42
		hp_label.outline_size = 10
		hp_label.pixel_size = 0.01
		hp_label.modulate = Color(1.0, 0.35, 0.15)
		hp_label.position.y = 2.7
		add_child(hp_label)
	elif etype != 0:
		hp_label = Label3D.new()
		if etype == 3:
			hp_label.modulate = Color(1, 0.85, 0.3)
		hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		hp_label.font_size = 40
		hp_label.outline_size = 8
		hp_label.pixel_size = 0.01
		hp_label.modulate = Color(1, 0.4, 0.3)
		hp_label.position.y = 2.5
		add_child(hp_label)


func muzzle_position() -> Vector3:
	return muzzle.global_position


## Server-side AI step (difficulty-scaled brains + anti-armor hunter).
func server_tick(delta: float, world) -> void:
	if etype == COMMANDO:
		_commando_tick(delta, world)
		return
	var ai: int = int(world.DIFF.get("ai", 1))
	retarget -= delta
	if etype == 4:
		# Strictly hunt piloted vehicles; else advance on highest vehicle-time player
		var pil = world.nearest_piloted_player(global_position)
		if pil != null:
			target = pil
		elif retarget <= 0.0 or target == null or not is_instance_valid(target) or target.state != 0:
			target = world.highest_vehicle_time_player()
			retarget = 0.8
	elif retarget <= 0.0 or target == null or not is_instance_valid(target) or target.state != 0:
		target = world.nearest_alive_player(global_position)
		retarget = 1.0
		buffed = etype != 3 and world.commander_near(global_position)
		react_t = -1.0
	if not is_on_floor():
		velocity.y -= 14.0 * delta
	else:
		velocity.y = 0.0
	if shield_cd > 0.0:
		shield_cd -= delta
	elif shield < max_shield:
		shield = minf(max_shield, shield + 45.0 * delta)
	# Dodge live grenades on Clone Commander
	if ai >= 3 and world != null:
		var gpos = world.nearest_live_grenade(global_position, 8.0)
		if gpos != null:
			var away: Vector3 = global_position - gpos
			away.y = 0.0
			if away.length() > 0.1:
				away = away.normalized()
				velocity.x = away.x * stats["speed"] * 1.4
				velocity.z = away.z * stats["speed"] * 1.4
				move_and_slide()
				_update_visual(delta)
				return
	if target == null:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var aim_h: Vector3 = target.aim_target_pos() if target.has_method("aim_target_pos") else target.global_position + Vector3(0, 1.2, 0)
	var eye := global_position + Vector3(0, 1.5, 0)
	los_cd -= delta
	if los_cd <= 0.0:
		los_cd = 0.2 + (eid % 5) * 0.01
		los_cache = world.has_los(eye, aim_h)
	var los: bool = los_cache
	if etype == 2:
		if not los:
			cover_t += delta
		else:
			cover_t = 0.0
	# OOM keeps standoff on Veteran+
	var range_mul := 0.7
	if etype == 3:
		range_mul = 0.85
		if ai >= 2:
			range_mul = 0.55  # prefer 18-26m
	var want_move: bool = dist > stats["range"] * range_mul or not los
	if etype == 3 and ai >= 2 and dist < 18.0:
		want_move = true  # back off
	if etype == 4:
		# Hold fire / approach until someone is piloting
		want_move = target == null or not target.piloting() or dist > stats["range"] * 0.75 or not los
	var speed: float = stats["speed"]
	if etype == 2:
		deployed = not want_move
		if ai >= 3 and cover_t > 3.0 and deployed:
			deployed = false
			want_move = true
			cover_t = 0.0
	var dir: Vector3 = to.normalized() if dist > 0.01 else Vector3.ZERO
	# Flanking offset on Clone Commander
	if ai >= 3 and want_move and dist > 12.0 and dist < 42.0 and etype != 4:
		var ang: float = 0.56 if (eid % 2) == 0 else -0.56  # ±32°
		dir = dir.rotated(Vector3.UP, ang)
	if want_move:
		var goal: Vector3 = target.global_position
		if etype == 3 and ai >= 2 and dist < 26.0:
			goal = global_position - dir * 8.0  # retreat
		dir = _nav_dir(delta, goal, dir)
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		if etype == 1 and ai >= 2 and los:
			# B2s advance while firing
			pass
	elif ai == 0:
		# Cadet: stand still to shoot
		velocity.x = 0.0
		velocity.z = 0.0
	elif ai == 1 or etype == 0:
		strafe_t -= delta
		if strafe_t <= 0.0:
			strafe_t = randf_range(1.0, 2.5)
			strafe_dir = -strafe_dir
		var side := dir.cross(Vector3.UP) * strafe_dir
		velocity.x = side.x * (1.5 if ai < 2 else 2.4)
		velocity.z = side.z * (1.5 if ai < 2 else 2.4)
	elif ai >= 2:
		# Veteran+ juke strafe
		strafe_t -= delta
		if strafe_t <= 0.0:
			strafe_t = randf_range(0.45, 1.1)
			strafe_dir = -strafe_dir
		var juke: Vector3 = dir.cross(Vector3.UP) * strafe_dir + dir * (0.3 if etype == 1 else 0.0)
		velocity.x = juke.x * 2.8
		velocity.z = juke.z * 2.8
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	if dist > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(1.0, delta * 6.0))
	move_and_slide()
	fire_cd -= delta
	# Reaction window after first LOS
	if los and react_t < 0.0:
		react_t = float(world.DIFF.get("react", 0.3))
	if react_t > 0.0:
		react_t -= delta
	var can_shoot: bool = los and dist < stats["range"] and fire_cd <= 0.0 and (etype != 2 or deployed) and react_t <= 0.0
	if etype == 4:
		can_shoot = can_shoot and target.piloting()
	if can_shoot:
		fire_cd = stats["rof"] * randf_range(0.8, 1.3) * (0.7 if buffed else 1.0)
		if etype == 4:
			world.enemy_anti_armor_fire(self, target, dist)
		else:
			world.enemy_fire(self, target, dist)
	_update_visual(delta)


func _nav_dir(delta: float, goal: Vector3, fallback: Vector3) -> Vector3:
	if agent == null:
		return fallback
	repath -= delta
	if repath <= 0.0:
		repath = 0.5 + (eid % 7) * 0.05   # staggered so repaths don't all land on one frame
		agent.target_position = goal
	if agent.is_navigation_finished():
		return fallback
	var nxt := agent.get_next_path_position() - global_position
	nxt.y = 0.0
	if nxt.length() < 0.05:
		return fallback
	return nxt.normalized()


## Returns true if the hit came from the shielded front of a deployed droideka.
func shield_blocks(from: Vector3) -> bool:
	if etype != 2 or shield <= 0.0 or not deployed:
		return false
	var to_shooter := from - global_position
	to_shooter.y = 0.0
	var fwd := -global_transform.basis.z
	return fwd.dot(to_shooter.normalized()) > -0.25


## Server: apply damage. Returns true if destroyed.
func apply_damage(dmg: float, from: Vector3, explosive: bool) -> bool:
	if etype == COMMANDO:
		if act in [Act.ROLL, Act.FLIP, Act.SIDESTEP] and not explosive:
			dmg *= 0.5   # mid-dodge: bolts graze for half
		shield_cd = 3.0
		var soak := minf(shield, dmg)
		shield -= soak
		hp -= dmg - soak
		threat = maxf(threat, 0.6)   # getting hit makes it want to move
		if hp < float(stats["hp"]) * 0.45 and not cloak_used and hp > 0.0:
			cloak_used = true
			cloak_t = 3.0
		return hp <= 0.0
	if etype == 2 and shield > 0.0 and deployed and (explosive or shield_blocks(from)):
		shield = maxf(0.0, shield - dmg * (2.0 if explosive else 1.0))
		shield_cd = 4.0
		return false
	hp -= dmg
	return hp <= 0.0


func pack_state() -> PackedFloat32Array:
	var flags := 1.0 if deployed else 0.0
	if etype == COMMANDO:
		flags = float(pack_flags())
	return PackedFloat32Array([eid, etype, global_position.x, global_position.y, global_position.z,
		rotation.y, hp, shield, flags])


## Commando: act (0-7) | cloaked << 3 | right-side << 4, carried in the existing flags float.
func pack_flags() -> int:
	return act | (8 if cloak_t > 0.0 else 0) | (16 if act_side > 0.0 else 0)


func unpack_flags(f: int) -> void:
	act = f & 7
	cloak_t = 1.0 if (f & 8) != 0 else 0.0
	act_side = 1.0 if (f & 16) != 0 else -1.0


func apply_state(d: PackedFloat32Array, i: int) -> void:
	net_pos = Vector3(d[i + 2], d[i + 3], d[i + 4])
	net_rot = d[i + 5]
	hp = d[i + 6]
	shield = d[i + 7]
	if etype == COMMANDO:
		unpack_flags(int(d[i + 8]))
	else:
		deployed = d[i + 8] > 0.5


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		return
	position = position.lerp(net_pos, minf(1.0, delta * 8.0))
	rotation.y = lerp_angle(rotation.y, net_rot, minf(1.0, delta * 10.0))
	_update_visual(delta)


func _update_visual(_delta: float) -> void:
	if etype == COMMANDO:
		_commando_visual(_delta)
		return
	if char_model != null and not dead:
		var flat := global_position - _last_pos
		flat.y = 0.0
		_last_pos = global_position
		if _delta > 0.0:
			_speed = lerpf(_speed, flat.length() / _delta, minf(1.0, _delta * 8.0))
		shot_t -= _delta
		if _speed > 0.5:
			char_model.play("run", clampf(_speed / float(stats["speed"]), 0.6, 1.6))
		else:
			char_model.play("shoot" if shot_t > 0.0 else "idle")
	if etype == 2:
		model.visible = deployed
		ball.visible = not deployed
		if not deployed:
			ball.rotation.x -= 0.3
		shield_mesh.visible = deployed and shield > 0.0
		shield_mat.albedo_color.a = 0.1 + 0.25 * (shield / max_shield)
	if hp_label != null:
		if etype == 4:
			hp_label.text = "ANTI-ARMOR  %d" % int(maxf(hp, 0.0))
		else:
			var t := "%d" % int(maxf(hp, 0.0))
			if etype == 2 and deployed:
				t += "  SH %d" % int(shield)
			hp_label.text = t


## Play the death animation, drop collision, then free (used instead of an instant despawn).
func die() -> void:
	if dead:
		return
	dead = true
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	if hp_label != null:
		hp_label.visible = false
	if aura != null:
		aura.visible = false
	if char_model == null:
		queue_free()
		return
	char_model.play("death")
	get_tree().create_timer(2.2).timeout.connect(queue_free)


# ------------------------------------------------------------------ BX commando (server AI)
## Is the target looking down its sights at us? (narrow cone from the player's eye)
func _aimed_at_by(p) -> bool:
	if p == null or not ("pitch" in p):
		return false
	var eye: Vector3 = p.global_position + Vector3(0, 1.6, 0)
	var to: Vector3 = global_position + Vector3(0, 1.1, 0) - eye
	var d := to.length()
	if d > 70.0 or d < 1.0:
		return false
	var ry: float = p.rotation.y
	var pt: float = p.pitch
	var fwd := Vector3(-sin(ry) * cos(pt), sin(pt), -cos(ry) * cos(pt))
	# ~1.4 m wide cone at any range
	return fwd.dot(to / d) > cos(atan2(1.4, d))


## Server: a player bolt flew past (near-miss) -> commando reacts next tick.
func near_miss(from: Vector3, to: Vector3) -> void:
	var c := global_position + Vector3(0, 1.0, 0)
	var seg := to - from
	var L := seg.length()
	if L < 0.1:
		return
	var t := clampf((c - from).dot(seg) / (L * L), 0.0, 1.0)
	if (from + seg * t).distance_to(c) < 2.5 and from.distance_to(c) > 3.0:
		threat = 2.0


func _start_act(a: int, t: float, vel: Vector3) -> void:
	act = a
	act_t = t
	velocity = vel
	melee_done = false


## Dodge: roll / flip / sidestep sideways relative to the shooter, jump-dodge over fire if airborne room.
func _dodge(dir: Vector3, world) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	# Pick the side with room (raycast 4 m), else random
	act_side = 1.0 if randf() < 0.5 else -1.0
	if world != null and not world.has_los(global_position + Vector3(0, 1, 0), global_position + Vector3(0, 1, 0) + side * act_side * 4.0):
		act_side = -act_side
	var r := randf()
	dodges += 1
	if r < 0.45:
		_start_act(Act.ROLL, 0.45, side * act_side * 10.0)
	elif r < 0.75:
		_start_act(Act.FLIP, 0.6, side * act_side * 7.5 + Vector3(0, 6.5, 0) - dir * 2.0)
	else:
		_start_act(Act.SIDESTEP, 0.28, side * act_side * 12.0)
	dodge_cd = randf_range(1.1, 1.8)   # fair: a window to land shots between dodges
	threat = 0.0


func _commando_tick(delta: float, world) -> void:
	for k in ["dodge_cd", "melee_cd", "leap_cd", "wallhop_cd", "cloak_t"]:
		set(k, maxf(0.0, float(get(k)) - delta))
	if shield_cd > 0.0:
		shield_cd -= delta
	elif shield < max_shield:
		shield = minf(max_shield, shield + 30.0 * delta)
	var floor_ok := is_on_floor()
	if not floor_ok:
		velocity.y -= 18.0 * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	retarget -= delta
	if retarget <= 0.0 or target == null or not is_instance_valid(target) or target.state != 0:
		target = world.nearest_alive_player(global_position)
		retarget = 0.6
	# Mid-action: keep the committed motion (telegraphed, can't steer)
	if act != Act.NONE:
		act_t -= delta
		if act == Act.MELEE and not melee_done and act_t < 0.22 and target != null and is_instance_valid(target):
			melee_done = true
			if target.global_position.distance_to(global_position) < 3.0:
				world.commando_melee(self, target)
		if act_t <= 0.0 and (floor_ok or act_t < -1.0):
			act = Act.NONE
		move_and_slide()
		_update_visual(delta)
		return
	if target == null:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_update_visual(delta)
		return
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var dir: Vector3 = to / dist if dist > 0.01 else Vector3.FORWARD
	var aim_h: Vector3 = target.aim_target_pos() if target.has_method("aim_target_pos") else target.global_position + Vector3(0, 1.2, 0)
	los_cd -= delta
	if los_cd <= 0.0:
		los_cd = 0.15
		los_cache = world.has_los(global_position + Vector3(0, 1.5, 0), aim_h)
	var los: bool = los_cache
	# Threat: being aimed at builds up (≈0.2 s reaction), near misses/hits spike it.
	if los and _aimed_at_by(target):
		threat += delta * 5.0
	else:
		threat = maxf(0.0, threat - delta * 2.0)
	if threat >= 1.0 and dodge_cd <= 0.0 and floor_ok:
		_dodge(dir, world)
		move_and_slide()
		_update_visual(delta)
		return
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(1.0, delta * 10.0))
	# Vibroblade: close in and strike (0.25 s wind-up telegraph)
	if dist < 2.6 and melee_cd <= 0.0 and floor_ok:
		melee_cd = 1.2
		_start_act(Act.MELEE, 0.5, dir * 2.0)
		move_and_slide()
		_update_visual(delta)
		return
	# Sprint-leap: pounce over cover onto the target
	if dist > 6.0 and dist < 15.0 and leap_cd <= 0.0 and floor_ok and (los or dist < 9.0):
		leap_cd = randf_range(5.0, 7.0)
		var hv := clampf(dist - 1.5, 4.0, 13.0) / 0.9
		_start_act(Act.LEAP, 0.9, dir * hv + Vector3(0, 8.0, 0))
		move_and_slide()
		_update_visual(delta)
		return
	# Movement: squad flanking. Commandos fan out to alternating sides of the target.
	var want: Vector3
	var speed: float = stats["speed"]
	if dist > 13.0 or not los:
		var slot: float = 1.0 if (eid % 2) == 0 else -1.0
		var flank: Vector3 = target.global_position + dir.cross(Vector3.UP) * slot * minf(10.0, dist * 0.45)
		want = _nav_dir(delta, flank, dir)
	else:
		# Close: unpredictable strafe-advance
		strafe_t -= delta
		if strafe_t <= 0.0:
			strafe_t = randf_range(0.3, 0.9)
			strafe_dir = -strafe_dir if randf() < 0.7 else strafe_dir
		want = (dir.cross(Vector3.UP) * strafe_dir + dir * 0.6).normalized()
		speed = 5.5
	velocity.x = want.x * speed
	velocity.z = want.z * speed
	move_and_slide()
	# Wall-hop: blocked while running -> vault it
	if is_on_wall() and floor_ok and wallhop_cd <= 0.0:
		wallhop_cd = 1.0
		velocity.y = 8.0
	fire_cd -= delta
	if react_t < 0.0 and los:
		react_t = float(world.DIFF.get("react", 0.3))
	if react_t > 0.0:
		react_t -= delta
	if los and dist < stats["range"] and fire_cd <= 0.0 and react_t <= 0.0 and cloak_t <= 0.0:
		fire_cd = stats["rof"] * randf_range(0.8, 1.2)
		world.enemy_fire(self, target, dist)
	_update_visual(delta)


func _commando_visual(delta: float) -> void:
	if dead or char_model == null:
		return
	if act != _vis_act:
		_vis_act = act
		_vis_t = 0.0
	_vis_t += delta
	var flat := global_position - _last_pos
	flat.y = 0.0
	_last_pos = global_position
	if delta > 0.0:
		_speed = lerpf(_speed, flat.length() / delta, minf(1.0, delta * 8.0))
	shot_t -= delta
	var b := Basis()
	match act:
		Act.ROLL:
			b = Basis(Vector3.FORWARD, -act_side * TAU * clampf(_vis_t / 0.45, 0.0, 1.0))
			char_model.play("run", 1.6)
		Act.FLIP:
			b = Basis(Vector3.FORWARD, -act_side * TAU * clampf(_vis_t / 0.6, 0.0, 1.0))
			char_model.play("jump", 1.4)
		Act.LEAP:
			b = Basis(Vector3.RIGHT, -TAU * clampf(_vis_t / 0.8, 0.0, 1.0))  # front flip pounce
			char_model.play("jump", 1.2)
		Act.MELEE:
			char_model.play("punch", 1.8)
		Act.SIDESTEP:
			char_model.play("run", 1.8)
		_:
			if _speed > 0.5:
				char_model.play("run", clampf(_speed / 6.0, 0.8, 1.6))
			else:
				char_model.play("shoot" if shot_t > 0.0 else "idle")
	var c := Vector3(0, 1.0, 0)
	model.transform = Transform3D(b, c - b * c)
	# Cloak: flickering shimmer (telegraph), name tag hidden
	if cloak_t > 0.0:
		model.visible = (Engine.get_frames_drawn() % 10) < 2
	else:
		model.visible = true
	if hp_label != null:
		hp_label.visible = cloak_t <= 0.0
		hp_label.text = "BX  %d  SH %d" % [int(maxf(hp, 0.0)), int(shield)]
