extends Node3D

## Home Invasion — main controller.
##
## Division of labour: Sim owns every gameplay decision (movement collision,
## pathing, the thief's brain, damage, visibility). This file owns presentation
## and input, and mirrors Sim's rects into Godot physics bodies purely so that
## bullets can be traced in 3D.

const LAYER_WORLD := 1
const LAYER_THIEF := 2

## Mixamo characters. Each folder holds idle.fbx (the mesh-carrying export) plus
## eight animation-only files that actor.gd merges in at runtime. Mixamo rigs are
## standardised, so clips retarget without work, and it finally gives us proper
## pistol animations — Aiming Gun, Shooting Pistol, Reloading.
const CHAR_PLAYER := "res://assets/mixamo/player"
const CHAR_THIEF := "res://assets/mixamo/thief"
const CHAR_SCALE := 1.0

var player := {}
var thief := {}
var loot: Array = []
var events: Array = []
var state := "play"

var player_actor: Actor
var thief_actor: Actor
var thief_hitbox: StaticBody3D
var cam: Camera3D
var sun: DirectionalLight3D
var minimap: Minimap

var yaw := 0.0
var pitch := 0.24
var msg := ""
var msg_t := 0.0
var fire_held := false

# ------------------------------------------------------------------ aim scheme
#
# `yaw`/`pitch` are the BODY: they orient the view, and movement is relative to them.
# `aim_yaw`/`aim_pitch` are an offset from the body, and the gun and the bullets follow
# that. With aim_cone false the offset is forced to zero and the two are the same thing,
# which is the ordinary first-person behaviour.
#
# In cone mode the mouse moves the aim within a cone in front of you and the view holds
# still, so the crosshair and the gun visibly travel across the screen. Push the aim to
# the edge of the cone and the body turns to follow it; walking also turns the body
# toward wherever you are aiming, so the view catches up on its own.
#
# Toggle at runtime with T. Richard asked for this as an experiment, explicitly to be
# reverted to plain first person if he does not like it, so both paths stay live.
const CONE_YAW := 0.61          # ~35 degrees either side
const CONE_PITCH := 0.38        # ~22 degrees up and down
const CONE_RECENTRE := 3.2      # rad/s the body turns toward the aim while walking
const AIM_SENS_X := 0.0022
const AIM_SENS_Y := 0.0018
const PITCH_MIN := -0.30        # looking up
const PITCH_MAX := 0.85         # looking down
## View kick per shot in radians, and how fast it settles. A pistol barely moves the
## sights; a shotgun shoves them. Firing used to leave the view perfectly still, which
## is a large part of why shooting read as a cursor click rather than a gun going off.
const RECOIL := {"pistol": 0.022, "shotgun": 0.062}
const RECOIL_RECOVER := 0.85    # rad/s the view drifts back

## Camera offset behind and above the homeowner's eye. At zero the camera is inside his
## head and he must be hidden; pulled back he is drawn, which is what Richard asked for.
##
## A foot is very close: at 0.30 m his head is 0.22 m wide and subtends about 40 degrees,
## which is more than half the width of the screen. CAM_BACK is the value that actually
## reads, and it is a single number to tune.
const CAM_BACK := 0.90
## Ceiling on the lift, and it is a gameplay limit rather than a taste one: the walls are
## 2.0 m and the eye is 1.65 m, so much above +0.25 m the camera rises over the walls and
## the house becomes a dollhouse — you see the intruder over cover the minimap hides.
const CAM_UP := 0.22
## Sideways offset. A gun held in front of the body is hidden by the body from directly
## behind, so seeing the weapon at all needs the camera off his shoulder.
const CAM_SIDE := 0.42
## Below this camera-to-eye distance the model is hidden. A long boom in a small house
## jams against the wall behind constantly, and a jammed camera sits inside his back.
const CAM_FADE := 0.42

var aim_cone := false
var aim_yaw := 0.0
var aim_pitch := 0.0
## Radians of view kick still to drift back down after a shot.
var recoil_recover := 0.0
## Live camera offset, so the distance can be tuned without a code edit.
var cam_back := CAM_BACK
var cam_up := CAM_UP
var cam_side := CAM_SIDE

var _lbl_hp: Label
var _lbl_weapon: Label
var _lbl_ammo: Label
var _lbl_stance: Label
var _lbl_loot: Label
var _lbl_banner: Label
var _bar: ColorRect
var _overlay: Panel
var _ov_title: Label
var _ov_sub: Label
var _tracers: Array = []
var _loot_nodes: Array = []
var _crosshair: Control

# --------------------------------------------------------------------- effects
#
# The hit point has always been computed and then thrown away — used only as the tracer's
# end — so nothing in the house ever showed that it had been shot. Marks are POOLED and
# reused oldest-first rather than freed, because one shotgun blast is nine of them and a
# long round would otherwise churn dozens of nodes per trigger pull.
const MARK_MAX := 48
var _marks: Array[MeshInstance3D] = []
var _mark_i := 0
var _mark_mat: StandardMaterial3D
var _flash: MeshInstance3D
var _flash_t := 0.0
## Set when he breaks off and runs, so the loss text can say how much he got away with
## rather than claiming he took everything.
var _ran_off := false
var _escaped_with := 0

# ------------------------------------------------------------------------ audio
#
# The project had NO audio at all until 2026-10-04 — no AudioStreamPlayer, nothing on
# disk. The intruder arrived in complete silence, which for a home invasion removes the
# sense you would actually rely on: you hear him before you see him.
#
# The samples are synthesised by tools/gen-sfx.py, not recorded. There was no library to
# download and no microphone in the loop, and it turns out that suits this set — a
# gunshot is a noise transient over a low thump and a footstep is a filtered click, and
# both of those synthesis does convincingly. It would not work for a voice.
#
# The player's own gun is a plain AudioStreamPlayer: it is at the listener, so 3D
# positioning buys nothing and risks an odd pan. Everything in the world is a 3D player,
# so the intruder's shots come FROM the intruder and are muffled by distance.
var _snd_own: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i := 0
var _sfx := {}
var _step_player := 0.0
var _step_thief := 0.0
var _thief_door_z := 0.0

# Debug: `godot --path . -- --shot` renders 120 frames, writes shot.png next to
# the project and quits. Lets the build be verified visually without a human.
var _shot_frames := -1
var _shot_path := "res://shot.png"
var _shot_moved := false
var _shot_yaw := INF
var _shot_pitch := INF
var _shot_after := 0.0
var _shot_wait := 0.0
var _shot_pos := Vector2(INF, INF)
var _shot_hide_player := false
## Hold an aim offset for screenshots. Cone mode only moves the crosshair in response to
## mouse motion, and a screenshot has no mouse, so without this the cone state cannot be
## photographed at all.
var _shot_aim := 0.0
## Force the intruder to be carrying a named item, so the hand attachment can be
## photographed on demand instead of hunting for the moment he happens to pick one up.
## He only grabs three times in a ~99 s round and the window is a few seconds wide.
var _shot_carry := ""
## Hold the trigger during a capture. Without it a screenshot fires nothing — there is no
## mouse — so anything that only happens when you shoot (impact marks, the muzzle flash,
## recoil) cannot be photographed at all.
var _shot_fire := false


func _ready() -> void:
	# Process AFTER the scene tree's own nodes. The AnimationPlayer is a descendant and
	# writes the skeleton pose during its process step, so anything that overrides a bone
	# — Actor.grip() — would be overwritten every frame at the default priority.
	process_priority = 100
	_setup_environment()
	House.build_all(self)
	_build_collision()
	_spawn_actors()
	_build_hud()
	_build_audio()
	_build_effects()
	reset()
	_build_loot()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	var args := OS.get_cmdline_user_args()
	# debug: start holding the shotgun so the export can be eyeballed with it
	if args.has("--shotgun") and player_actor != null:
		player["weapon"] = "shotgun"
		player["mag"] = Sim.WEAPONS["shotgun"]["mag"]
		player_actor.set_weapon("shotgun")
	if args.has("--shot"):
		_shot_frames = 140
	for a in args:
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
			_shot_frames = 140
		if a == "--shot-moved":
			_shot_moved = true
		# aim control, so a screenshot can be pointed at a chosen background:
		# verifying a HUD change against the right backdrop otherwise means guessing
		if a.begins_with("--shot-yaw="):
			_shot_yaw = float(a.substr(11))
		if a.begins_with("--shot-pitch="):
			_shot_pitch = float(a.substr(13))
		# let the round run this many seconds first, so mid-game states (an intruder
		# actually carrying something, a delivery pile) can be captured at all
		if a.begins_with("--shot-after="):
			_shot_after = float(a.substr(13))
			_shot_wait = _shot_after
		# stand somewhere specific. Rooms are walled off from the spawn, so without
		# this the only thing photographable is whatever you can see from the hall.
		if a.begins_with("--shot-pos="):
			var bits := a.substr(11).split(",")
			if bits.size() == 2:
				_shot_pos = Vector2(float(bits[0]), float(bits[1]))
		# the camera sits behind the pawn, so he occludes whatever is directly in
		# front of him — which is exactly what a prop inspection wants to see
		if a == "--shot-hide-player":
			_shot_hide_player = true
		if a.begins_with("--shot-aim="):
			_shot_aim = float(a.substr(11))
		if a.begins_with("--carry="):
			_shot_carry = a.substr(8)
		if a == "--shot-fire":
			_shot_fire = true
		# force the fallback scheme, so "does reverting still work" is checkable
		if a == "--aim=fixed":
			aim_cone = false
		if a.begins_with("--cam-back="):
			cam_back = float(a.substr(11))
		if a.begins_with("--cam-up="):
			cam_up = float(a.substr(9))
		if a.begins_with("--cam-side="):
			cam_side = float(a.substr(11))


# ------------------------------------------------------------- environment
func _setup_environment() -> void:
	# Cinematic dark, modelled on the reference screenshots: almost no ambient
	# fill, a few strong motivated sources, and the contrast carried by shadow
	# rather than by brightness. The previous version lit the scene flat and
	# evenly, which exposed every flat texture instead of hiding it.
	var we := WorldEnvironment.new()
	var env := Environment.new()

	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	# Daytime, deliberately. Dusk looked better, but you could not see the van or watch
	# the intruder cross the driveway, and those are the two things the round is about.
	# The dusk values are kept here so the mood can be restored: top (0.100,0.130,0.200),
	# horizon (0.235,0.260,0.310), ground bottom (0.055,0.060,0.070), ground horizon
	# (0.130,0.140,0.155), sun energy 0.28 in (0.58,0.70,0.95), ambient 0.22.
	sm.sky_top_color = Color(0.150, 0.330, 0.650)
	sm.sky_horizon_color = Color(0.640, 0.760, 0.880)
	sm.ground_bottom_color = Color(0.180, 0.190, 0.180)
	sm.ground_horizon_color = Color(0.480, 0.540, 0.520)
	sm.sun_angle_max = 8.0
	sky.sky_material = sm
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Daylight sky as ambient. Godot does not occlude skylight, so this lights the
	# interior too — which is exactly why the house now needs a ceiling to keep the
	# direct sun out (see House.build_all).
	env.ambient_light_energy = 0.55
	# sky_contribution below 1.0 is what stops the ceilings rendering black. A sky-only
	# ambient is DIRECTIONAL: an upward-facing floor samples the bright upper hemisphere,
	# a downward-facing ceiling samples the dark ground half, and the most visible surface
	# in every interior got almost nothing. Blending in a plain colour lifts it.
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_color = Color(0.62, 0.60, 0.56)

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 3.0

	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 3.0
	env.ssao_power = 1.6

	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.10
	# daylight pushes most of the frame past the old 0.85 threshold, which bloomed the
	# whole image; raise it so only genuinely bright things glow
	env.glow_hdr_threshold = 1.60
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	# a touch of distance haze, nothing like the night fog this replaces
	env.fog_light_color = Color(0.600, 0.680, 0.780)
	env.fog_density = 0.0035
	# fog_sky_affect=1.0 tints the SKY with the fog colour, which crushed the whole
	# upper frame to black. Let the sky show through; the fog still works on geometry.
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0

	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.0

	we.environment = env
	add_child(we)

	# --- the sun, now the key light. It used to be a weak cool rim whose only job was
	#     to separate the house from the night; outside is meant to be readable now, so
	#     this carries the daylight and casts the exterior shadows.
	sun = DirectionalLight3D.new()
	# Y = 216, not 36: the light travels along its own -Z, so at 36 it came from the
	# south and left the intruder's front — the side you look at as he walks up the
	# drive — in shadow, a black silhouette with no visible pistol. Flipped, he is lit
	# as he approaches, which is the whole point of the daylight change.
	sun.rotation_degrees = Vector3(-52, 216, 0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_bias = 0.03
	add_child(sun)

	# --- warm interior practicals. These do the real work: strong, local, with
	#     real falloff, so the rooms read as pools of light in a dark house.
	var warm := Color(1.0, 0.78, 0.50)
	var practicals := [
		[Vector3(-5.4, 2.0, -11.0), 9.0, 9.0],   # living room
		[Vector3(-6.9, 1.5, -9.7),  5.0, 4.5],   # the floor lamp
		[Vector3( 5.8, 2.0, -11.0), 8.0, 9.0],   # kitchen
		[Vector3( 0.0, 2.0, -11.0), 6.0, 7.0],   # front hall
		[Vector3( 0.0, 2.0, -14.4), 5.0, 5.0],   # the interior opening
		[Vector3(-5.5, 1.9, -17.0), 6.0, 8.0],   # bedroom
		[Vector3( 5.5, 1.9, -17.0), 6.0, 8.0],   # study
	]
	for spec in practicals:
		var l := OmniLight3D.new()
		l.position = spec[0]
		l.light_color = warm
		l.light_energy = spec[1]
		l.omni_range = spec[2]
		l.omni_attenuation = 1.6
		l.shadow_enabled = true
		l.shadow_bias = 0.04
		add_child(l)

	# a cold spill on the driveway so the van area is not pitch black
	var porch := OmniLight3D.new()
	porch.position = Vector3(0, 2.2, -7.0)
	porch.light_color = Color(0.75, 0.82, 1.0)
	porch.light_energy = 3.5
	porch.omni_range = 8.0
	add_child(porch)

	cam = Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.08
	cam.far = 300.0
	add_child(cam)


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "WorldCollision"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	for w in Sim.WALLS:
		_add_box(body, w, Sim.WALL_HEIGHT)
	for f in Sim.FURNITURE:
		if f.get("flat", false):
			continue
		_add_box(body, f["rect"], f["h"])

	# The floor, the ceiling and the van had NO collision at all, so a bullet passed
	# straight through them: you could not shoot the van, and a round aimed at the ground
	# carried on to the horizon. Movement does not use physics — the sim is 2D and owns
	# position — so these exist only to stop rays.
	var house := Sim.HOUSE
	_add_box_at(body, house, 0.14, -0.06)                       # floor slab
	_add_box_at(body, house, 0.22, House.WALL_TARGET_H + 0.11)  # ceiling slab
	_add_box_at(body, Sim.VAN, 1.8, 0.9)                        # the van


## Same as _add_box but with the box's vertical CENTRE given rather than its base.
func _add_box_at(parent: Node3D, r: Rect2, h: float, centre_y: float) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(r.size.x, h, r.size.y)
	cs.shape = shape
	cs.position = Vector3(r.position.x + r.size.x * 0.5, centre_y,
		r.position.y + r.size.y * 0.5)
	parent.add_child(cs)


func _add_box(parent: Node3D, r: Rect2, h: float) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(r.size.x, h, r.size.y)
	cs.shape = shape
	cs.position = Vector3(r.position.x + r.size.x * 0.5, h * 0.5,
		r.position.y + r.size.y * 0.5)
	parent.add_child(cs)


# ------------------------------------------------------------------ actors
func _spawn_actors() -> void:
	player_actor = Actor.create(CHAR_PLAYER, CHAR_SCALE)
	if player_actor.root != null:
		add_child(player_actor.root)
		House.ground_node(player_actor.root)
		player_actor.ground_offset = player_actor.root.position.y
		player_actor.attach_weapon()
		# the player dictionary does not exist yet — _spawn_actors runs before
		# reset(), so name the starting weapon literally rather than reading it
		player_actor.set_weapon("pistol")

	thief_actor = Actor.create(CHAR_THIEF, CHAR_SCALE)
	if thief_actor.root != null:
		add_child(thief_actor.root)
		House.ground_node(thief_actor.root)
		thief_actor.ground_offset = thief_actor.root.position.y
		# he carries a pistol as well; _update_actors holsters it while he is loaded up
		thief_actor.attach_weapon()
		thief_actor.set_weapon("pistol")

	# a separate body so bullet rays can tell the thief from the scenery
	thief_hitbox = StaticBody3D.new()
	thief_hitbox.name = "ThiefHitbox"
	thief_hitbox.collision_layer = LAYER_THIEF
	thief_hitbox.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.85, 0)
	thief_hitbox.add_child(cs)
	add_child(thief_hitbox)


# ---------------------------------------------------------------------- loot
## A visible, recognisable object per valuable, so the theft can actually be read.
##
## There never was one: the only cues that the intruder had taken something were the
## HUD counter, a greyed dot on the minimap, and — until the gaits were unified to
## fix foot-skating — the fact that a laden intruder walked where a hunting one ran.
## With that gone he simply left the house looking empty handed.
##
## Each item now sits on the floor where it belongs, rides with the intruder while he
## carries it, and is set down where he handed it over. Positioned from the actor's
## transform each frame, the same approach as the weapon props, rather than
## reparented — that avoids the BoneAttachment3D trap recorded in AGENTS.md.
##
## Every prop is assembled from boxes and cylinders, so there is nothing to import
## and no licence to worry about. Each is modelled with its base at y = 0, which is
## what lets the same node drop straight onto the floor at either end.
## Where a carried item's own origin sits relative to his hand, in his facing frame.
## Each prop is modelled with its base at y = 0, so these hang it off the grip: the
## laptop sits in the palm, the TV and the safe are carried by their top edge.
const CARRY_HANG := {
	"TV": Vector3(0.06, -0.60, 0.05),
	"Laptop": Vector3(0.02, -0.03, 0.07),
	"Safe": Vector3(0.05, -0.47, 0.06),
}


func _build_loot() -> void:
	for l in loot:
		var prop := _make_prop(String(l["label"]))
		prop.position = Vector3((l["pos"] as Vector2).x, 0.0, (l["pos"] as Vector2).y)
		add_child(prop)
		_loot_nodes.append(prop)


## One primitive of a prop.
func _part(parent: Node3D, mesh: Mesh, pos: Vector3, col: Color,
		rough: float = 0.55, metal: float = 0.0,
		rot: Vector3 = Vector3.ZERO) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.rotation = rot
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = rough
	mat.metallic = metal
	# a trace of self-illumination, so a valuable is still findable in a dim corner. These
	# are gameplay objectives, and at 0.10 they measured near-black in the bedroom — but
	# the scene is bright daylight and textured now, so this is back down to a hint rather
	# than the glow that stood in for lighting when everything was flat and dark.
	mat.emission_enabled = true
	mat.emission = col * 0.07
	m.material_override = mat
	parent.add_child(m)


func _box(w: float, h: float, d: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return b


## A stand-in for each valuable that reads as the thing it claims to be.
func _make_prop(label: String) -> Node3D:
	var p := Node3D.new()
	match label:
		"TV":
			# flat panel on a small stand: dark bezel, darker glossy screen
			_part(p, _box(0.98, 0.58, 0.05), Vector3(0, 0.50, 0.0), Color(0.10, 0.10, 0.12), 0.45)
			_part(p, _box(0.90, 0.50, 0.02), Vector3(0, 0.50, 0.036), Color(0.03, 0.04, 0.06), 0.12, 0.5)
			_part(p, _box(0.10, 0.18, 0.06), Vector3(0, 0.12, 0.0), Color(0.10, 0.10, 0.12), 0.45)
			_part(p, _box(0.48, 0.03, 0.22), Vector3(0, 0.015, 0.0), Color(0.10, 0.10, 0.12), 0.45)
		"Laptop":
			# base with a keyboard well, and a lid tipped back off the hinge
			_part(p, _box(0.34, 0.02, 0.24), Vector3(0, 0.01, 0.0), Color(0.70, 0.72, 0.75), 0.35, 0.6)
			_part(p, _box(0.29, 0.006, 0.14), Vector3(0, 0.023, 0.02), Color(0.13, 0.13, 0.15), 0.75)
			var lid := Node3D.new()
			lid.position = Vector3(0, 0.02, -0.12)
			lid.rotation.x = deg_to_rad(-100.0)
			p.add_child(lid)
			_part(lid, _box(0.34, 0.22, 0.014), Vector3(0, 0.11, 0.0), Color(0.70, 0.72, 0.75), 0.35, 0.6)
			_part(lid, _box(0.30, 0.18, 0.006), Vector3(0, 0.11, 0.010), Color(0.05, 0.06, 0.08), 0.15, 0.4)
		"Safe":
			# heavy dark body, proud door, dial and handle
			_part(p, _box(0.46, 0.46, 0.40), Vector3(0, 0.23, 0.0), Color(0.24, 0.25, 0.28), 0.55, 0.5)
			_part(p, _box(0.38, 0.38, 0.03), Vector3(0, 0.23, 0.205), Color(0.33, 0.34, 0.37), 0.50, 0.6)
			var dial := CylinderMesh.new()
			dial.top_radius = 0.05
			dial.bottom_radius = 0.05
			dial.height = 0.04
			# CylinderMesh runs along +Y, so tip it to face out of the door
			_part(p, dial, Vector3(0.09, 0.28, 0.23), Color(0.78, 0.79, 0.81),
				0.25, 0.9, Vector3(PI * 0.5, 0.0, 0.0))
			_part(p, _box(0.16, 0.035, 0.035), Vector3(0.09, 0.15, 0.23),
				Color(0.78, 0.79, 0.81), 0.25, 0.9)
		_:
			# an unrecognised label keeps a plain crate rather than nothing at all
			_part(p, _box(0.36, 0.30, 0.26), Vector3(0, 0.15, 0.0), Color(0.95, 0.73, 0.26), 0.45)
	return p


func _update_loot() -> void:
	for i in _loot_nodes.size():
		var prop: Node3D = _loot_nodes[i]
		var l: Dictionary = loot[i]
		if l["delivered"]:
			# set down where it was handed over, so you can see what he got away with
			prop.visible = true
			prop.position = Vector3(Sim.DROP.x - 0.55 + 0.55 * float(i), 0.0, Sim.DROP.y)
			prop.rotation.y = 0.6 * float(i)
		elif l["taken"]:
			# Held in his HAND. This used to hang off the model root, which sits at his
			# FEET, so the item floated at hip height — the laptop visibly hovering
			# between his thighs. The hand bone moves with the animation, so taking the
			# position from it is what makes the object look carried rather than glued
			# to his middle. Only the position comes from the bone; the orientation is
			# his facing, because a Mixamo hand bone's own axes are rotated.
			var ok := thief_actor != null and thief_actor.root != null
			prop.visible = ok
			if ok:
				var b := thief_actor.carry_basis()
				var hang: Vector3 = CARRY_HANG.get(String(l["label"]),
					Vector3(0.0, -0.30, 0.06))
				prop.global_transform = Transform3D(b,
					thief_actor.hand_origin() + b * hang)
		else:
			prop.visible = true
			prop.position = Vector3((l["pos"] as Vector2).x, 0.0, (l["pos"] as Vector2).y)
			prop.rotation.y = 0.0


# -------------------------------------------------------------------- state
func reset() -> void:
	player = Sim.create_player()
	thief = Sim.create_thief()
	loot = Sim.create_loot()
	events = []
	state = "play"
	_ran_off = false
	_escaped_with = 0
	msg = "DEFEND YOUR HOME"
	msg_t = 2.4
	yaw = 0.0
	pitch = 0.03
	# clear the aim offset, but deliberately leave aim_cone alone: the round restarts
	# without silently flipping the scheme the player just chose with T
	aim_yaw = 0.0
	aim_pitch = 0.0
	fire_held = false
	_overlay.visible = false
	_refresh_hud()


# -------------------------------------------------------------------- input
## Uses _input rather than _unhandled_input. A Control left on the default
## MOUSE_FILTER_STOP consumes clicks before the unhandled stage — and the
## centre-screen crosshair is made of ColorRects sitting exactly where you aim,
## so every shot was being eaten by the crosshair.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if aim_cone:
			# The mouse moves the aim, not the view. A view that never shifts under the
			# cursor is the whole point of the cone.
			aim_yaw -= event.relative.x * AIM_SENS_X
			aim_pitch = clampf(aim_pitch + event.relative.y * AIM_SENS_Y,
				-CONE_PITCH, CONE_PITCH)
			# Pushing past the edge turns the body with it, so you can still spin on the
			# spot — it just costs a deliberate push rather than a careless twitch.
			var over_y := absf(aim_yaw) - CONE_YAW
			if over_y > 0.0:
				yaw += signf(aim_yaw) * over_y
				aim_yaw = signf(aim_yaw) * CONE_YAW
			# Same at the vertical limits, where the body stops and the aim stops with it
			var total := clampf(pitch + aim_pitch, PITCH_MIN, PITCH_MAX)
			var over_p := (pitch + aim_pitch) - total
			if over_p != 0.0:
				pitch = total
				aim_pitch -= over_p
		else:
			yaw -= event.relative.x * AIM_SENS_X
			pitch = clampf(pitch + event.relative.y * AIM_SENS_Y, PITCH_MIN, PITCH_MAX)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		fire_held = event.pressed
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		elif event.keycode == KEY_ENTER and state != "play":
			reset()
		elif event.keycode == KEY_1 and state == "play":
			player["weapon"] = "pistol"
			player["mag"] = Sim.WEAPONS["pistol"]["mag"]
			player["reloading"] = 0.0
			if player_actor != null:
				player_actor.set_weapon("pistol")
		elif event.keycode == KEY_2 and state == "play":
			player["weapon"] = "shotgun"
			player["mag"] = Sim.WEAPONS["shotgun"]["mag"]
			player["reloading"] = 0.0
			if player_actor != null:
				player_actor.set_weapon("shotgun")
		elif event.keycode == KEY_R and state == "play":
			var spec: Dictionary = Sim.WEAPONS[player["weapon"]]
			if player["reloading"] <= 0.0 and player["mag"] < spec["mag"]:
				player["reloading"] = spec["reload"]
				# Actor.RELOAD was merged into every character from the beginning and
				# referenced nowhere — a clip the project paid for and never played.
				if player_actor != null:
					player_actor.play_for(Actor.RELOAD, float(spec["reload"]))
		elif event.keycode == KEY_T:
			# Both schemes stay live on purpose: this is an experiment, and Richard asked
			# to fall back to plain first person if he does not like the cone.
			aim_cone = not aim_cone
			aim_yaw = 0.0
			aim_pitch = 0.0
			msg = "Aim: cone — mouse moves the gun" if aim_cone \
				else "Aim: fixed — mouse turns you"
			msg_t = 2.4


func _move_axis() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1.0
	return v.normalized() if v.length() > 1.0 else v


# ------------------------------------------------------------------- update
func _process(delta: float) -> void:
	var playing := state == "play"
	var player_moving := false

	if playing:
		var axis := _move_axis()
		player["crouching"] = Input.is_key_pressed(KEY_C) or Input.is_key_pressed(KEY_CTRL)
		player["sprinting"] = Input.is_key_pressed(KEY_SHIFT) \
			and not player["crouching"] and axis.length() > 0.0

		var speed := Sim.PLAYER_SPEED
		if player["crouching"]:
			speed = Sim.PLAYER_CROUCH_SPEED
		elif player["sprinting"]:
			speed = Sim.PLAYER_SPRINT_SPEED

		if axis.length() > 0.0:
			player_moving = true
			# camera-relative: forward is the yaw direction in XZ
			var fwd := Vector2(sin(yaw), cos(yaw))
			# Camera-RIGHT, computed rather than guessed. Godot's basis is
			# right-handed and the camera looks down -Z, so at yaw 0 — looking
			# toward +Z — its right vector is -X, not +X. The old (cos, -sin) was
			# the mirror of this, which is exactly why A strafed right and D left.
			var right := Vector2(-cos(yaw), sin(yaw))
			var dir := (fwd * -axis.y + right * axis.x).normalized()
			var p: Vector2 = player["pos"] + dir * speed * delta
			p = Sim.resolve_circle(p, Sim.PLAYER_RADIUS)
			p = Sim.clamp_to_world(p, Sim.PLAYER_RADIUS)
			player["pos"] = p

		if player["reloading"] > 0.0:
			player["reloading"] -= delta
			if player["reloading"] <= 0.0:
				player["mag"] = Sim.WEAPONS[player["weapon"]]["mag"]
		player["cd"] -= delta
		if fire_held and player["cd"] <= 0.0 and player["reloading"] <= 0.0 \
		and player["mag"] > 0:
			_fire()

		Sim.step_thief(thief, player, loot, events, delta)
		_drain_events()

	_update_actors(delta, playing, player_moving)
	_update_footsteps(delta, playing, player_moving)
	_update_door_sound()
	_update_loot()
	_update_camera()
	# Deliberately after the camera moves: the viewmodel follows the camera transform, so
	# placing it earlier would leave the gun trailing the view by one frame while turning.
	# set_weapon is re-asserted every frame so dying puts the gun away, and a weapon
	# switch survives a round reset.
	if player_actor != null and player_actor.root != null:
		player_actor.set_weapon(player["weapon"] if player["alive"] else "none")
		# Back in his hand: the camera is behind him now, so the animated hand is in frame,
		# and a gun floating in mid-air beside his shoulder reads as detached once you can
		# actually see him. update_weapon points it along the aim from the hand bone.
		player_actor.update_weapon(_aim_dir())
	_update_crosshair()
	# Close the hand on whatever he is carrying. Deliberately last, and only possible
	# because of process_priority in _ready: the AnimationPlayer rewrites the pose during
	# its own step, so a grip applied any earlier is gone before the frame is drawn.
	if thief_actor != null and thief_actor.root != null:
		thief_actor.grip(1.15 if thief.get("carry", "") != "" else 0.0)
	_update_tracers(delta)
	if _flash != null and _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.visible = false
	_draw_minimap()

	if msg_t > 0.0:
		msg_t -= delta
	_lbl_banner.text = msg if msg_t > 0.0 else ""
	_refresh_hud()

	# Capture overrides apply whenever they were ASKED for, not only under --shot.
	# --write-movie never sets _shot_frames, so a recording silently ignored every one of
	# them: it ignored --shot-fire (so the gun never went off), --shot-pos, the aim angles
	# and --carry. That invalidated a whole hunt for the muzzle flash before it was spotted.
	if _shot_moved:
		# stand just inside the front door, looking into the house
		player["pos"] = Vector2(0.0, -9.5)
		yaw = PI
		pitch = 0.03
	if _shot_yaw != INF:
		yaw = deg_to_rad(_shot_yaw)
	if _shot_pitch != INF:
		pitch = deg_to_rad(_shot_pitch)
	if _shot_fire:
		# takes effect next frame: _fire() is driven earlier in _process
		fire_held = true
	if _shot_carry != "":
		thief["carry"] = _shot_carry
		for l in loot:
			l["taken"] = String(l["label"]) == _shot_carry
			l["delivered"] = false
	if _shot_pos.x != INF:
		player["pos"] = _shot_pos
	if _shot_aim != 0.0:
		aim_yaw = deg_to_rad(_shot_aim)
	if _shot_hide_player and player_actor != null and player_actor.root != null:
		player_actor.root.visible = false

	if _shot_frames > 0 and _shot_wait > 0.0:
		_shot_wait = maxf(0.0, _shot_wait - delta)
	elif _shot_frames > 0:
		_shot_frames -= 1
		# stderr on purpose: print() is block-buffered when redirected, so a run
		# that has to be killed loses every stdout line and looks like a hang
		# with no cause. This one survives.
		if _shot_frames % 20 == 0:
			printerr("[shot] %d frames left" % _shot_frames)
		if _shot_frames == 0:
			_capture_and_quit()


func _capture_and_quit() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path)
	printerr("SHOT: saved=", err == OK, " path=", _shot_path, " size=", img.get_size())
	get_tree().quit()


func _drain_events() -> void:
	for ev in events:
		match ev["type"]:
			"thiefShot":
				# He used to damage you by standing still: sim.gd fired him and nothing
				# ever played the clip. Actor.SHOOT was only ever referenced for the
				# player.
				if thief_actor != null and thief["alive"]:
					thief_actor.play_once(Actor.SHOOT)
				_play_at("gunshot_pistol",
					Vector3(thief["pos"].x, 1.3, thief["pos"].y), -3.0)
				var shot_from := Vector3(thief["pos"].x, 1.3, thief["pos"].y)
				var shot_to := Vector3(player["pos"].x, 1.3, player["pos"].y)
				# His shots are NOT guaranteed. Every event has always carried a spread
				# that nothing ever read, so 100% of them hit — unlike the player's own
				# weapons, which scatter. Accuracy now falls off with range, so a hit is
				# earned rather than looking like he fired through whatever you ducked
				# behind. Resolved here rather than in sim.gd so the sim stays pure and
				# its tests stay deterministic.
				var range_m := shot_from.distance_to(shot_to)
				if randf() <= clampf(1.0 - range_m * 0.02, 0.55, 1.0):
					_add_tracer(shot_from, shot_to)
					Sim.damage_player(player, Sim.THIEF_DAMAGE, events)
				else:
					# it goes wide: end the tracer off to one side instead of on you
					var wide := Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5),
						randf_range(-1.0, 1.0)).normalized()
					_add_tracer(shot_from, shot_to + wide * 1.4)
			"grabbed":
				msg = "They grabbed the %s!" % ev["label"]
				msg_t = 1.8
			"thiefHit":
				# sim.gd has always emitted this and game.gd has never read it, so
				# shooting a man produced no feedback at all beyond a HUD counter.
				_play_at("impact", Vector3(thief["pos"].x, 1.15, thief["pos"].y), -2.0)
			"playerHit":
				_play_at("impact", Vector3(player["pos"].x, 1.15, player["pos"].y), 0.0)
			"delivered":
				msg = "They got the %s!" % ev["label"]
				msg_t = 2.0
			"allStolen":
				_ran_off = false
				state = "lose"
				_show_overlay(false)
			"escaped":
				# He broke off and ran. A partial loss is a different outcome from losing
				# everything, and the text has to say which one happened.
				_ran_off = true
				_escaped_with = 3 - Sim.remaining(loot)
				state = "lose"
				_show_overlay(false)
			"thiefDown":
				# Whatever he was carrying falls where he does, rather than vanishing with
				# him. It goes back into the world at his position, so the valuables are
				# still findable after the round is won.
				if String(thief["carry"]) != "":
					for l in loot:
						if String(l["label"]) == String(thief["carry"]):
							l["taken"] = false
							l["delivered"] = false
							l["pos"] = thief["pos"]
					thief["carry"] = ""
				state = "win"
				_show_overlay(true)
			"playerDown":
				state = "lose"
				_show_overlay(false)
	events.clear()


## Speed to play `clip` at so its feet keep up with `actual` metres per second.
## A clip with no measurable ground travel (an idle) plays at 1.0.
func _clip_speed(a: Actor, clip: String, actual: float) -> float:
	var mps := a.clip_mps(clip)
	if actual <= 0.0 or mps < 0.05:
		return 1.0
	return clampf(actual / mps, 0.15, 3.0)


func _update_actors(delta: float, playing: bool, player_moving: bool) -> void:
	if player_actor == null or player_actor.root == null:
		return
	# Crouch squashes the model vertically; the ground offset scales with it so
	# the feet stay planted instead of sinking.
	var base: float = player_actor.base_scale
	var sy := base * (0.76 if player["crouching"] else 1.0)
	player_actor.root.scale = Vector3(base, sy, base)

	player_actor.tick(delta)
	player_actor.root.position = Vector3(player["pos"].x,
		player_actor.ground_offset * (sy / base), player["pos"].y)
	player_actor.root.rotation.y = yaw
	# Cone mode: walking turns the body toward wherever you are aiming, so the view
	# catches up on its own and you are never stuck aiming sideways down a corridor.
	# The recoil recovery rides along here because this runs before _update_camera().
	if recoil_recover > 0.0:
		var back := minf(recoil_recover, RECOIL_RECOVER * delta)
		pitch = clampf(pitch + back, PITCH_MIN, PITCH_MAX)
		recoil_recover -= back
	if aim_cone and playing and player_moving and aim_yaw != 0.0:
		var swing := clampf(aim_yaw, -CONE_RECENTRE * delta, CONE_RECENTRE * delta)
		yaw += swing
		aim_yaw -= swing

	# Playback speed comes from how fast the clip itself covered ground before its
	# root motion was stripped (Actor.clip_mps). Playing a 5.6 m/s sprint clip at
	# speed_scale 1.0 while the body moves 1.3 m/s is what made the feet skate.
	if player["crouching"]:
		# real crouch clips now, instead of only squashing the model
		var c := Actor.CROUCH_WALK if player_moving else Actor.CROUCH_IDLE
		var cs := Sim.PLAYER_CROUCH_SPEED if player_moving else 0.0
		player_actor.play(c, _clip_speed(player_actor, c, cs))
	elif player_moving:
		# Both gaits use the run clip. PLAYER_SPEED is 4.2 m/s, which is a jog,
		# and the walk clip is authored at 1.7 m/s — playing it here would need a
		# 2.5x cadence. Scaling the run clip keeps the stride length honest.
		var ms := Sim.PLAYER_SPRINT_SPEED if player["sprinting"] else Sim.PLAYER_SPEED
		player_actor.play(Actor.RUN, _clip_speed(player_actor, Actor.RUN, ms))
	else:
		# AIM, not IDLE. The homeowner is armed and the camera is behind him now: in the
		# idle clip his arms hang at his sides, so the pistol sat at his hip and his own
		# body hid it completely. The aim pose holds it out where it can be seen, which is
		# also how a person stands with a weapon ready. Safe to play because
		# _strip_to_upper_body() removes the hips, so it no longer swivels him.
		player_actor.play(Actor.AIM)

	# ---- thief
	thief_actor.tick(delta)
	var tp: Vector2 = thief["pos"]
	thief_actor.root.position = Vector3(tp.x, thief_actor.ground_offset, tp.y)
	# the model faces +Z at rotation 0; Sim measures yaw from +X toward +Z
	thief_actor.root.rotation.y = atan2(cos(thief["yaw"]), sin(thief["yaw"]))
	thief_actor.root.visible = true
	thief_hitbox.position = Vector3(tp.x, 0, tp.y)

	var sees: bool = thief["alive"] and playing \
		and Sim.thief_sees(tp, float(thief["yaw"]), player["pos"])

	# His pistol is out only while his hands are free — which is precisely when the
	# sim lets him fire. Prop and rule agree, so a holstered gun never shoots and a
	# drawn one always could.
	thief_actor.set_weapon("pistol" if (thief["alive"] and thief["carry"] == "") else "none")
	thief_actor.update_weapon(_thief_aim(tp, sees))

	if not thief["alive"]:
		if thief_actor.has_clip(Actor.DEATH):
			thief_actor.play(Actor.DEATH, 1.0)
		thief_hitbox.collision_layer = 0
	else:
		thief_hitbox.collision_layer = LAYER_THIEF
		var moving: bool = playing and (thief["route"] as Array).size() > 0
		if thief["carry"] != "" or moving:
			# He only ever moves at THIEF_SPEED, so the run clip — authored at
			# 5.6 m/s — played as a slow-motion sprint on the spot. The walk clip
			# is the one that matches his actual pace, and using a single clip for
			# both states also stops the model swapping gait on every grab.
			thief_actor.play(Actor.WALK,
				_clip_speed(thief_actor, Actor.WALK, Sim.THIEF_SPEED))
		elif sees:
			thief_actor.play(Actor.AIM)
		else:
			thief_actor.play(Actor.IDLE)


func _update_camera() -> void:
	# First person: the camera sits at the homeowner's eye and looks straight down the
	# aim axis, so the crosshair, the gun and the bullet are all the same line.
	#
	# It used to hang 4.4 m behind on an over-the-shoulder boom. Any mouse movement then
	# swung the whole room past the character, which reads as the *scene* moving rather
	# than the player turning, and it left the gun pinned to the screen because the
	# camera and the aim rotated together — so the mouse could never position the gun.
	#
	# It also cures a misfire that was never fixed: _fire() casts from the eye, but
	# aimed at a point projected from a camera offset 0.72 m to the right and 0.30 m up,
	# so shots landed roughly 0.6 m left and 0.3 m low of the crosshair at room range.
	# With the camera on the eye those two points coincide and the error is gone.
	var eye := Sim.CROUCH_EYE_HEIGHT if player["crouching"] else Sim.EYE_HEIGHT
	var p: Vector2 = player["pos"]
	# the BODY, not the aim: in cone mode the view deliberately does not follow the mouse
	var view := _view_dir()
	var pivot := Vector3(p.x, eye, p.y)
	var right := Vector3(-cos(yaw), 0.0, sin(yaw))
	var desired := pivot - view * cam_back + Vector3.UP * cam_up + right * cam_side

	# Pull in if the wall behind would swallow the camera. Short, but in a house with
	# walls every few metres this fires constantly — which is why the model below fades
	# out rather than leaving you staring at the inside of his back.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pivot, desired)
	q.collision_mask = LAYER_WORLD
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		desired = (hit["position"] as Vector3) + (pivot - desired).normalized() * 0.14

	if player_actor != null and player_actor.root != null:
		# _shot_hide_player has to be honoured here rather than in the shot block, because
		# this runs later every frame and would simply turn him back on.
		player_actor.root.visible = player["alive"] and not _shot_hide_player \
			and desired.distance_to(pivot) > CAM_FADE

	cam.position = desired
	cam.look_at(cam.position + view * 20.0, Vector3.UP)


# ------------------------------------------------------------------ combat
## Where the intruder points his pistol: at the homeowner when he can actually see
## him, and straight ahead otherwise. Tracking you through a wall would look wrong,
## and the sim already runs the same sight test for his trigger finger.
func _thief_aim(tp: Vector2, sees: bool) -> Vector3:
	var from := Vector3(tp.x, 1.30, tp.y)
	# Sim measures yaw from +X toward +Z, so his facing is (cos, sin) in XZ
	var to := from + Vector3(cos(thief["yaw"]), 0.0, sin(thief["yaw"]))
	if sees and player["alive"]:
		to = Vector3(player["pos"].x, Sim.EYE_HEIGHT, player["pos"].y)
	return (to - from).normalized()


## Where the BODY faces — the camera's forward, and the frame movement is relative to.
func _view_dir() -> Vector3:
	return Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)).normalized()


## Where the gun points and the bullets go. In cone mode this is the body direction plus
## the aim offset; with the cone off the offset is pinned at zero and the two are the
## same direction, which is ordinary first-person behaviour.
func _aim_dir() -> Vector3:
	var ay := yaw + aim_yaw
	var ap := clampf(pitch + aim_pitch, PITCH_MIN, PITCH_MAX)
	return Vector3(sin(ay) * cos(ap), -sin(ap), cos(ay) * cos(ap)).normalized()


func _fire() -> void:
	var spec: Dictionary = Sim.WEAPONS[player["weapon"]]
	player["mag"] -= 1
	player["cd"] = spec["cd"]
	if player_actor != null:
		player_actor.play_once(Actor.SHOOT)
	# the sights jump, then partly settle — which is what a real sight picture does between
	# shots, and what makes a shotgun feel different from a pistol
	var kick: float = RECOIL.get(String(player["weapon"]), 0.022)
	pitch = clampf(pitch - kick, PITCH_MIN, PITCH_MAX)
	recoil_recover += kick * 0.65
	_play_own("gunshot_" + String(player["weapon"]))
	# He hears it. A shotgun at room range is not the same event as a pistol across the
	# house, and this is what gives the firearm a deterrent value beyond its damage.
	var heard := clampf(1.6 - player["pos"].distance_to(thief["pos"]) / 18.0, 0.15, 1.6)
	if String(player["weapon"]) == "shotgun":
		heard *= 1.5
	Sim.alert_thief(thief, player["pos"], heard)

	# The ray starts at the CAMERA, not the eye. With the camera pulled back behind the
	# homeowner those are different points, and casting from the eye while the crosshair
	# sits on the camera's forward is precisely the mismatch that put shots 0.6 m left and
	# 0.3 m low before. From the camera the crosshair is honest by construction, whatever
	# the camera offset happens to be.
	var origin := cam.global_position
	var base_dir := _aim_dir()
	# the tracer is drawn from the gun even though the ray is cast from the camera
	var muzzle: Vector3 = origin
	if player_actor != null:
		var m := player_actor.muzzle()
		if m != Vector3.ZERO:
			muzzle = m
	_add_flash(muzzle)

	var space := get_world_3d().direct_space_state
	for i in int(spec["pellets"]):
		var spread: float = spec["spread"]
		var d := base_dir + Vector3(
			randf_range(-spread, spread),
			randf_range(-spread, spread),
			randf_range(-spread, spread))
		d = d.normalized()

		var q := PhysicsRayQueryParameters3D.create(origin, origin + d * 140.0)
		q.collision_mask = LAYER_WORLD | LAYER_THIEF
		var hit := space.intersect_ray(q)
		var end: Vector3 = origin + d * 90.0
		if not hit.is_empty():
			end = hit["position"]
			var collider = hit["collider"]
			var hit_thief: bool = collider is Node \
				and collider.name == "ThiefHitbox" and thief["alive"]
			if hit_thief:
				Sim.damage_thief(thief, spec["dmg"], events)
			# A mark on whatever it struck. The hit point has always been computed and then
			# used ONLY as the tracer's end, so emptying a shotgun into a wardrobe left no
			# sign of it — the single biggest reason shooting felt like it was happening to
			# the HUD rather than to the house.
			_add_impact(end, hit["normal"],
				int(spec["pellets"]) > 1, hit_thief)
		_add_tracer(muzzle, end)
	_drain_events()
	if player["mag"] <= 0:
		player["reloading"] = spec["reload"]
		if player_actor != null:
			player_actor.play_for(Actor.RELOAD, float(spec["reload"]))


func _add_tracer(from: Vector3, to: Vector3) -> void:
	var im := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = from.distance_to(to)
	im.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.92, 0.66)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.85, 0.45)
	im.material_override = m
	var mid := (from + to) * 0.5
	im.position = mid
	# cylinder points along +Y, so aim it down the shot
	var up := Vector3.UP
	var dir := (to - from).normalized()
	if absf(dir.dot(up)) < 0.999:
		var axis := up.cross(dir).normalized()
		im.basis = Basis(axis, up.angle_to(dir))
	add_child(im)
	_tracers.append({"node": im, "t": 0.06})


func _update_tracers(delta: float) -> void:
	for i in range(_tracers.size() - 1, -1, -1):
		_tracers[i]["t"] -= delta
		if _tracers[i]["t"] <= 0.0:
			_tracers[i]["node"].queue_free()
			_tracers.remove_at(i)


# --------------------------------------------------------------------- hud
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.45)
	panel.position = Vector2(16, 16)
	panel.size = Vector2(260, 108)
	layer.add_child(panel)

	_lbl_hp = _mk_label(layer, Vector2(28, 26), 26, Color(1, 1, 1))
	_bar = ColorRect.new()
	_bar.color = Color(0.13, 0.77, 0.37)
	_bar.position = Vector2(28, 62)
	_bar.size = Vector2(236, 10)
	layer.add_child(_bar)

	_lbl_weapon = _mk_label(layer, Vector2(300, 26), 22, Color(1, 1, 1))
	_lbl_ammo = _mk_label(layer, Vector2(300, 54), 15, Color(0.82, 0.85, 0.88))
	_lbl_stance = _mk_label(layer, Vector2(300, 76), 13, Color(0.62, 0.66, 0.70))
	_lbl_loot = _mk_label(layer, Vector2(460, 26), 22, Color(1, 0.85, 0.45))

	_lbl_banner = _mk_label(layer, Vector2(0, 150), 30, Color(0.99, 0.90, 0.55))
	_lbl_banner.size = Vector2(1600, 40)
	_lbl_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	minimap = Minimap.new()
	minimap.position = Vector2(1600 - 250 - 16, 900 - 210 - 16)
	layer.add_child(minimap)

	# Crosshair. This used to be two bare 2-pixel white ColorRects, which is why it
	# seemed to be "only sometimes there": against the lit cream walls it was white
	# on white, and a 2-pixel line also aliases away whenever the window is scaled
	# below the 1600x900 reference, so it flickered in and out with head movement.
	# Every arm is now a white core over a black outline, with a centre dot, so it
	# reads against any background at any scale.
	var cx := 800.0
	var cy := 450.0
	var half := 11.0          # arm length out from the centre
	var thick := 2.0          # core thickness
	var edge := 1.0           # outline thickness on each side
	var core := Color(1.0, 1.0, 1.0, 0.95)
	var rim := Color(0.0, 0.0, 0.0, 0.65)
	var dot := Rect2(cx - 1.5, cy - 1.5, 3.0, 3.0)
	var arms: Array[Rect2] = [
		Rect2(cx - thick * 0.5, cy - half, thick, half * 2.0),    # vertical
		Rect2(cx - half, cy - thick * 0.5, half * 2.0, thick),    # horizontal
	]
	# The crosshair lives in its own Control so cone mode can slide the whole thing
	# across the screen as one unit.
	_crosshair = Control.new()
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.position = Vector2.ZERO
	layer.add_child(_crosshair)
	# every outline first, so no core is ever covered by a neighbouring outline
	for a in arms:
		_add_hud_rect(_crosshair, a.grow(edge), rim)
	_add_hud_rect(_crosshair, dot.grow(edge), rim)
	for a in arms:
		_add_hud_rect(_crosshair, a, core)
	_add_hud_rect(_crosshair, dot, core)

	_overlay = Panel.new()
	_overlay.position = Vector2(0, 0)
	_overlay.size = Vector2(1600, 900)
	var om := StyleBoxFlat.new()
	om.bg_color = Color(0, 0, 0, 0.72)
	_overlay.add_theme_stylebox_override("panel", om)
	_overlay.visible = false
	layer.add_child(_overlay)

	_ov_title = _mk_label(layer, Vector2(0, 360), 54, Color(1, 1, 1))
	_ov_title.size = Vector2(1600, 70)
	_ov_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ov_sub = _mk_label(layer, Vector2(0, 440), 17, Color(0.82, 0.85, 0.88))
	_ov_sub.size = Vector2(1600, 30)
	_ov_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_make_hud_click_through(layer)


## Nothing in the HUD is interactive, so every Control becomes mouse-transparent.
func _make_hud_click_through(layer: CanvasLayer) -> void:
	for c in layer.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


## One flat rectangle of HUD. Used to build the crosshair, whose arms and centre dot
## each need an outline drawn behind a core.
# ------------------------------------------------------------------------ audio
func _build_audio() -> void:
	for name in ["gunshot_pistol", "gunshot_shotgun", "footstep", "impact",
			"door", "van_idle"]:
		var p := "res://assets/audio/%s.wav" % name
		if ResourceLoader.exists(p):
			_sfx[name] = load(p)
		else:
			push_warning("audio: missing " + p)

	_snd_own = AudioStreamPlayer.new()
	_snd_own.volume_db = -4.0
	add_child(_snd_own)

	# A small pool, because a shotgun blast, an impact and a footfall can overlap and a
	# single player would cut itself off. Six is more than the game can produce at once.
	for i in 6:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 45.0
		p.unit_size = 5.0
		add_child(p)
		_pool.append(p)

	# The van idles for the whole round. It is the reason the intruder is in a hurry and
	# the reason you can hear that someone has arrived, and it was a silent prop.
	var idle = _sfx.get("van_idle")
	if idle != null:
		var v := AudioStreamPlayer3D.new()
		v.stream = idle
		v.global_position = Vector3(Sim.VAN.position.x + Sim.VAN.size.x * 0.5, 1.0,
			Sim.VAN.position.y + Sim.VAN.size.y * 0.5)
		v.max_distance = 60.0
		v.unit_size = 12.0
		v.volume_db = -6.0
		if idle is AudioStreamWAV:
			var w := idle as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			# Setting loop_mode alone is not enough: the loop region defaults to an
			# empty span, so the stream plays nothing at all and the round is silent
			# between gunshots. Measured — 211 of 499 windows in a captured mix were
			# EXACTLY zero, which a continuous idle makes impossible.
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * float(w.mix_rate))
		add_child(v)
		v.play()


## The player's own weapon: at the listener, so no 3D.
func _play_own(name: String, db := 0.0) -> void:
	var s = _sfx.get(name)
	if s == null or _snd_own == null:
		return
	_snd_own.stream = s
	_snd_own.volume_db = db
	_snd_own.play()


## A sound somewhere in the world. Position matters: it is how you tell where he is.
func _play_at(name: String, pos: Vector3, db := 0.0) -> void:
	var s = _sfx.get(name)
	if s == null or _pool.is_empty():
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = s
	p.global_position = pos
	p.volume_db = db
	p.play()


## Footfalls for both of them.
##
## Nothing in the project made a sound before this, so the intruder crossed the house in
## silence and the only warning was the minimap dot — which is the one thing a defending
## homeowner does NOT have.
func _update_footsteps(delta: float, playing: bool, player_moving: bool) -> void:
	if not playing:
		return
	var ppos: Vector2 = player["pos"]
	if player_moving:
		_step_player -= delta
		if _step_player <= 0.0:
			var sprinting: bool = player["sprinting"]
			_step_player = 0.30 if sprinting else 0.44
			_play_at("footstep", Vector3(ppos.x, 0.1, ppos.y),
				-5.0 if sprinting else -9.0)
	else:
		_step_player = 0.0

	var moving: bool = thief["alive"] and (thief["route"] as Array).size() > 0
	if moving:
		var tp: Vector2 = thief["pos"]
		var laden: bool = String(thief["carry"]) != ""
		_step_thief -= delta
		if _step_thief <= 0.0:
			# a laden man is slower and plants harder
			_step_thief = 0.62 if laden else 0.46
			_play_at("footstep", Vector3(tp.x, 0.1, tp.y), -4.0 if laden else -6.0)
	else:
		_step_thief = 0.0


## The front door, which does not exist as an object — so this is the sound of him
## crossing the threshold line. It is the cue that someone has come in.
func _update_door_sound() -> void:
	var z: float = thief["pos"].y
	var door_line: float = Sim.HOUSE.end.y
	if (_thief_door_z - door_line) * (z - door_line) < 0.0:
		_play_at("door", Vector3(thief["pos"].x, 1.0, door_line), -6.0)
	_thief_door_z = z


func _build_effects() -> void:
	_flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.34, 0.34)
	_flash.mesh = q
	var m := StandardMaterial3D.new()
	var tex = load("res://assets/textures/muzzle_flash.png")
	if tex == null:
		push_warning("effects: missing muzzle_flash texture")
	else:
		m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# billboarded: a flash is a light bloom, not an object with a facing
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flash.material_override = m
	_flash.visible = false
	add_child(_flash)


func _add_impact(pos: Vector3, normal: Vector3, big: bool, on_flesh: bool) -> void:
	if _mark_mat == null:
		_mark_mat = StandardMaterial3D.new()
		var tex = load("res://assets/textures/bullet_hole.png")
		if tex != null:
			_mark_mat.albedo_texture = tex
		_mark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mark_mat.roughness = 1.0
		# drawn on top of the surface it sits on, so a 1 cm offset cannot z-fight
		_mark_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		_mark_mat.no_depth_test = false
	var m: MeshInstance3D
	if _marks.size() < MARK_MAX:
		m = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.16, 0.16)
		m.mesh = q
		m.material_override = _mark_mat
		add_child(m)
		_marks.append(m)
	else:
		m = _marks[_mark_i]
		_mark_i = (_mark_i + 1) % MARK_MAX
	var s := 1.7 if big else 1.0
	if on_flesh:
		s *= 0.7
	m.scale = Vector3(s, s, s)
	var up := Vector3.UP
	if absf(normal.dot(up)) > 0.95:
		up = Vector3.RIGHT
	# QuadMesh faces +Z, so -Z is aimed back down the surface normal
	m.global_transform = Transform3D(Basis.looking_at(-normal, up), pos + normal * 0.012)
	m.visible = true


## The flash at the muzzle. Firing used to produce a tracer and nothing else.
func _add_flash(pos: Vector3) -> void:
	if _flash == null:
		return
	_flash.global_position = pos
	_flash.visible = true
	_flash_t = 0.045
	_flash.rotate_y(randf() * TAU)


func _add_hud_rect(parent: Node, r: Rect2, col: Color) -> void:
	var c := ColorRect.new()
	c.color = col
	c.position = r.position
	c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)


## Slide the crosshair to wherever the aim actually points.
##
## Only in cone mode. With the cone off the aim IS the view, so the true position is the
## screen centre and leaving the Control at zero avoids any dependence on resolution.
func _update_crosshair() -> void:
	if _crosshair == null:
		return
	if not aim_cone:
		_crosshair.position = Vector2.ZERO
		return
	# Project by hand rather than with Camera3D.unproject_position: that returns window
	# pixels, while the HUD is laid out in a fixed 1600x900 design space, and the two
	# disagree at any other window size.
	var fwd := -cam.global_transform.basis.z
	var right := cam.global_transform.basis.x
	var up := cam.global_transform.basis.y
	var a := _aim_dir()
	var z := a.dot(fwd)
	if z <= 0.01:
		return
	var half_h := tan(deg_to_rad(cam.fov * 0.5))
	var half_w := half_h * (1600.0 / 900.0)
	_crosshair.position = Vector2(
		(a.dot(right) / z) / half_w * 800.0,
		-(a.dot(up) / z) / half_h * 450.0)


func _mk_label(parent: Node, pos: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(l)
	return l


func _refresh_hud() -> void:
	if player.is_empty():
		return
	var spec: Dictionary = Sim.WEAPONS[player["weapon"]]
	_lbl_hp.text = "%d" % int(maxf(0.0, player["hp"]))
	_bar.size.x = 236.0 * clampf(player["hp"] / 100.0, 0.0, 1.0)
	_bar.color = Color(0.13, 0.77, 0.37) if player["hp"] > 50.0 \
		else (Color(0.96, 0.62, 0.04) if player["hp"] > 25.0 else Color(0.94, 0.27, 0.27))
	_lbl_weapon.text = spec["name"]
	_lbl_ammo.text = "reloading" if player["reloading"] > 0.0 \
		else "%d / %d" % [int(player["mag"]), int(spec["mag"])]
	var stance := "STANDING"
	if player["crouching"]:
		stance = "CROUCHING"
	elif player["sprinting"]:
		stance = "SPRINTING"
	# No hit points on screen. It printed the intruder's exact health, through walls, which
	# is information the player has not earned; the whole point of the minimap's fog of war
	# is that he has to be found. This reports what the homeowner can actually tell.
	# "running" is fair — a man breaking off and bolting is not subtle.
	var tstate := "down" if not thief["alive"] else (
		"running" if String(thief["mode"]) == "flee" else (
			"hurting" if thief["hp"] <= 40.0 else (
				"hit" if thief["hp"] < 100.0 else "unhurt")))
	if _shot_fire or _shot_frames != -1:
		# capture mode only: the raw numbers underneath the state, so AI behaviour can be
		# read straight out of a screenshot instead of guessed at
		tstate += " [fear %.1f stag %.1f]" % [float(thief["fear"]), float(thief["stagger"])]
	_lbl_stance.text = "%s    intruder: %s" % [stance, tstate]
	_lbl_loot.text = "LOOT STOLEN  %d / 3" % (3 - Sim.remaining(loot))


func _draw_minimap() -> void:
	if minimap != null and not player.is_empty():
		minimap.update_state({"pos": player["pos"], "yaw": yaw}, thief, loot)


func _show_overlay(win: bool) -> void:
	_overlay.visible = true
	_ov_title.text = "HOME DEFENDED" if win else "FAILURE"
	_ov_title.add_theme_color_override("font_color",
		Color(0.13, 0.77, 0.37) if win else Color(0.94, 0.27, 0.27))
	# no longer "the van drove off": the van is scenery and never moves, so the text was
	# contradicting the screen. See ROADMAP item 22 for making it actually leave.
	if win:
		_ov_sub.text = ("Intruder neutralised — %d/3 valuables still in the house."
			% Sim.remaining(loot)) + "  [ENTER] to play again"
	elif _ran_off:
		_ov_sub.text = ("He broke off and ran — %d of 3 with him." % _escaped_with) \
			+ "  [ENTER] to play again"
	elif player["alive"]:
		_ov_sub.text = "He got everything into the van.  [ENTER] to play again"
	else:
		_ov_sub.text = "You were killed defending the house.  [ENTER] to play again"
