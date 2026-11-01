extends CharacterBody3D
## Separatist droid. AI runs only on the server; clients interpolate synced state.

const STATE_SIZE := 9  # id, type, x, y, z, rot_y, hp, shield, deployed
const TYPES := {
	0: {"name": "B1 Battle Droid", "hp": 60.0, "speed": 3.4, "range": 26.0, "dmg": 6.0, "rof": 1.3, "acc": 0.4, "credits": 10, "shield": 0.0},
	1: {"name": "B2 Super Droid", "hp": 240.0, "speed": 2.3, "range": 22.0, "dmg": 9.0, "rof": 0.55, "acc": 0.4, "credits": 25, "shield": 0.0},
	2: {"name": "Droideka", "hp": 130.0, "speed": 7.0, "range": 20.0, "dmg": 7.0, "rof": 0.35, "acc": 0.35, "credits": 40, "shield": 220.0},
}

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

var model: Node3D
var ball: MeshInstance3D
var shield_mesh: MeshInstance3D
var shield_mat: StandardMaterial3D
var muzzle: Node3D
var hp_label: Label3D


func get_enemy_id() -> int:
	return eid


func _ready() -> void:
	stats = TYPES[etype].duplicate()
	if Game.world != null:
		stats["hp"] = float(stats["hp"]) * float(Game.world.DIFF["hp"])
		stats["dmg"] = float(stats["dmg"]) * float(Game.world.DIFF["dmg"])
	hp = stats["hp"]
	max_shield = stats["shield"]
	shield = max_shield
	strafe_dir = 1.0 if (eid % 2) == 0 else -1.0
	collision_layer = 4
	collision_mask = 1 | 4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = [0.4, 0.6, 0.7][etype]
	cap.height = [1.9, 2.0, 1.6][etype]
	cs.shape = cap
	cs.position.y = cap.height / 2.0
	add_child(cs)
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


func _mat(c: Color, metal: float = 0.3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.5
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
		0:  # B1: skinny tan droid with long head
			var tan := Color(0.78, 0.68, 0.48)
			_box(Vector3(0.38, 0.5, 0.22), Vector3(0, 1.3, 0), tan)
			_box(Vector3(0.12, 0.6, 0.1), Vector3(0, 1.75, 0), tan)
			_box(Vector3(0.16, 0.14, 0.45), Vector3(0, 2.05, -0.12), tan)
			_box(Vector3(0.08, 0.9, 0.08), Vector3(-0.12, 0.5, 0), tan)
			_box(Vector3(0.08, 0.9, 0.08), Vector3(0.12, 0.5, 0), tan)
			_box(Vector3(0.07, 0.07, 0.6), Vector3(0.22, 1.3, -0.3), tan)
			_box(Vector3(0.06, 0.1, 0.55), Vector3(0.22, 1.3, -0.5), Color(0.15, 0.15, 0.15))
			muzzle.position = Vector3(0.22, 1.3, -0.8)
		1:  # B2: bulky gunmetal super droid
			var steel := Color(0.3, 0.33, 0.4)
			_box(Vector3(0.9, 0.8, 0.55), Vector3(0, 1.4, 0), steel)
			_box(Vector3(0.3, 0.2, 0.3), Vector3(0, 1.9, 0.05), steel)
			_box(Vector3(0.25, 1.0, 0.3), Vector3(-0.25, 0.5, 0), steel)
			_box(Vector3(0.25, 1.0, 0.3), Vector3(0.25, 0.5, 0), steel)
			_box(Vector3(0.25, 0.25, 0.8), Vector3(-0.6, 1.35, -0.25), steel)
			_box(Vector3(0.25, 0.25, 0.8), Vector3(0.6, 1.35, -0.25), steel)
			_box(Vector3(0.12, 0.12, 0.2), Vector3(0, 1.92, -0.12), Color(1, 0.3, 0.1))
			muzzle.position = Vector3(0.6, 1.35, -0.7)
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
	model.add_child(muzzle)
	if etype != 0:
		hp_label = Label3D.new()
		hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		hp_label.font_size = 40
		hp_label.outline_size = 8
		hp_label.pixel_size = 0.01
		hp_label.modulate = Color(1, 0.4, 0.3)
		hp_label.position.y = 2.5
		add_child(hp_label)


func muzzle_position() -> Vector3:
	return muzzle.global_position


## Server-side AI step.
func server_tick(delta: float, world) -> void:
	retarget -= delta
	if retarget <= 0.0 or target == null or not is_instance_valid(target) or target.state != 0:
		target = world.nearest_alive_player(global_position)
		retarget = 1.0
	if not is_on_floor():
		velocity.y -= 14.0 * delta
	else:
		velocity.y = 0.0
	if shield_cd > 0.0:
		shield_cd -= delta
	elif shield < max_shield:
		shield = minf(max_shield, shield + 45.0 * delta)
	if target == null:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var eye := global_position + Vector3(0, 1.5, 0)
	var los: bool = world.has_los(eye, target.global_position + Vector3(0, 1.2, 0))
	var want_move: bool = dist > stats["range"] * 0.7 or not los
	var speed: float = stats["speed"]
	if etype == 2:
		deployed = not want_move
	var dir := to.normalized() if dist > 0.01 else Vector3.ZERO
	if want_move:
		dir = _nav_dir(delta, target.global_position, dir)
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	elif etype == 0:
		# B1s shuffle sideways while shooting
		strafe_t -= delta
		if strafe_t <= 0.0:
			strafe_t = randf_range(1.0, 2.5)
			strafe_dir = -strafe_dir
		var side := dir.cross(Vector3.UP) * strafe_dir
		velocity.x = side.x * 1.5
		velocity.z = side.z * 1.5
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	if dist > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(1.0, delta * 6.0))
	move_and_slide()
	fire_cd -= delta
	if los and dist < stats["range"] and fire_cd <= 0.0 and (etype != 2 or deployed):
		fire_cd = stats["rof"] * randf_range(0.8, 1.3)
		world.enemy_fire(self, target, dist)
	_update_visual(delta)


func _nav_dir(delta: float, goal: Vector3, fallback: Vector3) -> Vector3:
	if agent == null:
		return fallback
	repath -= delta
	if repath <= 0.0:
		repath = 0.5
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
	if etype == 2 and shield > 0.0 and deployed and (explosive or shield_blocks(from)):
		shield = maxf(0.0, shield - dmg * (2.0 if explosive else 1.0))
		shield_cd = 4.0
		return false
	hp -= dmg
	return hp <= 0.0


func pack_state() -> PackedFloat32Array:
	return PackedFloat32Array([eid, etype, global_position.x, global_position.y, global_position.z,
		rotation.y, hp, shield, 1.0 if deployed else 0.0])


func apply_state(d: PackedFloat32Array, i: int) -> void:
	net_pos = Vector3(d[i + 2], d[i + 3], d[i + 4])
	net_rot = d[i + 5]
	hp = d[i + 6]
	shield = d[i + 7]
	deployed = d[i + 8] > 0.5


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		return
	position = position.lerp(net_pos, minf(1.0, delta * 10.0))
	rotation.y = lerp_angle(rotation.y, net_rot, minf(1.0, delta * 10.0))
	_update_visual(delta)


func _update_visual(_delta: float) -> void:
	if etype == 2:
		model.visible = deployed
		ball.visible = not deployed
		if not deployed:
			ball.rotation.x -= 0.3
		shield_mesh.visible = deployed and shield > 0.0
		shield_mat.albedo_color.a = 0.1 + 0.25 * (shield / max_shield)
	if hp_label != null:
		var t := "%d" % int(maxf(hp, 0.0))
		if etype == 2 and deployed:
			t += "  SH %d" % int(shield)
		hp_label.text = t
