extends SceneTree

## Can a bone be AIMED, so the arm can be posed into a carry by hand?
##
##   godot --headless --path . --script test/probe_pose.gd
##
## This is the question the whole carry pose turns on, and it is cheap to answer directly
## rather than by rendering. `Actor.grip()` writes `set_bone_pose_rotation` and has never
## visibly done anything; `test/probe_carry.gd` searched local rotations blindly and kept
## picking degenerate ones. The remaining route is a SkeletonModifier3D that runs after the
## AnimationPlayer and writes a bone's GLOBAL pose — so what matters is:
##
##   1. does the AnimationPlayer run before the modifier, or after?
##   2. does a global override on a parent bone MOVE ITS CHILDREN?
##
## If (2) is false there is no route to a carry pose without a real clip, and that is worth
## knowing for certain instead of assuming it.

var _a: Actor = null
var _frames := 0
var _sk: Skeleton3D = null
var _arm := -1
var _hand := -1
var _rest := Vector3.ZERO


func _initialize() -> void:
	_a = Actor.create("res://assets/mixamo/thief", 1.0)
	if _a == null or _a.root == null:
		print("no actor — the Mixamo assets are absent")
		quit()
		return
	root.add_child(_a.root)
	_a.attach_weapon()
	for c in _a.root.find_children("*", "Skeleton3D", true, false):
		_sk = c as Skeleton3D
		break
	if _sk == null:
		print("no skeleton")
		quit()
		return
	for i in _sk.get_bone_count():
		var n := String(_sk.get_bone_name(i))
		if n.ends_with("RightArm"):
			_arm = i
		elif n.ends_with("RightHand"):
			_hand = i
	if _arm < 0 or _hand < 0:
		print("no right arm chain")
		quit()
		return
	_a.play(Actor.WALK, 1.0)


func _bone_world(i: int) -> Transform3D:
	return _sk.global_transform * _sk.get_bone_global_pose(i)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false

	# A CONTROL FIRST. The walk clip is playing, so the hand moves on its own every frame —
	# without measuring that, any write at all would look like it worked.
	if _frames == 5:
		_rest = _bone_world(_hand).origin
		return false
	if _frames == 7:
		var drift := _bone_world(_hand).origin.distance_to(_rest)
		print("control: two frames of animation alone move the hand %.4f m" % drift)
		_sk.set_bone_pose_rotation(_arm, Quaternion(Vector3.FORWARD, 1.2))
		return false
	if _frames == 9:
		var d_local := _bone_world(_hand).origin.distance_to(_rest)
		print("a LOCAL pose rotation moved it %.4f m total" % d_local)
		var g := _bone_world(_arm)
		var spin := Transform3D(Basis(Quaternion(Vector3.FORWARD, 1.2)) * g.basis, g.origin)
		_sk.set_bone_global_pose_override(_arm, spin, 1.0, true)
		return false
	if _frames == 11:
		var d_glob := _bone_world(_hand).origin.distance_to(_rest)
		print("a GLOBAL pose override moved it %.4f m total" % d_glob)
		print("")
		print("VERDICT: %s" % ("a carry pose IS reachable by posing"
			if d_glob > 0.15 else "NO route to a carry pose without a real clip"))
		return true
	return false
