## Hand-designed levels built from CC0 model kits (see CREDITS.md).
## Repeated props are batched into one MultiMeshInstance3D per (model, sub-mesh, tint) so a map
## with hundreds of rocks/fungi costs a handful of draw calls. Collision uses cheap primitive
## shapes (boxes/cylinders) which the navmesh baker also reads.
extends RefCounted

var w: Node            # the world node
var parent: Node3D     # nav region: everything with collision goes here
var deco: Node3D       # visual-only batches
var _model_cache := {}
var _batches := {}     # key -> {"parts": Array, "xforms": Array}
var _mats := {}
var spawn_points: Array = []   # droid entry points (server picks from these)
var occluders := 0
var rooms: Array = []          # interior centres of enterable buildings (mapcheck reachability)
var lava_rects: Array = []     # Rect2 (x, z) of burning lava
var safe_rects: Array = []     # Rect2 bridges over lava
var sun: DirectionalLight3D
var env: Environment
const SMALL := ["plant", "crate", "barrel", "light_floor", "sack_trench", "rock"]
const CHUNK := 48.0
## Graphics preset at build time: 0 Low, 1 Medium, 2 High. Only visual-only dressing depends on it;
## anything with collision is identical on every peer.
var q := 1
var _low_skip := 0
var decks: Array = []          # v1.3: tops of hills/platforms (mapcheck: must be reachable on foot)
const KEEP_LOW := ["mountain_group", "gunship", "antenna", "turret_cannon", "landing_pad", "base", "container_structure"]


func _init(world: Node, region: Node3D) -> void:
	w = world
	parent = region
	deco = Node3D.new()
	deco.name = "Props"
	world.add_child(deco)
	q = Game.quality()


# ------------------------------------------------------------------ primitives
func mat(c: Color, rough: float = 0.9, emit: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [c.to_html(), rough, emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if c.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m


## Solid box (visual + collision). rot is Euler radians.
func box(pos: Vector3, size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO, visible := true, occlude := false) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	# Layer 8 = "camera blocker": only big solids stop the third-person camera. Thin props
	# (flag poles, crates, barrels) must not, or the camera collapses into the trooper's head.
	if minf(size.x, size.z) >= 0.5 and size.y >= 1.5 and maxf(size.x, size.z) >= 2.5:
		b.collision_layer = 1 | 8
	b.collision_mask = 0
	if visible:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat(color)
		mi.mesh = bm
		b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	b.position = pos
	b.rotation = rot
	parent.add_child(b)
	if occlude and minf(size.x, minf(size.y, size.z)) > 1.5:
		var oi := OccluderInstance3D.new()
		var bo := BoxOccluder3D.new()
		bo.size = size * 0.95
		oi.occluder = bo
		b.add_child(oi)
		occluders += 1
	return b


func cyl(pos: Vector3, r_bottom: float, r_top: float, h: float, color: Color, visible := true, sides := 12) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1 | 8 if maxf(r_bottom, r_top) >= 1.2 else 1
	b.collision_mask = 0
	if visible:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.bottom_radius = r_bottom
		cm.top_radius = r_top
		cm.height = h
		cm.radial_segments = sides
		cm.rings = 1
		cm.material = mat(color)
		mi.mesh = cm
		b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = maxf(r_bottom, r_top)
	sh.height = h
	cs.shape = sh
	b.add_child(cs)
	b.position = pos + Vector3(0, h / 2.0, 0)
	parent.add_child(b)
	return b


## Walkable ramp from a (low end, on the floor) to b (high end, on top surface).
func ramp(a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var run := flat.length()
	var rise := b.y - a.y
	var length := sqrt(run * run + rise * rise)
	var yaw := atan2(-flat.x, -flat.y)
	var pitch := atan2(rise, run)
	var center := (a + b) / 2.0
	var thick := 0.6
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var off := basis * Vector3(0, -thick / 2.0, 0)
	var body := box(center + off, Vector3(width, thick, length), color)
	body.collision_layer = 1 | 8
	body.transform.basis = basis


## Decorative flat disc (no collision): pads, ponds, decals.
func disc(pos: Vector3, radius: float, color: Color, emit := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.04
	cm.radial_segments = 24
	cm.rings = 1
	cm.material = mat(color, 0.15, emit)
	mi.mesh = cm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deco.add_child(mi)
	return mi


func light(pos: Vector3, color: Color, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	l.position = pos
	l.distance_fade_enabled = true
	l.distance_fade_begin = 60.0
	l.distance_fade_length = 10.0
	l.add_to_group("map_light")
	deco.add_child(l)


# ------------------------------------------------------------------ model kit props
func _model(name: String) -> Dictionary:
	if _model_cache.has(name):
		return _model_cache[name]
	var ps: PackedScene = load("res://models/%s.glb" % name)
	var inst := ps.instantiate()
	var parts := []
	var aabb := AABB()
	var first := true
	var stack := [[inst, Transform3D.IDENTITY]]
	while stack.size() > 0:
		var it = stack.pop_back()
		var n: Node = it[0]
		var xf: Transform3D = it[1]
		if n is Node3D and n != inst:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mesh: Mesh = (n as MeshInstance3D).mesh
			parts.append({"mesh": mesh, "xf": xf})
			var a: AABB = xf * mesh.get_aabb()
			aabb = a if first else aabb.merge(a)
			first = false
		for c in n.get_children():
			stack.append([c, xf])
	inst.free()
	var d := {"parts": parts, "aabb": aabb}
	_model_cache[name] = d
	return d


## Place a kit model. collide: "box" (rotated AABB), "cyl" (trunk/stem: radius frac of width), "none".
## size: target height in metres (model is uniformly scaled), or <=0 to use scale param.
func prop(name: String, pos: Vector3, yaw: float = 0.0, height: float = 0.0, collide := "box", tint := Color.WHITE, scale_mul := 1.0, col_frac := 0.25) -> void:
	var md := _model(name)
	var aabb: AABB = md["aabb"]
	var s := scale_mul
	if height > 0.0 and aabb.size.y > 0.001:
		s = height / aabb.size.y
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
	# sit the model's bottom on pos.y
	var c0 := aabb.get_center()
	var xf := Transform3D(basis, pos - basis * Vector3(c0.x, aabb.position.y, c0.z))
	if collide == "none" and q == 0 and not (name in KEEP_LOW):
		_low_skip += 1
		if _low_skip % 2 == 1:
			return   # Low: half the purely decorative props
	var ch := CHUNK * (2.0 if q == 0 else 1.0)   # Low: bigger batches = fewer draw calls
	var cell := Vector2i(floori(pos.x / ch), floori(pos.z / ch))
	var key := name + "|" + tint.to_html() + "|" + str(cell)
	if not _batches.has(key):
		_batches[key] = {"name": name, "tint": tint, "xforms": []}
	_batches[key]["xforms"].append(xf)
	if collide == "none":
		return
	var sz := aabb.size * s
	var ctr := xf * aabb.get_center()
	if collide == "cyl":
		var r := maxf(0.25, minf(sz.x, sz.z) * col_frac)
		cyl(Vector3(ctr.x, pos.y, ctr.z), r, r, sz.y, Color.WHITE, false)
	else:
		var b := box(ctr, sz * Vector3(0.9, 1.0, 0.9), Color.WHITE, Vector3(0, yaw, 0), false)
		b.name = "C_" + name


## Build MultiMesh batches. Call once after all props were placed.
func flush(vis_end: float = 0.0) -> void:
	for key in _batches:
		var bt: Dictionary = _batches[key]
		var md := _model(bt["name"])
		var tint: Color = bt["tint"]
		for part in md["parts"]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part["mesh"]
			mm.instance_count = bt["xforms"].size()
			for i in bt["xforms"].size():
				mm.set_instance_transform(i, bt["xforms"][i] * part["xf"])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.name = ("MM_small_" if bt["name"] in SMALL else "MM_") + bt["name"]
			if tint != Color.WHITE:
				var m0: Material = part["mesh"].surface_get_material(0)
				if m0 is BaseMaterial3D:
					var m2 := (m0 as BaseMaterial3D).duplicate() as BaseMaterial3D
					m2.albedo_color = m2.albedo_color * tint
					mmi.material_override = m2
			if vis_end > 0.0:
				mmi.visibility_range_end = vis_end
			elif q == 0 and bt["name"] in SMALL:
				mmi.visibility_range_end = 60.0   # Low: small clutter fades out past 60 m
			deco.add_child(mmi)
	_batches.clear()


## Perf: fold every static box/cylinder visual into one mesh per (material, 48 m chunk).
## Collision bodies stay as they are; only the MeshInstance3D children are replaced.
## Typical map: ~150 primitive draw calls -> ~25.
func merge_static() -> int:
	var groups := {}
	for b in parent.get_children():
		if not (b is StaticBody3D):
			continue
		for c in b.get_children():
			if not (c is MeshInstance3D):
				continue
			var mi := c as MeshInstance3D
			var pm := mi.mesh as PrimitiveMesh
			if pm == null or not (pm is BoxMesh or pm is CylinderMesh):
				continue
			var m: Material = pm.material
			if m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			var xf: Transform3D = (b as Node3D).transform * mi.transform
			var ch := CHUNK * (2.0 if q == 0 else 1.0)
			var cell := Vector2i(floori(xf.origin.x / ch), floori(xf.origin.z / ch))
			var key := [m, cell]
			if not groups.has(key):
				groups[key] = []
			groups[key].append([pm, xf])
			b.remove_child(mi)
			mi.queue_free()
	var n := 0
	for key in groups:
		var st := SurfaceTool.new()
		for it in groups[key]:
			st.append_from(it[0], 0, it[1])
		var mesh := st.commit()
		mesh.surface_set_material(0, key[0])
		var out := MeshInstance3D.new()
		out.mesh = mesh
		out.name = "Merged%d" % n
		deco.add_child(out)
		n += 1
	return n


# ------------------------------------------------------------------ v1.2: buildings + lava
## Enterable two-room building: front door, back door, an interior doorway, windows on the
## sides and a roof. Local -Z is the front. Walls are ordinary boxes (they stop bullets and
## blasts like every other wall, and get merged into a few draw calls).
func building(c: Vector3, yaw: float, w: float, d: float, color: Color, accent: Color) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var h := 3.4
	var t := 0.4
	var rot := Vector3(0, yaw, 0)
	var put := func(local: Vector3, size: Vector3, col: Color) -> void:
		box(c + bs * local, size, col, rot)
	# front (door centred) and back (door offset) walls, along local X
	for wall in [[-d / 2.0, -w / 4.0], [d / 2.0, w / 4.0]]:
		var z: float = wall[0]
		var door: float = wall[1]
		var dw := 2.6
		var left_len: float = (door - dw / 2.0) - (-w / 2.0)
		var right_len: float = (w / 2.0) - (door + dw / 2.0)
		put.call(Vector3(-w / 2.0 + left_len / 2.0, h / 2.0, z), Vector3(left_len, h, t), color)
		put.call(Vector3(w / 2.0 - right_len / 2.0, h / 2.0, z), Vector3(right_len, h, t), color)
		put.call(Vector3(door, (h + 2.7) / 2.0, z), Vector3(dw, h - 2.7, t), color)        # lintel
		put.call(Vector3(door, 2.85, z - signf(z) * 0.25), Vector3(dw + 0.6, 0.15, 0.3), accent)  # door frame
	# side walls along local Z with a window opening (sill 1.1 m, top 2.2 m)
	for sx in [-1.0, 1.0]:
		var x: float = sx * w / 2.0
		var ww := 2.0
		var seg := (d - ww) / 2.0
		put.call(Vector3(x, h / 2.0, -d / 2.0 + seg / 2.0), Vector3(t, h, seg), color)
		put.call(Vector3(x, h / 2.0, d / 2.0 - seg / 2.0), Vector3(t, h, seg), color)
		put.call(Vector3(x, 0.55, 0), Vector3(t, 1.1, ww), color)
		put.call(Vector3(x, (h + 2.2) / 2.0, 0), Vector3(t, h - 2.2, ww), color)
	# interior divider (along Z at x = 0) with a doorway
	var seg2 := (d - 2.4) / 2.0
	put.call(Vector3(0, h / 2.0, -d / 2.0 + seg2 / 2.0), Vector3(0.3, h, seg2), color.darkened(0.1))
	put.call(Vector3(0, h / 2.0, d / 2.0 - seg2 / 2.0), Vector3(0.3, h, seg2), color.darkened(0.1))
	put.call(Vector3(0, (h + 2.7) / 2.0, 0), Vector3(0.3, h - 2.7, 2.4), color.darkened(0.1))
	# roof with a trim band, plus a lit ceiling panel (emissive, no dynamic light)
	put.call(Vector3(0, h + 0.2, 0), Vector3(w + 0.6, 0.4, d + 0.6), color.darkened(0.25))
	put.call(Vector3(0, h + 0.45, 0), Vector3(w * 0.5, 0.15, d * 0.5), accent)
	for sx in [-1.0, 1.0]:
		var panel := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(1.6, 0.05, 0.8)
		pm.material = mat(Color(1.0, 0.95, 0.8), 0.5, 1.5)
		panel.mesh = pm
		panel.position = c + bs * Vector3(sx * w / 4.0, h - 0.05, 0)
		panel.rotation = rot
		panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		deco.add_child(panel)
		# floor tile so interiors read as rooms
		var fl := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(w / 2.0 - 0.5, 0.03, d - 0.5)
		fm.material = mat(color.darkened(0.45), 0.8)
		fl.mesh = fm
		fl.position = c + bs * Vector3(sx * w / 4.0, 0.015, 0)
		fl.rotation = rot
		deco.add_child(fl)
		rooms.append(c + bs * Vector3(sx * w / 4.0, 0, d / 4.0))
	# furniture: a console with a glowing screen and some crates for cover
	put.call(Vector3(-w / 4.0, 0.5, d / 2.0 - 0.9), Vector3(2.2, 1.0, 0.7), Color(0.25, 0.26, 0.3))
	var scr := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(1.8, 0.6, 0.05)
	sm.material = mat(Color(0.3, 0.8, 1.0), 0.4, 2.0)
	scr.mesh = sm
	scr.position = c + bs * Vector3(-w / 4.0, 1.35, d / 2.0 - 0.62)
	scr.rotation = rot
	deco.add_child(scr)
	prop("crate", c + bs * Vector3(w / 2.0 - 1.0, 0, -d / 2.0 + 1.0), yaw + 0.3, 1.0, "box")
	prop("crate", c + bs * Vector3(w / 2.0 - 1.0, 0, d / 2.0 - 1.2), yaw, 1.0, "box")


## Animated lava (scrolling procedural shader, unshaded so it glows without lights). Burns troopers.
static var _lava_shader: Shader


static var _lava_low: StandardMaterial3D = null


static func lava_material(flow: Vector2, size: Vector2) -> Material:
	if Game.quality() == 0:
		# Low: static, unshaded, no per-pixel noise or scrolling
		if _lava_low == null:
			_lava_low = StandardMaterial3D.new()
			_lava_low.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_lava_low.albedo_color = Color(1.0, 0.42, 0.08)
			_lava_low.cull_mode = BaseMaterial3D.CULL_DISABLED
		return _lava_low
	if _lava_shader == null:
		_lava_shader = Shader.new()
		_lava_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform vec2 flow = vec2(1.0, 0.0);
uniform vec2 scale = vec2(10.0, 10.0);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec2 uv = UV * scale;
	float n = noise(uv * 0.35 - flow * TIME * 0.35) * 0.6 + noise(uv * 0.9 - flow * TIME * 0.8 + 7.0) * 0.4;
	float crust = smoothstep(0.5, 0.72, n);
	vec3 glow = vec3(1.0, 0.82, 0.3) * 1.8;
	vec3 hot = vec3(1.0, 0.38, 0.05) * 1.4;
	vec3 dark = vec3(0.16, 0.05, 0.02);
	ALBEDO = mix(mix(glow, hot, smoothstep(0.2, 0.48, n)), dark, crust);
}
"""
	var m := ShaderMaterial.new()
	m.shader = _lava_shader
	m.set_shader_parameter("flow", flow)
	m.set_shader_parameter("scale", size)
	return m


## A flat lava river: centre (x, z), size (x, z) in metres, flow direction in the XZ plane.
func lava_river(center: Vector2, size: Vector2, flow: Vector2) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	pm.material = lava_material(flow, size)
	mi.mesh = pm
	mi.position = Vector3(center.x, 0.04, center.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deco.add_child(mi)
	# dark basalt banks either side
	var horizontal := size.x > size.y
	for s in [-1.0, 1.0]:
		var bank := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(size.x, 0.12, 0.8) if horizontal else Vector3(0.8, 0.12, size.y)
		bm.material = mat(Color(0.08, 0.05, 0.04), 0.95)
		bank.mesh = bm
		bank.position = Vector3(center.x, 0.06, center.y) + (Vector3(0, 0, s * (size.y / 2.0 + 0.4)) if horizontal else Vector3(s * (size.x / 2.0 + 0.4), 0, 0))
		deco.add_child(bank)
	lava_rects.append(Rect2(center - size / 2.0, size))


## Vertical lava fall (map edge feature) pouring down into a river.
func lava_fall(base: Vector3, width: float, height: float, yaw: float) -> void:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(width, height)
	qm.material = lava_material(Vector2(0.0, -1.6), Vector2(width, height))
	mi.mesh = qm
	mi.position = base + Vector3(0, height / 2.0, 0)
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deco.add_child(mi)
	# rock cliff behind the fall
	box(base + Basis(Vector3.UP, yaw) * Vector3(0, height / 2.0, -1.5), Vector3(width + 6.0, height + 2.0, 2.5), Color(0.12, 0.08, 0.07), Vector3(0, yaw, 0))


## Low metal bridge slab across lava (walkable step, railings), marks a safe rectangle.
func lava_bridge(center: Vector2, size: Vector2, color: Color) -> void:
	box(Vector3(center.x, 0.1, center.y), Vector3(size.x, 0.2, size.y), color)
	var along_x := size.x > size.y
	for s in [-1.0, 1.0]:
		var off := Vector3(0, 0.7, s * (size.y / 2.0 - 0.1)) if along_x else Vector3(s * (size.x / 2.0 - 0.1), 0.7, 0)
		var rs := Vector3(size.x, 0.12, 0.12) if along_x else Vector3(0.12, 0.12, size.y)
		box(Vector3(center.x, 0, center.y) + off, rs, Color(0.85, 0.55, 0.15))
	safe_rects.append(Rect2(center - size / 2.0, size))


## Lava geyser: a vent on the ground that periodically erupts a column of lava (world.gd animates
## and applies damage). Returns the column node.
var geysers: Array = []   # [{"pos": Vector3, "col": MeshInstance3D, "phase": float}]


func lava_geyser(pos: Vector3, phase: float) -> void:
	var vent := MeshInstance3D.new()
	var vm := CylinderMesh.new()
	vm.top_radius = 1.6
	vm.bottom_radius = 2.2
	vm.height = 0.5
	vm.radial_segments = 10
	vm.material = mat(Color(0.1, 0.06, 0.05), 0.95)
	vent.mesh = vm
	vent.position = pos + Vector3(0, 0.25, 0)
	deco.add_child(vent)
	var core := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.05
	cm.radial_segments = 10
	cm.material = lava_material(Vector2(0, 1), Vector2(3, 3))
	core.mesh = cm
	core.position = pos + Vector3(0, 0.52, 0)
	deco.add_child(core)
	var col := MeshInstance3D.new()
	var colm := CylinderMesh.new()
	colm.top_radius = 0.5
	colm.bottom_radius = 0.9
	colm.height = 1.0
	colm.radial_segments = 8
	colm.material = lava_material(Vector2(0, -2.5), Vector2(4, 8))
	col.mesh = colm
	col.position = pos
	col.visible = false
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deco.add_child(col)
	geysers.append({"pos": pos, "col": col, "phase": phase})


## True if a ground position is in burning lava (not on a bridge).
func in_lava(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	for r in safe_rects:
		if r.has_point(q):
			return false
	for r in lava_rects:
		if r.has_point(q):
			return true
	return false


# ------------------------------------------------------------------ v1.3: terrain
## Walkable low-poly hill / ridge: a frustum (sides-gon) stretched by (sx, sz), convex collision.
## Keep (r_bottom - r_top) >= ~1.5 * h so slopes stay under 35 degrees (walkable + navmesh).
func hill(c: Vector3, r_bottom: float, r_top: float, h: float, color: Color, sx := 1.0, sz := 1.0, yaw := 0.0, sides := 7) -> StaticBody3D:
	var cm := CylinderMesh.new()
	cm.bottom_radius = r_bottom
	cm.top_radius = r_top
	cm.height = h
	cm.radial_segments = sides
	cm.rings = 1
	cm.material = mat(color)
	var b := StaticBody3D.new()
	b.collision_layer = 1 | 8
	b.collision_mask = 0
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var pts := PackedVector3Array()
	for i in sides:
		var a := TAU * float(i) / float(sides)
		pts.append(Vector3(sin(a) * r_bottom, -h / 2.0, cos(a) * r_bottom))
		pts.append(Vector3(sin(a) * r_top, h / 2.0, cos(a) * r_top))
	var sh := ConvexPolygonShape3D.new()
	sh.points = pts
	cs.shape = sh
	b.add_child(cs)
	b.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sx, 1.0, sz)), c + Vector3(0, h / 2.0 - 0.02, 0))
	parent.add_child(b)
	decks.append(c + Vector3(0, h, 0))
	return b


## Raised platform with ramps on the listed sides (0 = +Z, 1 = -Z, 2 = +X, 3 = -X).
func platform(c: Vector3, size: Vector3, color: Color, ramp_sides := [0, 1], ramp_col := Color(0, 0, 0, 0), pillars := false) -> void:
	var top := c.y + size.y
	if pillars:
		box(Vector3(c.x, top - 0.3, c.z), Vector3(size.x, 0.6, size.z), color, Vector3.ZERO, true, true)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				cyl(Vector3(c.x + sx * (size.x / 2.0 - 0.8), c.y, c.z + sz * (size.z / 2.0 - 0.8)), 0.5, 0.5, size.y - 0.6, color.darkened(0.2), true, 8)
	else:
		box(Vector3(c.x, c.y + size.y / 2.0, c.z), size, color, Vector3.ZERO, true, true)
	decks.append(Vector3(c.x, top, c.z))
	var rc := ramp_col if ramp_col.a > 0.0 else color.lightened(0.08)
	var run := size.y * 2.4
	for sd in ramp_sides:
		match sd:
			0:
				ramp(Vector3(c.x, c.y, c.z + size.z / 2.0 + run), Vector3(c.x, top, c.z + size.z / 2.0 - 0.3), 4.0, rc)
			1:
				ramp(Vector3(c.x, c.y, c.z - size.z / 2.0 - run), Vector3(c.x, top, c.z - size.z / 2.0 + 0.3), 4.0, rc)
			2:
				ramp(Vector3(c.x + size.x / 2.0 + run, c.y, c.z), Vector3(c.x + size.x / 2.0 - 0.3, top, c.z), 4.0, rc)
			3:
				ramp(Vector3(c.x - size.x / 2.0 - run, c.y, c.z), Vector3(c.x - size.x / 2.0 + 0.3, top, c.z), 4.0, rc)


# ------------------------------------------------------------------ composite pieces
## Rock arch spanning between a and b (both on the floor), gap height h.
func rock_arch(a: Vector3, b: Vector3, h: float, color: Color, tint: Color) -> void:
	var mid := (a + b) / 2.0
	var span := a.distance_to(b)
	var yaw := atan2(b.x - a.x, b.z - a.z)
	for p in [a, b]:
		cyl(p, 2.6, 2.0, h + 1.0, color, true, 7)
		prop("rock_large", p + Vector3(0, h * 0.25, 0), yaw + 1.3, h * 0.55, "none", tint)
	box(mid + Vector3(0, h + 1.4, 0), Vector3(3.6, 2.4, span + 3.0), color, Vector3(0, yaw, 0))
	prop("rock_large", mid + Vector3(0, h + 1.6, 0), yaw, 2.6, "none", tint, 1.0)


## Concrete bunker: 3 walls + roof with a firing slit facing `yaw` (front = -Z local).
func bunker(pos: Vector3, yaw: float, color: Color) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var walls := [
		[Vector3(0, 1.0, -2.6), Vector3(6.0, 2.0, 0.6)],   # front (low, slit above)
		[Vector3(-2.7, 1.5, 0), Vector3(0.6, 3.0, 5.8)],
		[Vector3(2.7, 1.5, -0.8), Vector3(0.6, 3.0, 4.2)],   # leaves a rear-right doorway
		[Vector3(0, 1.5, 2.6), Vector3(3.5, 3.0, 0.6)],
		[Vector3(0, 3.2, 0), Vector3(6.4, 0.4, 6.0)],        # roof
	]
	for wd in walls:
		box(pos + bs * wd[0], wd[1], color, Vector3(0, yaw, 0))
	prop("sack_trench", pos + bs * Vector3(0, 0, -4.2), yaw, 1.1, "box")


## Command post landmark: low ring wall with 4 gates. Flag/ring visuals live in world.gd.
func post_ring(center: Vector3, radius: float, color: Color) -> void:
	var csg := CSGCombiner3D.new()
	csg.use_collision = true
	csg.collision_layer = 1
	csg.collision_mask = 0
	csg.position = center
	var outer := CSGCylinder3D.new()
	outer.radius = radius + 1.6
	outer.height = 1.3
	outer.sides = 20
	outer.position.y = 0.65
	outer.material = mat(color, 0.6)
	csg.add_child(outer)
	var inner := CSGCylinder3D.new()
	inner.operation = CSGShape3D.OPERATION_SUBTRACTION
	inner.radius = radius + 1.0
	inner.height = 2.0
	inner.sides = 20
	inner.position.y = 0.65
	csg.add_child(inner)
	for d in 4:
		var door := CSGBox3D.new()
		door.operation = CSGShape3D.OPERATION_SUBTRACTION
		door.size = Vector3(3.6, 3, 4)
		door.rotation.y = d * PI / 2.0
		door.position = Vector3(sin(d * PI / 2.0), 0, cos(d * PI / 2.0)) * (radius + 1.3) + Vector3(0, 0.65, 0)
		csg.add_child(door)
	parent.add_child(csg)


## Ground slab with a subtle noise texture so big floors aren't flat colour.
func ground(size: float, color: Color, color2: Color) -> void:
	var b := box(Vector3(0, -0.5, 0), Vector3(size, 1, size), color)
	b.collision_layer = 1 | 8
	b.name = "Ground"
	var mi := b.get_child(0) as MeshInstance3D
	var m := StandardMaterial3D.new()
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.03
	nt.noise = fn
	var grad := Gradient.new()
	grad.set_color(0, color2)
	grad.set_color(1, color)
	nt.color_ramp = grad
	m.albedo_texture = nt
	m.uv1_scale = Vector3(24, 24, 24)
	m.roughness = 0.95
	(mi.mesh as BoxMesh).material = m


## Map boundary: invisible tall walls + a visual cliff/railing dressing callback.
func boundary(half: float) -> void:
	for i in 4:
		var horizontal := i < 2
		var s := 1.0 if i % 2 == 0 else -1.0
		var pos := Vector3(0, 10, s * (half + 2)) if horizontal else Vector3(s * (half + 2), 10, 0)
		var size := Vector3(half * 2 + 8, 20, 4) if horizontal else Vector3(4, 20, half * 2 + 8)
		box(pos, size, Color.WHITE, Vector3.ZERO, false)


## Environment: procedural sky, fog, sun with cheap shadows.
func environment(d: Dictionary) -> DirectionalLight3D:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = d["sky_top"]
	sm.sky_horizon_color = d["sky_hor"]
	sm.ground_horizon_color = d["sky_hor"]
	sm.ground_bottom_color = d["fog"].darkened(0.5)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = d["ambient"]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = d["fog"]
	env.fog_density = d["fog_density"]
	env.fog_sky_affect = 0.6
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = d.get("sun_rot", Vector3(-50, 35, 0))
	sun.light_color = d["sun"]
	sun.light_energy = d["sun_energy"]
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	w.add_child(sun)
	self.sun = sun
	self.env = env
	return sun
