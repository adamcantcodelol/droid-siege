## Animated CC0 character (Quaternius GLB) with recolouring, weapon-mesh selection,
## cross-faded logical animations and a cheap animation LOD (far characters tick less often).
extends Node3D

static var _mat_cache := {}
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
	if cam != null and _frame % anim_lod_every != 0:
		if cam.global_position.distance_squared_to(global_position) > anim_lod_far * anim_lod_far:
			return
	ap.advance(_acc)
	_acc = 0.0
	if pose_cb.is_valid():
		pose_cb.call()


func set_shadows(on: bool) -> void:
	for mi in meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
