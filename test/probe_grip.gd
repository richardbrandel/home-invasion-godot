extends SceneTree

## Which way do Mixamo's fingers bend?
##
## The hand bone's own axes are not something you can assume, so this sweeps all six
## candidates (three axes x two signs) and reports which one actually brings the fingertips
## TOWARD the palm. A grip that curls the wrong way throws the fingers open, which is worse
## than not curling them at all.
##
## Reads the RESULTING POSITION, not the rotation: `test/probe_carry.gd` swept rotations and
## kept picking rotations about the bone's own length axis, which move nothing.

const FINGERS := ["Thumb", "Index", "Middle", "Ring", "Pinky"]
const CURL := 0.42


func _init() -> void:
	if load("res://assets/mixamo/thief/idle.fbx") == null:
		print("VERDICT: no asset to measure (fresh clone)")
		quit()
		return

	var rest := _measure(-1, 1.0)
	print("  rest pose (control): mean fingertip-to-palm %.4f m" % rest)
	print()
	print("  axis  sign   fingertip-to-palm      change")
	var best := 1e9
	var best_desc := ""
	for axis in 3:
		for s in [1.0, -1.0]:
			var d := _measure(axis, s)
			var tag := String(["X", "Y", "Z"][axis])
			print("  %-5s %+5.1f   %.4f m              %+.4f m" % [tag, s, d, d - rest])
			if d < best:
				best = d
				best_desc = "axis %s sign %+.1f" % [tag, s]
	print()
	if best < rest:
		print("VERDICT: %s closes the hand (%.4f m against a %.4f m rest)"
			% [best_desc, best, rest])
	else:
		print("VERDICT: NO candidate closes the hand — best was %.4f against a %.4f m rest"
			% [best, rest])
	quit()


## Mean distance from the palm to the last joint of each finger, after curling by this
## candidate. axis < 0 means "leave the pose alone", which is the control.
func _measure(axis: int, s: float) -> float:
	var inst := (load("res://assets/mixamo/thief/idle.fbx") as PackedScene).instantiate()
	var sk: Skeleton3D = null
	for c in inst.find_children("*", "Skeleton3D", true, false):
		sk = c as Skeleton3D
		break
	if sk == null:
		return 99.0

	var hand := _bone(sk, "RightHand")
	if hand < 0:
		inst.free()
		return 99.0

	if axis >= 0:
		# LOCAL rotation about the bone's own axis: the chain stays connected, so a fall in
		# fingertip-to-palm distance here really does mean the hand closed.
		var a := Vector3(1, 0, 0) if axis == 0 else (Vector3(0, 1, 0) if axis == 1 else Vector3(0, 0, 1))
		var q := Quaternion(a * s, CURL)
		for f in FINGERS:
			for j in range(1, 5):
				var b := _bone(sk, "RightHand%s%d" % [f, j])
				if b >= 0:
					sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * q)
		sk.force_update_all_bone_transforms()

	var palm := sk.get_bone_global_pose(hand).origin
	var total := 0.0
	var n := 0
	for f in ["Index", "Middle", "Ring", "Pinky"]:
		var last := _bone(sk, "RightHand%s4" % f)
		if last < 0:
			continue
		total += palm.distance_to(sk.get_bone_global_pose(last).origin)
		n += 1
	inst.free()
	return total / float(maxi(n, 1))


func _bone(sk: Skeleton3D, suffix: String) -> int:
	for i in sk.get_bone_count():
		if String(sk.get_bone_name(i)).ends_with(suffix):
			return i
	return -1
