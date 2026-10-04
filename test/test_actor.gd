extends SceneTree

## Headless tests for the Mixamo clip normalisation in actor.gd.
##   godot --headless --path . --script test/test_actor.gd
##
## These lock in the four faults the first outside playtest turned up:
##   - root motion stripped, so the mesh cannot walk away from its node and then
##     snap back on the next clip change ("the enemy teleports around randomly")
##   - locomotion clips actually loop
##   - aim/shoot are upper-body only, so they cannot spin the character
##   - each clip's authored ground speed is measured, so playback can be sped up
##     or slowed to match and the feet stop skating
##
## assets/mixamo is gitignored, so on a fresh clone this reports SKIP and passes.

const PLAYER := "res://assets/mixamo/player"
const THIEF := "res://assets/mixamo/thief"

var n_pass := 0
var n_fail := 0


func check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  PASS  ", label)
		n_pass += 1
	else:
		print("  FAIL  ", label)
		if detail != "":
			print("        ", detail)
		n_fail += 1


func _banner(t: String) -> void:
	print("\n", t)


func _bone(clip: Animation, i: int) -> String:
	return String(clip.track_get_path(i).get_concatenated_subnames())


## Peak horizontal travel still left in the hips position track, in metres.
func _hip_travel(clip: Animation) -> float:
	for i in clip.get_track_count():
		var b := _bone(clip, i).to_lower()
		if not (b.contains("hips") or b.contains("root")):
			continue
		var v0 = clip.track_get_key_value(i, 0)
		if not (v0 is Vector3):
			continue
		var lo: Vector3 = v0
		var hi: Vector3 = v0
		for k in clip.track_get_key_count(i):
			var v: Vector3 = clip.track_get_key_value(i, k)
			lo = lo.min(v)
			hi = hi.max(v)
		return maxf(hi.x - lo.x, hi.z - lo.z)
	return 0.0


func _lower_body_track(a: Actor, clip: Animation) -> String:
	for i in clip.get_track_count():
		var b := _bone(clip, i)
		if a._is_lower_body(b):
			return b
	return ""


func _bones(clip: Animation) -> Array:
	var out: Array = []
	for i in clip.get_track_count():
		out.append(_bone(clip, i))
	return out


func _close(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func _init() -> void:
	if not ResourceLoader.exists(PLAYER + "/idle.fbx"):
		print("\nSKIP: assets/mixamo is not present (it is gitignored).")
		print("      restore it with: python3 tools/mixamo-fetch.py fetch assets/mixamo both\n")
		quit(0)
		return

	var a := Actor.create(PLAYER, 1.0)
	if a.anim == null:
		print("\nFAIL: could not build the player actor\n")
		quit(1)
		return

	# ---------------------------------------------------------------- inventory
	_banner("clip inventory")
	# Counted rather than hard-coded. It was 8 and became 11 when the carry, shove and hit
	# clips landed — and the homeowner's folder deliberately holds only some of CLIP_FILES,
	# because he neither carries nor searches. Asserting the exact expected SET means a
	# missing or mis-named file fails here instead of silently playing nothing.
	var want := [Actor.WALK, Actor.RUN, Actor.CROUCH_IDLE, Actor.CROUCH_WALK, Actor.AIM,
		Actor.SHOOT, Actor.RELOAD, Actor.DEATH, Actor.PUSH, Actor.SHOVE_REACT,
		Actor.HIT_REACT]
	var missing: Array = []
	for k in want:
		if not a.has_clip(k):
			missing.append(k)
	check("the mesh clip plus every animation clip the homeowner needs merged",
		missing.is_empty() and a.merged == want.size() and a.has_clip(Actor.IDLE),
		"merged=%d want=%d missing=%s" % [a.merged, want.size(), missing])

	# --------------------------------------------------------------- loop modes
	_banner("looping")
	for key in [Actor.IDLE, Actor.WALK, Actor.RUN, Actor.CROUCH_IDLE, Actor.CROUCH_WALK]:
		var c: Animation = a.anim.get_animation(key)
		check("%s loops" % key, c != null and c.loop_mode == Animation.LOOP_LINEAR,
			"loop_mode=%d" % (c.loop_mode if c else -1))
	for key in [Actor.AIM, Actor.SHOOT, Actor.RELOAD, Actor.DEATH]:
		var c: Animation = a.anim.get_animation(key)
		check("%s is a one-shot" % key, c != null and c.loop_mode == Animation.LOOP_NONE,
			"loop_mode=%d" % (c.loop_mode if c else -1))

	# -------------------------------------------------------------- root motion
	_banner("root motion")
	# measured before stripping, so the game can match playback to real movement
	check("walk measured at ~1.69 m/s", _close(a.clip_mps(Actor.WALK), 1.69, 0.08),
		"%.2f m/s" % a.clip_mps(Actor.WALK))
	check("run measured at ~5.61 m/s", _close(a.clip_mps(Actor.RUN), 5.61, 0.15),
		"%.2f m/s" % a.clip_mps(Actor.RUN))
	check("crouch_walk measured at ~0.90 m/s",
		_close(a.clip_mps(Actor.CROUCH_WALK), 0.90, 0.08),
		"%.2f m/s" % a.clip_mps(Actor.CROUCH_WALK))
	check("idle reports no ground travel", a.clip_mps(Actor.IDLE) < 0.05,
		"%.3f m/s" % a.clip_mps(Actor.IDLE))

	for key in a.clip_names():
		if key == Actor.DEATH:
			continue    # the fall is the root motion, and nothing snaps after it
		var c: Animation = a.anim.get_animation(key)
		var travel := _hip_travel(c)
		check("no hip travel left in %s" % key, travel < 0.02, "%.3f m" % travel)

	# the death clip must KEEP its travel, or the body will not fall over
	var d: Animation = a.anim.get_animation(Actor.DEATH)
	check("death keeps its fall", _hip_travel(d) > 0.5, "%.3f m" % _hip_travel(d))

	# --------------------------------------------------------- upper-body only
	_banner("upper body only")
	for key in [Actor.SHOOT, Actor.AIM]:
		var c: Animation = a.anim.get_animation(key)
		var lb := _lower_body_track(a, c)
		check("%s has no hips or leg tracks" % key, lb == "", "found %s" % lb)
		var bones := _bones(c)
		check("%s keeps the spine" % key,
			"mixamorig8_Spine2" in bones, "tracks=%d" % c.get_track_count())
		check("%s keeps the gun hand" % key,
			"mixamorig8_RightHand" in bones, "tracks=%d" % c.get_track_count())

	# a locomotion clip must NOT have been stripped
	var w: Animation = a.anim.get_animation(Actor.WALK)
	check("walk still animates the legs",
		_lower_body_track(a, w) != "" and w.get_track_count() > 40,
		"tracks=%d" % w.get_track_count())

	# -------------------------------------------------------------- the thief
	_banner("thief")
	# The thief is the actor the teleporting was actually reported against, so
	# check him separately rather than trusting the shared code path.
	var t := Actor.create(THIEF, 1.0)
	check("thief built", t.anim != null and t.has_clip(Actor.WALK))
	if t.anim != null:
		check("thief walk measured at ~1.83 m/s",
			_close(t.clip_mps(Actor.WALK), 1.83, 0.15),
			"%.2f m/s" % t.clip_mps(Actor.WALK))
		for key in [Actor.WALK, Actor.RUN, Actor.CROUCH_WALK]:
			var c: Animation = t.anim.get_animation(key)
			var travel := _hip_travel(c)
			check("thief %s cannot walk off its node" % key, travel < 0.02,
				"%.3f m" % travel)
		check("thief run is not the clip the game plays",
			t.clip_mps(Actor.RUN) > 4.0,
			"%.2f m/s — the game plays walk at %.2f" % [
				t.clip_mps(Actor.RUN), t.clip_mps(Actor.WALK)])

	print("\n%d passed, %d failed\n" % [n_pass, n_fail])
	quit(1 if n_fail > 0 else 0)
