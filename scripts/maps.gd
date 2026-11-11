## Layouts for the three hand-designed maps. Coordinates: +Z is "south" (LZ side), map is 190 x 190.
## All decoration RNG uses a fixed seed so every peer builds the identical level.
extends RefCounted

const POST_CLEAR := 13.0
var B   # MapBuilder
var M: Dictionary
var r := RandomNumberGenerator.new()
var rain: Node3D = null
var rooms_keep: Array = []     # building centres: scatter keeps props out of them


## Enterable building + keep scattered props out of it.
func _room(c: Vector3, yaw: float, color: Color, accent: Color, w := 14.0, d := 10.0) -> void:
	B.building(c, yaw, w, d, color, accent)
	rooms_keep.append(c)


func build(builder, m: Dictionary) -> void:
	B = builder
	M = m
	r.seed = 1337
	B.environment(M)
	B.boundary(95.0)
	match String(M.get("layout", "geonosis")):
		"felucia":
			_felucia()
		"kamino":
			_kamino()
		"umbara":
			_umbara()
		"christophsis":
			_christophsis()
		"mustafar":
			_mustafar()
		_:
			_geonosis()
	for i in M["posts"].size():
		B.post_ring(M["posts"][i], 7.0, M.get("post_col", Color(0.62, 0.62, 0.66)))
	_lz_pad()
	B.flush()


## True if p is far enough from posts, LZ and team spawns (keeps lanes and objectives clear).
func _clear(p: Vector3, extra := 0.0) -> bool:
	for c in M["posts"]:
		if Vector2(p.x - c.x, p.z - c.z).length() < POST_CLEAR + extra:
			return false
	for c in [M["lz"]] + M["spawns"]:
		if Vector2(p.x - c.x, p.z - c.z).length() < 14.0 + extra:
			return false
	return true


## Scatter n copies of a model in a rect, avoiding objectives and a list of [center, radius] keep-outs.
func _scatter(model: String, n: int, rect: Rect2, hmin: float, hmax: float, collide: String, tint := Color.WHITE, keep := [], col_frac := 0.25) -> void:
	var placed := 0
	var tries := 0
	while placed < n and tries < n * 30:
		tries += 1
		var p := Vector3(r.randf_range(rect.position.x, rect.end.x), 0, r.randf_range(rect.position.y, rect.end.y))
		if not _clear(p):
			continue
		var bad := false
		for rm in rooms_keep:
			if Vector2(p.x - rm.x, p.z - rm.z).length() < 11.0:
				bad = true
		for k in keep:
			if Vector2(p.x - k[0].x, p.z - k[0].z).length() < k[1]:
				bad = true
				break
		if bad:
			continue
		B.prop(model, p, r.randf() * TAU, r.randf_range(hmin, hmax), collide, tint, 1.0, col_frac)
		placed += 1


func _lz_pad() -> void:
	var lz: Vector3 = M["lz"]
	B.disc(lz + Vector3(0, 0.03, 0), 8.0, Color(0.32, 0.33, 0.37))
	B.disc(lz + Vector3(0, 0.05, 0), 6.6, M.get("lz_glow", Color(1.0, 0.75, 0.2)), 0.6)
	B.disc(lz + Vector3(0, 0.07, 0), 6.2, Color(0.3, 0.31, 0.35))
	for sx in [-1.0, 1.0]:
		B.prop("crate", lz + Vector3(sx * 9.0, 0, 5.0), 0.3 * sx, 1.1, "box")
		B.prop("crate", lz + Vector3(sx * 9.6, 0, 3.6), 0.9, 1.1, "box")
		B.prop("barrel", lz + Vector3(sx * 8.0, 0, 6.6), 0.0, 1.2, "cyl", Color.WHITE, 1.0, 0.45)
		B.prop("light_floor", lz + Vector3(sx * 7.4, 0, -7.4), 0.0, 2.2, "none")
		B.light(lz + Vector3(sx * 7.4, 2.4, -7.4), M.get("lz_glow", Color(1.0, 0.75, 0.2)), 1.2, 9.0)
	# team spawns get the same small staging area (Versus)
	for i in M["spawns"].size():
		var sp: Vector3 = M["spawns"][i]
		var c := Color(1.0, 0.3, 0.25) if i == 0 else Color(0.35, 0.55, 1.0)   # team 0 = RED
		B.disc(sp + Vector3(0, 0.04, 0), 5.0, c.darkened(0.4), 0.3)
		B.prop("sack_trench", sp + Vector3(-6, 0, (6.0 if sp.z < 0 else -6.0)), 0.0, 1.0, "box")
		B.prop("sack_trench", sp + Vector3(6, 0, (6.0 if sp.z < 0 else -6.0)), 0.0, 1.0, "box")


# ======================================================================= GEONOSIS
## Canyon outpost: two long mesas split the map into west / centre / east lanes. Rock arches
## frame the centre lane, bunkers guard ALPHA, and a droid factory belches smoke in the NE.
func _geonosis() -> void:
	var rock: Color = M["rock"]
	var cliff: Color = M["cliff"]
	var tint := Color(1.25, 0.82, 0.6)
	B.ground(240.0, M["ground"], M["ground"].darkened(0.18))
	# --- canyon rim: big rock formations around the edge (visual + collision)
	for i in 28:
		var t := float(i) / 28.0 * TAU
		var p := Vector3(cos(t), 0, sin(t)) * 1.0
		p = Vector3(clampf(p.x * 140.0, -99, 99), 0, clampf(p.z * 140.0, -99, 99))
		B.prop("mountain_group", p, t, r.randf_range(16, 26), "none", tint)
	# --- mesas (elevated lanes) with passes
	var mesas := [
		[Vector3(-24, 0, -42.5), Vector3(12, 5, 35)],
		[Vector3(-24, 0, -2.5), Vector3(12, 5, 25)],
		[Vector3(24, 0, -7.5), Vector3(12, 5, 25)],
		[Vector3(24, 0, 32.5), Vector3(12, 5, 35)],
	]
	for m in mesas:
		B.box(m[0] + Vector3(0, m[1].y / 2.0, 0), m[1], cliff, Vector3.ZERO, true, true)
		for k in 3:
			var top: Vector3 = m[0] + Vector3(r.randf_range(-3, 3), m[1].y, r.randf_range(-m[1].z / 2.5, m[1].z / 2.5))
			B.prop("rock", top, r.randf() * TAU, r.randf_range(1.4, 2.2), "box", tint)
		# skirt rocks so mesas read as natural formations
		for k in 4:
			var side := -1.0 if k % 2 == 0 else 1.0
			var sp: Vector3 = m[0] + Vector3(side * (m[1].x / 2.0 + 0.5), 0, r.randf_range(-m[1].z / 2.5, m[1].z / 2.5))
			B.prop("rock_large", sp, r.randf() * TAU, r.randf_range(3.0, 5.5), "box", tint)
	# ramps up onto each mesa (south end of west mesas, north end of east mesas)
	B.ramp(Vector3(-24, 0, 21), Vector3(-24, 5, 10.0), 5.0, rock)
	B.ramp(Vector3(-24, 0, -71), Vector3(-24, 5, -60.0), 5.0, rock)
	B.ramp(Vector3(24, 0, -31), Vector3(24, 5, -20.0), 5.0, rock)
	B.ramp(Vector3(24, 0, 61), Vector3(24, 5, 50.0), 5.0, rock)
	# sandbag nests on the mesa tops
	for p in [Vector3(-24, 5, -50), Vector3(-24, 5, 0), Vector3(24, 5, -12), Vector3(24, 5, 38)]:
		B.prop("sack_trench", p, PI / 2.0, 1.0, "box")
	# --- rock arches (landmarks over the lanes)
	B.rock_arch(Vector3(-8, 0, 12), Vector3(8, 0, 12), 7.0, rock, tint)
	B.rock_arch(Vector3(-36, 0, -8), Vector3(-52, 0, -8), 8.0, rock, tint)
	B.rock_arch(Vector3(36, 0, -42), Vector3(52, 0, -42), 8.0, rock, tint)
	# --- v1.2: enterable buildings (two-room outposts)
	_room(Vector3(-62, 0, -30), 0.0, Color(0.62, 0.52, 0.42), Color(0.75, 0.3, 0.15))
	_room(Vector3(56, 0, 45), PI / 2.0, Color(0.62, 0.52, 0.42), Color(0.75, 0.3, 0.15))
	# --- bunkers
	B.bunker(Vector3(-12, 0, -44), 0.0, Color(0.55, 0.5, 0.45))
	B.bunker(Vector3(12, 0, -44), 0.0, Color(0.55, 0.5, 0.45))
	B.bunker(Vector3(66, 0, 20), -PI / 2.0, Color(0.55, 0.5, 0.45))
	B.bunker(Vector3(-62, 0, 48), PI / 2.0, Color(0.55, 0.5, 0.45))
	# --- droid factory (NE): hull, smokestacks, pipes, gun turrets, glowing doors
	var f := Vector3(62, 0, -68)
	B.box(f + Vector3(0, 6, 0), Vector3(28, 12, 18), Color(0.45, 0.36, 0.3), Vector3.ZERO, true, true)
	B.box(f + Vector3(0, 13, 0), Vector3(20, 2, 12), Color(0.38, 0.3, 0.26))
	for sx in [-8.0, 0.0, 8.0]:
		B.cyl(f + Vector3(sx, 14, 3), 1.4, 1.0, 10.0, Color(0.3, 0.26, 0.24), true, 10)
		B.disc(f + Vector3(sx, 24.05, 3), 0.9, Color(1.0, 0.4, 0.1), 3.0)
	B.prop("container_structure", f + Vector3(-20, 0, 8), PI / 2.0, 4.6, "box", Color(1.1, 0.85, 0.7))
	B.prop("pipes", f + Vector3(-15, 0, -4), 0.0, 1.0, "box")
	B.prop("pipes", f + Vector3(15, 0, 4), 0.0, 1.0, "box")
	B.prop("antenna", f + Vector3(10, 14, -4), 0.0, 3.0, "none")
	B.prop("turret_cannon", f + Vector3(-9, 14, -5), PI, 1.6, "none")
	B.prop("turret_cannon", f + Vector3(9, 14, 5), 0.6, 1.6, "none")
	for dx in [-6.0, 6.0]:
		B.box(f + Vector3(dx, 2.5, 9.05), Vector3(4, 5, 0.2), Color(1.0, 0.25, 0.1), Vector3.ZERO, true)
		B.light(f + Vector3(dx, 3, 11), Color(1.0, 0.35, 0.1), 2.0, 12.0)
	for i in 6:
		B.prop("container_red" if i % 2 == 0 else "container_green", f + Vector3(-12 + i * 5.0, 0, 16 + (i % 3) * 1.5), PI / 2.0, 2.6, "box", Color(1.0, 0.85, 0.7))
	B.spawn_points.append_array([f + Vector3(-6, 0, 13), f + Vector3(6, 0, 13), Vector3(-80, 0, -70), Vector3(-82, 0, 10), Vector3(80, 0, 50), Vector3(-30, 0, -84), Vector3(40, 0, 82), Vector3(-75, 0, 75)])
	# --- post landmarks
	var a: Vector3 = M["posts"][0]
	B.cyl(a + Vector3(-9, 0, -9), 0.7, 0.5, 12.0, Color(0.5, 0.45, 0.4))
	B.prop("antenna", a + Vector3(-9, 12, -9), 0.0, 2.4, "none")
	B.light(a + Vector3(-9, 12.5, -9), Color(1, 0.2, 0.15), 1.5, 14.0)
	var bp: Vector3 = M["posts"][1]
	B.box(bp + Vector3(9, 1, -9), Vector3(4, 2, 4), Color(0.5, 0.45, 0.42))
	B.prop("turret_cannon", bp + Vector3(9, 2, -9), -PI / 2.0, 1.6, "none")
	var cp: Vector3 = M["posts"][2]
	B.prop("gunship", cp + Vector3(-17, 0, -12), 2.4, 3.2, "box", Color(0.95, 0.9, 0.85))   # crashed LAAT wreck
	# --- cover rocks along lanes
	var keep := [[f, 22.0]]
	_scatter("rock", 22, Rect2(-15, -80, 30, 140), 1.2, 2.2, "box", tint, keep)          # centre lane (low cover)
	_scatter("rock_large", 10, Rect2(-90, -85, 55, 165), 2.5, 4.5, "box", tint, keep)    # west lane
	_scatter("rock_large", 10, Rect2(35, -45, 55, 125), 2.5, 4.5, "box", tint, keep)     # east lane
	_scatter("rock_formation", 8, Rect2(-90, -90, 180, 180), 7.0, 12.0, "cyl", tint, keep + [[Vector3(0, 0, 0), 18.0]], 0.3)
	_scatter("barrel", 10, Rect2(-60, -60, 120, 120), 1.1, 1.1, "cyl", Color(1.0, 0.85, 0.75), keep, 0.45)


# ======================================================================= FELUCIA
## Jungle ruins: giant fungi canopy, glowing ponds, a stepped temple overlook in the north,
## broken walls and colonnades around every post.
func _felucia() -> void:
	var stone := Color(0.42, 0.46, 0.4)
	B.ground(240.0, M["ground"], M["ground"].darkened(0.25))
	# --- perimeter: dense jungle wall
	for i in 40:
		var t := float(i) / 40.0 * TAU
		var p := Vector3(clampf(cos(t) * 140.0, -97, 97), 0, clampf(sin(t) * 140.0, -97, 97))
		if i % 2 == 0:
			B.prop("tree_spiral", p, t, r.randf_range(12, 20), "none", Color(0.75, 1.0, 0.9))
		B.prop("mushroom", p * 0.93, t, r.randf_range(10, 16), "none", Color(1.2, 0.7, 1.1))
	# --- ponds (bioluminescent)
	var ponds := [[Vector3(-18, 0, -8), 9.0], [Vector3(62, 0, 5), 7.0], [Vector3(-60, 0, 28), 8.0], [Vector3(20, 0, 62), 6.0]]
	for pd in ponds:
		B.disc(pd[0] + Vector3(0, 0.02, 0), pd[1] + 1.2, Color(0.12, 0.2, 0.12))
		B.disc(pd[0] + Vector3(0, 0.05, 0), pd[1], Color(0.1, 0.55, 0.6, 0.85), 0.5)
		B.light(pd[0] + Vector3(0, 1.5, 0), Color(0.3, 1.0, 0.9), 1.0, pd[1] * 2.0)
		for k in 6:
			var t := k / 6.0 * TAU + 0.4
			B.prop("rock", pd[0] + Vector3(cos(t), 0, sin(t)) * (pd[1] + 1.5), t, r.randf_range(0.8, 1.4), "box", Color(0.6, 0.8, 0.7))
	# --- temple overlook (north, between ALPHA and BRAVO): 2 tiers + ramps
	var tp := Vector3(-5, 0, -62)
	B.box(tp + Vector3(0, 1.5, 0), Vector3(26, 3, 18), stone, Vector3.ZERO, true, true)
	B.box(tp + Vector3(0, 4.5, -2), Vector3(14, 3, 10), stone.darkened(0.1), Vector3.ZERO, true, true)
	B.ramp(Vector3(0, 0, -44.5), Vector3(0, 3, -53), 5.0, stone)
	B.ramp(Vector3(-4.5, 3, -53.5), Vector3(-4.5, 6, -59.0), 3.0, stone)
	for sx in [-11.0, 11.0]:
		B.cyl(tp + Vector3(sx, 3, 7), 0.9, 0.8, 6.0, stone.lightened(0.1), true, 8)
	B.cyl(tp + Vector3(0, 6, -4), 1.2, 0.6, 7.0, stone.lightened(0.15), true, 6)   # obelisk
	B.light(tp + Vector3(0, 13.5, -4), Color(0.6, 1.0, 0.4), 2.0, 18.0)
	# --- v1.2: overgrown ruin buildings you can enter
	_room(Vector3(-72, 0, 55), 0.3, stone, Color(0.35, 0.7, 0.4))
	_room(Vector3(70, 0, -25), -0.2, stone, Color(0.35, 0.7, 0.4))
	# --- broken walls + colonnades (cover lanes)
	var walls := [
		[Vector3(-30, 0, -20), 12.0, 0.2], [Vector3(-38, 0, 10), 10.0, 1.4], [Vector3(25, 0, -20), 14.0, -0.3],
		[Vector3(45, 0, 30), 12.0, 1.2], [Vector3(-10, 0, 45), 10.0, 0.1], [Vector3(-70, 0, -10), 12.0, 1.57],
		[Vector3(70, 0, -55), 10.0, 0.6], [Vector3(-25, 0, 70), 10.0, -0.4],
	]
	for wd in walls:
		var yaw: float = wd[2]
		var bs := Basis(Vector3.UP, yaw)
		var segs := int(wd[1] / 3.0)
		for s in segs:
			if s == segs / 2:
				continue  # broken gap
			var hh := r.randf_range(1.4, 3.2)
			B.box(wd[0] + bs * Vector3((s - segs / 2.0) * 3.0, hh / 2.0, 0), Vector3(2.9, hh, 1.0), stone.darkened(r.randf_range(0, 0.15)), Vector3(0, yaw, 0))
	for i in 5:
		var p := Vector3(-48 + i * 7.0, 0, 52)
		if i == 2:
			B.box(p + Vector3(0, 0.6, 2), Vector3(1.2, 1.2, 6.0), stone, Vector3(0, 0.3, 0))   # fallen column
		else:
			B.cyl(p, 0.8, 0.7, r.randf_range(4.0, 7.0), stone.lightened(0.1), true, 8)
	# --- post landmarks: A ancient gate, B giant glowing fungus, C statue plinth
	var a: Vector3 = M["posts"][0]
	for sx in [-4.0, 4.0]:
		B.cyl(a + Vector3(sx, 0, -11), 1.0, 0.9, 9.0, stone.lightened(0.1), true, 8)
	B.box(a + Vector3(0, 9.6, -11), Vector3(11, 1.4, 2.2), stone)
	var bp: Vector3 = M["posts"][1]
	B.prop("mushroom", bp + Vector3(11, 0, -6), 0.5, 20.0, "cyl", Color(0.8, 1.6, 1.5), 1.0, 0.1)
	B.light(bp + Vector3(11, 14, -6), Color(0.4, 1.0, 0.9), 2.0, 22.0)
	var cp: Vector3 = M["posts"][2]
	B.box(cp + Vector3(-10, 1, -10), Vector3(4, 2, 4), stone)
	B.box(cp + Vector3(-10, 4.5, -10), Vector3(2, 5, 2), stone.lightened(0.2))
	B.box(cp + Vector3(-10, 7.6, -10), Vector3(3.2, 1.2, 1.2), stone.lightened(0.2))
	# --- fungi forest + undergrowth
	var keep := [[tp, 18.0]]
	for pd in ponds:
		keep.append([pd[0], pd[1] + 3.0])
	_scatter("mushroom", 26, Rect2(-88, -88, 176, 176), 7.0, 15.0, "cyl", Color(1.3, 0.75, 1.2), keep, 0.1)
	_scatter("mushroom", 30, Rect2(-88, -88, 176, 176), 1.2, 2.5, "none", Color(0.7, 1.5, 1.4), keep)
	_scatter("tree_spiral", 10, Rect2(-88, -88, 176, 176), 6.0, 11.0, "cyl", Color(0.8, 1.1, 1.0), keep, 0.12)
	_scatter("tree_blob", 5, Rect2(-88, -88, 176, 176), 5.0, 9.0, "cyl", Color(0.85, 1.2, 0.9), keep, 0.12)
	_scatter("plant", 45, Rect2(-90, -90, 180, 180), 0.8, 2.0, "none", Color(0.8, 1.2, 0.9), [])
	_scatter("rock_large", 10, Rect2(-88, -88, 176, 176), 1.6, 3.2, "box", Color(0.6, 0.75, 0.7), keep)
	B.spawn_points.append_array([Vector3(-85, 0, -85), Vector3(0, 0, -86), Vector3(85, 0, -80), Vector3(-86, 0, 0), Vector3(86, 0, -20), Vector3(-80, 0, 80), Vector3(85, 0, 35), Vector3(-30, 0, 86)])


# ======================================================================= KAMINO
## Rain-lashed platform city: a metal deck over a stormy ocean, Tipoca-style domes on stilts,
## a raised central gantry with ramps, cargo yards and a parked gunship on a landing pad.
func _kamino() -> void:
	var deck := Color(0.55, 0.58, 0.62)
	var white := Color(0.85, 0.88, 0.9)
	B.ground(196.0, M["ground"], M["ground"].darkened(0.12))
	# ocean far below the deck edge
	var ocean := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	pm.material = B.mat(Color(0.05, 0.12, 0.18), 0.1)
	ocean.mesh = pm
	ocean.position = Vector3(0, -14, 0)
	B.deco.add_child(ocean)
	# deck-edge railings (visual, collision is the invisible boundary)
	for i in 4:
		var horiz := i < 2
		var s := 1.0 if i % 2 == 0 else -1.0
		var pos := Vector3(0, 0.6, s * 97.5) if horiz else Vector3(s * 97.5, 0.6, 0)
		var size := Vector3(196, 1.2, 0.3) if horiz else Vector3(0.3, 1.2, 196)
		B.box(pos, size, Color(0.3, 0.32, 0.36))
	# deck stripes (lanes)
	for x in [-30.0, 30.0]:
		var stripe := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6, 0.02, 180)
		bm.material = B.mat(Color(0.9, 0.75, 0.2), 0.5, 0.2)
		stripe.mesh = bm
		stripe.position = Vector3(x, 0.01, 0)
		B.deco.add_child(stripe)
	# --- Tipoca domes on stilts (landmarks / big occluders)
	var domes := [[Vector3(-68, 0, -68), 14.0], [Vector3(70, 0, 62), 12.0], [Vector3(-72, 0, 48), 10.0], [Vector3(72, 0, -70), 11.0]]
	for d in domes:
		var c: Vector3 = d[0]
		var rad: float = d[1]
		B.cyl(c, rad * 0.35, rad * 0.35, 6.0, deck.darkened(0.2), true, 10)
		var dome := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rad
		sm.height = rad * 0.9
		sm.radial_segments = 20
		sm.rings = 8
		sm.material = B.mat(white, 0.3)
		dome.mesh = sm
		dome.position = c + Vector3(0, 6.0 + rad * 0.2, 0)
		B.deco.add_child(dome)
		B.cyl(c + Vector3(0, 6.0, 0), rad * 0.9, rad * 0.9, rad * 0.25, white, false)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = rad * 0.98
		tm.outer_radius = rad * 1.04
		tm.rings = 24
		tm.ring_segments = 4
		tm.material = B.mat(Color(0.6, 0.85, 1.0), 0.3, 2.0)
		ring.mesh = tm
		ring.position = c + Vector3(0, 6.3 + rad * 0.2, 0)
		B.deco.add_child(ring)
	# --- raised central gantry (elevation) with ramps east/west and a crossing bridge
	B.box(Vector3(0, 2.75, -5), Vector3(34, 0.5, 10), deck.darkened(0.1), Vector3.ZERO, true)
	for sx in [-15.0, -5.0, 5.0, 15.0]:
		for sz in [-9.0, -1.0]:
			B.cyl(Vector3(sx, 0, sz), 0.45, 0.45, 2.5, deck.darkened(0.3), true, 8)
	B.ramp(Vector3(-28, 0, -5), Vector3(-17, 3, -5), 4.0, deck)
	B.ramp(Vector3(28, 0, -5), Vector3(17, 3, -5), 4.0, deck)
	for sx in [-16.5, 16.5]:   # railings on the gantry
		B.box(Vector3(sx * 0.6, 3.5, -9.8), Vector3(14, 1.0, 0.2), Color(0.3, 0.32, 0.36))
		B.box(Vector3(sx * 0.6, 3.5, -0.2), Vector3(14, 1.0, 0.2), Color(0.3, 0.32, 0.36))
	B.prop("antenna", Vector3(0, 3.0, -5), 0.0, 3.0, "none")
	B.light(Vector3(0, 6.5, -5), Color(0.6, 0.85, 1.0), 1.6, 16.0)
	# --- v1.2: Kaminoan control rooms (enterable)
	_room(Vector3(-30, 0, -75), 0.0, white, Color(0.4, 0.75, 1.0))
	_room(Vector3(40, 0, 75), PI, white, Color(0.4, 0.75, 1.0))
	# --- cargo yards (cover)
	var yards := [Vector3(-55, 0, -10), Vector3(55, 0, 10), Vector3(-25, 0, 55), Vector3(30, 0, -60)]
	for yi in yards.size():
		var yc: Vector3 = yards[yi]
		for k in 4:
			var off := Vector3((k % 2) * 8.0 - 4.0, 0, (k / 2) * 7.0 - 3.5)
			var model := "container_red" if (k + yi) % 2 == 0 else "container_green"
			B.prop(model, yc + off, (PI / 2.0 if yi % 2 == 0 else 0.0) + r.randf_range(-0.15, 0.15), 2.6, "box", Color(0.85, 0.9, 1.0))
		B.prop("crate", yc + Vector3(0, 0, 9), 0.4, 1.2, "box")
		B.prop("barrel", yc + Vector3(2, 0, 9.5), 0.0, 1.2, "cyl", Color.WHITE, 1.0, 0.45)
	B.prop("container_structure", Vector3(-15, 0, -45), 0.0, 4.6, "box", Color(0.8, 0.88, 1.0))
	B.prop("container_structure", Vector3(20, 0, 40), PI, 4.6, "box", Color(0.8, 0.88, 1.0))
	# sci-fi wall segments as lane cover
	for p in [Vector3(-40, 0, 15), Vector3(40, 0, -40), Vector3(-10, 0, 20), Vector3(12, 0, -30), Vector3(-60, 0, 70), Vector3(60, 0, -85)]:
		B.prop("scifi_wall", p, r.randf_range(-0.3, 0.3) + (PI / 2.0 if p.x > 0 else 0.0), 2.2, "box", Color(0.85, 0.9, 1.0))
	# light posts in rows along the stripes
	for z in range(-80, 81, 32):
		for x in [-30.0, 30.0]:
			var lp := Vector3(x + 1.5, 0, float(z))
			if not _clear(lp, -6.0):
				continue
			B.prop("light_floor", lp, 0.0, 2.6, "cyl", Color.WHITE, 1.0, 0.4)
	# --- post landmarks
	var a: Vector3 = M["posts"][0]
	B.prop("landing_pad", a + Vector3(-12, 0, -8), 0.0, 0.6, "none")
	B.cyl(a + Vector3(-12, 0, -8), 1.0, 0.6, 10.0, white, true, 8)
	B.light(a + Vector3(-12, 10.5, -8), Color(0.5, 0.8, 1.0), 2.0, 16.0)
	var bp: Vector3 = M["posts"][1]
	B.box(bp + Vector3(16, 1.0, 0), Vector3(12, 2, 14), deck.darkened(0.15))
	B.ramp(bp + Vector3(10, 0, 9.5), bp + Vector3(10, 2, 7), 3.0, deck)
	B.prop("gunship", bp + Vector3(16, 2.0, 0), PI / 2.0, 3.0, "box")
	var cp: Vector3 = M["posts"][2]
	B.prop("antenna", cp + Vector3(10, 0, 8), 0.0, 4.0, "none")
	B.prop("turret_cannon", cp + Vector3(-10, 0, -8), 0.5, 1.6, "box")
	B.spawn_points.append_array([Vector3(-85, 0, -40), Vector3(-40, 0, -86), Vector3(40, 0, -86), Vector3(86, 0, -30), Vector3(86, 0, 30), Vector3(-86, 0, 20), Vector3(-50, 0, 86), Vector3(50, 0, 86)])
	_add_rain()


func _add_rain() -> void:
	var p := CPUParticles3D.new()
	p.name = "Rain"
	p.amount = 600
	p.lifetime = 1.2
	p.preprocess = 1.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(22, 1, 22)
	p.direction = Vector3(0.15, -1, 0)
	p.spread = 3.0
	p.initial_velocity_min = 28.0
	p.initial_velocity_max = 34.0
	p.gravity = Vector3.ZERO
	var qm := QuadMesh.new()
	qm.size = Vector2(0.02, 0.45)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.85, 1.0, 0.22)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	qm.material = m
	p.mesh = qm
	p.position = Vector3(0, 18, 0)
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	B.deco.add_child(p)
	rain = p


# ======================================================================= UMBARA
func _umbara() -> void:
	var rock: Color = M["rock"]
	var cliff: Color = M["cliff"]
	B.ground(240.0, M["ground"], M["ground"].lightened(0.05))
	for i in 20:
		var t := float(i) / 20.0 * TAU
		var p := Vector3(clampf(cos(t) * 130.0, -98, 98), 0, clampf(sin(t) * 130.0, -98, 98))
		B.prop("mountain_group", p, t, r.randf_range(14, 22), "none", Color(0.5, 0.4, 0.8))
	B.box(Vector3(0, 0.05, 0), Vector3(14, 0.1, 140), Color(0.12, 0.12, 0.18), Vector3.ZERO, false, false)
	for z in range(-60, 61, 12):
		B.light(Vector3(-6.5, 0.4, float(z)), Color(0.3, 1.0, 0.95), 1.4, 8.0)
		B.light(Vector3(6.5, 0.4, float(z)), Color(1.0, 0.3, 0.85), 1.4, 8.0)
		B.prop("light_floor", Vector3(-6.5, 0, float(z)), 0.0, 1.4, "none")
		B.prop("light_floor", Vector3(6.5, 0, float(z)), 0.0, 1.4, "none")
	for side in [-1.0, 1.0]:
		B.box(Vector3(side * 22, 0.6, -10), Vector3(3.5, 1.2, 50), cliff, Vector3.ZERO, true, true)
		B.prop("sack_trench", Vector3(side * 18, 0, -30), PI / 2.0, 1.0, "box")
		B.prop("sack_trench", Vector3(side * 18, 0, 10), PI / 2.0, 1.0, "box")
		B.bunker(Vector3(side * 40, 0, -20), PI / 2.0 * side, Color(0.25, 0.22, 0.35))
	_room(Vector3(-50, 0, 60), 0.0, Color(0.22, 0.2, 0.3), Color(0.3, 1.0, 0.95))
	_room(Vector3(55, 0, -65), PI / 2.0, Color(0.22, 0.2, 0.3), Color(1.0, 0.3, 0.85))
	B.box(Vector3(0, 3, -5), Vector3(8, 6, 8), cliff, Vector3.ZERO, true, true)
	B.box(Vector3(0, 6.05, -5), Vector3(9, 0.2, 9), cliff, Vector3.ZERO, true, true)  # ATC deck
	B.ramp(Vector3(-12, 0, -5), Vector3(-4.5, 6.05, -5), 5.0, rock)
	B.ramp(Vector3(12, 0, -5), Vector3(4.5, 6.05, -5), 5.0, rock)
	B.prop("antenna", Vector3(0, 6.2, -5), 0.0, 3.2, "none")
	B.prop("container_structure", Vector3(-35, 0, 30), 0.4, 4.0, "box", Color(0.6, 0.5, 0.9))
	B.prop("container_structure", Vector3(38, 0, 28), -0.3, 4.0, "box", Color(0.6, 0.5, 0.9))
	for i in 8:
		B.prop("plant", Vector3(r.randf_range(-70, 70), 0, r.randf_range(-70, 70)), r.randf() * TAU, r.randf_range(2.0, 4.0), "none", Color(0.4, 1.2, 1.0))
	_scatter("crate", 18, Rect2(-70, -70, 140, 140), 1.0, 1.3, "box", Color.WHITE, [])
	_scatter("rock_large", 8, Rect2(-80, -80, 160, 160), 2.0, 3.5, "box", Color(0.4, 0.3, 0.6), [])


# ======================================================================= CHRISTOPHSIS
func _christophsis() -> void:
	var rock: Color = M["rock"]
	var cliff: Color = M["cliff"]
	B.ground(240.0, M["ground"], M["ground"].darkened(0.1))
	for i in 16:
		var t := float(i) / 16.0 * TAU
		var p := Vector3(clampf(cos(t) * 125.0, -96, 96), 0, clampf(sin(t) * 125.0, -96, 96))
		B.prop("mountain_group", p, t, r.randf_range(12, 20), "none", Color(0.5, 0.85, 1.0))
	for c in [Vector3(-25, 0, -15), Vector3(30, 0, -35), Vector3(-40, 0, 40), Vector3(20, 0, 25), Vector3(0, 0, -50), Vector3(50, 0, 10)]:
		B.cyl(c + Vector3(0, 6, 0), 1.2, 0.6, 12.0, Color(0.3, 0.85, 0.95), true)
		B.light(c + Vector3(0, 8, 0), Color(0.4, 1.0, 1.0), 1.0, 14.0)
	B.box(Vector3(0, 1.25, 0), Vector3(70, 2.5, 10), cliff, Vector3.ZERO, true, true)  # solid bridge body
	B.box(Vector3(0, 2.6, 0), Vector3(72, 0.25, 12), cliff, Vector3.ZERO, true, true)  # walkable deck
	B.ramp(Vector3(-42, 0, 0), Vector3(-32, 2.6, 0), 6.0, rock)
	B.ramp(Vector3(42, 0, 0), Vector3(32, 2.6, 0), 6.0, rock)
	B.ramp(Vector3(0, 0, -22), Vector3(0, 2.6, -12), 6.0, rock)
	B.ramp(Vector3(0, 0, 22), Vector3(0, 2.6, 12), 6.0, rock)
	for p in [Vector3(-20, 2.6, 4), Vector3(20, 2.6, -4), Vector3(0, 2.6, 0)]:
		B.prop("sack_trench", p, 0.0, 1.0, "box")
	_room(Vector3(-60, 0, 65), 0.0, Color(0.55, 0.62, 0.7), Color(0.3, 0.9, 1.0))
	_room(Vector3(30, 0, -70), 0.0, Color(0.55, 0.62, 0.7), Color(0.3, 0.9, 1.0))
	B.bunker(Vector3(-50, 0, -10), 0.0, Color(0.4, 0.55, 0.65))
	B.bunker(Vector3(50, 0, 15), PI, Color(0.4, 0.55, 0.65))
	B.prop("scifi_wall", Vector3(-15, 0, 35), 0.2, 2.0, "box", Color(0.6, 0.9, 1.0))
	B.prop("scifi_wall", Vector3(18, 0, -40), -0.3, 2.0, "box", Color(0.6, 0.9, 1.0))
	_scatter("crate", 14, Rect2(-75, -75, 150, 150), 1.0, 1.2, "box")
	_scatter("rock_large", 6, Rect2(-85, -85, 170, 170), 2.0, 3.5, "box", Color(0.4, 0.7, 0.8), [])


# ======================================================================= MUSTAFAR
func _mustafar() -> void:
	var rock: Color = M["rock"]
	var cliff: Color = M["cliff"]
	B.ground(240.0, M["ground"], M["ground"].lightened(0.08))
	for i in 18:
		var t := float(i) / 18.0 * TAU
		var p := Vector3(clampf(cos(t) * 128.0, -97, 97), 0, clampf(sin(t) * 128.0, -97, 97))
		B.prop("mountain_group", p, t, r.randf_range(14, 24), "none", Color(0.9, 0.4, 0.2))
	# --- v1.2: flowing lava. A river splits the map east-west, fed by two lava falls; two side
	# channels branch off it. Cross on the raised platforms or the metal bridges. Lava burns troopers.
	B.lava_river(Vector2(0, 5), Vector2(186, 8), Vector2(1, 0))
	B.lava_river(Vector2(-62, -44), Vector2(8, 92), Vector2(0, 1))
	B.lava_river(Vector2(35, 32), Vector2(8, 54), Vector2(0, -1))
	B.lava_fall(Vector3(-62, 0, -91.5), 8.0, 18.0, 0.0)
	B.lava_fall(Vector3(93.5, 0, 5), 8.0, 16.0, -PI / 2.0)
	for br in [Vector2(-75, 5), Vector2(-40, 5), Vector2(70, 5)]:
		B.lava_bridge(br, Vector2(6, 11), Color(0.3, 0.28, 0.27))
	B.lava_bridge(Vector2(-62, -40), Vector2(11, 6), Color(0.3, 0.28, 0.27))
	B.lava_bridge(Vector2(35, 45), Vector2(11, 6), Color(0.3, 0.28, 0.27))
	for lp in [Vector3(-40, 2, 5), Vector3(-62, 2, -60), Vector3(35, 2, 40)]:
		B.light(lp, Color(1.0, 0.4, 0.1), 1.6, 18.0)
	_room(Vector3(-75, 0, 40), 0.0, Color(0.28, 0.2, 0.17), Color(1.0, 0.45, 0.1))
	_room(Vector3(65, 0, -50), PI / 2.0, Color(0.28, 0.2, 0.17), Color(1.0, 0.45, 0.1))
	B.box(Vector3(0, 0.5, 5), Vector3(12, 1.0, 14), cliff, Vector3.ZERO, true, true)
	B.box(Vector3(-30, 0.5, -10), Vector3(14, 1.0, 12), cliff, Vector3.ZERO, true, true)
	B.box(Vector3(35, 0.5, 10), Vector3(14, 1.0, 12), cliff, Vector3.ZERO, true, true)
	B.box(Vector3(0, 0.5, -35), Vector3(50, 1.0, 8), cliff, Vector3.ZERO, true, true)
	B.ramp(Vector3(0, 0, 22), Vector3(0, 1.0, 12), 6.0, rock)
	B.ramp(Vector3(0, 0, -52), Vector3(0, 1.0, -40), 6.0, rock)
	B.ramp(Vector3(-40, 0, -10), Vector3(-34, 1.0, -10), 5.0, rock)
	B.ramp(Vector3(45, 0, 10), Vector3(39, 1.0, 10), 5.0, rock)
	B.box(Vector3(0, 3, -8), Vector3(10, 6, 10), cliff, Vector3.ZERO, true, true)
	B.prop("pipes", Vector3(-8, 0, -8), 0.0, 1.2, "box")
	B.prop("pipes", Vector3(8, 0, -8), PI / 2.0, 1.2, "box")
	B.prop("antenna", Vector3(0, 6, -8), 0.0, 2.5, "none")
	for p in [Vector3(-20, 0, 25), Vector3(25, 0, -25), Vector3(-40, 0, 5)]:
		B.prop("scifi_wall", p, r.randf_range(-0.2, 0.2), 2.2, "box", Color(0.5, 0.3, 0.2))
	B.bunker(Vector3(50, 0, -15), -PI / 2.0, Color(0.35, 0.2, 0.15))
	B.bunker(Vector3(-55, 0, 20), PI / 2.0, Color(0.35, 0.2, 0.15))
	_scatter("barrel", 16, Rect2(-70, -70, 140, 140), 1.1, 1.3, "cyl", Color.WHITE, [], 0.45)
	_scatter("crate", 12, Rect2(-70, -70, 140, 140), 1.0, 1.2, "box")
	_scatter("rock_large", 8, Rect2(-85, -85, 170, 170), 2.0, 3.8, "box", Color(0.4, 0.2, 0.12), [])
