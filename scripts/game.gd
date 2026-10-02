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

# Debug: `godot --path . -- --shot` renders 120 frames, writes shot.png next to
# the project and quits. Lets the build be verified visually without a human.
var _shot_frames := -1
var _shot_path := "res://shot.png"
var _shot_moved := false


func _ready() -> void:
	_setup_environment()
	House.build_all(self)
	_build_collision()
	_spawn_actors()
	_build_hud()
	reset()
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
	# Deep dusk, not a void: the first pass crushed these to near-black and the
	# whole upper frame read as a hole rather than a sky.
	sm.sky_top_color = Color(0.100, 0.130, 0.200)
	sm.sky_horizon_color = Color(0.235, 0.260, 0.310)
	sm.ground_bottom_color = Color(0.055, 0.060, 0.070)
	sm.ground_horizon_color = Color(0.130, 0.140, 0.155)
	sm.sun_angle_max = 8.0
	sky.sky_material = sm
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.22        # was 0.55 — the flat fill is the enemy

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 3.0

	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 3.0
	env.ssao_power = 1.6

	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.045, 0.055, 0.080)
	env.fog_density = 0.022
	# fog_sky_affect=1.0 tints the SKY with the fog colour, which crushed the whole
	# upper frame to black. Let the sky show through; the fog still works on geometry.
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0

	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.30
	env.adjustment_saturation = 0.82

	we.environment = env
	add_child(we)

	# --- one weak, cool key from outside. Not the main source; it exists to
	#     separate the house from the night and to cast the exterior shadows.
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 36, 0)
	sun.light_color = Color(0.58, 0.70, 0.95)
	sun.light_energy = 0.28
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


# -------------------------------------------------------------------- state
func reset() -> void:
	player = Sim.create_player()
	thief = Sim.create_thief()
	loot = Sim.create_loot()
	events = []
	state = "play"
	msg = "DEFEND YOUR HOME"
	msg_t = 2.4
	yaw = 0.0
	pitch = 0.03
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
		yaw -= event.relative.x * 0.0022
		pitch = clampf(pitch + event.relative.y * 0.0018, -0.30, 0.85)
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
			var right := Vector2(cos(yaw), -sin(yaw))
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
	_update_camera()
	_update_tracers(delta)
	_draw_minimap()

	if msg_t > 0.0:
		msg_t -= delta
	_lbl_banner.text = msg if msg_t > 0.0 else ""
	_refresh_hud()

	if _shot_frames > 0:
		_shot_frames -= 1
		if _shot_moved:
			# stand just inside the front door, looking into the house
			player["pos"] = Vector2(0.0, -9.5)
			yaw = PI
			pitch = 0.03
		if _shot_frames == 0:
			_capture_and_quit()


func _capture_and_quit() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path)
	print("SHOT: saved=", err == OK, " path=", _shot_path, " size=", img.get_size())
	get_tree().quit()


func _drain_events() -> void:
	for ev in events:
		match ev["type"]:
			"thiefShot":
				_add_tracer(Vector3(thief["pos"].x, 1.3, thief["pos"].y),
					Vector3(player["pos"].x, 1.3, player["pos"].y))
				Sim.damage_player(player, Sim.THIEF_DAMAGE, events)
			"grabbed":
				msg = "They grabbed the %s!" % ev["label"]
				msg_t = 1.8
			"delivered":
				msg = "They got the %s!" % ev["label"]
				msg_t = 2.0
			"allStolen":
				state = "lose"
				_show_overlay(false)
			"thiefDown":
				state = "win"
				_show_overlay(true)
			"playerDown":
				state = "lose"
				_show_overlay(false)
	events.clear()


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
	player_actor.root.visible = player["alive"]
	# keep the prop pointing where the bullet actually goes
	player_actor.update_weapon(_aim_dir())

	var speed := 1.0
	if player["sprinting"]:
		speed = 1.5
	elif player["crouching"]:
		speed = 0.5
	if player["crouching"]:
		# real crouch clips now, instead of only squashing the model
		player_actor.play(Actor.CROUCH_WALK if player_moving else Actor.CROUCH_IDLE, speed)
	elif player_moving:
		player_actor.play(Actor.RUN if player["sprinting"] else Actor.WALK, speed)
	else:
		player_actor.play(Actor.IDLE)

	# ---- thief
	thief_actor.tick(delta)
	var tp: Vector2 = thief["pos"]
	thief_actor.root.position = Vector3(tp.x, thief_actor.ground_offset, tp.y)
	# the model faces +Z at rotation 0; Sim measures yaw from +X toward +Z
	thief_actor.root.rotation.y = atan2(cos(thief["yaw"]), sin(thief["yaw"]))
	thief_actor.root.visible = true
	thief_hitbox.position = Vector3(tp.x, 0, tp.y)

	if not thief["alive"]:
		if thief_actor.has_clip(Actor.DEATH):
			thief_actor.play(Actor.DEATH, 1.0)
		thief_hitbox.collision_layer = 0
	else:
		thief_hitbox.collision_layer = LAYER_THIEF
		var moving: bool = playing and (thief["route"] as Array).size() > 0
		var sees: bool = playing and Sim.can_see(tp, player["pos"], Sim.THIEF_SIGHT)
		if thief["carry"] != "":
			thief_actor.play(Actor.WALK, 0.8)
		elif moving:
			thief_actor.play(Actor.RUN, 1.0)
		elif sees:
			thief_actor.play(Actor.AIM)
		else:
			thief_actor.play(Actor.IDLE)


func _update_camera() -> void:
	# Position the camera by walking BACK along the aim axis from the shoulder
	# pivot. Deriving both from one axis is what keeps the crosshair on the
	# bullet path; an independently computed look_at drifted off it and pitched
	# the view into the floor.
	#
	# The camera is deliberately kept near eye level: raised above the 2 m walls
	# it turns the house into a dollhouse and lets the player see the intruder
	# over walls that the minimap correctly hides.
	var eye := Sim.CROUCH_EYE_HEIGHT if player["crouching"] else Sim.EYE_HEIGHT
	var dist := 4.4      # was 5.6 — the character and weapon read too small
	var p: Vector2 = player["pos"]
	var aim := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)).normalized()
	var pivot := Vector3(p.x, eye + 0.30, p.y)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var desired := pivot - aim * dist + right * 0.72

	# pull in when scenery is between the player and the camera
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pivot, desired)
	q.collision_mask = LAYER_WORLD
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		desired = (hit["position"] as Vector3) + (pivot - desired).normalized() * 0.28

	cam.position = desired
	cam.look_at(pivot + aim * 20.0, Vector3.UP)


# ------------------------------------------------------------------ combat
func _aim_dir() -> Vector3:
	return -cam.global_transform.basis.z


func _fire() -> void:
	var spec: Dictionary = Sim.WEAPONS[player["weapon"]]
	player["mag"] -= 1
	player["cd"] = spec["cd"]
	if player_actor != null:
		player_actor.play_once(Actor.SHOOT)

	var eye := Sim.CROUCH_EYE_HEIGHT if player["crouching"] else Sim.EYE_HEIGHT
	var origin := Vector3(player["pos"].x, eye, player["pos"].y)
	var aim_point := cam.global_position + _aim_dir() * 100.0
	var base_dir := (aim_point - origin).normalized()

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
			if collider is Node and collider.name == "ThiefHitbox" and thief["alive"]:
				Sim.damage_thief(thief, spec["dmg"], events)
		_add_tracer(origin, end)
	_drain_events()

	if player["mag"] <= 0:
		player["reloading"] = spec["reload"]


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

	# crosshair
	var cross := ColorRect.new()
	cross.color = Color(1, 1, 1, 0.85)
	cross.position = Vector2(800 - 1, 450 - 9)
	cross.size = Vector2(2, 18)
	layer.add_child(cross)
	var cross2 := ColorRect.new()
	cross2.color = Color(1, 1, 1, 0.85)
	cross2.position = Vector2(800 - 9, 450 - 1)
	cross2.size = Vector2(18, 2)
	layer.add_child(cross2)

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
	_lbl_stance.text = "%s    thief: %s" % [stance,
		("%d hp" % int(maxf(0.0, thief["hp"]))) if thief["alive"] else "down"]
	_lbl_loot.text = "LOOT STOLEN  %d / 3" % (3 - Sim.remaining(loot))


func _draw_minimap() -> void:
	if minimap != null and not player.is_empty():
		minimap.update_state({"pos": player["pos"], "yaw": yaw}, thief, loot)


func _show_overlay(win: bool) -> void:
	_overlay.visible = true
	_ov_title.text = "HOME DEFENDED" if win else "FAILURE"
	_ov_title.add_theme_color_override("font_color",
		Color(0.13, 0.77, 0.37) if win else Color(0.94, 0.27, 0.27))
	_ov_sub.text = ("Thief neutralised — %d/3 valuables still in the house.  [ENTER] to play again"
		% Sim.remaining(loot)) if win \
		else ("The van drove off with everything.  [ENTER] to play again" if player["alive"]
			else "You were killed defending the house.  [ENTER] to play again")
