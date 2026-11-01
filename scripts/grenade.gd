extends Node3D
## Thermal detonator. Simple ballistic projectile that bounces off level geometry.
## Only the thrower's copy (owned) asks the server to explode.

const FUSE := 1.8
var velocity := Vector3.ZERO
var owned := false
var fuse := FUSE
var light: OmniLight3D


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.3, 0.25)
	m.metallic = 0.6
	sm.material = m
	mi.mesh = sm
	add_child(mi)
	light = OmniLight3D.new()
	light.light_color = Color(1, 0.2, 0.1)
	light.omni_range = 2.0
	add_child(light)


func _physics_process(delta: float) -> void:
	fuse -= delta
	light.light_energy = 1.0 + 2.0 * float(int(fuse * 8.0) % 2)
	if fuse <= 0.0:
		if owned:
			Game.net_server("req_explode", [global_position])
		queue_free()
		return
	velocity.y -= 14.0 * delta
	var next := global_position + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(global_position, next, 1)
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		global_position = next
	else:
		var n: Vector3 = res["normal"]
		global_position = res["position"] + n * 0.13
		velocity = velocity.bounce(n) * 0.4
