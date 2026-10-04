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

const CLIP_FILES := [WALK, RUN, CROUCH_IDLE, CROUCH_WALK, AIM, SHOOT, RELOAD, DEATH]

## Clips meant to run forever; everything else is a one-shot that holds its last
## frame. A Mixamo export sets none of this, so every clip arrived as LOOP_NONE —
## which is why the walk froze mid-stride after a single cycle.
const LOOPING := [IDLE, WALK, RUN, CROUCH_IDLE, CROUCH_WALK]

## Where the first gunshot lands inside SHOOT, and how long to stay in the shoot
## pose. That clip is 2.67 s and holds two shots — the right forearm spikes to
## 43 deg/step at 0.44 s and again at 2.00 s (measured in test/anim_probe.gd).
## Seeking past the wind-up makes every trigger pull show the shot itself, and the
## short window hands the locomotion animation back quickly instead of freezing
## the legs for the clip's full 2.67 s.
const SHOOT_SEEK := 0.36
const ONE_SHOT_WINDOW := 0.42

var root: Node3D
var anim: AnimationPlayer
var ground_offset := 0.0
var base_scale := 1.0
var merged := 0
var _pistol: Node3D = null
var _shotgun: Node3D = null
var _holder: Node3D = null
var _skeleton: Skeleton3D = null
var _hand_bone := -1
var _current := ""
var _one_shot := ""
var _one_shot_t := 0.0
var _clip_mps := {}


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
	metal.roughness = 0.42
	metal.metallic = 0.75

	# Both props point along local +Z, which is the axis update_weapon aligns.
	_pistol = Node3D.new()
	var slide := MeshInstance3D.new()
	var sb := BoxMesh.new(); sb.size = Vector3(0.075, 0.10, 0.34)
	slide.mesh = sb; slide.position = Vector3(0, 0.02, 0.15)
	_pistol.add_child(slide)
	var grip := MeshInstance3D.new()
	var gb := BoxMesh.new(); gb.size = Vector3(0.070, 0.17, 0.085)
	grip.mesh = gb; grip.position = Vector3(0, -0.10, 0.0)
	_pistol.add_child(grip)

	_shotgun = Node3D.new()
	var barrel := MeshInstance3D.new()
	var rb := CylinderMesh.new(); rb.top_radius = 0.035; rb.bottom_radius = 0.035; rb.height = 0.85
	barrel.mesh = rb
	# CylinderMesh runs along +Y; tip it so it runs along +Z like the pistol
	barrel.rotation.x = PI * 0.5
	barrel.position = Vector3(0, 0.02, 0.30)
	_shotgun.add_child(barrel)
	var stock := MeshInstance3D.new()
	var tb := BoxMesh.new(); tb.size = Vector3(0.085, 0.12, 0.36)
	stock.mesh = tb; stock.position = Vector3(0, -0.02, -0.10)
	_shotgun.add_child(stock)

	for part in [_pistol, _shotgun]:
		_holder.add_child(part)
		for c in part.get_children():
			(c as MeshInstance3D).material_override = metal
		part.visible = false
	_pistol.visible = true


## The first-person weapon is drawn smaller than the one the intruder holds. That is
## normal for a viewmodel and invisible to the player, but it matters here: at world
## scale and this distance the pistol still covered the lower right of the frame.
const VIEWMODEL_SCALE := 0.75
## How far the gun slides toward the aim, in metres per unit of tangent. Roughly the swing
## of a real arm at this distance; 0 pins the gun in place and only turns it.
const VIEWMODEL_SWING := 0.42


## First-person viewmodel placement.
##
## In third person the prop rides the animated right hand, which sits about 0.45 m below
## the eye. With the camera now at the eye that is roughly 56 degrees off axis — far
## outside a 68 degree frame — so the gun vanished completely. A first-person weapon is
## normally presented at a fixed offset in front of the camera instead. The basis is
## built exactly as update_weapon() builds it, so the prop looks identical either way.
##
## Must be called AFTER the camera moves, or the gun trails the view by a frame.
func update_viewmodel(cam: Camera3D, aim_dir: Vector3) -> void:
	if _holder == null or cam == null:
		return
	# Position is fixed in camera space; only the orientation follows the aim. That is
	# what makes the gun visibly swing across the screen in cone mode instead of staying
	# welded to one spot.
	var cf := -cam.global_transform.basis.z
	var cu := Vector3.UP
	if absf(cf.dot(cu)) > 0.98:
		cu = Vector3.RIGHT
	var cright := cf.cross(cu).normalized()
	var cup := cright.cross(cf).normalized()
	# Held low and to the right, pushed out to 0.58 m. At 0.36 m the grip sat 0.26 m from
	# the eye and covered a third of the screen.
	var origin := cam.global_position + cright * 0.20 + cup * -0.15 + cf * 0.58

	var fwd := aim_dir
	if fwd.length() < 0.001:
		fwd = cf
	fwd = fwd.normalized()

	# Swing the gun toward the aim as well as turning it, which is what an arm actually
	# does: aiming 20 degrees off the body moves the hand, not just the wrist. Without
	# this the gun only rotated about its grip and barely travelled on screen, so cone mode
	# looked like nothing was happening.
	var cz := maxf(fwd.dot(cf), 0.15)
	origin += cright * (fwd.dot(cright) / cz * VIEWMODEL_SWING) \
		+ cup * (fwd.dot(cup) / cz * VIEWMODEL_SWING)

	var world_up := Vector3.UP
	if absf(fwd.dot(world_up)) > 0.98:
		world_up = Vector3.RIGHT
	var right := fwd.cross(world_up).normalized()
	var real_up := right.cross(fwd).normalized()
	var b := Basis(right, real_up, fwd).scaled(Vector3(VIEWMODEL_SCALE, VIEWMODEL_SCALE,
		VIEWMODEL_SCALE))
	_holder.global_transform = Transform3D(b, origin)


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
