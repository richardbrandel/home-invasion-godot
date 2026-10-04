extends SceneTree

## Does the intruder ever actually fire with a wall between him and the homeowner?
##   godot --headless --path . --script test/probe_wallshot.gd
##
## The suite already asserts this, but it does so with Sim.los_blocked() — the very
## function the sim uses to decide. That checks the code against itself: if seg_rect
## has an edge case, both sides share it and the test still passes. This re-implements
## the segment/rectangle clip from scratch and counts genuine violations.

const DT := 1.0 / 60.0


## Independent slab clip. Ray casting of a segment against an axis-aligned rectangle.
func _seg_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var tmin := 0.0
	var tmax := 1.0
	for axis in 2:
		var s: float = a[axis]
		var e: float = b[axis]
		var lo: float = r.position[axis]
		var hi: float = r.position[axis] + r.size[axis]
		var d := e - s
		if absf(d) < 1e-12:
			if s < lo or s > hi:
				return false
		else:
			var t1 := (lo - s) / d
			var t2 := (hi - s) / d
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return false
	return true


func _first_wall_between(a: Vector2, b: Vector2) -> Rect2:
	for w in Sim.WALLS:
		if _seg_hits_rect(a, b, w):
			return w
	return Rect2()


func _initialize() -> void:
	var player := Sim.create_player()
	var thief := Sim.create_thief()
	var loot := Sim.create_loot()
	var events: Array = []

	var t := 0.0
	var shots := 0
	var violations := 0
	var blocked_frames := 0
	var worst := ""

	while t < 600.0:
		# drive the homeowner along a wandering path, pushed out of solids exactly the
		# way game.gd does, so every sampled position is one a real player could hold
		var want := Vector2(sin(t * 0.9) * 6.0, -12.0 + cos(t * 0.6) * 6.0)
		want = Sim.resolve_circle(want, Sim.PLAYER_RADIUS)
		want = Sim.clamp_to_world(want, Sim.PLAYER_RADIUS)
		player["pos"] = want

		events = []
		Sim.step_thief(thief, player, loot, events, DT)
		for ev in events:
			if ev["type"] != "thiefShot":
				continue
			shots += 1
			var w := _first_wall_between(thief["pos"], player["pos"])
			if w.size != Vector2.ZERO:
				violations += 1
				if worst == "":
					worst = "t=%.1fs  thief=(%.2f,%.2f)  player=(%.2f,%.2f)  wall=%s" % [
						t, (thief["pos"] as Vector2).x, (thief["pos"] as Vector2).y,
						(player["pos"] as Vector2).x, (player["pos"] as Vector2).y, w]
		events.clear()

		if _first_wall_between(thief["pos"], player["pos"]).size != Vector2.ZERO:
			blocked_frames += 1
		t += DT

	print("simulated          : %.0f s" % t)
	print("frames with a wall between them: ", blocked_frames, "  (so there was ample opportunity)")
	print("shots fired        : ", shots)
	print("FIRED THROUGH A WALL: ", violations)
	if worst != "":
		print("  first violation  : ", worst)
	print("VERDICT: ", "clean" if violations == 0 else "BUG - the intruder really does shoot through walls")
	quit()
