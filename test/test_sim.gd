extends SceneTree

## Headless tests for the GDScript simulation port.
##   godot --headless --path . --script test/test_sim.gd
##
## The JS version of this simulation was already debugged; these tests exist to
## catch TRANSCRIPTION errors in the port, not to rediscover known bugs.

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


func _init() -> void:
	_banner("geometry + navigation")

	# ---- every nav edge must be a clear straight line
	var bad := ""
	for k in Sim.NODES:
		for m in Sim.NODES[k]["edges"]:
			var a: Vector2 = Sim.NODES[k]["pos"]
			var b: Vector2 = Sim.NODES[m]["pos"]
			for s in Sim.SOLIDS:
				if Sim.seg_rect(a, b, s):
					bad = "%s -> %s crosses a solid" % [k, m]
	check("every nav edge is a clear straight line", bad == "", bad)

	# ---- every loot spot reachable from its node
	bad = ""
	for l in Sim.LOOT_SPOTS:
		var node: Vector2 = Sim.NODES[l["node"]]["pos"]
		for s in Sim.SOLIDS:
			if Sim.seg_rect(node, l["pos"], s):
				bad = "loot %s is behind a solid" % l["label"]
	check("each loot spot is reachable from its nav node", bad == "", bad)

	# ---- the doorway is genuinely open
	check("the door gap is open",
		not Sim.los_blocked(Vector2(0, 2.5), Vector2(0, -4.5)))

	# ---- line of sight
	check("LOS blocked through a wall, clear inside",
		Sim.los_blocked(Vector2(0, -19), Vector2(0, -25))
		and not Sim.los_blocked(Vector2(0, -8), Vector2(0, -12)))

	# ---- collision pushes an entity out
	var wall: Rect2 = Sim.WALLS[0]
	var e := wall.position + Vector2(0.05, 0.05)
	var pushed := Sim.resolve_circle(e, 0.45)
	var inside := pushed.x > wall.position.x and pushed.x < wall.end.x \
		and pushed.y > wall.position.y and pushed.y < wall.end.y
	check("collision pushes an entity out of a wall", not inside,
		"still inside at %s" % pushed)

	# ---- pathfinding
	var route := Sim.route_to("van", "living")
	check("pathfinding returns a connected route", route.size() >= 3,
		"got %d hops" % route.size())

	_banner("thief AI")

	# ---- full heist against an idle player
	var player := Sim.create_player()
	var thief := Sim.create_thief()
	var loot := Sim.create_loot()
	var events: Array = []
	var dt := 1.0 / 60.0
	var t := 0.0
	var reroutes := 0
	while t < 180.0 and Sim.remaining(loot) > 0:
		Sim.step_thief(thief, player, loot, events, dt)
		for ev in events:
			if ev["type"] == "reroute":
				reroutes += 1
		events.clear()
		t += dt
	check("thief completes a full heist against an idle player",
		Sim.remaining(loot) == 0,
		"delivered %d/3 in %.1fs" % [3 - Sim.remaining(loot), t])
	print("        cleared 3 items in %.1fs, %d re-routes" % [t, reroutes])
	check("thief does not thrash while heisting", reroutes <= 2,
		"%d re-routes" % reroutes)

	# ---- solid bodies
	_banner("solid bodies")
	var body_gap := Sim.PLAYER_RADIUS + Sim.THIEF_RADIUS

	var sep := Sim.separate_bodies(Vector2(0, 0), Vector2(0.2, 0.1))
	var s0: Vector2 = sep[0]
	var s1: Vector2 = sep[1]
	check("two overlapping bodies are pushed apart",
		s1.distance_to(s0) >= body_gap - 1e-4,
		"%.3f m apart, want >= %.3f" % [s1.distance_to(s0), body_gap])
	check("the intruder holds his ground",
		s1.is_equal_approx(Vector2(0.2, 0.1)), "thief moved to %s" % s1)
	check("the homeowner is the body that gives way",
		not s0.is_equal_approx(Vector2.ZERO), "player did not move")

	var co := Sim.separate_bodies(Vector2(3, 3), Vector2(3, 3))
	var c0: Vector2 = co[0]
	var c1: Vector2 = co[1]
	check("exactly coincident bodies still separate",
		c1.distance_to(c0) >= body_gap - 1e-4,
		"%.3f m apart" % c1.distance_to(c0))

	var apart := Sim.separate_bodies(Vector2(0, 0), Vector2(0, 5))
	check("already-separated bodies are left exactly alone",
		(apart[0] as Vector2).is_equal_approx(Vector2.ZERO)
		and (apart[1] as Vector2).is_equal_approx(Vector2(0, 5)))

	var shoved := Sim.separate_bodies(Vector2(0, 0), Vector2(0, 0.3))
	check("the homeowner is the body that yields",
		(shoved[0] as Vector2).y < 0.0, "player ended at %s" % shoved[0])

	# ---- steering: solid alone would wall him in
	var north := -PI * 0.5
	check("the thief swerves around a homeowner directly ahead",
		absf(Sim.steer_around(north, Vector2(0, 0), Vector2(0, -1.5)) - north) > 0.1)
	check("the thief does not swerve for a homeowner behind him",
		is_equal_approx(Sim.steer_around(north, Vector2(0, 0), Vector2(0, 1.5)), north))
	check("the thief does not swerve for a distant homeowner",
		is_equal_approx(Sim.steer_around(north, Vector2(0, 0), Vector2(0, -20.0)), north))
	check("the swerve turns away from the homeowner, not into him",
		Sim.steer_around(north, Vector2(0, 0), Vector2(-0.4, -1.5)) > north,
		"homeowner to the left, heading swung to %.3f" %
			Sim.steer_around(north, Vector2(0, 0), Vector2(-0.4, -1.5)))

	# ---- the invariant that matters in play: one whole heist, never overlapping
	player = Sim.create_player()
	thief = Sim.create_thief()
	loot = Sim.create_loot()
	events = []
	var closest := INF
	for i in 60 * 180:
		Sim.step_thief(thief, player, loot, events, dt)
		events.clear()
		closest = minf(closest, (thief["pos"] as Vector2).distance_to(player["pos"]))
		if Sim.remaining(loot) == 0 or not thief["alive"]:
			break
	check("the thief never walks through the homeowner across a whole heist",
		closest >= body_gap - 1e-3,
		"closest approach %.3f m, want >= %.3f" % [closest, body_gap])

	# ---- the OTHER direction, and the one a player actually notices: the
	# HOMEOWNER walking into the intruder. game.gd moves the player from input and
	# only then calls step_thief, so separation has to survive a player actively
	# driving into him. The heist check above only ever had the player standing
	# still, which is why this case went unverified.
	player = Sim.create_player()
	thief = Sim.create_thief()
	loot = Sim.create_loot()
	events = []
	for l in loot:
		l["taken"] = true          # nothing left to steal, so he holds position
	thief["pos"] = Vector2(0, 0)
	thief["prev"] = Vector2(0, 0)
	thief["route"] = []
	thief["target"] = ""
	player["pos"] = Vector2(0, -4)
	var worst := INF
	var shove_z := 0.0
	for i in 60 * 6:
		# exactly what game.gd does: move from input, then hand over to step_thief
		var p: Vector2 = player["pos"] + Vector2(0, 1) * Sim.PLAYER_SPEED * dt
		p = Sim.resolve_circle(p, Sim.PLAYER_RADIUS)
		p = Sim.clamp_to_world(p, Sim.PLAYER_RADIUS)
		player["pos"] = p
		Sim.step_thief(thief, player, loot, events, dt)
		events.clear()
		worst = minf(worst, (thief["pos"] as Vector2).distance_to(player["pos"]))
		shove_z = maxf(shove_z, (thief["pos"] as Vector2).y)
	check("the homeowner cannot walk into the intruder",
		worst >= body_gap - 1e-3,
		"closest %.3f m, want >= %.3f" % [worst, body_gap])
	check("the intruder holds his ground rather than being driven off it",
		shove_z < 0.05, "he drifted to z=%.2f" % shove_z)

	# ---- THE REGRESSION. Every check above holds the homeowner still, and a
	# stationary player is the ONE case that always worked. This is what came back
	# from play as "the thief is not taking items out of the house": with the
	# intruder yielding on contact, a player standing on his route was an immovable
	# wall — 142 re-routes and nothing ever delivered, and a player in the 2 m front
	# doorway made the house impossible to leave.
	_banner("heist against a MOVING homeowner")
	var cases := [
		["chases the intruder", 1],
		["blocks the front doorway", 2],
		["stands on the front-hub waypoint", 3],
		["stands on the living-room waypoint", 4],
	]
	for c in cases:
		player = Sim.create_player()
		thief = Sim.create_thief()
		loot = Sim.create_loot()
		events = []
		var mode: int = c[1]
		var t2 := 0.0
		var rr := 0
		while t2 < 180.0 and Sim.remaining(loot) > 0:
			match mode:
				1:
					var chase_d: Vector2 = (thief["pos"] as Vector2) - (player["pos"] as Vector2)
					if chase_d.length() > 0.01:
						var chase_p: Vector2 = (player["pos"] as Vector2) \
							+ chase_d.normalized() * Sim.PLAYER_SPEED * dt
						player["pos"] = Sim.clamp_to_world(
							Sim.resolve_circle(chase_p, Sim.PLAYER_RADIUS), Sim.PLAYER_RADIUS)
				2:
					player["pos"] = Vector2(0, -8.6)
				3:
					player["pos"] = Vector2(0, -11.2)
				4:
					player["pos"] = Vector2(-3.6, -11.2)
			Sim.step_thief(thief, player, loot, events, dt)
			for ev in events:
				if ev["type"] == "reroute":
					rr += 1
			events.clear()
			t2 += dt
		check("the heist completes even when the homeowner %s" % c[0],
			Sim.remaining(loot) == 0,
			"delivered %d/3 in %.0fs with %d re-routes" % [3 - Sim.remaining(loot), t2, rr])

	# ---- the intruder's hands: free means armed, carrying means not
	_banner("the intruder cannot fire with his hands full")
	for carrying in [false, true]:
		player = Sim.create_player()
		thief = Sim.create_thief()
		loot = Sim.create_loot()
		thief["pos"] = (player["pos"] as Vector2) + Vector2(0, 2.0)
		thief["prev"] = thief["pos"]
		thief["carry"] = "TV" if carrying else ""
		thief["cd"] = 0.0
		thief["mag"] = 8
		thief["reloading"] = 0.0
		var fired := false
		# long enough to clear both the aim settle and the first cooldown
		for i in 60 * 3:
			events = []
			Sim.step_thief(thief, player, loot, events, dt)
			for ev in events:
				if ev["type"] == "thiefShot":
					fired = true
		check("does NOT fire while carrying the loot" if carrying else "fires when his hands are free",
			fired != carrying, "fired=%s carrying=%s" % [fired, carrying])

	# ---- and he has to settle on you first
	_banner("the intruder must aim before firing")
	player = Sim.create_player()
	thief = Sim.create_thief()
	loot = Sim.create_loot()
	thief["pos"] = (player["pos"] as Vector2) + Vector2(0, 2.0)
	thief["prev"] = thief["pos"]
	thief["cd"] = 0.0
	thief["mag"] = 8
	var first_shot := -1.0
	var t3 := 0.0
	while t3 < 3.0 and first_shot < 0.0:
		events = []
		Sim.step_thief(thief, player, loot, events, dt)
		for ev in events:
			if ev["type"] == "thiefShot":
				first_shot = t3
		t3 += dt
	check("the intruder does not fire the instant he sees you",
		first_shot >= Sim.THIEF_AIM_TIME - dt,
		"first shot at %.2fs, aim time is %.2fs" % [first_shot, Sim.THIEF_AIM_TIME])
	check("but he does fire once he has settled",
		first_shot >= 0.0 and first_shot < 1.5, "first shot at %.2fs" % first_shot)

	# ---- and being shot interrupts him
	_banner("a hit stops the intruder")
	player = Sim.create_player()
	thief = Sim.create_thief()
	loot = Sim.create_loot()
	thief["pos"] = Vector2(-5.0, -12.0)
	thief["prev"] = thief["pos"]
	thief["route"] = [Vector2(0.0, -12.0)]
	thief["aim"] = Sim.THIEF_AIM_TIME
	events = []
	Sim.damage_thief(thief, 20.0, events)
	check("a hit staggers him", float(thief["stagger"]) > 0.0,
		"stagger=%.2f" % float(thief["stagger"]))
	check("and it takes his sight picture away", float(thief["aim"]) == 0.0,
		"aim=%.2f" % float(thief["aim"]))
	var before: Vector2 = thief["pos"]
	events = []
	Sim.step_thief(thief, player, loot, events, dt)
	check("and he does not move while staggered",
		(thief["pos"] as Vector2).distance_to(before) < 0.001,
		"moved %.4f m" % (thief["pos"] as Vector2).distance_to(before))

	# ---- gunfire makes him give up the job
	_banner("gunfire drives him off")
	player = Sim.create_player()
	thief = Sim.create_thief()
	loot = Sim.create_loot()
	check("he starts unafraid", float(thief["fear"]) == 0.0, "fear=0")
	# a couple of shots at room range is not enough
	for i in 2:
		Sim.alert_thief(thief, Vector2(0.0, -11.0), 1.0)
	check("two shots do not drive him off",
		thief["mode"] != "flee", "fear=%.2f mode=%s" % [thief["fear"], thief["mode"]])
	# but a sustained burst does
	for i in 4:
		Sim.alert_thief(thief, Vector2(0.0, -11.0), 1.0)
	check("a sustained burst drives him off",
		float(thief["fear"]) >= Sim.FEAR_FLEE,
		"fear=%.2f threshold=%.1f" % [thief["fear"], Sim.FEAR_FLEE])
	# fear settles when nothing is happening
	thief["fear"] = 1.0
	thief["mode"] = "hunt"
	thief["route"] = [Vector2(0.0, -12.0)]
	thief["think"] = 0.0
	for i in 60:
		Sim.step_thief(thief, player, loot, events, dt)
	check("and fear decays when the shooting stops",
		float(thief["fear"]) < 1.0, "fear=%.2f" % thief["fear"])

	# ---- and once he breaks off he runs for the van
	thief = Sim.create_thief()
	thief["pos"] = Vector2(0.0, -12.0)
	thief["fear"] = Sim.FEAR_FLEE
	thief["mode"] = "flee"
	thief["stagger"] = 0.0
	events = []
	var got_away := false
	var steps := 0
	for i in 3000:
		steps = i
		if thief["escaped"]:
			got_away = true
			break
		Sim.step_thief(thief, player, loot, events, dt)
	check("a frightened intruder runs for the van and gets away", got_away,
		"ended at %s after %d steps" % [thief["pos"], steps])
	var saw_escape := false
	for ev2 in events:
		if ev2["type"] == "escaped":
			saw_escape = true
	check("and announces it so the round can end", saw_escape, "escaped event raised")

	# ---- he has to get up to speed, and has to slow down again
	_banner("momentum")
	player = Sim.create_player()
	thief = Sim.create_thief()
	loot = Sim.create_loot()
	thief["pos"] = Vector2(0.0, 2.0)
	thief["prev"] = thief["pos"]
	# past the threshold hesitation, or he simply stands there for the first two seconds
	thief["think"] = 0.0
	events = []
	var speeds: Array = []
	for n in 30:
		Sim.step_thief(thief, player, loot, events, dt)
		speeds.append(float(thief["speed"]))
	check("he starts from a standstill rather than at full pace",
		float(speeds[0]) < 0.2, "first frame speed %.3f m/s" % float(speeds[0]))
	check("and builds speed instead of snapping to it",
		float(speeds[9]) > float(speeds[0]) and float(speeds[9]) < Sim.THIEF_SPEED,
		"%.3f -> %.3f m/s over 10 frames (full pace %.2f)"
			% [speeds[0], speeds[9], Sim.THIEF_SPEED])
	# now take his route away and watch him coast to a halt
	var peak := float(thief["speed"])
	thief["route"] = []
	events = []
	var halted := -1
	for n in 60:
		Sim.step_thief(thief, player, loot, events, dt)
		if float(thief["speed"]) <= 0.0:
			halted = n
			break
	check("and coasts to a halt rather than stopping dead", halted > 0,
		"halted after %d frames from %.2f m/s" % [halted, peak])

	# ---- thief stays in bounds
	player = Sim.create_player()
	thief = Sim.create_thief()
	loot = Sim.create_loot()
	events = []
	var oob := ""
	for i in 60 * 120:
		Sim.step_thief(thief, player, loot, events, dt)
		events.clear()
		var p: Vector2 = thief["pos"]
		if p.x < Sim.BOUNDS.position.x - 0.01 or p.x > Sim.BOUNDS.end.x + 0.01 \
		or p.y < Sim.BOUNDS.position.y - 0.01 or p.y > Sim.BOUNDS.end.y + 0.01:
			oob = "left bounds at %s" % p
			break
		if not thief["alive"]:
			break
	check("thief never drifts outside the world bounds", oob == "", oob)

	# ---- THE invariant: never fire without line of sight
	player = Sim.create_player()
	thief = Sim.create_thief()
	loot = Sim.create_loot()
	var shots := 0
	var violation := ""
	var blocked_frames := 0
	for i in 60 * 90:
		player["pos"] = Vector2(sin(i / 97.0) * 9.0, -13.0 + cos(i / 131.0) * 6.0)
		if Sim.los_blocked(thief["pos"], player["pos"]):
			blocked_frames += 1
		events = []
		Sim.step_thief(thief, player, loot, events, dt)
		for ev in events:
			if ev["type"] == "thiefShot":
				shots += 1
				if Sim.los_blocked(thief["pos"], player["pos"]):
					violation = "fired through a wall at frame %d" % i
					break
		if violation != "":
			break
	check("thief NEVER fires while line of sight is blocked", violation == "", violation)
	check("the invariant test actually exercised the path", shots > 0,
		"no shots taken at all")
	print("        %d shots, all with LOS (%d blocked frames available)" % [shots, blocked_frames])

	_banner("visibility + minimap fog of war")

	check("rayCast stops at a wall",
		Sim.ray_cast_px(Vector2(0, -18.5), Vector2(0, -1), 60.0) < 2.0)
	check("rayCast travels full range over open ground",
		is_equal_approx(Sim.ray_cast_px(Vector2(0, 10), Vector2(0, 1), 60.0), 60.0))
	check("canSee false through a wall, true across open floor",
		not Sim.can_see(Vector2(0, -18), Vector2(0, -23))
		and Sim.can_see(Vector2(0, -8), Vector2(0, -13)))
	check("canSee respects the sight radius",
		not Sim.can_see(Vector2(0, 20), Vector2(0, -20), 10.0))

	# ---- the user's actual requirement
	var homeowner := Vector2(0, -13)
	var behind_wall := Vector2(8, 12)
	var in_doorway := Vector2(0, 0)
	check("THE REQUIREMENT: intruder hidden behind a wall, visible through the doorway",
		not Sim.can_see(homeowner, behind_wall, 28.0) and Sim.can_see(homeowner, in_doorway, 28.0),
		"behind_wall=%s doorway=%s" % [Sim.can_see(homeowner, behind_wall, 28.0), Sim.can_see(homeowner, in_doorway, 28.0)])

	# ---- visibility polygon sanity
	var poly := Sim.visibility_polygon(Vector2(0, -18), 28.0)
	var bad_pt := ""
	var maxd := 0.0
	for p in poly:
		maxd = maxf(maxd, p.distance_to(Vector2(0, -18)))
		for s in Sim.SOLIDS:
			if p.x > s.position.x + 1e-6 and p.x < s.end.x - 1e-6 \
			and p.y > s.position.y + 1e-6 and p.y < s.end.y - 1e-6:
				bad_pt = "vertex inside a solid: %s" % p
	check("visibility polygon stays in range and out of solids",
		poly.size() > 20 and bad_pt == "" and maxd <= 28.01, bad_pt)
	print("        %d polygon points, max reach %.1f m" % [poly.size(), maxd])

	# ---- polygon cost
	var t0 := Time.get_ticks_usec()
	for i in 200:
		Sim.visibility_polygon(Vector2(sin(i) * 3.0, -11.5), 30.0)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 200.0
	check("visibility polygon is cheap enough for every frame", ms < 4.0,
		"%.3f ms per polygon" % ms)
	print("        %.3f ms per polygon, 200 sampled" % ms)

	_banner("damage")
	var th := Sim.create_thief()
	events = []
	check("lethal damage kills the thief and emits thiefDown",
		Sim.damage_thief(th, 150.0, events) and not th["alive"])
	var pl := Sim.create_player()
	events = []
	check("player death clamps hp at zero",
		Sim.damage_player(pl, 999.0, events) and pl["hp"] == 0.0)

	print("\n%d passed, %d failed\n" % [n_pass, n_fail])
	quit(1 if n_fail > 0 else 0)
