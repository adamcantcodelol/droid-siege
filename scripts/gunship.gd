## Low-poly LAAT/i style republic gunship built from primitives (no textures). Nose faces -Z.
## Static parts are merged per material (mech.gd merge_meshes), so the whole ship is ~10 draw calls.
## Animated nodes: "TurretL"/"TurretR" (door guns, swivel), "Doors" (bay doors, slide open).
extends RefCounted

const MechVisual := preload("res://scripts/mech.gd")


static var _root: Node3D


static func _p(mesh: Mesh, pos: Vector3, c: Color, rot := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	return MechVisual._add(parent if parent != null else _root, mesh, pos, c, rot, c == Color(0.4, 0.7, 1.0))


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "LAAT"
	var hull := Color(0.86, 0.86, 0.8)
	var green := Color(0.42, 0.5, 0.33)
	var red := Color(0.62, 0.12, 0.1)
	var dark := Color(0.14, 0.15, 0.17)
	var glass := Color(0.12, 0.22, 0.32)
	_root = root
	# --- fuselage: troop bay, tapered nose, raised cockpit, tail boom
	_p(MechVisual._box(Vector3(3.4, 2.6, 7.0)), Vector3(0, 0, 0.5), hull)
	_p(MechVisual._box(Vector3(3.0, 0.5, 7.4)), Vector3(0, -1.45, 0.5), dark)            # belly
	_p(MechVisual._prism(Vector3(3.4, 2.2, 3.2)), Vector3(0, -0.2, -4.6), hull, Vector3(-PI / 2, 0, 0))
	_p(MechVisual._box(Vector3(2.2, 1.4, 2.6)), Vector3(0, 1.4, -3.0), hull)             # cockpit block
	_p(MechVisual._box(Vector3(1.9, 0.7, 0.2)), Vector3(0, 1.55, -4.32), glass)           # front glass
	for s in [-1.0, 1.0]:
		_p(MechVisual._box(Vector3(0.2, 0.6, 1.6)), Vector3(1.11 * s, 1.5, -3.2), glass)   # side glass
		_p(MechVisual._box(Vector3(0.6, 0.6, 0.6)), Vector3(1.0 * s, -0.6, -5.4), glass)  # nose bubbles
	_p(MechVisual._box(Vector3(1.6, 1.6, 4.5)), Vector3(0, 0.5, 6.0), hull)              # tail boom
	_p(MechVisual._box(Vector3(0.3, 3.0, 2.4)), Vector3(0, 2.3, 7.4), hull, Vector3(-0.35, 0, 0))  # fin
	_p(MechVisual._box(Vector3(0.32, 1.0, 1.0)), Vector3(0, 3.3, 7.9), red, Vector3(-0.35, 0, 0))
	_p(MechVisual._box(Vector3(5.0, 0.2, 1.4)), Vector3(0, 1.1, 8.0), hull)              # tail plane
	# --- clone markings: green stripes + red nose band
	_p(MechVisual._box(Vector3(3.45, 0.35, 7.05)), Vector3(0, 0.75, 0.5), green)
	_p(MechVisual._box(Vector3(2.25, 0.3, 2.65)), Vector3(0, 1.9, -3.0), red)
	_p(MechVisual._box(Vector3(1.65, 0.3, 4.55)), Vector3(0, 0.9, 6.0), green)
	# --- swept wings with wingtip ball turrets and engine pods
	for s in [-1.0, 1.0]:
		_p(MechVisual._box(Vector3(5.6, 0.35, 2.6)), Vector3(4.3 * s, 1.35, 0.6), hull, Vector3(0, -0.22 * s, 0))
		_p(MechVisual._box(Vector3(5.0, 0.38, 0.6)), Vector3(4.3 * s, 1.38, -0.4), green, Vector3(0, -0.22 * s, 0))
		var tip := Vector3(7.0 * s, 1.35, 1.6)
		var ball := SphereMesh.new()
		ball.radius = 0.55
		ball.height = 1.1
		ball.radial_segments = 10
		ball.rings = 5
		_p(ball, tip, hull)
		_p(MechVisual._cyl(0.08, 1.2, 6), tip + Vector3(0, 0, -0.9), dark, Vector3(PI / 2, 0, 0))
		_p(MechVisual._cyl(0.45, 2.6, 10), Vector3(2.0 * s, 1.9, 3.6), dark, Vector3(PI / 2, 0, 0))    # engine pod
		_p(MechVisual._cyl(0.3, 0.2, 10), Vector3(2.0 * s, 1.9, 4.95), Color(0.4, 0.7, 1.0), Vector3(PI / 2, 0, 0))
		# mass-driver missile racks on the wing roots
		_p(MechVisual._box(Vector3(0.7, 0.4, 1.4)), Vector3(2.4 * s, 0.95, -0.4), dark)
		# rear landing skids
		_p(MechVisual._box(Vector3(0.25, 1.2, 0.25)), Vector3(1.3 * s, -2.0, -1.5), dark)
		_p(MechVisual._box(Vector3(0.25, 1.2, 0.25)), Vector3(1.3 * s, -2.0, 2.5), dark)
		_p(MechVisual._box(Vector3(0.35, 0.15, 4.6)), Vector3(1.3 * s, -2.6, 0.5), dark)
	# --- open troop bay: dark interior visible through the side doors
	_p(MechVisual._box(Vector3(3.42, 1.7, 3.4)), Vector3(0, -0.35, 0.6), Color(0.08, 0.08, 0.09))
	var doors := Node3D.new()
	doors.name = "Doors"
	root.add_child(doors)
	for s in [-1.0, 1.0]:
		_p(MechVisual._box(Vector3(0.12, 1.75, 3.5)), Vector3(1.78 * s, -0.35, 0.6), hull, Vector3.ZERO, doors)
	# --- door gun turrets (swivel)
	for s in [-1.0, 1.0]:
		var tur := Node3D.new()
		tur.name = "TurretL" if s < 0 else "TurretR"
		tur.position = Vector3(1.6 * s, 0.2, -0.6)
		root.add_child(tur)
		_p(MechVisual._box(Vector3(0.4, 0.4, 0.5)), Vector3.ZERO, dark, Vector3.ZERO, tur)
		_p(MechVisual._cyl(0.06, 1.3, 6), Vector3(0.0, 0.05, -0.7), dark, Vector3(PI / 2, 0, 0), tur)
	MechVisual.merge_meshes(root)
	return root


## Open (1) / close (0) the side bay doors: they slide back along the hull.
static func set_doors(root: Node3D, open_amt: float) -> void:
	var d := root.get_node_or_null("Doors")
	if d != null:
		d.position.z = 3.2 * clampf(open_amt, 0.0, 1.0)


## Point both door guns at a world position.
static func aim_turrets(root: Node3D, target: Vector3) -> void:
	for n in ["TurretL", "TurretR"]:
		var t := root.get_node_or_null(n) as Node3D
		if t != null and t.global_position.distance_to(target) > 1.0:
			t.look_at(target, Vector3.UP)
