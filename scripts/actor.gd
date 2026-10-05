extends RefCounted
class_name Actor

## Wraps one Mixamo character.
##
## Mixamo's export model forces a choice: `skin: true` gives the character mesh
## PLUS one animation (~48-106 MB), `skin: false` gives the animation alone
## (~0.4 MB) with no mesh. So the character is built from a single skin-carrying
## FBX and the remaining eight clips are merged in at runtime from the light
## files. That is what took the asset set from 1.3 GB to 161 MB.
##
## All Mixamo rigs share a skeleton, so the tracks resolve without retargeting.

## Clip keys — these are the FILE names, deliberately, so a key always maps to
## something greppable on disk.
const IDLE := "idle"
const WALK := "walk"
const RUN := "run"
const CROUCH_IDLE := "crouch_idle"
const CROUCH_WALK := "crouch_walk"
const AIM := "aim"
const SHOOT := "shoot"
const RELOAD := "reload"
const DEATH := "death"
## Fetched 2026-10-04 and wired in afterwards. Each of these replaces a stand-in:
## the hand-built carry pose, a stand-still for the search dwell, the shoot clip for both
## shoves, and nothing at all for a hit reaction or a grab.
const CARRY_WALK := "carry_walk"
const CARRY_IDLE := "carry_idle"
const PICKUP := "pickup"
const LOOK_AROUND := "look_around"
const PUSH := "push"
const SHOVE_REACT := "shove_react"
const HIT_REACT := "hit_react"

const CLIP_FILES := [WALK, RUN, CROUCH_IDLE, CROUCH_WALK, AIM, SHOOT, RELOAD, DEATH,
	CARRY_WALK, CARRY_IDLE, PICKUP, LOOK_AROUND, PUSH, SHOVE_REACT, HIT_REACT]

## Clips meant to run forever; everything else is a one-shot that holds its last
## frame. A Mixamo export sets none of this, so every clip arrived as LOOP_NONE —
## which is why the walk froze mid-stride after a single cycle.
const LOOPING := [IDLE, WALK, RUN, CROUCH_IDLE, CROUCH_WALK,
	CARRY_WALK, CARRY_IDLE, LOOK_AROUND]

## Where the first gunshot lands inside SHOOT, and how long to stay in the shoot
## pose. That clip is 2.67 s and holds two shots — the right forearm spikes to
## 43 deg/step at 0.44 s and again at 2.00 s (measured in test/anim_probe.gd).
## Seeking past the wind-up makes every trigger pull show the shot itself, and the
## short window hands the locomotion animation back quickly instead of freezing
## the legs for the clip's full 2.67 s.
const SHOOT_SEEK := 0.36
const ONE_SHOT_WINDOW := 0.42

## PUSH is 8.00 s and only about a quarter of a second of it is the thrust. Measured from
## its keyframes: the right forearm spikes to 496 deg/s across t = 0.33-0.43 s, with a
## second, identical push at 7.33 s. It is a repeated shove cycle, so play one of them.
## Judged by length alone this clip looks like a crate-pushing loop and I nearly discarded
## it — it is the strongest thrust of every candidate measured.
const PUSH_SEEK := 0.30
const PUSH_WINDOW := 0.34

var root: Node3D
var anim: AnimationPlayer
var ground_offset := 0.0
var base_scale := 1.0
var merged := 0
var _pistol: Node3D = null
var _shotgun: Node3D = null
var _holder: Node3D
var kit_root: Node3D
var _beanie: MeshInstance3D
var _bag: MeshInstance3D
var _gloves: Array[MeshInstance3D] = []
var _kit_bones := {}
var carry_pose: SkeletonModifier3D
var grip_pose: SkeletonModifier3D
var _skeleton: Skeleton3D = null
var _hand_bone := -1
var _current := ""
var _one_shot := ""
var _one_shot_t := 0.0
var _clip_mps := {}
var _finger_bones: Array[int] = []


static func _first_anim_player(node: Node) -> AnimationPlayer:
	for c in node.find_children("*", "AnimationPlayer", true, false):
		return c as AnimationPlayer
	return null


## Load the mesh-carrying FBX. `dir` is a res:// folder holding idle.fbx plus
## the animation-only files.
static func create(dir: String, scale := 1.0) -> Actor:
	var a := Actor.new()
	a.base_scale = scale
	var path := dir + "/idle.fbx"
	if not ResourceLoader.exists(path):
		push_error("Actor: missing " + path)
		return a
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("Actor: could not load " + path)
		return a
	a.root = packed.instantiate() as Node3D
	a.root.scale = Vector3(scale, scale, scale)
	a.anim = _first_anim_player(a.root)
	if a.anim == null:
		push_warning("Actor: no AnimationPlayer in " + path)

	# The mesh file ships TWO clips: "Take 001" is the BIND POSE — a T-pose with
	# no motion — and "mixamo_com" is the actual Idle. Taking list[0] grabbed the
	# bind pose, which is why the character stood with its arms out. Pick the
	# clip that is not the bind pose.
	if a.anim != null:
		var idle_src := ""
		for n in a.anim.get_animation_list():
			if String(n) != "Take 001":
				idle_src = String(n)
				break
		if idle_src != "" and not a.anim.has_animation(IDLE):
			# duplicate before normalising: this is the resource as loaded from
			# disk, and flattening it in place would corrupt the source clip
			var idle_clip: Animation = a.anim.get_animation(idle_src).duplicate(true)
			a._normalize_clip(IDLE, idle_clip)
			a._add_clip(IDLE, idle_clip)

	a._merge(dir)
	return a


## Godot 4 removed AnimationPlayer.add_animation(); clips live in an
## AnimationLibrary, and the default one is named "". This adds to that library,
## creating it if the imported scene somehow has none.
func _add_clip(name: String, clip: Animation) -> bool:
	if anim == null or clip == null:
		return false
	var lib := anim.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		anim.add_animation_library("", lib)
	lib.add_animation(name, clip)
	return true


## Pull each animation-only FBX's clip into this character's AnimationPlayer.
func _merge(dir: String) -> void:
	if anim == null:
		return
	for key in CLIP_FILES:
		var path := "%s/%s.fbx" % [dir, key]
		if not ResourceLoader.exists(path):
			push_warning("Actor: missing clip file " + path)
			continue
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		var inst := packed.instantiate()
		var src := _first_anim_player(inst)
		if src == null:
			inst.free()
			continue
		var list := src.get_animation_list()
		if list.is_empty():
			inst.free()
			continue
		# never merge the bind pose, even if it sorts first
		var pick := ""
		for n in list:
			if String(n) != "Take 001":
				pick = String(n)
				break
		if pick == "":
			pick = String(list[0])
		var clip := src.get_animation(pick)
		if clip != null:
			var copy := clip.duplicate(true) as Animation
			if copy != null:
				# tracks must address the character we are animating, not the
				# throwaway instance the clip was loaded from
				_retarget(copy, inst, root)
				_normalize_clip(key, copy)
				if _add_clip(key, copy):
					merged += 1
		inst.free()


## Rewrite Animation track paths from `from_root` to `to_root` when the two
## hierarchies disagree. Identical paths are left untouched — that is the case
## for Mixamo, so this normally does nothing.
func _retarget(clip: Animation, from_root: Node, to_root: Node) -> void:
	for i in clip.get_track_count():
		var p := clip.track_get_path(i)
		var s := String(p)
		var from_name := String(from_root.name)
		if from_name != "" and s.begins_with(from_name):
			clip.track_set_path(i, NodePath(String(to_root.name) + s.substr(from_name.length())))


# ----------------------------------------------------- clip normalisation
## Mixamo exports these clips WITH root motion baked in: the Hips track carries
## the character's real ground travel, start to finish — walk +1.75 m over
## 1.033 s, run +3.55 m over 0.633 s (both measured; see test/anim_probe.gd).
## Godot applies that straight to the skeleton, so the mesh walks away from the
## node the simulation is moving, and then every clip change or restart snaps it
## back to the origin, metres at a time. On the thief — who switches clip on
## every grab, sighting and reroute — that read as "teleports around randomly".
##
## So the travel is measured first (it is the clip's authored ground speed, which
## is worth keeping) and then removed, because the simulation owns position.
func _normalize_clip(key: String, clip: Animation) -> void:
	_clip_mps[key] = _measure_root_motion(clip)
	clip.loop_mode = Animation.LOOP_LINEAR if LOOPING.has(key) else Animation.LOOP_NONE
	if key == DEATH:
		# the fall IS the root motion, and nothing has to snap back afterwards
		return
	if key == SHOOT or key == AIM:
		_strip_to_upper_body(clip)
	else:
		_flatten_root_travel(clip)


func _bone_of(clip: Animation, track: int) -> String:
	return String(clip.track_get_path(track).get_concatenated_subnames())


func _is_root_bone(bone: String) -> bool:
	var b := bone.to_lower()
	return b.contains("hips") or b.contains("root")


## The hips and everything below them.
func _is_lower_body(bone: String) -> bool:
	if _is_root_bone(bone):
		return true
	for part in ["UpLeg", "Leg", "Foot", "ToeBase", "Toe_End"]:
		if bone.ends_with(part):
			return true
	return false


## Metres of ground the clip covers per second at speed_scale 1.0: the distance
## between its first and last hips keyframe, over the clip's length.
func _measure_root_motion(clip: Animation) -> float:
	if clip.length <= 0.0:
		return 0.0
	for i in clip.get_track_count():
		if not _is_root_bone(_bone_of(clip, i)):
			continue
		var v0 = clip.track_get_key_value(i, 0)
		if not (v0 is Vector3):
			continue
		var kc := clip.track_get_key_count(i)
		if kc < 2:
			return 0.0
		var p0: Vector3 = v0
		var p1: Vector3 = clip.track_get_key_value(i, kc - 1)
		return (p1 - p0).length() / clip.length
	return 0.0


## Pin the hips' horizontal travel to its first frame. The vertical component is
## kept deliberately: it is the bob, and the standing height.
func _flatten_root_travel(clip: Animation) -> void:
	for i in clip.get_track_count():
		if not _is_root_bone(_bone_of(clip, i)):
			continue
		var v0 = clip.track_get_key_value(i, 0)
		if not (v0 is Vector3):
			continue
		var base: Vector3 = v0
		for k in clip.track_get_key_count(i):
			var v: Vector3 = clip.track_get_key_value(i, k)
			clip.track_set_key_value(i, k, Vector3(base.x, v.y, base.z))


## Drop the hips and every leg bone, leaving an upper-body-only overlay. The
## removed bones keep whatever the locomotion clip last put them in, which is the
## point: the legs carry on walking while the torso aims and fires.
##
## It also removes the turn, which is the part the playtest actually noticed.
## Both of these clips rotate the hips hard — shoot swivels 87 deg out and back,
## aim turns 148 deg — so the character span on the spot and the animation fought
## the yaw the game sets on the root every frame.
func _strip_to_upper_body(clip: Animation) -> void:
	# backwards: remove_track shifts every index after the one it drops
	for i in range(clip.get_track_count() - 1, -1, -1):
		if _is_lower_body(_bone_of(clip, i)):
			clip.remove_track(i)


## Ground speed the clip was authored at, in metres per second. Play the clip at
## `actual_speed / clip_mps(key)` and its feet stop skating.
func clip_mps(key: String) -> float:
	return float(_clip_mps.get(key, 0.0))


func clip_names() -> PackedStringArray:
	return anim.get_animation_list() if anim != null else PackedStringArray()


func has_clip(name: String) -> bool:
	return anim != null and anim.has_animation(name)


func play(name: String, speed := 1.0) -> void:
	if anim == null or not anim.has_animation(name):
		return
	if _one_shot != "":
		return
	if _current == name:
		anim.speed_scale = speed
		return
	_current = name
	anim.speed_scale = speed
	anim.play(name, 0.2)


## Play a clip as a one-shot for `seconds`, then hand control back to locomotion.
## play_once() uses ONE_SHOT_WINDOW, which is tuned for SHOOT's two-shot timing and is
## far too short for a reload that genuinely takes 1.15-1.6 s.
func play_for(name: String, seconds: float) -> void:
	if anim == null or not anim.has_animation(name):
		return
	_one_shot = name
	_one_shot_t = maxf(seconds, 0.15)
	anim.speed_scale = 1.0
	anim.play(name, 0.08)


func play_once(name: String) -> void:
	if anim == null or not anim.has_animation(name):
		return
	_one_shot = name
	_one_shot_t = ONE_SHOT_WINDOW
	anim.speed_scale = 1.0
	anim.play(name, 0.08)
	if name == SHOOT:
		# skip the wind-up so the trigger pull lands on the shot
		anim.seek(SHOOT_SEEK)
	elif name == PUSH:
		# same trick: seek into the thrust and hand the locomotion back quickly
		anim.seek(PUSH_SEEK)
		_one_shot_t = PUSH_WINDOW


func tick(delta: float) -> void:
	if _one_shot != "":
		_one_shot_t -= delta
		if _one_shot_t <= 0.0:
			_one_shot = ""
			_current = ""

## Attach a weapon that FOLLOWS THE AIM, not the hand bone.
##
## Parenting the prop to the hand bone looked wrong: a Mixamo hand bone's local
## axes are rotated relative to the character, so the shotgun ended up pointing
## down between the legs. Instead the props live under the character root, are
## moved to the hand bone's world position each frame, and are oriented along the
## aim direction — which is also the direction the bullet actually travels, so
## the visual and the mechanics now agree.
func attach_weapon() -> void:
	if root == null:
		return
	for c in root.find_children("*", "Skeleton3D", true, false):
		_skeleton = c as Skeleton3D
		break
	if _skeleton == null:
		push_warning("Actor: no Skeleton3D")
		return
	for i in _skeleton.get_bone_count():
		if String(_skeleton.get_bone_name(i)).ends_with("RightHand"):
			_hand_bone = i
			break
	if _hand_bone < 0:
		push_warning("Actor: no RightHand bone")

	# A holder beside the model root, NOT under the bone. Deliberately not a child of
	# root either: first person hides the model, and in Godot a hidden ancestor hides
	# every descendant — which would take the weapon with it and leave you holding
	# nothing. update_weapon() writes a global transform, so the parent is arbitrary.
	_holder = Node3D.new()
	_holder.top_level = false
	var holder_parent: Node = root.get_parent()
	if holder_parent == null:
		holder_parent = root
	holder_parent.add_child(_holder)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.10, 0.11, 0.13)
	metal.roughness = 0.38
	metal.metallic = 0.80

	var poly := StandardMaterial3D.new()
	poly.albedo_color = Color(0.07, 0.07, 0.08)
	poly.roughness = 0.72
	poly.metallic = 0.05

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.26, 0.27, 0.29)
	steel.roughness = 0.34
	steel.metallic = 0.90

	# A real pistol reads by CONTRAST between its parts, not by any one of them: a blued
	# slide and barrel against a matte black polymer frame, with a harder rubber grip below
	# that. One dark metal for the lot is what made both weapons look like machined blocks
	# however much geometry was bolted on.
	var blued := StandardMaterial3D.new()
	blued.albedo_color = Color(0.055, 0.058, 0.068)
	blued.roughness = 0.26
	blued.metallic = 0.92
	var grip_mat := StandardMaterial3D.new()
	grip_mat.albedo_color = Color(0.038, 0.038, 0.042)
	grip_mat.roughness = 0.88
	grip_mat.metallic = 0.02

	# Both props point along local +Z, which is the axis update_weapon aligns.
	# Built from primitives but with the parts that make a gun legible at a glance:
	# a slide with sights and serrations, a frame, an angled grip, a trigger and
	# guard, a magazine base, and a barrel that actually protrudes.
	_pistol = Node3D.new()
	_part(_pistol, _box(0.025, 0.030, 0.188), Vector3(0, 0.0, 0.062), blued)      # slide
	_part(_pistol, _box(0.023, 0.024, 0.150), Vector3(0, -0.028, 0.046), poly)    # frame
	# the visible controls every service pistol has, on the left where you would see them
	_part(_pistol, _box(0.004, 0.007, 0.026), Vector3(-0.014, -0.006, 0.020), steel)  # slide stop
	_part(_pistol, _box(0.004, 0.010, 0.008), Vector3(-0.014, -0.020, 0.010), steel)  # takedown
	_part(_pistol, _box(0.006, 0.008, 0.006), Vector3(-0.013, -0.040, 0.030), steel)  # mag release
	_part(_pistol, _box(0.006, 0.009, 0.006), Vector3(0, 0.028, 0.140), metal)    # front sight
	_part(_pistol, _box(0.022, 0.009, 0.007), Vector3(0, 0.028, -0.020), metal)   # rear sight
	for i in 4:                                                                    # slide serrations
		_part(_pistol, _box(0.033, 0.030, 0.004), Vector3(0, 0.0, -0.010 - 0.012 * i), steel)
	_part(_pistol, _box(0.022, 0.020, 0.006), Vector3(0.016, 0.004, 0.030), poly) # ejection port
	var barrel := _cyl(0.0085, 0.0085, 0.075)
	_part(_pistol, barrel, Vector3(0, 0.004, 0.185), steel, Vector3(PI * 0.5, 0, 0))
	# grip raked back the way a real one is, then the magazine base under it
	var grip := Node3D.new()
	grip.position = Vector3(0, -0.030, 0.010)
	grip.rotation.x = deg_to_rad(-16.0)
	_pistol.add_child(grip)
	_part(grip, _box(0.028, 0.112, 0.046), Vector3(0, -0.052, 0), grip_mat)
	# finger grooves down the front strap, which is what makes a grip look like a grip
	for i in 3:
		_part(grip, _box(0.026, 0.006, 0.048), Vector3(0, -0.022 - 0.030 * i, 0.001), poly)
	_part(grip, _box(0.030, 0.010, 0.048), Vector3(0, -0.108, 0), steel)   # magazine base
	# trigger guard as a real loop, with the trigger inside it
	var guard := TorusMesh.new()
	guard.inner_radius = 0.016
	guard.outer_radius = 0.021
	_part(_pistol, guard, Vector3(0, -0.050, 0.038), poly, Vector3(0, PI * 0.5, 0))
	_part(_pistol, _box(0.005, 0.020, 0.006), Vector3(0, -0.048, 0.036), steel)

	_shotgun = Node3D.new()
	_part(_shotgun, _box(0.042, 0.058, 0.150), Vector3(0, 0.006, 0.010), blued)   # receiver
	_part(_shotgun, _box(0.006, 0.010, 0.020), Vector3(-0.022, -0.010, 0.020), steel) # action bar
	_part(_shotgun, _box(0.008, 0.008, 0.008), Vector3(0, 0.032, 0.000), steel)   # safety
	_part(_shotgun, _box(0.020, 0.020, 0.008), Vector3(0.024, 0.012, 0.030), poly)  # port
	var sbarrel := _cyl(0.0115, 0.0115, 0.470)
	_part(_shotgun, sbarrel, Vector3(0, 0.020, 0.320), blued, Vector3(PI * 0.5, 0, 0))
	var tube := _cyl(0.0090, 0.0090, 0.400)
	_part(_shotgun, tube, Vector3(0, -0.008, 0.290), metal, Vector3(PI * 0.5, 0, 0))
	# a ROUND bead: it is the one part you actually aim by, and as a box it vanished
	var bead := SphereMesh.new()
	bead.radius = 0.0040
	bead.height = 0.0080
	_part(_shotgun, bead, Vector3(0, 0.035, 0.556), steel)
	_part(_shotgun, _box(0.046, 0.042, 0.130), Vector3(0, -0.004, 0.190), poly)   # forend
	for i in 5:                                                                    # forend ribs
		_part(_shotgun, _box(0.048, 0.044, 0.004), Vector3(0, -0.004, 0.146 + 0.022 * i), poly)
	_part(_shotgun, _box(0.040, 0.048, 0.200), Vector3(0, -0.004, -0.155), poly)  # stock
	_part(_shotgun, _box(0.036, 0.030, 0.060), Vector3(0, 0.018, -0.235), poly)   # comb
	_part(_shotgun, _box(0.042, 0.052, 0.016), Vector3(0, -0.010, -0.262), steel) # butt pad
	var sguard := TorusMesh.new()
	sguard.inner_radius = 0.018
	sguard.outer_radius = 0.023
	_part(_shotgun, sguard, Vector3(0, -0.052, 0.000), poly, Vector3(0, PI * 0.5, 0))
	_part(_shotgun, _box(0.005, 0.022, 0.006), Vector3(0, -0.050, -0.002), steel)

	for part in [_pistol, _shotgun]:
		_holder.add_child(part)
		part.visible = false
	_pistol.visible = true


## One primitive of a weapon prop.
func _part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.rotation = rot
	m.material_override = mat
	parent.add_child(m)
	return m


func _box(w: float, h: float, d: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return b


func _cyl(r: float, top: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = r
	c.top_radius = top
	c.height = h
	c.radial_segments = 12
	return c


## World position of the muzzle, so a tracer can be drawn out of the gun rather than out
## of the camera. This is drawing only — the shot ray itself is cast from the camera so
## that the crosshair stays honest (see game.gd _fire).
## The intruder's kit: a beanie, gloves and a holdall.
##
## He is a shirtless, heavily muscled Mixamo man, which reads as NAKED rather than as a
## burglar — the audit's point, and most of why the two characters are hard to tell apart
## at a glance. There is no clothed mesh to swap in, so the kit is built from primitives
## and ridden on the bones, exactly as both characters' weapons already are.
## Pose the arms into a carry. Attached to the SKELETON, because a SkeletonModifier3D only
## runs for the skeleton it belongs to, and because it has to run after the AnimationPlayer
## has written the frame — which is exactly what that hook is for.
func attach_carry_pose() -> void:
	if _skeleton == null:
		return
	var script := load("res://scripts/carry_pose.gd")
	if script == null:
		push_warning("Actor: missing carry_pose.gd")
		return
	carry_pose = script.new() as SkeletonModifier3D
	carry_pose.name = "CarryPose"
	_skeleton.add_child(carry_pose)


## 0 = arms as the animation leaves them, 1 = holding something in front.
func set_carry(amount: float) -> void:
	if carry_pose != null:
		carry_pose.weight = clampf(amount, 0.0, 1.0)


## Curl the trigger hand's fingers so it grips whatever it is holding.
##
## The axis and sign are MEASURED by test/probe_grip.gd, which sweeps all six candidates and
## reports which one brings the fingertips toward the palm: X, sign +1, taking the mean
## fingertip-to-palm distance from 0.1836 m at rest to 0.1593 m closed.
func attach_grip_pose() -> void:
	if _skeleton == null:
		return
	var script := load("res://scripts/grip_pose.gd")
	if script == null:
		push_warning("Actor: missing grip_pose.gd")
		return
	grip_pose = script.new() as SkeletonModifier3D
	grip_pose.name = "GripPose"
	grip_pose.set("axis", 0)
	grip_pose.set("axis_sign", 1.0)
	grip_pose.set("hand", "Right")
	_skeleton.add_child(grip_pose)


## 0 = fingers as the animation leaves them, 1 = closed on a grip.
func set_grip(amount: float) -> void:
	if grip_pose != null:
		grip_pose.weight = clampf(amount, 0.0, 1.0)


func attach_kit() -> void:
	if root == null or _skeleton == null:
		return
	# Beside `root`, never under it, and for the same reason the weapon is: a hidden
	# ancestor hides every descendant, and the model is hidden when the camera jams
	# against a wall behind the player.
	var holder_parent: Node = root.get_parent()
	if holder_parent == null:
		holder_parent = root
	kit_root = Node3D.new()
	holder_parent.add_child(kit_root)

	# The mesh itself is bare skin from the collarbones down, and a shirtless man with a
	# beanie on still reads as a naked man with a beanie on. There is no clothed variant to
	# swap in, so the BODY MATERIAL is darkened instead — which takes the face with it, and
	# a dark face under a dark hat is exactly what a balaclava looks like.
	#
	# Only `root` is walked, so the weapons on the holder beside it are untouched.
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		for surf in mi.get_surface_override_material_count():
			pass
		var src := mi.get_active_material(0)
		if src is StandardMaterial3D and mi.material_override == null:
			var dup := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
			# 0.24 was so dark that every tonal boundary in the character's own texture
			# vanished and he rendered as a flat silhouette. Richard: "the thief is all
			# black, we need some detail." This MULTIPLIES the existing texture rather than
			# replacing it, so the detail was always there to recover — it just needed
			# lifting above the point where the tonemapper crushes it to black.
			dup.albedo_color = dup.albedo_color * Color(0.34, 0.35, 0.41)
			mi.material_override = dup

	# Kit pieces are deliberately DIFFERENT tones from each other and from the body. A single
	# near-black for all of them is what made him read as one shape.
	var hat := StandardMaterial3D.new()
	hat.albedo_color = Color(0.150, 0.152, 0.175)
	hat.roughness = 0.94
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color(0.070, 0.071, 0.082)
	glove.roughness = 0.80
	var cloth := StandardMaterial3D.new()
	# a worn olive canvas, so the bag is legible against him and against the world
	cloth.albedo_color = Color(0.215, 0.205, 0.155)
	cloth.roughness = 0.97

	_beanie = _part(kit_root, _cyl(0.098, 0.082, 0.105), Vector3.ZERO, hat)
	_beanie.name = "Beanie"
	_bag = _part(kit_root, _box(0.28, 0.32, 0.13), Vector3.ZERO, cloth)
	_bag.name = "Holdall"
	for i in 2:
		var g := _part(kit_root, _box(0.082, 0.098, 0.150), Vector3.ZERO, glove)
		g.name = "Glove%d" % i
		_gloves.append(g)


func _kit_bone(suffix: String) -> int:
	if not _kit_bones.has(suffix):
		var found := -1
		for i in _skeleton.get_bone_count():
			if String(_skeleton.get_bone_name(i)).ends_with(suffix):
				found = i
				break
		_kit_bones[suffix] = found
	return int(_kit_bones[suffix])


## World transform of a bone, or identity if the rig has no such bone.
func _bone_tf(suffix: String) -> Transform3D:
	var i := _kit_bone(suffix)
	if i < 0 or _skeleton == null:
		return Transform3D()
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(i)


## Called every frame, AFTER the animation has written the pose. A bone global read before
## that is last frame's, which makes the hat lag by a frame and swim on the head.
func update_kit() -> void:
	if kit_root == null or _skeleton == null:
		return
	if _kit_bone("Head") >= 0:
		var h := _bone_tf("Head")
		# the bone's origin is the base of the skull and +Y runs up it
		h.origin += h.basis.y * 0.075
		_beanie.global_transform = h
	if _kit_bone("RightHand") >= 0:
		_gloves[0].global_transform = _bone_tf("RightHand")
	if _kit_bone("LeftHand") >= 0:
		_gloves[1].global_transform = _bone_tf("LeftHand")
	if _kit_bone("Spine2") >= 0:
		# only the POSITION comes from the spine; the orientation comes from the body's
		# yaw, so the bag hangs upright instead of rolling with his shoulders
		var b := carry_basis()
		_bag.global_transform = Transform3D(b, _bone_tf("Spine2").origin - b.z * 0.155)


func muzzle() -> Vector3:
	if _holder == null:
		return Vector3.ZERO
	var t := _holder.global_transform
	return t.origin + t.basis.z * 0.40


## Hand bone world position, for placing something the character is HOLDING.
##
## Origin only, deliberately. A Mixamo hand bone's own axes are rotated relative to the
## character — parenting a prop to it is what once pointed the shotgun down between his
## legs — so callers take the position and supply their own orientation.
func hand_origin() -> Vector3:
	if _skeleton == null or _hand_bone < 0:
		return root.global_position if root != null else Vector3.ZERO
	return (_skeleton.global_transform * _skeleton.get_bone_global_pose(_hand_bone)).origin


## Upright, yaw-only basis for orienting a carried object. Using the character's facing
## rather than the hand's keeps a carried TV the right way up while it still follows the
## arm, because only the POSITION is taken from the bone.
func carry_basis() -> Basis:
	if root == null:
		return Basis()
	return Basis(Vector3.UP, root.rotation.y)


## Curl the right hand's fingers so it reads as gripping something.
##
## There is no carry or grab animation in the asset set — the clips are idle, walk, run,
## crouch_idle, crouch_walk, aim, shoot, reload and death — so the hand cannot be posed
## by playing one. The fingers are real bones, so they are curled directly.
##
## This must run AFTER the AnimationPlayer has written the pose for the frame, which is
## why game.gd calls it at the end of _process and not from tick().
func grip(amount: float) -> void:
	if _skeleton == null or amount <= 0.0:
		return
	if _finger_bones.is_empty():
		for i in _skeleton.get_bone_count():
			var n := String(_skeleton.get_bone_name(i))
			if n.contains("RightHand") and n != "mixamorig:RightHand" \
					and not n.ends_with("RightHand"):
				_finger_bones.append(i)
	for i in _finger_bones:
		var n := String(_skeleton.get_bone_name(i))
		# the thumb folds the other way, and the middle joint of a finger bends most
		var dir := -1.0 if n.contains("Thumb") else 1.0
		var seg := 1.0
		if n.ends_with("2"):
			seg = 1.30
		elif n.ends_with("3"):
			seg = 0.85
		_skeleton.set_bone_pose_rotation(i,
			Quaternion(Vector3.RIGHT, amount * seg * dir))


## Called every frame with the direction the player is aiming.
func update_weapon(aim_dir: Vector3) -> void:
	if _holder == null or _skeleton == null:
		return
	var hand := root.global_transform
	if _hand_bone >= 0:
		hand = _skeleton.global_transform * _skeleton.get_bone_global_pose(_hand_bone)

	var fwd := aim_dir
	if fwd.length() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var up := Vector3.UP
	if absf(fwd.dot(up)) > 0.98:
		up = Vector3.RIGHT
	var right := fwd.cross(up).normalized()
	var real_up := right.cross(fwd).normalized()
	# basis whose local +Z is the aim direction, matching how the props are built
	_holder.global_transform = Transform3D(Basis(right, real_up, fwd), hand.origin)


func set_weapon(which: String) -> void:
	if _pistol != null:
		_pistol.visible = which == "pistol"
	if _shotgun != null:
		_shotgun.visible = which == "shotgun"
