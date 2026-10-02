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
			a._add_clip(IDLE, a.anim.get_animation(idle_src))

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
	var a := anim.get_animation(name)
	_one_shot_t = a.length if a else 0.6
	anim.speed_scale = 1.0
	anim.play(name, 0.08)


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

	# a holder under the model root, NOT under the bone
	_holder = Node3D.new()
	_holder.top_level = false
	root.add_child(_holder)

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
