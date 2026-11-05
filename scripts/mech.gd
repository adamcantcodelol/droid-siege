## AT-RT style walker: one low-poly box mesh set (~14 parts, no textures, no particles).
## Used both for the parked mech in the world and as the pilot's body while driving.

static var _mats := {}


static func _mat(c: Color) -> StandardMaterial3D:
	if not _mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.7
		_mats[c] = m
	return _mats[c]


static func _part(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(c)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func build() -> Node3D:
	var root := Node3D.new()
	var hull := Color(0.62, 0.6, 0.55)
	var dark := Color(0.25, 0.25, 0.28)
	var red := Color(0.7, 0.2, 0.15)
	for s in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "Leg" + ("L" if s < 0 else "R")
		leg.position = Vector3(0.55 * s, 2.3, 0)
		root.add_child(leg)
		_part(leg, Vector3(0.35, 1.3, 0.4), Vector3(0, -0.55, 0.25), hull, Vector3(-0.35, 0, 0))   # thigh
		_part(leg, Vector3(0.28, 1.2, 0.3), Vector3(0, -1.55, 0.1), dark, Vector3(0.3, 0, 0))      # shin
		_part(leg, Vector3(0.6, 0.15, 0.9), Vector3(0, -2.2, -0.05), dark)                          # foot
	_part(root, Vector3(1.5, 0.45, 1.1), Vector3(0, 2.45, 0), dark)                 # hip block
	_part(root, Vector3(1.7, 1.1, 1.9), Vector3(0, 3.2, -0.1), hull)                # cockpit
	_part(root, Vector3(1.3, 0.45, 0.6), Vector3(0, 3.35, -1.15), hull)             # nose
	_part(root, Vector3(1.2, 0.18, 0.05), Vector3(0, 3.45, -1.46), Color(0.1, 0.12, 0.15))  # viewport
	_part(root, Vector3(1.75, 0.12, 1.95), Vector3(0, 3.8, -0.1), red)              # roof stripe
	for s in [-1.0, 1.0]:
		_part(root, Vector3(0.22, 0.22, 1.3), Vector3(1.0 * s, 3.0, -0.9), dark)    # chin cannons
	var muz := Node3D.new()
	muz.name = "Muzzle"
	muz.position = Vector3(1.0, 3.0, -1.6)
	root.add_child(muz)
	return root


## cheap walk cycle: swing the two leg pivots
static func animate(root: Node3D, t: float, amount: float) -> void:
	var l := root.get_node_or_null("LegL")
	var r := root.get_node_or_null("LegR")
	if l == null:
		return
	var sw := sin(t * 5.0) * 0.35 * amount
	l.rotation.x = sw
	r.rotation.x = -sw
	root.position.y = absf(sin(t * 5.0)) * 0.08 * amount
