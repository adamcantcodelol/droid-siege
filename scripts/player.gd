extends CharacterBody3D
const TrooperClass = preload("res://scripts/trooper_class.gd")
## Clone trooper. The owning peer simulates movement/shooting; other peers show
## an interpolated proxy from synced state.

const MechVisual := preload("res://scripts/mech.gd")
const SPEED := 6.0
const SPRINT_SPEED := 10.0
const AIM_SPEED := 3.5
const JUMP_VELOCITY := 6.2
const GRAVITY := 16.0
const FALL_GRAVITY := 24.0   # heavier on the way down: less floaty
const COYOTE := 0.12
const JUMP_BUFFER := 0.12
var _air_t := 0.0
var _jump_buf := 0.0
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
	_cs = CollisionShape3D.new()
	_cap = CapsuleShape3D.new()
	_cap.radius = 0.4
	_cap.height = 1.8
	_cs.shape = _cap
	_cs.position.y = 0.9
	add_child(_cs)
	if is_local:
		cls = Game.trooper_cls()
	_build_model()
	net_pos = position
	net_rot = rotation.y
	if is_local:
		cls = Game.trooper_cls()
		max_health = Game.max_health()
		health = max_health
		mag_size = Game.mag_size(0)
		mag = mag_size
		stored_mag = [mag_size, Game.mag_size(1)]
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
		rank_sprite = Sprite3D.new()
		rank_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		rank_sprite.no_depth_test = true
		rank_sprite.pixel_size = 0.012
		rank_sprite.position = Vector3(-0.7, 2.3, 0)
		rank_sprite.texture = Game.rank_icon(Game.peer_rank(peer_id))
		add_child(rank_sprite)


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
var anim_flags := 0          # bit0 fire,1 aim,2 sprint,3 air,4-5 weapon,6 mech,7 crouch
var shot_t := 0.0
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _shown_weapon := -1
var is_crouching := false
var crouch_toggle := false
var crouch_eye_y := 1.6
var stand_eye_y := 1.6
var slide_t := 0.0
var crouch_blend := 0.0
var _riding_open := false
var _cap: CapsuleShape3D = null
var _cs: CollisionShape3D = null
var cls := 0
var z6_spin := 0.0
var burst_left := 0
var cmd_cd := 0.0
var cmd_buff_t := 0.0
var bonus_hp := 0.0
var veh_vtype := 0
var veh_heat := 0.0
var veh_shell_cd := 0.0
var _last_attacker_id := 0
var _pvp_dead_sent := false
var emote_id := 0            # 0 none, 1 Floss, 2 Take the L, 3 Orange Justice, 4 Hit the Griddy
var emote_t := 0.0
var _emote_cycle := 0
var rank_sprite: Sprite3D = null
var _fp_saved_for_emote := false


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
		"Character_Main": armor, "Pants": armor.darkened(0.08), "Skin": armor.darkened(0.04),
		"Grey": accent, "Red": accent, "Wood": Color(0.15, 0.15, 0.17), "DarkWood": Color(0.1, 0.1, 0.12)},
		SOLDIER_ANIMS, WEAPON_MESHES, WEAPON_SHOW[0])
	model.add_child(body)
	char_model = body
	char_model.pose_cb = _apply_procedural_pose
	_build_armor_deco(accent)
	_shown_weapon = 0
	muzzle = Node3D.new()
	muzzle.position = Vector3(0.28, 1.27, -0.85)
	model.add_child(muzzle)


## Clone armour details that follow bones: T-visor + helmet ridge on the head, squad-coloured
## pauldron on the left shoulder. Parented to the model (not the bone: the GLB armature is
## scaled x100) and placed from the bone pose each frame. Render layer 2 so the first-person
## camera never sees them (same as the body meshes).
var deco: Array = []          # [node, bone_idx, offset]
var _skel: Skeleton3D = null


func _build_armor_deco(accent: Color) -> void:
	var sk: Array = char_model.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		return
	_skel = sk[0]
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.04, 0.04, 0.05)
	black.roughness = 0.2
	var acc := StandardMaterial3D.new()
	acc.albedo_color = accent
	var head := Node3D.new()
	model.add_child(head)
	for p in [[Vector3(0.26, 0.06, 0.04), Vector3(0, 0.03, 0)], [Vector3(0.07, 0.16, 0.04), Vector3(0, -0.06, 0)]]:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = p[0]
		mi.mesh = b
		mi.material_override = black
		mi.position = p[1] + Vector3(0, 0, 0.0)
		head.add_child(mi)
	var plate := MeshInstance3D.new()      # helmet faceplate (hides the cartoon face)
	var plb := BoxMesh.new()
	plb.size = Vector3(0.46, 0.4, 0.05)
	plate.mesh = plb
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.93, 0.93, 0.9)
	plate.material_override = wm
	plate.position = Vector3(0, -0.02, 0.03)
	head.add_child(plate)
	var ridge := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(0.05, 0.04, 0.34)
	ridge.mesh = rb
	ridge.material_override = acc
	ridge.position = Vector3(0, 0.2, 0.17)
	head.add_child(ridge)
	deco.append([head, _skel.find_bone("Head_2"), HEAD_DECO_OFS])
	var pad := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.2, 0.06, 0.24)
	pad.mesh = pb
	pad.material_override = acc
	pad.rotation.z = 0.35
	var sh := Node3D.new()
	sh.add_child(pad)
	model.add_child(sh)
	deco.append([sh, _skel.find_bone("UpperArm.R"), SHOULDER_DECO_OFS])
	for d in deco:
		for mi in d[0].get_children():
			mi.layers = 2
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


const HEAD_DECO_OFS := Vector3(0, 0.2, -0.31)
const SHOULDER_DECO_OFS := Vector3(0, 0.1, 0)


func _place_deco() -> void:
	if _skel == null:
		return
	for d in deco:
		if d[1] < 0:
			continue
		var bp: Vector3 = (_skel.global_transform * _skel.get_bone_global_pose(d[1])).origin
		d[0].global_position = bp + model.global_transform.basis * d[2]
		d[0].global_rotation = model.global_rotation


func _update_anim(delta: float) -> void:
	_place_deco()
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
	var firing: bool = (anim_flags & 1) != 0 or shot_t > 0.0
	var aiming: bool = (anim_flags & 2) != 0
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
	if event.is_action_pressed("view_toggle", false) and state == 0 \
			and not (Game.world != null and Game.world.hud != null and Game.world.hud.is_blocking()):
		toggle_view()
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
		velocity.y -= (GRAVITY if velocity.y > 0.0 else FALL_GRAVITY) * delta
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
	_update_crouch(delta, act)
	is_sprinting = act and Input.is_action_pressed("sprint") and input.y < -0.1 and not is_aiming and reloading <= 0.0 and not is_crouching
	var speed := SPRINT_SPEED if is_sprinting else (AIM_SPEED if is_aiming else SPEED)
	speed *= Game.class_speed_mult()
	if weapon == 0 and str(Game.class_weapon(0).get("kind", "")) == "z6" and (Input.is_action_pressed("fire") or Input.is_action_pressed("kb_fire")):
		speed *= float(Game.class_weapon(0).get("fire_slow", 0.72))
	if is_crouching and slide_t <= 0.0:
		speed *= 0.62
	if slide_t > 0.0:
		speed = SPRINT_SPEED * 1.30 * (slide_t / 0.45)
	if in_mech >= 0:
		var vst: Dictionary = MechVisual.stats(veh_vtype)
		speed = float(vst["boost"] if is_sprinting else vst["speed"])
		_jump_buf = 0.0
		if str(Game.class_weapon(0).get("kind", "")) == "z6" or true:
			pass
		# Heat cools when not firing
		var cool: float = float(vst.get("heat_cool", 0.55))
		if fire_cd > float(vst.get("interval", 0.3)) * 0.5:
			veh_heat = maxf(0.0, veh_heat - cool * delta)
		else:
			veh_heat = maxf(0.0, veh_heat - cool * 0.35 * delta)
		veh_shell_cd = maxf(0.0, veh_shell_cd - delta)
	if act and Input.is_action_just_pressed("interact"):
		if in_mech >= 0:
			exit_mech()
		elif revive_target == null:
			var mi: int = Game.world.mech_near(global_position)
			if mi >= 0:
				Game.net_all("mech_enter", [mi, peer_id])
	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	dir.y = 0
	dir = dir.normalized()
	# snappier: fast ground accel, even faster stop when the keys are released
	var accel := (16.0 if dir != Vector3.ZERO else 22.0) if is_on_floor() else 4.0
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * speed * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * speed * delta)
	_air_t = 0.0 if is_on_floor() else _air_t + delta
	_jump_buf = JUMP_BUFFER if (act and Input.is_action_just_pressed("jump")) else maxf(0.0, _jump_buf - delta)
	if in_mech < 0 and _jump_buf > 0.0 and _air_t < COYOTE and velocity.y <= 0.5:
		velocity.y = JUMP_VELOCITY   # coyote time + jump buffering
		_jump_buf = 0.0
		_air_t = COYOTE
	if not Input.is_action_pressed("jump") and velocity.y > 2.0:
		velocity.y -= 30.0 * delta   # short hop when jump is tapped
	move_and_slide()
	if position.y < -20.0:
		position = Game.world.LZ + Vector3(0, 2, 0)
		velocity = Vector3.ZERO

	_place_camera()
	# Camera zoom
	if cam != null:
		var want_fov := 72.0
		if is_sprinting:
			want_fov = 80.0
		if is_aiming:
			var sc: float = float(Game.class_weapon(weapon).get("scope", 0.0))
			want_fov = 75.0 / sc if sc > 1.0 else 50.0
		cam.fov = lerpf(cam.fov, want_fov, minf(1.0, delta * 10.0))
		spring.spring_length = lerpf(spring.spring_length, (7.0 if is_aiming else 8.5) if in_mech >= 0 else (1.8 if is_aiming else 3.2), minf(1.0, delta * 10.0))

	# Weapon
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			mag = mag_size
	crosshair_on_enemy = _crosshair_enemy() != null
	var want_fire: bool = Input.is_action_pressed("fire") or Input.is_action_pressed("kb_fire")
	if Game.control_mode == 1 and Game.auto_fire and crosshair_on_enemy:
		want_fire = true
	if not want_fire:
		z6_spin = maxf(0.0, z6_spin - delta * 0.5)
		if burst_left > 0 and fire_cd <= 0.0:
			pass  # finish burst below
	if act:
		var fire_ok: bool = want_fire or burst_left > 0
		if fire_ok and fire_cd <= 0.0 and reloading <= 0.0 and not is_sprinting:
			if in_mech >= 0:
				_shoot_mech()
			elif mag > 0:
				_shoot()
			else:
				_start_reload()
		if Input.is_action_just_pressed("reload") and mag < mag_size:
			_start_reload()
		if in_mech >= 0 and veh_vtype == 2 and veh_shell_cd <= 0.0:
			if Input.is_action_just_pressed("grenade") or Input.is_action_just_pressed("aim"):
				_fire_tank_shell()
		elif Input.is_action_just_pressed("grenade") and in_mech < 0:
			_throw_grenade()
		if Input.is_action_just_pressed("weapon1"):
			switch_weapon(0)
		elif Input.is_action_just_pressed("weapon2"):
			switch_weapon(1)
		elif Input.is_action_just_pressed("weapon_next"):
			switch_weapon(1 - weapon)
		if Input.is_action_just_pressed("battle_cmd"):
			_try_battle_command()


	# Emotes
	if act and in_mech < 0 and state == 0:
		if Input.is_action_just_pressed("emote"):
			_emote_cycle = (_emote_cycle % 4) + 1
			_start_emote(_emote_cycle)
		elif Input.is_action_just_pressed("emote1"):
			_start_emote(1)
		elif Input.is_action_just_pressed("emote2"):
			_start_emote(2)
		elif Input.is_action_just_pressed("emote3"):
			_start_emote(3)
		elif Input.is_action_just_pressed("emote4"):
			_start_emote(4)
	if emote_id > 0:
		var moving := input.length() > 0.1
		if moving or Input.is_action_pressed("jump") or Input.is_action_pressed("crouch") or Input.is_action_just_pressed("crouch_toggle") \
				or want_fire or Input.is_action_pressed("aim") or Input.is_action_just_pressed("grenade") or in_mech >= 0:
			_stop_emote()
		else:
			emote_t += delta

	# Health + officer aura regen
	cmd_cd = maxf(0.0, cmd_cd - delta)
	cmd_buff_t = maxf(0.0, cmd_buff_t - delta)
	if state == 0 and since_hit > 5.0 and health < max_health:
		var regen := 10.0
		if Game.world != null:
			regen += Game.world.officer_regen(peer_id)
		health = minf(max_health, health + regen * delta)
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
		anim_flags = (1 if shot_t > 0.0 else 0) | (2 if is_aiming else 0) | (4 if is_sprinting else 0) | (8 if not is_on_floor() else 0) | (weapon << 4) | (64 if in_mech >= 0 else 0) | (128 if is_crouching else 0) | ((emote_id & 7) << 8) | ((veh_vtype & 3) << 11)
		Game.net_all("player_state", [position, rotation.y, pitch, health, state | (anim_flags << 2)], false)


## Keyboard / trackpad camera: arrows or J/L turn, I/K look, plus light aim assist.
## Third-person camera: follow the SpringArm's collision distance, but never closer than
## MIN_CAM_DIST. Before this, a wall/pole right behind the trooper collapsed the camera to
## ~0 m, i.e. inside the helmet, so the player only saw the crosshair and no trooper.
const MIN_CAM_DIST := 1.25


var first_person := false
var in_mech := -1          # index into world.mechs while piloting
var mech_vis: Node3D = null
var viewmodel: Node3D = null


## First-person DC-15 style blaster: a few boxes parented to the camera, lower right, no shadows.
func _build_viewmodel() -> Node3D:
	var vm := Node3D.new()
	vm.position = VM_BASE
	cam.add_child(vm)
	var dark := Color(0.1, 0.1, 0.11)
	var metal := Color(0.32, 0.33, 0.36)
	var white := Color(0.88, 0.88, 0.85)
	var parts := [
		# [mesh, pos, color, rot]
		[Vector3(0.055, 0.075, 0.34), Vector3(0, 0, 0.02), dark, 0],          # receiver
		["cyl", 0.022, 0.42, Vector3(0, 0.012, -0.34), metal],               # barrel
		["cyl", 0.032, 0.05, Vector3(0, 0.012, -0.56), dark],                # muzzle
		[Vector3(0.075, 0.012, 0.18), Vector3(0, 0.05, -0.24), dark, 0],      # cooling fins (top)
		[Vector3(0.075, 0.012, 0.18), Vector3(0, 0.02, -0.24), dark, 0],
		[Vector3(0.075, 0.012, 0.18), Vector3(0, -0.01, -0.24), dark, 0],
		["cyl", 0.015, 0.12, Vector3(0, 0.06, -0.12), metal],                # scope tube
		[Vector3(0.012, 0.035, 0.012), Vector3(0, 0.05, -0.5), dark, 0],      # front sight post
		[Vector3(0.04, 0.11, 0.05), Vector3(0, -0.085, 0.07), dark, 0.25],    # grip
		[Vector3(0.035, 0.06, 0.14), Vector3(0, -0.06, -0.12), metal, 0],     # mag / handguard
		[Vector3(0.05, 0.05, 0.12), Vector3(0, -0.01, 0.22), dark, 0],        # stock
		[Vector3(0.075, 0.09, 0.1), Vector3(0.02, -0.11, 0.1), white, 0.2],   # gloved hand (armour white)
		[Vector3(0.07, 0.07, 0.09), Vector3(-0.01, -0.05, -0.18), white, 0],  # support hand
	]
	for pt in parts:
		var mi := MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.roughness = 0.45
		if pt[0] is String:
			var c := CylinderMesh.new()
			c.top_radius = pt[1]
			c.bottom_radius = pt[1]
			c.height = pt[2]
			c.radial_segments = 8
			c.rings = 1
			mi.mesh = c
			mi.rotation.x = PI / 2
			mi.position = pt[3]
			m.albedo_color = pt[4]
		else:
			var b := BoxMesh.new()
			b.size = pt[0]
			mi.mesh = b
			mi.position = pt[1]
			m.albedo_color = pt[2]
			mi.rotation.x = pt[3]
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vm.add_child(mi)
	return vm


const VM_BASE := Vector3(0.2, -0.2, -0.45)
var _vm_t := 0.0


## Walk bob, crisp fire kick and a dip while reloading (local first person only).
func _animate_viewmodel(delta: float) -> void:
	if viewmodel == null or not viewmodel.visible:
		return
	var hs := Vector2(velocity.x, velocity.z).length()
	var on: bool = is_on_floor() and hs > 0.5
	_vm_t += delta * (11.0 if is_sprinting else 8.0) * (1.0 if on else 0.0)
	var amp := clampf(hs / SPEED, 0.0, 1.4) * (0.012 if not is_aiming else 0.003)
	var target := VM_BASE + Vector3(cos(_vm_t * 0.5) * amp, -absf(sin(_vm_t * 0.5)) * amp, 0)
	if is_aiming:
		target = Vector3(0.0, -0.105, -0.3) + target - VM_BASE
	var rot := Vector3.ZERO
	if shot_t > 0.22:
		var k := (shot_t - 0.22) / 0.08
		target.z += 0.035 * k
		rot.x += 0.06 * k
	if reloading > 0.0:
		target.y -= 0.12
		rot.x -= 0.5
		rot.z += 0.3
	viewmodel.position = viewmodel.position.lerp(target, minf(1.0, delta * 18.0))
	viewmodel.rotation = viewmodel.rotation.lerp(rot, minf(1.0, delta * 14.0))
var mech_cs: CollisionShape3D = null
var _mech_t := 0.0
var _mech_prev_ry := 0.0
# Vehicle movement pulled from MechVisual.stats(veh_vtype)


func piloting() -> bool:
	return in_mech >= 0 if is_local else (anim_flags & 64) != 0


func exit_mech() -> void:
	if in_mech < 0:
		return
	var i := in_mech
	Game.net_all("mech_exit", [i, global_position, rotation.y])
	global_position += global_transform.basis.x * 2.4
	_place_camera()


func _shoot_mech() -> void:
	var st: Dictionary = MechVisual.stats(veh_vtype)
	if veh_heat >= float(st.get("heat_max", 1.0)):
		return  # overheated
	shot_t = 0.3
	fire_cd = float(st.get("interval", 0.38))
	veh_heat = minf(float(st.get("heat_max", 1.0)), veh_heat + float(st.get("heat_rate", 0.2)))
	var aim := _aim_point()
	var muz_n = null
	if mech_vis != null:
		muz_n = mech_vis.get_node_or_null("Body/Gun/Muzzle")
	var from: Vector3 = muz_n.global_position if muz_n != null else global_position + Vector3(0, 2.5, 0)
	var hit := _trace_shot(aim["pos"], 0.008)
	# Prefer muzzle as visual start but trust barrel-trace collider
	var to: Vector3 = hit["pos"]
	Game.world.spawn_bolt(from, to, 0)
	Game.net_all("bolt_fx", [from, to, 0], false)
	if Game.world != null:
		Game.world.player_bolt(from, to)
	Game.play_sfx("scatter", null, -4.0)
	var dmg := Game.weapon_damage(0) * float(st.get("dmg", 1.0))
	_apply_hit(hit["collider"], dmg, "vehicle", {}, to)


func _fire_tank_shell() -> void:
	var st: Dictionary = MechVisual.stats(2)
	veh_shell_cd = float(st.get("shell_cd", 6.0))
	var aim := _aim_point()
	var to: Vector3 = aim["pos"]
	Game.net_server("req_micro_splash", [to, float(st.get("shell_dmg", 75.0)), float(st.get("shell_r", 4.5))])
	Game.play_sfx("explosion", to, -6.0)


## V toggles first person: camera at the eyes, own body hidden from this camera (render layer 2)
## while it still casts a shadow and stays visible to everyone else.
func toggle_view() -> void:
	if emote_id != 0:
		_stop_emote()
	set_first_person(not first_person)
	Game.write_save()


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
	var fp: bool = first_person and in_mech < 0
	var fp_veh: bool = first_person and in_mech >= 0   # v1.3.1: cockpit view in vehicles too
	cam.cull_mask = (0xFFFFF & ~2) if (fp or fp_veh) else 0xFFFFF
	if viewmodel == null:
		viewmodel = _build_viewmodel()
	viewmodel.visible = fp and state == 0
	# mech: camera eye ~1.4 m above the cockpit roof and offset right, so the walker sits
	# in the lower-left of the frame and the crosshair has clear sight to the horizon
	if in_mech >= 0:
		var vst2: Dictionary = MechVisual.stats(veh_vtype)
		pivot.position.y = float(vst2.get("cam_y", 5.0))
		spring.position.x = float(vst2.get("cam_x", 1.4))
	else:
		pivot.position.y = crouch_eye_y
		spring.position.x = 0.75
		if slide_t > 0.0:
			pivot.position.y -= 0.15
	if fp:
		cam.position = Vector3(0.0, 0.05, -0.3)
		return
	if fp_veh:
		# driver's eye: top-front of the hull, looking past the guns
		var vs: Dictionary = MechVisual.stats(veh_vtype)
		var sz: Vector3 = vs.get("size", Vector3(2, 2, 3))
		pivot.position.y = float(vs.get("col_y", 1.0)) + sz.y * 0.5 + 0.35
		spring.position.x = 0.0
		cam.position = Vector3(0.0, 0.0, -sz.z * 0.5 - 0.15)
		return
	var d := clampf(spring.get_hit_length(), MIN_CAM_DIST, maxf(spring.spring_length, MIN_CAM_DIST))
	cam.position = spring.position + Vector3(0, 0, d)


func _process(_delta: float) -> void:
	if is_local:
		_place_camera()
		_animate_viewmodel(_delta)


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
	if not _riding_open and emote_id == 0:
		model.rotation.x = lerp_angle(model.rotation.x, target_rot, minf(1.0, delta * 6.0))
		if crouch_blend < 0.05:
			model.position.y = lerpf(model.position.y, target_y, minf(1.0, delta * 6.0))
	var pil := piloting()
	# Open-cockpit vehicles keep the trooper visible (BARC / AT-RT / ISP). Tank hides rider.
	_riding_open = pil and veh_vtype != 2
	model.visible = (not pil) or _riding_open
	if pil and mech_vis == null:
		mech_vis = MechVisual.build_type(veh_vtype)
		mech_vis.set_meta("vtype", veh_vtype)
		add_child(mech_vis)
		mech_cs = CollisionShape3D.new()
		var bx := BoxShape3D.new()
		var vst3: Dictionary = MechVisual.stats(veh_vtype)
		bx.size = vst3["size"]
		mech_cs.shape = bx
		mech_cs.position.y = float(vst3["col_y"])
		add_child(mech_cs)
	elif pil and mech_vis != null and int(mech_vis.get_meta("vtype", -1)) != veh_vtype:
		mech_vis.queue_free()
		mech_vis = MechVisual.build_type(veh_vtype)
		mech_vis.set_meta("vtype", veh_vtype)
		add_child(mech_vis)
		var vst4: Dictionary = MechVisual.stats(veh_vtype)
		if mech_cs != null and mech_cs.shape is BoxShape3D:
			(mech_cs.shape as BoxShape3D).size = vst4["size"]
			mech_cs.position.y = float(vst4["col_y"])
	if mech_vis != null:
		mech_vis.visible = pil
		if mech_cs != null:
			mech_cs.disabled = not pil
		if pil:
			var hv := Vector2(velocity.x, velocity.z).length() if is_local else net_pos.distance_to(position) * 10.0
			_mech_t += delta
			var turn := angle_difference(_mech_prev_ry, rotation.y) / maxf(delta, 0.001)
			_mech_prev_ry = rotation.y
			var spd0: float = float(MechVisual.stats(veh_vtype)["speed"])
			MechVisual.animate_type(mech_vis, veh_vtype, _mech_t, clampf(hv / maxf(spd0, 0.1), 0.0, 1.0), turn)
			MechVisual.flash_type(mech_vis, veh_vtype, shot_t > 0.22)
	# Seat / restore trooper transform (bone pose applied after AnimationPlayer via pose_cb)
	if _riding_open:
		_place_rider_seat()
		if char_model != null:
			char_model.set_visible_meshes(WEAPON_MESHES, [])
			_shown_weapon = -2
	elif _shown_weapon == -2:
		# Just exited an open-cockpit vehicle — restore infantry pose/weapon
		model.position = Vector3(0, target_y, 0)
		model.rotation = Vector3(target_rot, 0, 0)
		_shown_weapon = -1
		var skx := _emote_skeleton()
		if skx != null:
			skx.reset_bone_poses()
	# Crouch blend (visual)
	var want_cb := 1.0 if (is_crouching and not pil) else 0.0
	crouch_blend = lerpf(crouch_blend, want_cb, minf(1.0, delta * 12.0))
	_update_anim(delta)
	if emote_id > 0 and not is_local:
		emote_t += delta
	elif not is_local and emote_id == 0 and emote_t != 0.0:
		emote_t = 0.0
		_reset_emote_bones()
	var nametag_y := 2.3 - (0.55 * crouch_blend if not pil else 0.0)
	if _riding_open:
		nametag_y = model.position.y + 1.6
	if name_label != null:
		name_label.text = display_name + ("  [DOWNED - hold E]" if state == 1 else ("  [KIA]" if state == 2 else ""))
		name_label.position.y = nametag_y
	if rank_sprite != null:
		rank_sprite.position.y = nametag_y



func aim_target_pos() -> Vector3:
	return global_position + Vector3(0, crouch_eye_y * 0.85 if is_crouching else 1.2, 0)


func _barrel_origin() -> Vector3:
	var chest := global_position + Vector3(0, crouch_eye_y * 0.75, 0)
	var muz: Vector3 = muzzle.global_position if muzzle != null else chest + Vector3(0, 0, -0.5)
	# Exclude this CharacterBody3D rid only (CollisionShape3D has no get_rid)
	var q := PhysicsRayQueryParameters3D.create(chest, muz, 1, [get_rid()])
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	return chest if not res.is_empty() else muz


## Two-stage aim: camera finds crosshair point, then barrel ray (layer walls+targets) is truth.
func _trace_shot(aim_pos: Vector3, spread: float = 0.0) -> Dictionary:
	var origin := _barrel_origin()
	var dir := (aim_pos - origin).normalized()
	if spread > 0.0:
		var basis := cam.global_transform.basis if cam != null else global_transform.basis
		dir = (dir + basis.x * randf_range(-spread, spread) + basis.y * randf_range(-spread, spread)).normalized()
	var end := origin + dir * (origin.distance_to(aim_pos) + 0.5)
	if origin.distance_to(aim_pos) < 0.2:
		end = origin + dir * 250.0
	var q := PhysicsRayQueryParameters3D.create(origin, end, _shot_mask(), [get_rid()])
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		return {"pos": end, "collider": null, "from": origin}
	return {"pos": res["position"], "collider": res["collider"], "from": origin}


func _update_crouch(delta: float, act: bool) -> void:
	if in_mech >= 0:
		is_crouching = false
		crouch_toggle = false
		slide_t = 0.0
		return
	if act and Input.is_action_just_pressed("crouch_toggle"):
		crouch_toggle = not crouch_toggle
	var want: bool = crouch_toggle or (act and Input.is_action_pressed("crouch"))
	# Tactical slide: C while sprinting
	if act and Input.is_action_just_pressed("crouch") and is_sprinting and is_on_floor() and slide_t <= 0.0:
		slide_t = 0.45
		want = true
	if slide_t > 0.0:
		slide_t -= delta
		want = true
	# Stand-up check under low geometry
	if is_crouching and not want and _cap != null:
		var q := PhysicsRayQueryParameters3D.create(
			global_position + Vector3(0, 0.5, 0), global_position + Vector3(0, 1.85, 0), 1, [get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			want = true
	is_crouching = want
	var target_h := 1.1 if is_crouching else 1.8
	var target_eye := 0.98 if is_crouching else stand_eye_y
	if _cap != null:
		_cap.height = lerpf(_cap.height, target_h, minf(1.0, delta * 12.0))
		_cs.position.y = _cap.height * 0.5
	crouch_eye_y = lerpf(crouch_eye_y, target_eye, minf(1.0, delta * 12.0))


func _aim_point() -> Dictionary:
	var origin := cam.global_position if cam != null else global_position + Vector3(0, crouch_eye_y, 0)
	var fwd := -cam.global_transform.basis.z if cam != null else -global_transform.basis.z
	var spread := 0.012
	if is_crouching:
		spread *= 0.65
	if not is_aiming:
		fwd = (fwd + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
	var q := PhysicsRayQueryParameters3D.create(origin, origin + fwd * 250.0, _shot_mask(), [get_rid()])
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		return {"pos": origin + fwd * 250.0, "collider": null}
	return {"pos": res["position"], "collider": res["collider"]}


func _shoot() -> void:
	shot_t = 0.3
	var w: Dictionary = Game.class_weapon(weapon)
	var kind: String = str(w.get("kind", "rifle"))
	if kind == "scatter":
		_shoot_scatter()
		return
	# Burst carbine: queue remaining bolts
	if kind == "burst" and burst_left <= 0:
		burst_left = int(w.get("burst", 4)) - 1
		fire_cd = float(w.get("burst_gap", 0.045))
	elif kind == "burst" and burst_left > 0:
		burst_left -= 1
		fire_cd = float(w.get("burst_gap", 0.045)) if burst_left > 0 else Game.fire_interval(weapon)
	elif kind == "z6":
		z6_spin = minf(1.0, z6_spin + 0.08)
		var iv: float = lerpf(float(w.get("interval", 0.13)), float(w.get("min_interval", 0.055)), z6_spin)
		fire_cd = iv * pow(0.92, int(Game.save["rate"]))
	else:
		fire_cd = Game.fire_interval(weapon)
	mag -= 1
	var aim := _aim_point()
	var spr := 0.0 if is_aiming else 0.012
	if is_crouching:
		spr *= 0.65
	if kind == "sniper" and is_aiming:
		spr = 0.0
	var hit := _trace_shot(aim["pos"], spr)
	var from: Vector3 = hit["from"]
	var to: Vector3 = hit["pos"]
	var bolt_k: int = int(w.get("bolt", 0))
	Game.world.spawn_bolt(from, to, bolt_k)
	Game.net_all("bolt_fx", [from, to, bolt_k], false)
	if Game.world != null:
		Game.world.player_bolt(from, to)
	var dmg := Game.weapon_damage(weapon) * _dmg_aura_mult()
	var col = hit["collider"]
	_apply_hit(col, dmg, kind, w, to)
	if mag <= 0:
		_start_reload()


func _dmg_aura_mult() -> float:
	var m := 1.0
	if cmd_buff_t > 0.0:
		m *= 1.1
	if Game.world != null:
		m *= Game.world.officer_aura_mult(peer_id)
	return m


func _apply_hit(col, dmg: float, kind: String, w: Dictionary, hit_pos: Vector3) -> void:
	if col == null:
		return
	if col.has_method("get_peer_id"):
		if Game.world.is_hostile(peer_id, col.get_peer_id()):
			# Headshot bonus vs players near head height
			if kind == "sniper" and hit_pos.y > col.global_position.y + 1.35:
				dmg *= float(w.get("head_mult", 1.5))
			Game.net_server("req_pvp_damage", [col.get_peer_id(), dmg, global_position])
			Game.world.hud.hit_marker(false)
	elif col.has_method("get_enemy_id"):
		if kind == "sniper" and hit_pos.y > col.global_position.y + 1.45:
			dmg *= float(w.get("head_mult", 1.5))
		Game.net_server("req_damage", [col.get_enemy_id(), dmg, global_position])
		Game.world.hud.hit_marker(col.shield_blocks(global_position))
	if float(w.get("splash", 0.0)) > 0.0:
		Game.net_server("req_micro_splash", [hit_pos, float(w["splash"]), float(w.get("splash_r", 2.2))])


## Swap between the rifle (slot 1) and the scatter blaster (slot 2); each keeps its own magazine.
func switch_weapon(w: int) -> void:
	if w == weapon or state != 0:
		return
	stored_mag[weapon] = mag
	weapon = w
	mag_size = Game.mag_size(w)
	if stored_mag.size() < 2:
		stored_mag = [mag_size, Game.mag_size(1)]
	mag = stored_mag[w] if stored_mag[w] > 0 else mag_size
	z6_spin = 0.0
	burst_left = 0
	reloading = 0.0
	fire_cd = maxf(fire_cd, 0.35)
	Game.play_sfx("switch")
	anim_flags = (anim_flags & ~16) | (w << 4)


## Scatter blaster: 8 pellets in a cone, damage aggregated per target into one request each.
func _shoot_scatter() -> void:
	var w: Dictionary = Game.class_weapon(weapon)
	fire_cd = Game.fire_interval(weapon)
	mag -= 1
	var aim := _aim_point()
	var pellets: int = int(w.get("pellets", SHOTGUN_PELLETS))
	var rng: float = float(w.get("range", SHOTGUN_RANGE))
	var spread := 0.03 if is_aiming else 0.05
	if is_crouching:
		spread *= 0.65
	var per := Game.weapon_damage(weapon) * 0.45 * _dmg_aura_mult()
	var totals := {}
	var barrel := _barrel_origin()
	for i in pellets:
		var hit := _trace_shot(aim["pos"] + Vector3(randf_range(-1,1), randf_range(-1,1), randf_range(-1,1)) * spread * 8.0, spread)
		# Clamp pellet travel
		if barrel.distance_to(hit["pos"]) > rng:
			hit["pos"] = barrel + (hit["pos"] - barrel).normalized() * rng
			hit["collider"] = null
		if i % 2 == 0:
			Game.world.spawn_bolt(hit["from"], hit["pos"], int(w.get("bolt", 2)))
			Game.net_all("bolt_fx", [hit["from"], hit["pos"], int(w.get("bolt", 2))], false)
			if Game.world != null:
				Game.world.player_bolt(hit["from"], hit["pos"])
		var c = hit["collider"]
		if c != null:
			var falloff := clampf(1.25 - barrel.distance_to(hit["pos"]) / rng, 0.35, 1.0)
			totals[c] = totals.get(c, 0.0) + per * falloff
	for c in totals:
		if not is_instance_valid(c):
			continue
		_apply_hit(c, totals[c], "scatter", w, c.global_position if "global_position" in c else barrel)
	if mag <= 0:
		_start_reload()


func _start_reload() -> void:
	if reloading > 0.0 or mag >= mag_size:
		return
	var w: Dictionary = Game.class_weapon(weapon)
	reloading = float(w.get("reload", RELOAD_TIME))
	Game.play_sfx("reload")


func _throw_grenade() -> void:
	if grenades <= 0 or grenade_cd > 0.0:
		if grenades <= 0:
			Game.world.show_message("Out of grenades! They refill next match (upgrade the tier in the Armory).")
		return
	grenade_cd = 1.0
	grenades -= 1
	Game.write_save()
	var fwd := -cam.global_transform.basis.z if cam != null else -global_transform.basis.z
	var vel := fwd * 17.0 + Vector3(0, 4.0, 0)
	var pos := muzzle.global_position
	Game.world.spawn_grenade(pos, vel, true)
	Game.net_all("grenade_fx", [pos, vel], false)


func take_damage(dmg: float, from = null, attacker_id: int = 0) -> void:
	if god or state != 0 or not is_local:
		return
	# Vehicle absorbs hits on its own hull — trooper HP untouched until destruction bailout
	if in_mech >= 0 and Game.world != null:
		Game.world.damage_vehicle(in_mech, dmg, attacker_id, from if from is Vector3 else global_position)
		Game.play_sfx("hurt", null, -8.0)
		if Game.world.hud != null:
			Game.world.hud.damage_flash()
		return
	if attacker_id != 0:
		_last_attacker_id = attacker_id
	# Bonus temporary shield (Officer Battle Command) absorbs first
	if bonus_hp > 0.0:
		var soak := minf(bonus_hp, dmg)
		bonus_hp -= soak
		dmg -= soak
		if dmg <= 0.0:
			return
	health -= dmg
	since_hit = 0.0
	Game.play_sfx("hurt", null, -6.0)
	if Game.world.hud != null:
		Game.world.hud.damage_flash()
		if from is Vector3:
			Game.world.hud.damage_from(from)
	if health <= 0.0 and Game.world.versus:
		if _pvp_dead_sent:
			return
		_pvp_dead_sent = true
		health = 0.0
		state = 2
		respawn_t = 5.0
		reloading = 0.0
		Game.play_sfx("down")
		Game.net_server("pvp_died", [_last_attacker_id])
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
	_pvp_dead_sent = false
	_last_attacker_id = 0
	bonus_hp = 0.0
	is_crouching = false


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
	is_crouching = (anim_flags & 128) != 0
	emote_id = (anim_flags >> 8) & 7
	if (anim_flags & 64) != 0:
		veh_vtype = (anim_flags >> 11) & 3



func _try_battle_command() -> void:
	if cls != 3 or cmd_cd > 0.0 or state != 0:
		return
	var d: Dictionary = TrooperClass.def(3)
	cmd_cd = float(d.get("cmd_cd", 18.0))
	cmd_buff_t = float(d.get("cmd_dur", 6.0))
	bonus_hp = float(d.get("cmd_shield", 25.0))
	Game.play_sfx("capture", null, -4.0)
	if Game.world != null:
		Game.world.apply_battle_command(peer_id, global_position)
		Game.world.show_message("Battle Command! +shield & speed for nearby allies.")


func apply_class(new_cls: int) -> void:
	cls = TrooperClass.clamp_id(new_cls)
	if is_local:
		Game.save["cls"] = cls
		Game.write_save()
	max_health = Game.max_health() if is_local else float(TrooperClass.def(cls).get("hp", 100.0))
	health = minf(health, max_health)
	mag_size = Game.mag_size(weapon) if is_local else int(TrooperClass.weapon(cls, weapon).get("mag", 24))
	mag = mini(mag, mag_size)
	stored_mag = [Game.mag_size(0), Game.mag_size(1)] if is_local else stored_mag



func _start_emote(eid: int) -> void:
	if state != 0 or in_mech >= 0:
		return
	emote_id = clampi(eid, 1, 4)
	emote_t = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	is_sprinting = false
	# Watch yourself dance in 3rd person
	if first_person:
		_fp_saved_for_emote = true
		set_first_person(false)
	else:
		_fp_saved_for_emote = false


func _stop_emote() -> void:
	if emote_id == 0:
		return
	emote_id = 0
	emote_t = 0.0
	_reset_emote_bones()
	if _fp_saved_for_emote:
		_fp_saved_for_emote = false
		set_first_person(true)


func _emote_skeleton() -> Skeleton3D:
	if _skel != null:
		return _skel
	if char_model == null:
		return null
	var sks: Array = char_model.find_children("*", "Skeleton3D", true, false)
	return sks[0] if sks.size() > 0 else null


func _reset_emote_bones() -> void:
	var sk := _emote_skeleton()
	if sk != null:
		sk.reset_bone_poses()
	if model != null and not _riding_open:
		model.position.y = 0.0
		model.rotation = Vector3.ZERO


func _bone_rot(sk: Skeleton3D, name: String, eulers: Vector3) -> void:
	var idx := sk.find_bone(name)
	if idx < 0:
		return
	sk.set_bone_pose_rotation(idx, Quaternion.from_euler(eulers))


## Cringy Fortnite-style dances via bone pose + root bounce.
func _animate_emote(delta: float) -> void:
	var sk := _emote_skeleton()
	if sk == null:
		return
	var t := emote_t
	match emote_id:
		1:  # The Floss — hip sway + arms swinging across body
			model.rotation.y = sin(t * 14.0) * 0.35
			model.position.y = absf(sin(t * 14.0)) * 0.04
			_bone_rot(sk, "Hips", Vector3(0, sin(t * 14.0) * 0.5, 0))
			_bone_rot(sk, "UpperArm.L", Vector3(0.2, 0, -1.2 + sin(t * 14.0) * 1.4))
			_bone_rot(sk, "UpperArm.R", Vector3(0.2, 0, 1.2 + sin(t * 14.0) * 1.4))
			_bone_rot(sk, "LowerArm.L", Vector3(0.4, 0, 0))
			_bone_rot(sk, "LowerArm.R", Vector3(0.4, 0, 0))
		2:  # Take the L — hand on forehead, other on hip, side kicks
			model.position.y = absf(sin(t * 8.0)) * 0.06
			_bone_rot(sk, "UpperArm.R", Vector3(-2.2, 0.3, 0.6))
			_bone_rot(sk, "LowerArm.R", Vector3(-1.5, 0, 0))
			_bone_rot(sk, "UpperArm.L", Vector3(0.3, 0, 1.1))
			_bone_rot(sk, "LowerArm.L", Vector3(1.0, 0, 0))
			var kick := absf(sin(t * 8.0))
			_bone_rot(sk, "UpperLeg.L", Vector3(-kick * 1.1, 0, 0.2))
			_bone_rot(sk, "LowerLeg.L", Vector3(kick * 0.8, 0, 0))
			_bone_rot(sk, "UpperLeg.R", Vector3(-kick * 0.3, 0, -0.15))
		3:  # Orange Justice — bouncy knees + wild arm pumps
			model.position.y = absf(sin(t * 10.0)) * 0.1
			model.rotation.y = sin(t * 5.0) * 0.15
			_bone_rot(sk, "UpperLeg.L", Vector3(-0.5 + sin(t * 10.0) * 0.4, 0, 0.15))
			_bone_rot(sk, "UpperLeg.R", Vector3(-0.5 + cos(t * 10.0) * 0.4, 0, -0.15))
			_bone_rot(sk, "UpperArm.L", Vector3(-1.0 + sin(t * 12.0) * 1.2, 0, -0.8))
			_bone_rot(sk, "UpperArm.R", Vector3(-1.0 + cos(t * 12.0) * 1.2, 0, 0.8))
			_bone_rot(sk, "LowerArm.L", Vector3(sin(t * 12.0) * 1.0, 0, 0))
			_bone_rot(sk, "LowerArm.R", Vector3(cos(t * 12.0) * 1.0, 0, 0))
			_bone_rot(sk, "Torso", Vector3(sin(t * 10.0) * 0.2, 0, 0))
		4:  # Hit the Griddy — heel-toe bounce + goggle hands
			model.position.y = absf(sin(t * 12.0)) * 0.08
			model.rotation.y = sin(t * 6.0) * 0.25
			_bone_rot(sk, "UpperLeg.L", Vector3(-0.3 + sin(t * 12.0) * 0.5, 0, 0))
			_bone_rot(sk, "UpperLeg.R", Vector3(-0.3 + cos(t * 12.0) * 0.5, 0, 0))
			_bone_rot(sk, "Hips", Vector3(0, sin(t * 12.0) * 0.25, 0))
			# Arms swing low then snap to eyes
			var gog := 1.0 if fmod(t, 1.0) > 0.55 else 0.0
			_bone_rot(sk, "UpperArm.L", Vector3(lerpf(0.4, -2.0, gog), 0, lerpf(-0.6, -0.9, gog)))
			_bone_rot(sk, "UpperArm.R", Vector3(lerpf(0.4, -2.0, gog), 0, lerpf(0.6, 0.9, gog)))
			_bone_rot(sk, "LowerArm.L", Vector3(lerpf(0.2, -1.2, gog), 0, 0))
			_bone_rot(sk, "LowerArm.R", Vector3(lerpf(0.2, -1.2, gog), 0, 0))
	# Keep char_model from overwriting with locomotion while emoting
	if char_model != null:
		char_model.play("idle")



func _place_rider_seat() -> void:
	var seat := Vector3(0, 0.55, 0.35)
	match veh_vtype:
		0: seat = Vector3(0, 2.15, 0.25)  # AT-RT saddle
		1: seat = Vector3(0, 0.55, 0.35)  # BARC
		3: seat = Vector3(0, 0.65, 0.15)  # ISP
		_: seat = Vector3(0, 0.55, 0.35)
	var body: Node3D = mech_vis.get_node_or_null("Body") if mech_vis != null else null
	if body != null:
		model.position = body.position + seat
		model.rotation = Vector3(body.rotation.x * 0.85 - 0.12, 0.0, body.rotation.z * 0.9)
	else:
		model.position = seat
		model.rotation = Vector3(-0.12, 0, 0)


## Called from char_model after AnimationPlayer.advance so bone overrides stick.
func _apply_procedural_pose() -> void:
	if state != 0:
		return
	if emote_id > 0:
		_animate_emote(0.0)
		return
	if _riding_open:
		_pose_rider()
		return
	if crouch_blend > 0.01 or slide_t > 0.0:
		_pose_crouch()
		return
	# Clear residual hip pose position once standing again
	var sk := _emote_skeleton()
	if sk != null:
		var hip_i := sk.find_bone("Hips")
		if hip_i >= 0 and sk.get_bone_pose_position(hip_i).distance_to(sk.get_bone_rest(hip_i).origin) > 0.001:
			sk.set_bone_pose_position(hip_i, sk.get_bone_rest(hip_i).origin)


func _pose_rider() -> void:
	var sk := _emote_skeleton()
	if sk == null:
		return
	# Seated speeder / walker / ISP pose
	_bone_rot(sk, "Hips", Vector3(-0.15, 0, 0))
	_bone_rot(sk, "Abdomen", Vector3(0.2, 0, 0))
	_bone_rot(sk, "Torso", Vector3(0.28, 0, 0))
	_bone_rot(sk, "UpperLeg.L", Vector3(-1.15, 0.15, 0.35))
	_bone_rot(sk, "UpperLeg.R", Vector3(-1.15, -0.15, -0.35))
	_bone_rot(sk, "LowerLeg.L", Vector3(1.35, 0, 0))
	_bone_rot(sk, "LowerLeg.R", Vector3(1.35, 0, 0))
	_bone_rot(sk, "UpperArm.L", Vector3(-0.95, 0.2, -0.55))
	_bone_rot(sk, "UpperArm.R", Vector3(-0.95, -0.2, 0.55))
	_bone_rot(sk, "LowerArm.L", Vector3(-0.55, 0, 0))
	_bone_rot(sk, "LowerArm.R", Vector3(-0.55, 0, 0))
	if char_model != null:
		char_model.play("idle", 0.0)


func _pose_crouch() -> void:
	var sk := _emote_skeleton()
	if sk == null:
		return
	var b := crouch_blend
	var sliding := slide_t > 0.0
	var stride := 0.0
	if _speed > 0.35 and not sliding:
		stride = sin(Time.get_ticks_msec() * 0.012) * 0.35 * b
	# Drop hips so head falls ~0.55–0.65m while feet stay near floor
	var hip_i := sk.find_bone("Hips")
	if hip_i >= 0:
		var rest: Vector3 = sk.get_bone_rest(hip_i).origin
		# Armature is scaled x100 — 0.0045 skel units ≈ 0.45 m world before char_model scale
		sk.set_bone_pose_position(hip_i, rest + Vector3(0, -0.0048 * b, 0.0008 * b))
	if sliding:
		_bone_rot(sk, "Torso", Vector3(-0.35 * b, 0, 0))
		_bone_rot(sk, "Abdomen", Vector3(-0.15 * b, 0, 0))
		_bone_rot(sk, "UpperLeg.L", Vector3(-0.2 * b, 0, 0.1))
		_bone_rot(sk, "UpperLeg.R", Vector3(-1.25 * b, 0, -0.1))
		_bone_rot(sk, "LowerLeg.L", Vector3(0.3 * b, 0, 0))
		_bone_rot(sk, "LowerLeg.R", Vector3(1.5 * b, 0, 0))
	else:
		_bone_rot(sk, "Torso", Vector3(0.25 * b, 0, 0))
		_bone_rot(sk, "Abdomen", Vector3(0.12 * b, 0, 0))
		_bone_rot(sk, "UpperLeg.L", Vector3((-1.05 + stride) * b, 0, 0.22 * b))
		_bone_rot(sk, "UpperLeg.R", Vector3((-1.05 - stride) * b, 0, -0.22 * b))
		_bone_rot(sk, "LowerLeg.L", Vector3((1.55 - stride * 0.4) * b, 0, 0))
		_bone_rot(sk, "LowerLeg.R", Vector3((1.55 + stride * 0.4) * b, 0, 0))
	# Keep locomotion anim from fighting hard — hold idle while crouched standing still
	if char_model != null and _speed < 0.35 and not sliding:
		char_model.play("idle", 0.0)


func refresh_rank_sprite() -> void:
	if rank_sprite != null:
		rank_sprite.texture = Game.rank_icon(Game.peer_rank(peer_id))
