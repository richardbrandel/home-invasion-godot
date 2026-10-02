extends SceneTree

## Headless asset introspection. Run as:
##   godot --headless --path . --script test/introspect.gd
##
## Answers two questions the game code depends on:
##   1. which animations does each KayKit character actually ship with?
##   2. how big is each model, so placement and collision match the art?

const CHARS := "res://assets/kaykit/characters/"
const FURN := "res://assets/kaykit/furniture/"
const REST := "res://assets/kaykit/restaurant/"


func _model_size(root: Node) -> Vector3:
	# Must use GLOBAL transforms: glTF imports nest meshes under scaled parents,
	# so local m.transform silently drops that scale and reports fake sizes.
	var aabb := AABB()
	var first := true
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var m := c as MeshInstance3D
		if m.mesh == null:
			continue
		var box := m.get_aabb()
		var t := m.global_transform
		for i in 8:
			var p := t * box.get_endpoint(i)
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	return aabb.size


func _model_height(root: Node) -> float:
	var aabb := AABB()
	var first := true
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var m := c as MeshInstance3D
		if m.mesh == null:
			continue
		var box := m.get_aabb()
		for i in 8:
			var p := m.global_transform * box.get_endpoint(i)
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	return aabb.position.y


func _animations(root: Node) -> Array:
	var out: Array = []
	for n in root.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		if ap.get_animation_list().is_empty():
			continue
		for name in ap.get_animation_list():
			var a := ap.get_animation(name)
			out.append("%s (%.2fs)" % [name, a.length if a else 0.0])
	return out


func _report(dir_path: String, filter: String, want_anims: bool) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		print("  !! cannot open ", dir_path)
		return
	var files := d.get_files()
	files.sort()
	var shown := 0
	for f in files:
		if not (f.ends_with(".gltf") or f.ends_with(".glb")):
			continue
		if filter != "" and not f.to_lower().contains(filter):
			continue
		var packed: PackedScene = load(dir_path + f)
		if packed == null:
			print("  !! load failed: ", f)
			continue
		var inst := packed.instantiate()
		# add to the tree so global transforms resolve; remove again afterwards
		root.add_child(inst)
		var size := _model_size(inst)
		var base := _model_height(inst)
		var line := "  %-34s  %.2f w x %.2f h x %.2f d m   (base y=%.2f)" % [f, size.x, size.y, size.z, base]
		print(line)
		if want_anims:
			var anims := _animations(inst)
			if anims.is_empty():
				print("      (no animations found)")
			else:
				print("      ", anims.size(), " animations:")
				for a in anims:
					print("        - ", a)
		inst.free()
		shown += 1


func _init() -> void:
	print("\n########## CHARACTERS ##########")
	_report(CHARS, "", true)

	print("\n########## FURNITURE (seating, tables, beds, storage) ##########")
	_report(FURN, "couch", false)
	_report(FURN, "armchair", false)
	_report(FURN, "table_medium", false)
	_report(FURN, "bed_double_A", false)
	_report(FURN, "shelf_A_big", false)
	_report(FURN, "lamp_standing", false)
	_report(FURN, "rug_rectangle_A", false)
	_report(FURN, "pictureframe_large_A", false)

	print("\n########## KITCHEN ##########")
	_report(REST, "kitchencounter_straight_A", false)
	_report(REST, "fridge_A", false)
	_report(REST, "stove_multi", false)
	_report(REST, "kitchentable_A", false)
	_report(REST, "wall", false)
	_report(REST, "wall_doorway", false)
	_report(REST, "wall_window_open", false)
	_report(REST, "floor_kitchen", false)

	print("\n########## DONE ##########")
	quit()
