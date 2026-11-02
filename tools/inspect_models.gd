extends SceneTree
func _aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * n.transform
	if n is MeshInstance3D and n.mesh:
		var a: AABB = t * n.mesh.get_aabb()
		acc[0] = a if acc[0] == null else acc[0].merge(a)
	for c in n.get_children():
		_aabb(c, t, acc)
func _init():
	var d := DirAccess.open("res://models")
	for f in d.get_files():
		if not f.ends_with(".glb"): continue
		var s = load("res://models/" + f).instantiate()
		var acc = [null]
		_aabb(s, Transform3D.IDENTITY, acc)
		var ap = s.find_child("AnimationPlayer", true, false)
		var an = ap.get_animation_list() if ap else []
		print("%-26s aabb pos=%s size=%s anims=%s" % [f, acc[0].position if acc[0] else null, acc[0].size if acc[0] else null, an])
		s.free()
	quit()
