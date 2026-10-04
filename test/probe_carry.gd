extends SceneTree

## Search for the arm rotations that put the intruder's hands in a carrying position.
##
##   godot --headless --path . --script test/probe_carry.gd
##
## The asset set has no carry animation and the Mixamo account is unavailable, so the pose
## has to be built by hand. A Mixamo bone's local axes are not aligned to anything obvious
## — parenting a prop to the hand once pointed the shotgun down between his legs — and
## finding the right rotations by rendering is six renders per guess. Searching the numbers
## instead is exact and costs nothing.
##
## Works from the REST pose, which is a T-pose: arms straight out to the sides. That is a
## perfectly good reference for "bring the hands in front of the chest".

const TARGET_R := Vector3(0.17, 1.02, 0.34)   # right hand, model-root space
const TARGET_L := Vector3(-0.17, 1.02, 0.34)  # left hand
const STEPS := 12                              # angles per axis


func _index(sk: Skeleton3D) -> Dictionary:
	var out := {}
	for i in sk.get_bone_count():
		out[String(sk.get_bone_name(i))] = i
	return out


func _find(bones: Dictionary, suffix: String) -> int:
	for n in bones:
		if String(n).ends_with(suffix):
			return bones[n]
	return -1


## Move the hand by setting the shoulder and elbow, and report where it ended up.
func _hand_at(sk: Skeleton3D, shoulder: int, elbow: int, hand: int,
		sh: Quaternion, el: Quaternion, base_sh: Quaternion, base_el: Quaternion) -> Vector3:
	sk.set_bone_pose_rotation(shoulder, base_sh * sh)
	sk.set_bone_pose_rotation(elbow, base_el * el)
	return sk.get_bone_global_pose(hand).origin


func _search(sk: Skeleton3D, side: String, target: Vector3) -> void:
	var bones := _index(sk)
	var shoulder := _find(bones, side + "Arm")
	var elbow := _find(bones, side + "ForeArm")
	var hand := _find(bones, side + "Hand")
	if shoulder < 0 or elbow < 0 or hand < 0:
		print("  !! could not find the ", side, " arm chain")
		return
	var base_sh := sk.get_bone_pose_rotation(shoulder)
	var base_el := sk.get_bone_pose_rotation(elbow)

	# A coarse grid over both joints. The shoulder needs a big swing; the elbow only bends.
	var best_err := 1e9
	var best := {}
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for ai in axes.size():
		for si in STEPS + 1:
			var sa := -PI + TAU * float(si) / float(STEPS)
			for bi in axes.size():
				for ei in STEPS + 1:
					# an elbow bends one way only; the shoulder swings both
					var ea := PI * 0.5 * float(ei) / float(STEPS)
					var sh := Quaternion(axes[ai], sa)
					var el := Quaternion(axes[bi], ea)
					var p := _hand_at(sk, shoulder, elbow, hand, sh, el, base_sh, base_el)
					var err := p.distance_to(target)
					if err < best_err:
						best_err = err
						best = {"sa": sa, "sax": ai, "ea": ea, "eax": bi, "p": p}
	# leave the winner applied so the caller can see the result
	sk.set_bone_pose_rotation(shoulder,
		base_sh * Quaternion(axes[int(best["sax"])], float(best["sa"])))
	sk.set_bone_pose_rotation(elbow,
		base_el * Quaternion(axes[int(best["eax"])], float(best["ea"])))
	print("  %s arm:" % side)
	print("     shoulder: axis %s  angle %.3f rad (%.1f deg)"
		% [["RIGHT", "UP", "BACK"][int(best["sax"])], best["sa"], rad_to_deg(best["sa"])])
	print("     elbow   : axis %s  angle %.3f rad (%.1f deg)"
		% [["RIGHT", "UP", "BACK"][int(best["eax"])], best["ea"], rad_to_deg(best["ea"])])
	print("     hand ended at %s, target %s, error %.3f m"
		% [best["p"], target, best_err])


func _initialize() -> void:
	var a := Actor.create("res://assets/mixamo/thief", 1.0)
	if a.root == null:
		print("no actor")
		quit()
		return
	root.add_child(a.root)
	var sk: Skeleton3D = null
	for c in a.root.find_children("*", "Skeleton3D", true, false):
		sk = c as Skeleton3D
		break
	if sk == null:
		print("no skeleton")
		quit()
		return

	var hand_r := _find(_index(sk), "RightHand")
	print("rest pose right hand: ", sk.get_bone_global_pose(hand_r).origin)
	print("searching...")
	_search(sk, "Right", TARGET_R)
	_search(sk, "Left", TARGET_L)
	print("\nboth hands now:")
	for side in ["Right", "Left"]:
		var h := _find(_index(sk), side + "Hand")
		print("   %s hand at %s" % [side, sk.get_bone_global_pose(h).origin])
	quit()
