extends Node3D
## Visible blaster bolt travelling from `from` to `to` (visual only; damage is hitscan).

const SPEED := 150.0
var from := Vector3.ZERO
var to := Vector3.ZERO
var kind := 0   # 0 = republic (blue), 1 = droid (red)
var dir := Vector3.FORWARD
var remaining := 0.0


func _ready() -> void:
	var delta_v := to - from
	remaining = delta_v.length()
	if remaining < 0.05:
		queue_free()
		return
	dir = delta_v / remaining
	global_position = from
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	look_at(from + dir, up)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.07, 1.4)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var c := Color(0.35, 0.65, 1.0) if kind != 1 else Color(1.0, 0.2, 0.15)
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 4.0
	bm.material = m
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _process(delta: float) -> void:
	var step := SPEED * delta
	if step >= remaining:
		queue_free()
		return
	remaining -= step
	global_position += dir * step
