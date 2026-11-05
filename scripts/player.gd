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
var team := 0
var respawn_t := 0.0
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
var aim_toggled := false
var crosshair_on_enemy := false
var assist_target = null
var pitch := 0.0
var net_pos := Vector3.ZERO
var net_rot := 0.0
var sync_cd := 0.0

var pivot: Node3D
var spring: SpringArm3D
var cam: Camera3D
var model: Node3D
var char_model = null
const CharModel = preload("res://scripts/char_model.gd")
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
		spring.collision_mask = 8   # big solids only (see map_builder.box)
		spring.add_excluded_object(get_rid())
		pivot.add_child(spring)
		cam = Camera3D.new()
		cam.fov = 75.0
		cam.far = 400.0
		cam.near = 0.05
		pivot.add_child(cam)   # placed by _place_camera() from the spring's hit length
		cam.current = true
		set_first_person.call_deferred(bool(Game.save.get("fp", false)))
	else:
		name_label = Label3D.new()
		name_label.text = display_name
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.no_depth_test = true
		name_label.font_size = 48
		name_label.outline_size = 10
		name_label.pixel_size = 0.01
		name_label.modulate = SQUAD_COLORS[color_index % 4]
		if Game.world != null and Game.world.versus and not Game.world.ffa:
			name_label.modulate = Color(1, 0.35, 0.3) if team == 0 else Color(0.45, 0.65, 1.0)
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


const WEAPON_MESHES := ["Sniper", "SMG", "RocketLauncher", "Revolver", "Revolver_Small", "Pistol", "GrenadeLauncher", "ShortCannon", "Shotgun", "Sniper_2", "Shovel", "Knife_2", "Knife_1", "AK"]
const WEAPON_SHOW := [["AK"], ["Shotgun"]]
const SOLDIER_ANIMS := {"_raw_h": 2.26, "idle": "CharacterArmature|Idle", "aim": "CharacterArmature|Idle_Shoot",
	"run": "CharacterArmature|Run", "run_shoot": "CharacterArmature|Run_Gun", "jump": "CharacterArmature|Jump_Idle",
	"death": "CharacterArmature|Death", "hit": "CharacterArmature|HitReact"}

const WEAPON_NAMES := ["DC-15A RIFLE", "DP-23 SCATTER"]
const SHOTGUN_MAG := 6
const SHOTGUN_PELLETS := 8
const SHOTGUN_RANGE := 30.0
var weapon := 0
var stored_mag := [0, SHOTGUN_MAG]
var anim_flags := 0          # bit0 firing, bit1 aiming, bit2 sprint, bit3 airborne, bit4 weapon slot
var shot_t := 0.0
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _shown_weapon := -1


func _build_model() -> void:
	model = Node3D.new()
	add_child(model)
	var armor := Color(0.92, 0.92, 0.9)
	var accent: Color = SQUAD_COLORS[color_index % 4]
	if Game.world != null and Game.world.versus and not Game.world.ffa:
		accent = Color(0.9, 0.15, 0.12) if team == 0 else Color(0.15, 0.4, 1.0)
		armor = Color(1.0, 0.78, 0.75) if team == 0 else Color(0.78, 0.85, 1.0)
	var body = CharModel.new()
	body.name = "Body"
	body.setup("res://models/soldier.glb", 1.85, {
		"Character_Main": armor, "Pants": armor.darkened(0.08), "Skin": Color(0.12, 0.12, 0.14),
		"Grey": accent, "Red": accent, "Wood": Color(0.15, 0.15, 0.17), "DarkWood": Color(0.1, 0.1, 0.12)},
		SOLDIER_ANIMS, WEAPON_MESHES, WEAPON_SHOW[0])
	model.add_child(body)
	char_model = body
	_shown_weapon = 0
	muzzle = Node3D.new()
	muzzle.position = Vector3(0.28, 1.27, -0.85)
	model.add_child(muzzle)


func _update_anim(delta: float) -> void:
	if char_model == null:
		return
	var flat := global_position - _last_pos
	flat.y = 0.0
	_last_pos = global_position
	if delta > 0.0:
		_speed = lerpf(_speed, flat.length() / delta, minf(1.0, delta * 10.0))
	shot_t -= delta
	var w := (anim_flags >> 4) & 1
	if w != _shown_weapon:
		_shown_weapon = w
		char_model.set_visible_meshes(WEAPON_MESHES, WEAPON_SHOW[w])
	if state != 0:
		char_model.play("death")
		return
	var firing := (anim_flags & 1) != 0 or shot_t > 0.0
	var aiming := (anim_flags & 2) != 0
	if (anim_flags & 8) != 0:
		char_model.play("jump")
	elif _speed > 0.6:
		char_model.play("run_shoot" if firing else "run", clampf(_speed / SPEED, 0.6, 1.5))
	elif firing:
		char_model.play("aim")
	elif aiming:
		# Idle_Shoot is a looping fire cycle (with recoil); for ADS without firing hold its first frame
		char_model.play("aim", 0.0)
	else:
		char_model.play("idle")


# ------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if not is_local:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := Game.mouse_sensitivity * (0.5 if is_aiming else 1.0)
		rotation.y -= event.relative.x * sens
		pitch = clampf(pitch - event.relative.y * sens, -1.2, 1.0)
		pivot.rotation.x = pitch
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		switch_weapon(1 - weapon)
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
	if Game.world.hud != null and Game.world.hud.is_blocking():
		return false
	if Game.control_mode == 1:
		return true  # keyboard/trackpad mode works without a captured mouse
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
	if act and Input.is_action_just_pressed("kb_aim"):
		aim_toggled = not aim_toggled
	if not act:
		aim_toggled = false
	is_aiming = act and (Input.is_action_pressed("aim") or aim_toggled)
	if act and Game.control_mode == 1:
		_keyboard_look(delta)
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

	_place_camera()
	# Camera zoom
	if cam != null:
		cam.fov = lerpf(cam.fov, 50.0 if is_aiming else (80.0 if is_sprinting else 72.0), minf(1.0, delta * 10.0))
		spring.spring_length = lerpf(spring.spring_length, 1.8 if is_aiming else 3.2, minf(1.0, delta * 10.0))

	# Weapon
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			mag = mag_size
	crosshair_on_enemy = _crosshair_enemy() != null
	var want_fire := Input.is_action_pressed("fire") or Input.is_action_pressed("kb_fire")
	if Game.control_mode == 1 and Game.auto_fire and crosshair_on_enemy:
		want_fire = true
	if act:
		if want_fire and fire_cd <= 0.0 and reloading <= 0.0 and not is_sprinting:
			if mag > 0:
				_shoot()
			else:
				_start_reload()
		if Input.is_action_just_pressed("reload") and mag < mag_size:
			_start_reload()
		if Input.is_action_just_pressed("grenade"):
			_throw_grenade()
		if Input.is_action_just_pressed("view_toggle"):
			set_first_person(not first_person)
			Game.write_save()
		if Input.is_action_just_pressed("weapon1"):
			switch_weapon(0)
		elif Input.is_action_just_pressed("weapon2"):
			switch_weapon(1)
		elif Input.is_action_just_pressed("weapon_next"):
			switch_weapon(1 - weapon)

	# Health
	if state == 0 and since_hit > 5.0 and health < max_health:
		health = minf(max_health, health + 10.0 * delta)
	if state == 1:
		bleed -= delta
		if bleed <= 0.0:
			state = 2
			Game.world.show_message("You bled out. Your squad must finish the mission!")

	if Game.world.versus and state == 2 and not Game.world.ended:
		respawn_t -= delta
		if respawn_t <= 0.0:
			respawn()
	_handle_revive(delta, act)
	_update_pose(delta)

	sync_cd -= delta
	if sync_cd <= 0.0:
		sync_cd = 0.066  # 15 Hz player state (was 20 Hz)
		anim_flags = (1 if shot_t > 0.0 else 0) | (2 if is_aiming else 0) | (4 if is_sprinting else 0) | (8 if not is_on_floor() else 0) | (weapon << 4)
		Game.net_all("player_state", [position, rotation.y, pitch, health, state | (anim_flags << 2)], false)


## Keyboard / trackpad camera: arrows or J/L turn, I/K look, plus light aim assist.
## Third-person camera: follow the SpringArm's collision distance, but never closer than
## MIN_CAM_DIST. Before this, a wall/pole right behind the trooper collapsed the camera to
## ~0 m, i.e. inside the helmet, so the player only saw the crosshair and no trooper.
const MIN_CAM_DIST := 1.25


var first_person := false


## V toggles first person: camera at the eyes, own body hidden from this camera (render layer 2)
## while it still casts a shadow and stays visible to everyone else.
func set_first_person(on: bool) -> void:
	first_person = on
	Game.save["fp"] = on
	if char_model != null:
		for mi in char_model.meshes:
			mi.layers = 2
	if cam != null:
		cam.cull_mask = (0xFFFFF & ~2) if on else 0xFFFFF
		_place_camera()


func _place_camera() -> void:
	if cam == null:
		return
	if first_person:
		cam.position = Vector3(0.0, 0.05, -0.3)
		return
	var d := clampf(spring.get_hit_length(), MIN_CAM_DIST, maxf(spring.spring_length, MIN_CAM_DIST))
	cam.position = spring.position + Vector3(0, 0, d)


func _process(_delta: float) -> void:
	if is_local:
		_place_camera()


func _keyboard_look(delta: float) -> void:
	var turn := Input.get_axis("turn_left", "turn_right")
	var look := Input.get_axis("look_down", "look_up")
	var spd := Game.turn_speed * (0.5 if is_aiming else 1.0)
	rotation.y -= turn * spd * delta
	pitch = clampf(pitch + look * spd * 0.6 * delta, -1.2, 1.0)
	if Game.aim_assist and cam != null:
		assist_target = _assist_target()
		if assist_target != null:
			var aim_at: Vector3 = assist_target.global_position + Vector3(0, 1.2, 0)
			var d := aim_at - cam.global_position
			var want_yaw := atan2(-d.x, -d.z)
			var want_pitch := atan2(d.y, Vector2(d.x, d.z).length())
			var k := minf(1.0, delta * (7.0 if is_aiming else 4.0))
			rotation.y = lerp_angle(rotation.y, want_yaw, k)
			pitch = clampf(lerpf(pitch, want_pitch, k), -1.2, 1.0)
	pivot.rotation.x = pitch


## Nearest visible droid within ~10 degrees of the crosshair and 70 m.
func _assist_target():
	var best = null
	var best_ang := deg_to_rad(10.0)
	var fwd := -cam.global_transform.basis.z
	for e in Game.world.assist_candidates(self):
		if not is_instance_valid(e):
			continue
		var p: Vector3 = e.global_position + Vector3(0, 1.2, 0)
		var d := p - cam.global_position
		if d.length() > 70.0:
			continue
		var ang := fwd.angle_to(d)
		if ang < best_ang and Game.world.has_los(cam.global_position, p):
			best_ang = ang
			best = e
	return best


func _crosshair_enemy():
	if cam == null:
		return null
	var origin := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(origin, origin + fwd * 120.0, _shot_mask(), [get_rid()])
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		return null
	var col = res["collider"]
	if col != null and col.has_method("get_peer_id"):
		return col if Game.world.is_hostile(peer_id, col.get_peer_id()) and col.state == 0 else null
	return col if col != null and col.has_method("get_enemy_id") else null


func _shot_mask() -> int:
	return (1 | 4 | 2) if Game.world != null and Game.world.versus else (1 | 4)


func get_peer_id() -> int:
	return peer_id


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
	if state != 0 and char_model == null:
		target_rot = -PI / 2.0
		target_y = 0.3
	model.rotation.x = lerp_angle(model.rotation.x, target_rot, minf(1.0, delta * 6.0))
	model.position.y = lerpf(model.position.y, target_y, minf(1.0, delta * 6.0))
	model.visible = true
	_update_anim(delta)
	if name_label != null:
		name_label.text = display_name + ("  [DOWNED - hold E]" if state == 1 else ("  [KIA]" if state == 2 else ""))


func _aim_point() -> Dictionary:
	var origin := cam.global_position if cam != null else global_position + Vector3(0, 1.6, 0)
	var fwd := -cam.global_transform.basis.z if cam != null else -global_transform.basis.z
	if not is_aiming:
		fwd = (fwd + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.012).normalized()
	var q := PhysicsRayQueryParameters3D.create(origin, origin + fwd * 250.0, _shot_mask(), [get_rid()])
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		return {"pos": origin + fwd * 250.0, "collider": null}
	return {"pos": res["position"], "collider": res["collider"]}


func _shoot() -> void:
	shot_t = 0.3
	if weapon == 1:
		_shoot_scatter()
		return
	fire_cd = Game.fire_interval()
	mag -= 1
	var aim := _aim_point()
	var from := muzzle.global_position
	var to: Vector3 = aim["pos"]
	Game.world.spawn_bolt(from, to, 0)
	Game.net_all("bolt_fx", [from, to, 0], false)
	var col = aim["collider"]
	if col != null and col.has_method("get_peer_id"):
		if Game.world.is_hostile(peer_id, col.get_peer_id()):
			Game.net_server("req_pvp_damage", [col.get_peer_id(), Game.weapon_damage(), global_position])
			Game.world.hud.hit_marker(false)
	elif col != null and col.has_method("get_enemy_id"):
		Game.net_server("req_damage", [col.get_enemy_id(), Game.weapon_damage(), global_position])
		Game.world.hud.hit_marker(col.shield_blocks(global_position))
	if mag <= 0:
		_start_reload()


## Swap between the rifle (slot 1) and the scatter blaster (slot 2); each keeps its own magazine.
func switch_weapon(w: int) -> void:
	if w == weapon or state != 0:
		return
	stored_mag[weapon] = mag
	weapon = w
	mag_size = Game.mag_size() if w == 0 else SHOTGUN_MAG
	mag = stored_mag[w]
	reloading = 0.0
	fire_cd = maxf(fire_cd, 0.35)
	Game.play_sfx("switch")
	anim_flags = (anim_flags & ~16) | (w << 4)


## Scatter blaster: 8 pellets in a cone, damage aggregated per target into one request each.
func _shoot_scatter() -> void:
	fire_cd = 0.85 * pow(0.92, int(Game.save["rate"]))
	mag -= 1
	var origin := cam.global_position if cam != null else global_position + Vector3(0, 1.6, 0)
	var basis := cam.global_transform.basis if cam != null else global_transform.basis
	var spread := 0.03 if is_aiming else 0.05
	var per := Game.weapon_damage() * 0.45
	var totals := {}
	var space := get_world_3d().direct_space_state
	for i in SHOTGUN_PELLETS:
		var d := (-basis.z + basis.x * randf_range(-spread, spread) + basis.y * randf_range(-spread, spread)).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + d * SHOTGUN_RANGE, _shot_mask(), [get_rid()])
		var res := space.intersect_ray(q)
		var to: Vector3 = origin + d * SHOTGUN_RANGE if res.is_empty() else res["position"]
		if i % 2 == 0:
			Game.world.spawn_bolt(muzzle.global_position, to, 2)
			Game.net_all("bolt_fx", [muzzle.global_position, to, 2], false)
		if not res.is_empty() and res["collider"] != null:
			var c = res["collider"]
			var falloff := clampf(1.25 - origin.distance_to(to) / SHOTGUN_RANGE, 0.35, 1.0)
			totals[c] = totals.get(c, 0.0) + per * falloff
	for c in totals:
		if not is_instance_valid(c):
			continue
		if c.has_method("get_peer_id"):
			if Game.world.is_hostile(peer_id, c.get_peer_id()):
				Game.net_server("req_pvp_damage", [c.get_peer_id(), totals[c], global_position])
				Game.world.hud.hit_marker(false)
		elif c.has_method("get_enemy_id"):
			Game.net_server("req_damage", [c.get_enemy_id(), totals[c], global_position])
			Game.world.hud.hit_marker(c.shield_blocks(global_position))
	if mag <= 0:
		_start_reload()


func _start_reload() -> void:
	if reloading > 0.0 or mag >= mag_size:
		return
	reloading = RELOAD_TIME * (1.4 if weapon == 1 else 1.0)
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
	if health <= 0.0 and Game.world.versus:
		health = 0.0
		state = 2
		respawn_t = 5.0
		reloading = 0.0
		Game.play_sfx("down")
		Game.net_server("pvp_died", [])
		return
	if health <= 0.0:
		health = 0.0
		state = 1
		bleed = BLEED_TIME
		reloading = 0.0
		Game.play_sfx("down")
		Game.world.hud.add_feed("%s is DOWN!" % display_name, Color(1, 0.4, 0.3))
		Game.world.show_message("You're down! Hold on, a squadmate can revive you (E).")


func respawn() -> void:
	global_position = Game.world.spawn_point(peer_id)
	rotation.y = atan2(global_position.x, global_position.z)
	velocity = Vector3.ZERO
	health = max_health
	state = 0
	mag = mag_size
	since_hit = 10.0


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
	state = st & 3
	anim_flags = st >> 2
