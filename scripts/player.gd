extends CharacterBody3D
## Clone trooper. The owning peer simulates movement/shooting; other peers show
## an interpolated proxy from synced state.

const SPEED := 6.0
const SPRINT_SPEED := 10.0
const AIM_SPEED := 3.5
const JUMP_VELOCITY := 5.5
const GRAVITY := 14.0
const BLEED_TIME := 30.0
const REVIVE_TIME := 2.5
const RELOAD_TIME := 1.4
const SQUAD_COLORS := [Color(1.0, 0.55, 0.1), Color(0.2, 0.45, 1.0), Color(0.95, 0.85, 0.15), Color(0.85, 0.15, 0.15)]

var peer_id := 1
var color_index := 0
var display_name := "Trooper"
var is_local := false
var health := 100.0
var max_health := 100.0
var state := 0              # 0 alive, 1 downed, 2 dead
var god := false
var mag := 24
var mag_size := 24
var reloading := 0.0
var fire_cd := 0.0
var grenades := 0
var grenade_cd := 0.0
var bleed := BLEED_TIME
var since_hit := 10.0
var revive_progress := 0.0
var revive_target = null
var is_sprinting := false
var is_aiming := false
var pitch := 0.0
var net_pos := Vector3.ZERO
var net_rot := 0.0
var sync_cd := 0.0

var pivot: Node3D
var spring: SpringArm3D
var cam: Camera3D
var model: Node3D
var muzzle: Node3D
var name_label: Label3D


func _ready() -> void:
	is_local = peer_id == multiplayer.get_unique_id()
	collision_layer = 2
	collision_mask = 1 | 4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	_build_model()
	net_pos = position
	net_rot = rotation.y
	if is_local:
		max_health = Game.max_health()
		health = max_health
		mag_size = Game.mag_size()
		mag = mag_size
		grenades = int(Game.save["grenades"])
		pivot = Node3D.new()
		pivot.position = Vector3(0, 1.6, 0)
		add_child(pivot)
		spring = SpringArm3D.new()
		spring.spring_length = 3.2
		spring.margin = 0.3
		var probe := SphereShape3D.new()
		probe.radius = 0.35
		spring.shape = probe  # sphere sweep keeps the near plane out of walls
		spring.position = Vector3(0.75, 0.1, 0)
		spring.collision_mask = 1
		spring.add_excluded_object(get_rid())
		pivot.add_child(spring)
		cam = Camera3D.new()
		cam.fov = 75.0
		cam.far = 400.0
		cam.near = 0.05
		spring.add_child(cam)
		cam.current = true
	else:
		name_label = Label3D.new()
		name_label.text = display_name
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.no_depth_test = true
		name_label.font_size = 48
		name_label.outline_size = 10
		name_label.pixel_size = 0.01
		name_label.modulate = SQUAD_COLORS[color_index % 4]
		name_label.position = Vector3(0, 2.3, 0)
		add_child(name_label)


func _part(mesh: Mesh, pos: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.4
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _build_model() -> void:
	model = Node3D.new()
	add_child(model)
	var white := Color(0.92, 0.92, 0.9)
	var accent: Color = SQUAD_COLORS[color_index % 4]
	var dark := Color(0.12, 0.12, 0.14)
	var torso := CapsuleMesh.new()
	torso.radius = 0.3
	torso.height = 1.0
	_part(torso, Vector3(0, 1.15, 0), white, model)
	_part(_box(Vector3(0.62, 0.12, 0.42)), Vector3(0, 0.75, 0), dark, model)          # belt
	_part(_box(Vector3(0.22, 0.75, 0.24)), Vector3(-0.15, 0.37, 0), white, model)     # legs
	_part(_box(Vector3(0.22, 0.75, 0.24)), Vector3(0.15, 0.37, 0), white, model)
	_part(_box(Vector3(0.45, 0.5, 0.2)), Vector3(0, 1.2, 0.3), Color(0.8, 0.8, 0.78), model)  # backpack
	var head := SphereMesh.new()
	head.radius = 0.22
	head.height = 0.46
	_part(head, Vector3(0, 1.75, 0), white, model)
	_part(_box(Vector3(0.34, 0.07, 0.1)), Vector3(0, 1.78, -0.19), dark, model)        # visor T
	_part(_box(Vector3(0.08, 0.18, 0.1)), Vector3(0, 1.68, -0.19), dark, model)
	_part(_box(Vector3(0.06, 0.3, 0.46)), Vector3(0, 1.85, 0), accent, model)          # helmet stripe
	_part(_box(Vector3(0.18, 0.18, 0.5)), Vector3(-0.38, 1.25, 0), accent, model)      # shoulder pauldron
	_part(_box(Vector3(0.12, 0.6, 0.12)), Vector3(0.38, 1.15, -0.1), white, model)     # arm
	_part(_box(Vector3(0.1, 0.16, 0.75)), Vector3(0.28, 1.25, -0.45), dark, model)     # blaster
	muzzle = Node3D.new()
	muzzle.position = Vector3(0.28, 1.27, -0.85)
	model.add_child(muzzle)


# ------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if not is_local:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := Game.mouse_sensitivity * (0.5 if is_aiming else 1.0)
		rotation.y -= event.relative.x * sens
		pitch = clampf(pitch - event.relative.y * sens, -1.2, 1.0)
		pivot.rotation.x = pitch
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		var w = Game.world
		if w != null and w.hud != null and not w.hud.is_blocking():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _can_act() -> bool:
	if state != 0:
		return false
	if Game.world == null or Game.world.ended:
		return false
	if Game.is_headless():
		return true
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------ simulation
func _physics_process(delta: float) -> void:
	if not is_local:
		position = position.lerp(net_pos, minf(1.0, delta * 12.0))
		rotation.y = lerp_angle(rotation.y, net_rot, minf(1.0, delta * 12.0))
		_update_pose(delta)
		return

	fire_cd -= delta
	grenade_cd -= delta
	since_hit += delta
	var act := _can_act()

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var input := Vector2.ZERO
	if act:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	is_aiming = act and Input.is_action_pressed("aim")
	is_sprinting = act and Input.is_action_pressed("sprint") and input.y < -0.1 and not is_aiming and reloading <= 0.0
	var speed := SPRINT_SPEED if is_sprinting else (AIM_SPEED if is_aiming else SPEED)
	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	dir.y = 0
	dir = dir.normalized()
	var accel := 12.0 if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * speed * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * speed * delta)
	if act and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	move_and_slide()
	if position.y < -20.0:
		position = Game.world.LZ + Vector3(0, 2, 0)
		velocity = Vector3.ZERO

	# Camera zoom
	if cam != null:
		cam.fov = lerpf(cam.fov, 50.0 if is_aiming else (80.0 if is_sprinting else 72.0), minf(1.0, delta * 10.0))
		spring.spring_length = lerpf(spring.spring_length, 1.8 if is_aiming else 3.2, minf(1.0, delta * 10.0))

	# Weapon
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			mag = mag_size
	if act:
		if Input.is_action_pressed("fire") and fire_cd <= 0.0 and reloading <= 0.0 and not is_sprinting:
			if mag > 0:
				_shoot()
			else:
				_start_reload()
		if Input.is_action_just_pressed("reload") and mag < mag_size:
			_start_reload()
		if Input.is_action_just_pressed("grenade"):
			_throw_grenade()

	# Health
	if state == 0 and since_hit > 5.0 and health < max_health:
		health = minf(max_health, health + 10.0 * delta)
	if state == 1:
		bleed -= delta
		if bleed <= 0.0:
			state = 2
			Game.world.show_message("You bled out. Your squad must finish the mission!")

	_handle_revive(delta, act)
	_update_pose(delta)

	sync_cd -= delta
	if sync_cd <= 0.0:
		sync_cd = 0.05
		Game.net_all("player_state", [position, rotation.y, pitch, health, state], false)


func _handle_revive(delta: float, act: bool) -> void:
	revive_target = null
	if not act:
		revive_progress = 0.0
		return
	var best_d := 2.6
	for p in Game.world.players.values():
		if p == self or p.state != 1:
			continue
		var d: float = p.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			revive_target = p
	if revive_target != null and Input.is_action_pressed("interact"):
		revive_progress += delta
		if revive_progress >= REVIVE_TIME:
			revive_progress = 0.0
			Game.net_peer(revive_target.peer_id, "get_revived", [])
			Game.world.show_message("You revived %s!" % revive_target.display_name)
	else:
		revive_progress = 0.0


func _update_pose(delta: float) -> void:
	var target_rot := 0.0
	var target_y := 0.0
	if state != 0:
		target_rot = -PI / 2.0
		target_y = 0.3
	model.rotation.x = lerp_angle(model.rotation.x, target_rot, minf(1.0, delta * 6.0))
	model.position.y = lerpf(model.position.y, target_y, minf(1.0, delta * 6.0))
	model.visible = state != 2 or is_local
	if name_label != null:
		name_label.text = display_name + ("  [DOWNED - hold E]" if state == 1 else ("  [KIA]" if state == 2 else ""))


func _aim_point() -> Dictionary:
	var origin := cam.global_position if cam != null else global_position + Vector3(0, 1.6, 0)
	var fwd := -cam.global_transform.basis.z if cam != null else -global_transform.basis.z
	if not is_aiming:
		fwd = (fwd + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.012).normalized()
	var q := PhysicsRayQueryParameters3D.create(origin, origin + fwd * 250.0, 1 | 4, [get_rid()])
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		return {"pos": origin + fwd * 250.0, "collider": null}
	return {"pos": res["position"], "collider": res["collider"]}


func _shoot() -> void:
	fire_cd = Game.fire_interval()
	mag -= 1
	var aim := _aim_point()
	var from := muzzle.global_position
	var to: Vector3 = aim["pos"]
	Game.world.spawn_bolt(from, to, 0)
	Game.net_all("bolt_fx", [from, to, 0], false)
	var col = aim["collider"]
	if col != null and col.has_method("get_enemy_id"):
		Game.net_server("req_damage", [col.get_enemy_id(), Game.weapon_damage(), global_position])
		Game.world.hud.hit_marker(col.shield_blocks(global_position))
	if mag <= 0:
		_start_reload()


func _start_reload() -> void:
	if reloading > 0.0 or mag >= mag_size:
		return
	reloading = RELOAD_TIME
	Game.play_sfx("reload")


func _throw_grenade() -> void:
	if grenades <= 0 or grenade_cd > 0.0:
		if grenades <= 0:
			Game.world.show_message("No grenades! Buy more in the Armory.")
		return
	grenade_cd = 1.0
	grenades -= 1
	Game.save["grenades"] = grenades
	Game.write_save()
	var fwd := -cam.global_transform.basis.z if cam != null else -global_transform.basis.z
	var vel := fwd * 17.0 + Vector3(0, 4.0, 0)
	var pos := muzzle.global_position
	Game.world.spawn_grenade(pos, vel, true)
	Game.net_all("grenade_fx", [pos, vel], false)


func take_damage(dmg: float, from = null) -> void:
	if god or state != 0 or not is_local:
		return
	health -= dmg
	since_hit = 0.0
	Game.play_sfx("hurt", null, -6.0)
	if Game.world.hud != null:
		Game.world.hud.damage_flash()
		if from is Vector3:
			Game.world.hud.damage_from(from)
	if health <= 0.0:
		health = 0.0
		state = 1
		bleed = BLEED_TIME
		reloading = 0.0
		Game.play_sfx("down")
		Game.world.hud.add_feed("%s is DOWN!" % display_name, Color(1, 0.4, 0.3))
		Game.world.show_message("You're down! Hold on, a squadmate can revive you (E).")


func revive() -> void:
	if state != 1:
		return
	state = 0
	health = max_health * 0.4
	since_hit = 0.0


func net_update(pos: Vector3, ry: float, p: float, hp: float, st: int) -> void:
	net_pos = pos
	net_rot = ry
	pitch = p
	health = hp
	state = st
