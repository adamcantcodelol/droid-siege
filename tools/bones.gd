extends SceneTree
func _init():
	await process_frame
	for f in ["soldier", "robot", "robot_large"]:
		var s: Node3D = load("res://models/%s.glb" % f).instantiate()
		root.add_child(s)
		await process_frame
		var out := []
		for mi in s.find_children("*", "MeshInstance3D", true, false):
			var a: AABB = mi.global_transform * mi.mesh.get_aabb()
			out.append("%s y[%.2f..%.2f] x[%.2f..%.2f] z[%.2f..%.2f]" % [mi.name, a.position.y, a.end.y, a.position.x, a.end.x, a.position.z, a.end.z])
		print(f, ": ", out)
	quit()
