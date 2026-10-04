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
	# The axis is taken from the HAND's own basis, so this needs to know nothing about the
	# character's yaw or which way the arm happens to be pointing.
	var hb := sk.get_bone_global_pose(_hand).basis
	var a := hb.x if axis == 0 else (hb.y if axis == 1 else hb.z)
	a = a.normalized() * axis_sign
	var q := Quaternion(a, per_joint * weight)
	for b in _chain:
		var g := sk.get_bone_global_pose(b)
		# PERSISTENT — see the header.
		sk.set_bone_global_pose_override(b, Transform3D(Basis(q) * g.basis, g.origin),
			weight, true)
