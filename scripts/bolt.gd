extends Node3D
## Visible blaster bolt (visual only). Uses shared mesh/material caches + pooling-friendly reset.

const SPEED := 150.0
static var _meshes := {}       # kind -> BoxMesh with material
static var _pool_owner: Node = null

var from := Vector3.ZERO
var to := Vector3.ZERO
var kind := 0   # 0 blue republic, 1 red droid, 2 cyan scatter/sniper, 3 green/heavy
var dir := Vector3.FORWARD
var remaining := 0.0
var _mi: MeshInstance3D = null
var _alive := false


static func _kind_color(k: int) -> Color:
	match k:
		1: return Color(1.0, 0.2, 0.15)
		2: return Color(0.35, 0.95, 1.0)
		3: return Color(0.35, 1.0, 0.45)
		_: return Color(0.35, 0.65, 1.0)


static func _mesh_for(k: int) -> BoxMesh:
	if not _meshes.has(k):
		var bm := BoxMesh.new()
		bm.size = Vector3(0.07, 0.07, 1.4)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var c := _kind_color(k)
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 4.0
		bm.material = m
		_meshes[k] = bm
	return _meshes[k]


func reset_bolt(p_from: Vector3, p_to: Vector3, p_kind: int) -> void:
	from = p_from
	to = p_to
	kind = p_kind
	var delta_v := to - from
	remaining = delta_v.length()
	if remaining < 0.05:
		_alive = false
		visible = false
		set_process(false)
		return
	dir = delta_v / remaining
	global_position = from
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	look_at(from + dir, up)
	if _mi == null:
		_mi = MeshInstance3D.new()
		_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mi)
	_mi.mesh = _mesh_for(kind)
	visible = true
	_alive = true
	set_process(true)


func _ready() -> void:
	if not _alive and from != to:
		reset_bolt(from, to, kind)


func _process(delta: float) -> void:
	if not _alive:
		return
	var step := SPEED * delta
	if step >= remaining:
		_alive = false
		visible = false
		set_process(false)
		return
	remaining -= step
	global_position += dir * step
