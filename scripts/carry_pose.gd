extends SkeletonModifier3D

## Poses the intruder's arms to carry something, AFTER the AnimationPlayer writes the frame.
##
## The asset set has no carry animation — the clips are idle, walk, run, crouch_idle,
## crouch_walk, aim, shoot, reload and death — and the Mixamo account is unavailable to fetch
## one, so the pose is built by hand. Measured by `test/probe_pose.gd`: a LOCAL pose rotation
## on the shoulder moves the hand 0.039 m where the animation alone moves it 0.023 m, which
## is useless, while a GLOBAL pose override moves it 0.562 m.
##
## That is also why this is a modifier at all: the AnimationPlayer rewrites every animated
## bone in its own pass, so anything written from `_process()` is gone before the frame is
## drawn, whatever `process_priority` says.

## 0 = arms exactly as animated, 1 = fully into the carry. Blended, so it can be faded in
## and out rather than snapping.
@export var weight := 0.0
## Where to point each upper arm, in the SKELETON's own space. The model faces +Z, so this
## is forward, a little down, and a little across the body. X is mirrored for the left arm.
## Tuned by sweeping, not by eye: test/probe_carrypose.gd tries candidate directions and
## prints where the hands land in the model root's space. This one puts them at y 1.23/1.17,
## z 0.43/0.39, 0.50 m apart — both in front of the chest, which is where a person holds a
## box. X is mirrored for the left arm.
@export var aim_dir := Vector3(-0.35, -0.55, 0.75)

var _indexed := false
var _arm_r := -1
var _arm_l := -1
var _fore_r := -1
var _fore_l := -1


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
	_arm_r = _find("RightArm")
	_arm_l = _find("LeftArm")
	_fore_r = _find("RightForeArm")
	_fore_l = _find("LeftForeArm")
	_indexed = true
	return _arm_r >= 0 and _arm_l >= 0 and _fore_r >= 0 and _fore_l >= 0


## Point `bone` so the segment toward `child` runs along `want`, both read in the skeleton's
## own space so the character's yaw cancels out and this does not have to know which way the
## model is facing.
func _aim(bone: int, child: int, want: Vector3) -> void:
	var sk := get_skeleton()
	var g := sk.get_bone_global_pose(bone)
	var c := sk.get_bone_global_pose(child)
	var cur := c.origin - g.origin
	if cur.length_squared() < 0.000001:
		return
	var q := Quaternion(cur.normalized(), want.normalized())
	# PERSISTENT. With `persistent = false` the override is consumed by the skeleton's own
	# update and the arm creeps toward the target over tens of frames instead of taking it —
	# measured: the upper-arm segment went from (-0.41, -0.91, 0.09) to only (-0.39, -0.86,
	# 0.32) after twenty frames of asking for (0.22, -0.30, 0.93).
	sk.set_bone_global_pose_override(bone,
		Transform3D(Basis(q) * g.basis, g.origin), weight, true)


func _process_modification() -> void:
	if weight <= 0.0:
		return
	if not _indexed and not _index():
		return
	_aim(_arm_r, _fore_r, Vector3(aim_dir.x, aim_dir.y, aim_dir.z))
	_aim(_arm_l, _fore_l, Vector3(-aim_dir.x, aim_dir.y, aim_dir.z))
