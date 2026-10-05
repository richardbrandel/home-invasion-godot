extends SkeletonModifier3D

## Curls a character's fingers, so a hand actually grips the thing it is holding.
##
## Why this exists: Richard's report that "the gun hangs off the defender's wrist. It should
## be gripped with the fingers." He is right, and it is the reason the weapons still read as
## fake — a pistol can be modelled to the millimetre and it will look wrong while it floats
## beside the hand instead of in it.
##
## Same technique as `carry_pose.gd`, for the same measured reason: a LOCAL pose rotation on
## the shoulder moved the hand 0.039 m where the animation alone moved it 0.023 m, while a
## GLOBAL override moved it 0.562 m. The override must also be PERSISTENT or the skeleton's
## own update consumes it and the bone creeps instead of taking the pose.
##
## The curl axis and its sign are NOT guessed. Mixamo's hand bones do not point along an axis
## you can assume, so `test/probe_grip.gd` sweeps all six candidates and reports which one
## actually brings the fingertips toward the palm.

## 0 = the hand exactly as animated, 1 = fully curled.
@export var weight := 0.0
## How far each joint rotates. Spread across the chain, so a finger with three joints bends
## about three times this in total, which is roughly how a hand closes on a grip.
@export var per_joint := 0.42
## Which axis of the HAND bone to rotate about, 0 = X, 1 = Y, 2 = Z, and the sign to rotate.
## Defaults come from `test/probe_grip.gd`.
@export var axis := 1
@export var axis_sign := 1.0
## Which hand. "Right" or "Left".
@export var hand := "Right"

## NO THUMB. The thumb's first joint (CMC) is rotated roughly ninety degrees from the
## fingers, so rotating it about the palm's own axis splays it sideways instead of closing it
## — measured visually: including the thumb stretched the whole hand into a splayed claw.
const FINGERS := ["Index", "Middle", "Ring", "Pinky"]
## Four joints per finger in this rig; the last carries no child segment.
const JOINTS := 4

var _chain: Array[int] = []
var _hand := -1
var _indexed := false


func _find(suffix: String) -> int:
	var sk := get_skeleton()
	if sk == null:
		return -1
	for i in sk.get_bone_count():
		if String(sk.get_bone_name(i)).ends_with(suffix):
			return i
	return -1


func _index() -> bool:
	var sk := get_skeleton()
	if sk == null:
		return false
	_hand = _find(hand + "Hand")
	if _hand < 0:
		# "RightHand" ends with "RightHand" only if the prefix is right; the rigs are
		# mixamorig5_RightHand, and _find matches on suffix, so this is enough.
		return false
	_chain.clear()
	for f in FINGERS:
		for j in range(1, JOINTS + 1):
			var b := _find(hand + "Hand%s%d" % [f, j])
			if b >= 0:
				_chain.append(b)
	_indexed = true
	return _chain.size() > 0


func _process_modification() -> void:
	if weight <= 0.0:
		return
	if not _indexed and not _index():
		return
	var sk := get_skeleton()
	if sk == null:
		return
	# LOCAL rotation, not a global override, and that is the whole correction.
	#
	# The first version used `set_bone_global_pose_override` on every finger joint — the
	# technique that works for the shoulder in carry_pose.gd — and it stretched the fingers
	# into long noodles. The reason is that a global override sets each bone's pose
	# INDEPENDENTLY, so the chain came apart: a shoulder is a single joint and does not care,
	# a finger is three joints in a row and very much does.
	#
	# A local rotation is also safe here in a way it was not for the shoulder. The measured
	# complaint about local rotations (0.039 m of hand movement against a 0.023 m control) was
	# about moving an ARM, where the bone's own length axis dominates. And the AnimationPlayer
	# only rewrites bones a clip actually animates — these clips animate no fingers, so
	# nothing overwrites this.
	var q := Quaternion(_axis_vec(), per_joint * weight)
	for b in _chain:
		sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * q)


## The curl axis, taken in each bone's OWN local space. Mixamo finger bones run along local
## Y, so a curl is about X or Z; test/probe_grip.gd decides which.
func _axis_vec() -> Vector3:
	var a := Vector3(1, 0, 0) if axis == 0 else (Vector3(0, 1, 0) if axis == 1 else Vector3(0, 0, 1))
	return a * axis_sign
