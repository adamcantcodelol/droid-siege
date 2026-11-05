## AT-RT style scout walker, built from ~30 low-poly primitives (no textures, no particles).
## Used for the parked walker and as the pilot's body. Root faces -Z.

static var _mats := {}


static func _mat(c: Color, emit := false) -> StandardMaterial3D:
	var key := str(c) + str(emit)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.6
		m.metallic = 0.15
		if emit:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 3.0
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mats[key] = m
	return _mats[key]


static func _add(parent: Node3D, mesh: Mesh, pos: Vector3, c: Color, rot := Vector3.ZERO, emit := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c, emit)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


static func _cyl(r: float, h: float, seg := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _prism(s: Vector3) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = s
	return p


static func build() -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()      # leans/bobs; legs stay planted under it
	body.name = "Body"
	root.add_child(body)
	var hull := Color(0.78, 0.76, 0.7)
	var panel := Color(0.62, 0.6, 0.55)
	var dark := Color(0.22, 0.22, 0.25)
	var red := Color(0.72, 0.18, 0.12)
	# hip drum + saddle
	_add(body, _cyl(0.38, 1.3, 10), Vector3(0, 2.55, 0.15), dark, Vector3(0, 0, PI / 2))
	_add(body, _box(Vector3(0.9, 0.5, 1.2)), Vector3(0, 2.95, 0.2), panel)
	# armoured cockpit: main hull, angled nose (prism), sloped roof, red stripe
	_add(body, _box(Vector3(1.25, 0.8, 1.5)), Vector3(0, 3.35, -0.2), hull)
	_add(body, _prism(Vector3(1.25, 0.8, 0.9)), Vector3(0, 3.35, -1.28), hull, Vector3(-PI / 2, 0, 0))
	_add(body, _box(Vector3(1.1, 0.12, 1.2)), Vector3(0, 3.8, -0.05), red, Vector3(0.12, 0, 0))
	_add(body, _box(Vector3(0.9, 0.16, 0.06)), Vector3(0, 3.5, -1.02), Color(0.08, 0.1, 0.12), Vector3(-0.5, 0, 0))   # viewport slit
	# side saddlebars / handlebars and side armour
	for s in [-1.0, 1.0]:
		_add(body, _box(Vector3(0.1, 0.55, 1.3)), Vector3(0.68 * s, 3.25, -0.2), panel)
		_add(body, _cyl(0.04, 0.9, 6), Vector3(0.55 * s, 3.95, -0.6), dark, Vector3(PI / 2, 0, 0))
		_add(body, _cyl(0.035, 0.35, 6), Vector3(0.55 * s, 3.85, -1.05), dark)
		_add(body, _box(Vector3(0.22, 0.32, 0.5)), Vector3(0.8 * s, 2.85, 0.45), dark)        # saddle bags
	# chin-mounted heavy repeating cannon
	var gun := Node3D.new()
	gun.name = "Gun"
	gun.position = Vector3(0, 2.95, -1.0)
	body.add_child(gun)
	_add(gun, _box(Vector3(0.36, 0.3, 0.5)), Vector3(0, 0, 0), dark)
	for s in [-1.0, 1.0]:
		_add(gun, _cyl(0.06, 1.1, 8), Vector3(0.09 * s, 0, -0.75), dark, Vector3(PI / 2, 0, 0))
	_add(gun, _cyl(0.1, 0.2, 8), Vector3(0, 0, -1.25), Color(0.3, 0.3, 0.33), Vector3(PI / 2, 0, 0))
	var muz := Node3D.new()
	muz.name = "Muzzle"
	muz.position = Vector3(0, 0, -1.4)
	gun.add_child(muz)
	var flash := _add(muz, SphereMesh.new(), Vector3.ZERO, Color(1.0, 0.75, 0.3), Vector3.ZERO, true)
	flash.name = "Flash"
	flash.scale = Vector3(0.35, 0.35, 0.6)
	flash.visible = false
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# reverse-jointed legs: hip -> thigh (forward/down) -> knee -> shin (back/down) -> foot
	for s in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.name = "Hip" + ("L" if s < 0 else "R")
		hip.position = Vector3(0.62 * s, 2.55, 0.15)
		root.add_child(hip)
		_add(hip, _cyl(0.22, 0.2, 8), Vector3.ZERO, red, Vector3(0, 0, PI / 2))
		_add(hip, _box(Vector3(0.24, 1.2, 0.32)), Vector3(0, -0.5, -0.3), hull, Vector3(-0.55, 0, 0))
		var knee := Node3D.new()
		knee.name = "Knee"
		knee.position = Vector3(0, -1.0, -0.6)
		hip.add_child(knee)
		_add(knee, _cyl(0.15, 0.3, 8), Vector3.ZERO, dark, Vector3(0, 0, PI / 2))
		_add(knee, _box(Vector3(0.18, 1.3, 0.22)), Vector3(0, -0.6, 0.3), panel, Vector3(0.45, 0, 0))
		var ankle := Node3D.new()
		ankle.name = "Ankle"
		ankle.position = Vector3(0, -1.2, 0.58)
		knee.add_child(ankle)
		_add(ankle, _box(Vector3(0.42, 0.12, 0.8)), Vector3(0, -0.28, -0.18), dark)   # foot
		_add(ankle, _box(Vector3(0.3, 0.1, 0.25)), Vector3(0, -0.28, 0.32), dark)     # heel spur
	return root


## Articulated stride + turn lean. amount 0..1 = speed fraction, lean = turn rate (rad/s)
static func animate(root: Node3D, t: float, amount: float, lean := 0.0) -> void:
	var body := root.get_node_or_null("Body")
	if body == null:
		return
	var ph := t * 5.5
	for i in 2:
		var hip: Node3D = root.get_node("HipL" if i == 0 else "HipR")
		var sw := sin(ph + PI * i)
		hip.rotation.x = sw * 0.45 * amount
		var knee: Node3D = hip.get_node("Knee")
		knee.rotation.x = -maxf(0.0, cos(ph + PI * i)) * 0.5 * amount     # lift on the forward swing
		knee.get_node("Ankle").rotation.x = -hip.rotation.x - knee.rotation.x   # keep feet flat
	body.position.y = absf(sin(ph)) * 0.09 * amount
	body.rotation.z = lerpf(body.rotation.z, clampf(-lean * 0.08, -0.15, 0.15), 0.15)
	body.rotation.x = lerpf(body.rotation.x, -0.05 * amount, 0.1)


static func flash(root: Node3D, on: bool) -> void:
	var f := root.get_node_or_null("Body/Gun/Muzzle/Flash")
	if f != null:
		f.visible = on
		f.rotation.z = randf() * TAU
