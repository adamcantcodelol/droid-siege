## AT-RT style scout walker, built from ~30 low-poly primitives (no textures, no particles).
## Used for the parked walker and as the pilot's body. Root faces -Z.

## Vehicles: AT-RT walker, BARC speeder, TX-130 tank, ISP swamp speeder.
## build(vtype) returns a Node3D visual. Stats live in VEHICLES[].

const VEHICLES := [
	{"name": "AT-RT Walker", "hp": 220.0, "speed": 9.5, "boost": 13.5, "dmg": 1.45, "interval": 0.38,
		"heat_max": 1.0, "heat_rate": 0.22, "heat_cool": 0.55, "cam_y": 5.0, "cam_x": 1.4, "size": Vector3(1.6, 3.0, 1.8), "col_y": 2.1},
	{"name": "BARC Speeder", "hp": 130.0, "speed": 17.5, "boost": 24.0, "dmg": 0.85, "interval": 0.17,
		"heat_max": 1.0, "heat_rate": 0.12, "heat_cool": 0.7, "cam_y": 2.4, "cam_x": 1.0, "size": Vector3(1.2, 1.2, 2.4), "col_y": 0.9},
	{"name": "TX-130 Saber Tank", "hp": 320.0, "speed": 9.8, "boost": 13.5, "dmg": 1.6, "interval": 0.48,
		"heat_max": 1.0, "heat_rate": 0.18, "heat_cool": 0.5, "shell_cd": 6.0, "shell_dmg": 45.0, "shell_r": 4.5,
		"cam_y": 4.2, "cam_x": 1.6, "size": Vector3(2.8, 2.2, 3.6), "col_y": 1.3},
	{"name": "ISP Swamp Speeder", "hp": 200.0, "speed": 13.5, "boost": 18.5, "dmg": 1.05, "interval": 0.22,
		"heat_max": 1.0, "heat_rate": 0.14, "heat_cool": 0.65, "cam_y": 3.2, "cam_x": 1.3, "size": Vector3(2.4, 1.6, 3.0), "col_y": 1.0},
]

static func stats(vtype: int) -> Dictionary:
	return VEHICLES[clampi(vtype, 0, VEHICLES.size() - 1)]


static func build_type(vtype: int) -> Node3D:
	var root: Node3D
	match clampi(vtype, 0, 3):
		1: root = _build_barc()
		2: root = _build_tank()
		3: root = _build_isp()
		_: root = build()  # AT-RT
	merge_meshes(root)
	return root


## Perf: vehicles are built from 30-60 primitives. Within every node, fold the unnamed static
## MeshInstance3D children that share a material into one mesh (animated sub-nodes like legs,
## guns and named parts such as muzzle flashes keep their own transforms). ~5x fewer draw calls.
static func merge_meshes(node: Node) -> void:
	var groups := {}
	for c in node.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("@") and c.get_child_count() == 0 and c.visible:
			var mi := c as MeshInstance3D
			var m: Material = mi.material_override
			if m == null or mi.mesh == null:
				continue
			if not groups.has(m):
				groups[m] = []
			groups[m].append(mi)
	for m in groups:
		var list: Array = groups[m]
		if list.size() < 2:
			continue
		var st := SurfaceTool.new()
		for mi in list:
			for si in mi.mesh.get_surface_count():
				st.append_from(mi.mesh, si, mi.transform)
			node.remove_child(mi)
			mi.queue_free()
		var out := MeshInstance3D.new()
		out.mesh = st.commit()
		out.material_override = m
		node.add_child(out)
	for c in node.get_children():
		if not (c is MeshInstance3D):
			merge_meshes(c)


static func animate_type(root: Node3D, vtype: int, t: float, amount: float, lean := 0.0) -> void:
	match clampi(vtype, 0, 3):
		1, 3:
			var body := root.get_node_or_null("Body")
			if body != null:
				body.position.y = 0.05 + sin(t * 6.0) * 0.04 * (0.4 + amount)
				body.rotation.z = lerpf(body.rotation.z, clampf(-lean * 0.06, -0.28, 0.28), 0.2)
				body.rotation.x = lerpf(body.rotation.x, -0.04 * amount, 0.12)
		2:
			var body2 := root.get_node_or_null("Body")
			if body2 != null:
				body2.position.y = sin(t * 3.0) * 0.02 * amount
				body2.rotation.z = lerpf(body2.rotation.z, clampf(-lean * 0.03, -0.1, 0.1), 0.12)
		_:
			animate(root, t, amount, lean)


static func flash_type(root: Node3D, vtype: int, on: bool) -> void:
	flash(root, on)  # shared Flash node path Body/Gun/Muzzle/Flash when present
	var f2 := root.get_node_or_null("Body/Gun2/Muzzle/Flash")
	if f2 != null:
		f2.visible = on


static func _build_barc() -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var hull := Color(0.82, 0.82, 0.78)
	var dark := Color(0.18, 0.18, 0.2)
	var red := Color(0.7, 0.15, 0.12)
	_add(body, _box(Vector3(0.55, 0.35, 2.1)), Vector3(0, 0.85, 0), hull)
	_add(body, _prism(Vector3(0.5, 0.35, 0.7)), Vector3(0, 0.85, -1.25), hull, Vector3(-PI / 2, 0, 0))
	_add(body, _box(Vector3(0.2, 0.45, 0.55)), Vector3(0, 1.15, 0.35), dark)  # seat
	_add(body, _cyl(0.04, 0.7, 6), Vector3(0.22, 1.25, -0.55), dark, Vector3(0.8, 0, 0))
	_add(body, _cyl(0.04, 0.7, 6), Vector3(-0.22, 1.25, -0.55), dark, Vector3(0.8, 0, 0))
	for s in [-1.0, 1.0]:
		_add(body, _box(Vector3(0.08, 0.25, 0.9)), Vector3(0.42 * s, 0.75, 0.1), red)
		_add(body, _cyl(0.12, 0.35, 8), Vector3(0.55 * s, 0.55, 0.6), dark, Vector3(0, 0, PI / 2))  # thruster
	# v1.2 detail: engine glows, handlebars, side fairings, headlamp
	for s in [-1.0, 1.0]:
		_add(body, _cyl(0.08, 0.05, 8), Vector3(0.55 * s, 0.55, 0.79), Color(0.45, 0.75, 1.0), Vector3(PI / 2, 0, 0), true)
		_add(body, _box(Vector3(0.1, 0.3, 1.2)), Vector3(0.32 * s, 0.95, -0.55), hull, Vector3(0, 0.12 * s, 0))
		_add(body, _box(Vector3(0.35, 0.05, 0.05)), Vector3(0.32 * s, 1.55, -0.9), dark)
	_add(body, _box(Vector3(0.18, 0.1, 0.05)), Vector3(0, 0.92, -1.55), Color(1.0, 0.95, 0.7), Vector3.ZERO, true)
	_add(body, _box(Vector3(0.5, 0.06, 1.2)), Vector3(0, 1.04, -0.5), red)
	var gun := Node3D.new()
	gun.name = "Gun"
	gun.position = Vector3(0, 0.7, -1.35)
	body.add_child(gun)
	_add(gun, _cyl(0.05, 0.9, 8), Vector3(0.12, 0, -0.2), dark, Vector3(PI / 2, 0, 0))
	_add(gun, _cyl(0.05, 0.9, 8), Vector3(-0.12, 0, -0.2), dark, Vector3(PI / 2, 0, 0))
	var muz := Node3D.new()
	muz.name = "Muzzle"
	muz.position = Vector3(0, 0, -0.8)
	gun.add_child(muz)
	var flash := _add(muz, SphereMesh.new(), Vector3.ZERO, Color(1.0, 0.75, 0.3), Vector3.ZERO, true)
	flash.name = "Flash"
	flash.scale = Vector3(0.25, 0.25, 0.45)
	flash.visible = false
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


static func _build_tank() -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var hull := Color(0.72, 0.7, 0.65)
	var dark := Color(0.2, 0.2, 0.22)
	var red := Color(0.65, 0.14, 0.1)
	_add(body, _box(Vector3(2.6, 0.9, 3.4)), Vector3(0, 1.0, 0), hull)
	_add(body, _prism(Vector3(2.4, 0.7, 1.2)), Vector3(0, 1.15, -1.9), hull, Vector3(-PI / 2, 0, 0))
	_add(body, _box(Vector3(1.6, 0.55, 1.8)), Vector3(0, 1.7, 0.2), dark)  # turret
	_add(body, _box(Vector3(2.4, 0.12, 0.2)), Vector3(0, 1.5, 0), red)
	for s in [-1.0, 1.0]:
		_add(body, _box(Vector3(0.35, 0.55, 2.8)), Vector3(1.35 * s, 0.55, 0), dark)
		_add(body, _box(Vector3(0.25, 0.3, 0.8)), Vector3(1.2 * s, 1.35, -0.4), dark)
		# v1.2 detail: side sponsons with tapered noses, rear engines, repulsor glow strips
		_add(body, _box(Vector3(0.6, 0.5, 3.0)), Vector3(1.6 * s, 0.95, 0.3), hull)
		_add(body, _prism(Vector3(0.6, 0.5, 0.8)), Vector3(1.6 * s, 0.95, -1.6), hull, Vector3(-PI / 2, 0, 0))
		_add(body, _box(Vector3(0.62, 0.1, 2.0)), Vector3(1.6 * s, 1.15, 0.3), red)
		_add(body, _cyl(0.28, 0.7, 10), Vector3(0.75 * s, 1.05, 1.95), dark, Vector3(PI / 2, 0, 0))
		_add(body, _cyl(0.2, 0.05, 10), Vector3(0.75 * s, 1.05, 2.31), Color(0.45, 0.75, 1.0), Vector3(PI / 2, 0, 0), true)
		_add(body, _box(Vector3(0.12, 0.06, 2.6)), Vector3(1.0 * s, 0.52, 0), Color(0.45, 0.75, 1.0), Vector3.ZERO, true)
		_add(body, _box(Vector3(0.4, 0.06, 0.4)), Vector3(0.5 * s, 1.98, 0.7), dark)   # hatch bolts
	_add(body, _box(Vector3(1.0, 0.28, 0.5)), Vector3(0, 1.9, -0.55), Color(0.12, 0.22, 0.32))   # canopy glass
	_add(body, _box(Vector3(1.7, 0.08, 1.9)), Vector3(0, 1.99, 0.2), hull)                      # turret roof plate
	_add(body, _cyl(0.025, 1.2, 4), Vector3(-0.6, 2.5, 0.9), dark)                               # antenna
	_add(body, _box(Vector3(2.2, 0.35, 0.3)), Vector3(0, 0.75, -1.85), dark)                     # front skirt
	var gun := Node3D.new()
	gun.name = "Gun"
	gun.position = Vector3(0, 1.75, -1.0)
	body.add_child(gun)
	_add(gun, _cyl(0.1, 1.6, 8), Vector3(0.25, 0, -0.5), dark, Vector3(PI / 2, 0, 0))
	_add(gun, _cyl(0.1, 1.6, 8), Vector3(-0.25, 0, -0.5), dark, Vector3(PI / 2, 0, 0))
	var muz := Node3D.new()
	muz.name = "Muzzle"
	muz.position = Vector3(0, 0, -1.5)
	gun.add_child(muz)
	var flash := _add(muz, SphereMesh.new(), Vector3.ZERO, Color(1.0, 0.7, 0.25), Vector3.ZERO, true)
	flash.name = "Flash"
	flash.scale = Vector3(0.4, 0.4, 0.7)
	flash.visible = false
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


static func _build_isp() -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var hull := Color(0.78, 0.76, 0.7)
	var dark := Color(0.2, 0.22, 0.25)
	var teal := Color(0.2, 0.55, 0.55)
	_add(body, _box(Vector3(2.2, 0.55, 2.8)), Vector3(0, 0.9, 0), hull)
	_add(body, _box(Vector3(1.4, 0.45, 1.2)), Vector3(0, 1.35, 0.3), dark)
	for s in [-1.0, 1.0]:
		_add(body, _cyl(0.35, 1.4, 10), Vector3(1.15 * s, 0.7, 0.2), teal, Vector3(0, 0, PI / 2))
		_add(body, _box(Vector3(0.2, 0.35, 1.0)), Vector3(0.9 * s, 1.2, -0.8), dark)
		# v1.2 detail: big rear fan housings with glowing intakes, nose fins
		_add(body, _cyl(0.45, 0.5, 12), Vector3(0.65 * s, 1.2, 1.55), dark, Vector3(PI / 2, 0, 0))
		_add(body, _cyl(0.36, 0.05, 12), Vector3(0.65 * s, 1.2, 1.82), Color(0.45, 0.9, 0.9), Vector3(PI / 2, 0, 0), true)
		_add(body, _box(Vector3(0.08, 0.4, 0.8)), Vector3(1.05 * s, 1.1, -1.25), teal)
	_add(body, _box(Vector3(1.2, 0.4, 0.08)), Vector3(0, 1.75, -0.32), Color(0.12, 0.22, 0.32), Vector3(-0.5, 0, 0))   # windshield
	_add(body, _prism(Vector3(2.0, 0.4, 0.7)), Vector3(0, 0.9, -1.75), hull, Vector3(-PI / 2, 0, 0))                   # nose wedge
	_add(body, _box(Vector3(2.25, 0.08, 0.3)), Vector3(0, 1.18, -0.2), teal)
	var gun := Node3D.new()
	gun.name = "Gun"
	gun.position = Vector3(0.7, 1.1, -1.3)
	body.add_child(gun)
	_add(gun, _box(Vector3(0.25, 0.2, 0.7)), Vector3.ZERO, dark)
	var muz := Node3D.new()
	muz.name = "Muzzle"
	muz.position = Vector3(0, 0, -0.55)
	gun.add_child(muz)
	var flash := _add(muz, SphereMesh.new(), Vector3.ZERO, Color(1.0, 0.8, 0.4), Vector3.ZERO, true)
	flash.name = "Flash"
	flash.scale = Vector3(0.3, 0.3, 0.5)
	flash.visible = false
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gun2 := Node3D.new()
	gun2.name = "Gun2"
	gun2.position = Vector3(-0.7, 1.1, -1.3)
	body.add_child(gun2)
	_add(gun2, _box(Vector3(0.25, 0.2, 0.7)), Vector3.ZERO, dark)
	var muz2 := Node3D.new()
	muz2.name = "Muzzle"
	muz2.position = Vector3(0, 0, -0.55)
	gun2.add_child(muz2)
	var flash2 := _add(muz2, SphereMesh.new(), Vector3.ZERO, Color(1.0, 0.8, 0.4), Vector3.ZERO, true)
	flash2.name = "Flash"
	flash2.scale = Vector3(0.3, 0.3, 0.5)
	flash2.visible = false
	flash2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


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
