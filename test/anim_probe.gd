extends SceneTree

## Headless animation probe. Run as:
##   godot --headless --path . --script test/anim_probe.gd
##
## Answers the questions raised by the first outside playtest:
##   1. does a clip translate/rotate the root or hips (i.e. root motion)?
##   2. is any clip set to loop, and would looping it actually be seamless?
##   3. how far does the hips track travel, and is the travel monotonic?
##
## Probes the raw FBX files rather than the merged runtime clips: actor.gd
## duplicates those clips verbatim, so loop mode and track data are identical.

const DIRS := [
	"res://assets/mixamo/player",
	"res://assets/mixamo/thief",
]
const FILES := [
	"idle.fbx", "walk.fbx", "run.fbx", "crouch_idle.fbx", "crouch_walk.fbx",
	"aim.fbx", "shoot.fbx", "reload.fbx", "death.fbx",
]


func _loop_name(m: int) -> String:
	if m == Animation.LOOP_NONE:
		return "LOOP_NONE"
	elif m == Animation.LOOP_LINEAR:
		return "LOOP_LINEAR"
	elif m == Animation.LOOP_PINGPONG:
		return "LOOP_PINGPONG"
	return "LOOP_%d" % m


func _quat_angle(a: Quaternion, b: Quaternion) -> float:
	var d := absf(clampf(a.dot(b), -1.0, 1.0))
	return rad_to_deg(2.0 * acos(d))


func _bone(a: Animation, i: int) -> String:
	var s := String(a.track_get_path(i).get_concatenated_subnames())
	return s if s != "" else "(node)"


func _v3s(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]


## n evenly spaced samples across a track.
func _samples(a: Animation, i: int, n: int) -> Array:
	var kc := a.track_get_key_count(i)
	var out: Array = []
	if kc == 0:
		return out
	for j in n:
		var k := int(round(float(j) * float(kc - 1) / float(n - 1)))
		out.append(a.track_get_key_value(i, k))
	return out


## How far apart are the first and last keyframes of every track? A clip whose
## seam is large cannot loop cleanly, whatever its loop mode says.
func _seam_report(a: Animation) -> void:
	var pos_worst := 0.0
	var pos_where := ""
	var rot_worst := 0.0
	var rot_where := ""
	for i in a.get_track_count():
		var kc := a.track_get_key_count(i)
		if kc < 2:
			continue
		var v0 = a.track_get_key_value(i, 0)
		var v1 = a.track_get_key_value(i, kc - 1)
		var tn := type_string(typeof(v0))
		if tn == "Vector3":
			var d: float = (v0 - v1).length()
			if d > pos_worst:
				pos_worst = d
				pos_where = _bone(a, i)
		elif tn == "Quaternion":
			var q0: Quaternion = v0
			var q1: Quaternion = v1
			var qd := _quat_angle(q0, q1)
			if qd > rot_worst:
				rot_worst = qd
				rot_where = _bone(a, i)
	print("      seam: pos %.3f m (%s)   rot %.1f deg (%s)" % [
		pos_worst, pos_where, rot_worst, rot_where])


## Where does the hips bone actually go over the clip, and on which axis?
func _hips_report(a: Animation) -> void:
	for i in a.get_track_count():
		var b := _bone(a, i).to_lower()
		if not (b.contains("hips") or b.contains("root")):
			continue
		var kc := a.track_get_key_count(i)
		if kc < 2:
			continue
		var v0 = a.track_get_key_value(i, 0)
		var tn := type_string(typeof(v0))
		if tn == "Vector3":
			var rows: Array = []
			for v in _samples(a, i, 6):
				rows.append(_v3s(v))
			print("      hips pos  ", " ".join(rows))
		elif tn == "Quaternion":
			var rows: Array = []
			for v in _samples(a, i, 6):
				var e: Vector3 = (v as Quaternion).get_euler()
				rows.append(_v3s(Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))))
			print("      hips euler deg ", " ".join(rows))


## Per-sample angular speed of the right-arm chain. A gunshot is a spike; this
## locates the frame the clip actually fires on, so the one-shot window can start
## there instead of at the wind-up.
func _recoil_report(a: Animation, n: int) -> void:
	var want := ["RightHand", "RightForeArm", "RightArm", "Spine2", "Head"]
	print("      step = %.3f s; values are degrees of rotation per step" % (a.length / float(n)))
	for i in a.get_track_count():
		var b := _bone(a, i)
		var hit := false
		for w in want:
			if b.ends_with(w):
				hit = true
		if not hit:
			continue
		var kc := a.track_get_key_count(i)
		if kc < 3:
			continue
		var rows: Array = []
		var prev = null
		for j in range(0, n + 1):
			var k := int(round(float(j) * float(kc - 1) / float(n)))
			var v = a.track_get_key_value(i, k)
			if prev != null and typeof(v) == TYPE_QUATERNION:
				rows.append("%.0f" % _quat_angle(prev, v))
			prev = v
		print("      %-30s %s" % [b, " ".join(rows)])


func _probe_file(path: String, verbose: bool) -> void:
	if not ResourceLoader.exists(path):
		print("  !! missing ", path)
		return
	var packed: PackedScene = load(path)
	if packed == null:
		print("  !! load failed ", path)
		return
	var inst := packed.instantiate()
	root.add_child(inst)

	var ap: AnimationPlayer = null
	for c in inst.find_children("*", "AnimationPlayer", true, false):
		ap = c as AnimationPlayer
		break
	if ap == null:
		print("  no AnimationPlayer in ", path)
		inst.free()
		return

	print("\n=== ", path, " ===")
	for name in ap.get_animation_list():
		var a := ap.get_animation(name)
		if a == null:
			continue
		print("  clip '%s'  len=%.3fs  %s  tracks=%d" % [
			name, a.length, _loop_name(a.loop_mode), a.get_track_count()])
		_seam_report(a)
		_hips_report(a)
		if path.contains("shoot"):
			_recoil_report(a, 24)
		if verbose:
			for i in a.get_track_count():
				var kc := a.track_get_key_count(i)
				var tn := "?"
				if kc > 0:
					tn = type_string(typeof(a.track_get_key_value(i, 0)))
				print("      [%2d] %-34s %s" % [i, _bone(a, i), tn])
	inst.free()


func _init() -> void:
	print("########## ANIMATION PROBE ##########")
	for d in DIRS:
		print("\n---------------- ", d, " ----------------")
		for f in FILES:
			var ds := String(d)
			var fs := String(f)
			# full track listing only for the file the upper-body split needs
			var verbose: bool = ds.contains("player") and fs == "shoot.fbx"
			_probe_file(ds + "/" + fs, verbose)

	print("\n########## AnimationNode filter capability ##########")
	for cls in ["AnimationNode", "AnimationNodeAnimation", "AnimationNodeBlend2"]:
		var props: Array = []
		for p in ClassDB.class_get_property_list(cls, false):
			var pn := String(p["name"])
			if pn.contains("filter"):
				props.append(pn)
		print("  %-24s %s" % [cls, ", ".join(props)])

	print("\n########## DONE ##########")
	quit()
