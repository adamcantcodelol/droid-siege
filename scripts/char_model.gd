## Animated CC0 character (Quaternius GLB) with recolouring, weapon-mesh selection,
## cross-faded logical animations and a cheap animation LOD (far characters tick less often).
extends Node3D

static var _mat_cache := {}
static var _merge_cache := {}        # path -> {"mesh": ArrayMesh, "skin": Skin, "names": Array}
static var merge_enabled := true
static var cull_dist := 0.0          # >0: hide characters farther than this (Low quality)
var cull := true                     # frustum/distance culling (off for the local trooper)
var _cull_frame := 0
static var anim_lod_far := 35.0      # beyond this, animation advances at a reduced rate
static var anim_lod_every := 4       # far characters advance once every N frames

var ap: AnimationPlayer
var amap := {}            # logical -> real animation name
var cur := ""
var _acc := 0.0
var _frame := 0
var meshes: Array = []
var pose_cb: Callable


## path: res:// glb; height: target height (m); recolor: {material_name: Color};
## amap: {"idle": "...", "run": "...", ...}; keep_meshes: if not empty, mesh names not listed
## AND in `optional` are hidden (used for the soldier's weapon set).
func setup(path: String, height: float, recolor: Dictionary, anim_map: Dictionary, optional: Array = [], show: Array = []) -> void:
	var inst: Node3D = load(path).instantiate()
	add_child(inst)
	if merge_enabled:
		_merge_rigid(path, inst, optional)
	inst.rotation.y = PI   # Quaternius characters face +Z; our forward is -Z
	amap = anim_map
	ap = inst.find_child("AnimationPlayer", true, false)
	var aabb := AABB()
	var first := true
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		meshes.append(mi)
		# Skinned rest-pose bounds of these GLBs are tiny/offset (armature scaled x100), so the
		# renderer can frustum/occlusion-cull a character that is on screen. Never cull them.
		mi.extra_cull_margin = 16384.0
		mi.ignore_occlusion_culling = true
		if mi.name in optional and not (mi.name in show):
			mi.visible = false
			continue
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(s)
			if m != null and recolor.has(m.resource_name):
				mi.set_surface_override_material(s, _tinted(m, recolor[m.resource_name]))
		var a: AABB = mi.mesh.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
	# Skinned rest AABBs are unreliable across exporters; use a known height table instead.
	var raw_h: float = anim_map.get("_raw_h", aabb.size.y)
	scale = Vector3.ONE * (height / maxf(raw_h, 0.01))
	if ap != null:
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for k in ["idle", "run", "walk", "shoot", "run_shoot", "aim"]:
			if amap.has(k) and ap.has_animation(amap[k]):
				ap.get_animation(amap[k]).loop_mode = Animation.LOOP_LINEAR
		play("idle")


## Perf: Quaternius characters are a dozen bone-attached rigid parts plus skinned pieces, i.e.
## ~19 draw calls per droid. Fold every always-visible part into ONE skinned mesh with one surface
## per material (rigid parts become 1-bone skinned geometry), so a droid costs 3-4 draw calls.
func _merge_rigid(path: String, inst: Node3D, optional: Array) -> void:
	var sk: Skeleton3D = inst.find_child("Skeleton3D", true, false)
	if sk == null:
		return
	if not _merge_cache.has(path):
		_merge_cache[path] = _build_merged(sk, optional)
	var md: Dictionary = _merge_cache[path]
	if md.is_empty():
		return
	for n in sk.find_children("*", "MeshInstance3D", true, false):
		if String(n.name) in md["names"]:
			n.get_parent().remove_child(n)
			n.queue_free()
	var mi := MeshInstance3D.new()
	mi.name = "Merged"
	mi.mesh = md["mesh"]
	mi.skin = md["skin"]
	sk.add_child(mi)
	mi.skeleton = NodePath("..")


static func _build_merged(sk: Skeleton3D, optional: Array) -> Dictionary:
	var skin := Skin.new()
	var groups := {}   # material -> {"v","n","uv","b","w","i"}
	var names := []
	var order := []
	for n in sk.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or String(mi.name) in optional or mi.mesh.get_blend_shape_count() > 0:
			continue
		var bone_map := []   # source bind index -> new bind index
		var xf := Transform3D.IDENTITY
		var rigid_bind := -1
		if mi.skin != null:
			for bi in mi.skin.get_bind_count():
				var bone := mi.skin.get_bind_bone(bi)
				if bone < 0:
					bone = sk.find_bone(mi.skin.get_bind_name(bi))
				skin.add_bind(bone, mi.skin.get_bind_pose(bi))
				bone_map.append(skin.get_bind_count() - 1)
		else:
			# walk up to the BoneAttachment3D, accumulating the local transform chain
			var node: Node = mi
			var chain := Transform3D.IDENTITY
			var bone := -1
			while node != null and node != sk:
				if node is BoneAttachment3D:
					bone = sk.find_bone((node as BoneAttachment3D).bone_name)
					break
				chain = (node as Node3D).transform * chain
				node = node.get_parent()
			if bone < 0:
				continue
			var rest := sk.get_bone_global_rest(bone)
			xf = rest * chain
			skin.add_bind(bone, rest.affine_inverse())
			rigid_bind = skin.get_bind_count() - 1
		names.append(String(mi.name))
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var mat: Material = mi.mesh.surface_get_material(si)
			if not groups.has(mat):
				groups[mat] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "b": PackedInt32Array(), "w": PackedFloat32Array(), "i": PackedInt32Array()}
				order.append(mat)
			var g: Dictionary = groups[mat]
			var base: int = g["v"].size()
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms = arr[Mesh.ARRAY_NORMAL]
			var uvs = arr[Mesh.ARRAY_TEX_UV]
			var bones = arr[Mesh.ARRAY_BONES]
			var wts = arr[Mesh.ARRAY_WEIGHTS]
			var stride := 4
			if bones != null and verts.size() > 0:
				stride = bones.size() / verts.size()
			for vi in verts.size():
				g["v"].append(xf * verts[vi])
				g["n"].append((xf.basis * norms[vi]).normalized() if norms != null else Vector3.UP)
				g["uv"].append(uvs[vi] if uvs != null else Vector2.ZERO)
				if rigid_bind >= 0:
					g["b"].append_array([rigid_bind, 0, 0, 0])
					g["w"].append_array([1.0, 0.0, 0.0, 0.0])
				else:
					for k in 4:
						var bk: int = bones[vi * stride + k] if k < stride else 0
						g["b"].append(bone_map[bk] if bk < bone_map.size() else 0)
						g["w"].append(wts[vi * stride + k] if k < stride else 0.0)
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx != null:
				for ii in idx:
					g["i"].append(base + ii)
			else:
				for ii in verts.size():
					g["i"].append(base + ii)
	if names.size() < 2:
		return {}
	var am := ArrayMesh.new()
	for mat in order:
		var g: Dictionary = groups[mat]
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = g["v"]
		a[Mesh.ARRAY_NORMAL] = g["n"]
		a[Mesh.ARRAY_TEX_UV] = g["uv"]
		a[Mesh.ARRAY_BONES] = g["b"]
		a[Mesh.ARRAY_WEIGHTS] = g["w"]
		a[Mesh.ARRAY_INDEX] = g["i"]
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		am.surface_set_material(am.get_surface_count() - 1, mat)
	return {"mesh": am, "skin": skin, "names": names}


func set_visible_meshes(optional: Array, show: Array) -> void:
	for mi in meshes:
		if mi.name in optional:
			mi.visible = mi.name in show


static func _tinted(m: Material, c: Color) -> Material:
	var key := "%d|%s" % [m.get_instance_id(), c.to_html()]
	if not _mat_cache.has(key):
		var d := m.duplicate() as BaseMaterial3D
		if d != null:
			d.albedo_color = c
		_mat_cache[key] = d if d != null else m
	return _mat_cache[key]


func play(logical: String, speed := 1.0) -> void:
	if ap == null:
		return
	var real: String = amap.get(logical, amap.get("idle", ""))
	if real == "" or not ap.has_animation(real):
		return
	var key := real + ("|hold" if speed == 0.0 else "")
	ap.speed_scale = speed
	if key != cur:
		cur = key
		ap.play(real, 0.0 if speed == 0.0 else 0.18)
		if speed == 0.0:
			ap.seek(0.0, true)


func _process(delta: float) -> void:
	if ap == null:
		return
	_acc += delta
	_frame += 1
	var cam := get_viewport().get_camera_3d()
	if cull and cam != null:
		_cull_frame += 1
		if _cull_frame % 4 == 0 or not visible:
			var on := _on_screen(cam)
			if on != visible:
				visible = on
		if not visible:
			return
	if cam != null and _frame % anim_lod_every != 0:
		if cam.global_position.distance_squared_to(global_position) > anim_lod_far * anim_lod_far:
			return
	ap.advance(_acc)
	_acc = 0.0
	if pose_cb.is_valid():
		pose_cb.call()


## Cheap visibility: skip rendering AND skinning for characters behind the camera or (on Low)
## beyond the cull distance. Sphere-vs-frustum with a generous radius so nothing pops at edges.
func _on_screen(cam: Camera3D) -> bool:
	var p := global_position + Vector3(0, 1.0, 0)
	var d2 := cam.global_position.distance_squared_to(p)
	if d2 < 36.0:
		return true
	if cull_dist > 0.0 and d2 > cull_dist * cull_dist:
		return false
	for pl in cam.get_frustum():
		if pl.distance_to(p) > 2.5:
			return false
	return true


func set_shadows(on: bool) -> void:
	for mi in meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
