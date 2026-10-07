extends SceneTree

## Build the lit region from SOLID EDGES instead of a radial fan of rays.
##   godot --headless --path . --script test/probe_litfaces.gd
##
## NOT a test — the third step of the minimap investigation, and the one that has to
## succeed before anything in minimap.gd is rewritten.
##
## WHY THE OLD CONSTRUCTION CANNOT BE FIXED. `Sim.visibility_polygon` fires a ray per
## angle and connects the landing points in angle order. That outline is NOT SIMPLE: on
## 64% of positions two of its edges properly cross, because three rays a fraction of a
## degree apart (the +/-1e-4 corner triplets) can land on three different surfaces, and the
## edge joining those landings leaps across the interior. Godot's ear-clipper rejects a
## self-intersecting outline, which is the "triangulation failed" in the console.
##
## Measured, on 24,715 positions (test/probe_triangulation2.gd):
##   raw 64.4% failed | dedup 64.1% | spacing 0.01 m 64.4% | turn-filter 1 deg 31.7%
## Nothing that removes POINTS helps, because the crossings come from the ORDER, not from
## the points. That also explains the reverted sliver filter changing nothing.
##
## THE REPLACEMENT. For each solid, a lit face is a convex wedge from the viewer through one
## visible edge of that solid:
##
##     viewer -- e1,e2 -- e2',e1'            (the edge projected out to max range)
##
## Each wedge is at most 4 points, is simple, always triangulates, and needs no clipping.
## The lit region is the UNION of the wedges, which is what painting them all in one draw
## call onto the same target produces.
##
## WHAT THIS PROBE DOES NOT SETTLE: whether the union leaves visible gaps or leaks light
## through a wall's corners. That is a question for an IMAGE, not for a polygon count, so
## this probe only establishes that the construction is sound — 0% triangulation failures,
## every wedge simple — before the renderer is touched.

const MAX_RANGE := 30.0


func _init() -> void:
	print("\nlit-face construction probe")

	var positions := _positions()
	print("  positions: %d   solids: %d\n" % [positions.size(), Sim.SOLIDS.size()])

	var bad_wedges := 0
	var bad_frames := 0
	var total_wedges := 0
	var empty_frames := 0
	var worst_tris := 0

	for p in positions:
		var faces := lit_faces(p)
		if faces.is_empty():
			empty_frames += 1
		var this_bad := 0
		for w in faces:
			total_wedges += 1
			var tris := Geometry2D.triangulate_polygon(w)
			if tris.is_empty():
				bad_wedges += 1
				this_bad += 1
			else:
				worst_tris = maxi(worst_tris, tris.size() / 3)
		if this_bad > 0:
			bad_frames += 1

	print("  wedges emitted        : %d  (avg %.1f per position)"
		% [total_wedges, float(total_wedges) / positions.size()])
	print("  wedges that failed    : %d  (%.3f%%)"
		% [bad_wedges, 100.0 * float(bad_wedges) / maxf(1.0, float(total_wedges))])
	print("  positions with any bad: %d  (%.3f%%)"
		% [bad_frames, 100.0 * float(bad_frames) / positions.size()])
	print("  positions with no face: %d" % empty_frames)
	print("  max triangles in a wedge: %d" % worst_tris)

	print("")
	if bad_wedges == 0 and empty_frames == 0:
		print("  => construction is sound; safe to rewrite minimap.gd against it")
	else:
		print("  => NOT sound; do not rewrite the renderer yet")

	_coverage_check(positions)
	print("")
	quit(0)


## Does the union of wedges actually equal the visible region?
##
## This is the question the soundness check explicitly does not answer. The ground truth is
## `Sim.los_blocked` — the same call the sim uses to decide what the homeowner can see — and
## it is INDEPENDENT of the wedge construction, so this is not a test that calls the thing
## under test. A sample inside range and not blocked but covered by no wedge is a hole in
## the lit region; covered but blocked is light leaking through a wall.
func _coverage_check(positions: Array[Vector2]) -> void:
	print("\ncoverage vs line-of-sight ground truth")
	var step := 0.9
	var holes := 0
	var leaks := 0
	var lit := 0
	var dark := 0

	for viewer in positions:
		var faces := lit_faces(viewer)
		var x := viewer.x - MAX_RANGE
		while x <= viewer.x + MAX_RANGE:
			var y := viewer.y - MAX_RANGE
			while y <= viewer.y + MAX_RANGE:
				var q := Vector2(x, y)
				y += step
				if viewer.distance_to(q) > MAX_RANGE:
					continue
				var visible := not Sim.los_blocked(viewer, q)
				var covered := false
				for f in faces:
					if _point_in_tri(q, f[0], f[1], f[2]):
						covered = true
						break
				if visible and not covered:
					holes += 1
				elif covered and not visible:
					leaks += 1
				elif visible:
					lit += 1
				else:
					dark += 1
			x += step

	var tot := maxf(1.0, float(lit + holes + leaks))
	print("  samples lit correctly   : %d" % lit)
	print("  HOLES (visible, unlit)  : %d  (%.2f%%)" % [holes, 100.0 * holes / tot])
	print("  LEAKS (blocked, lit)    : %d  (%.2f%%)" % [leaks, 100.0 * leaks / tot])
	print("  correctly dark          : %d" % dark)
	if holes == 0 and leaks == 0:
		print("  => the union reproduces line of sight exactly")
	else:
		print("  => approxation only; a render is still needed before trusting it")


static func _point_in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p - a).cross(b - a)
	var d2 := (p - b).cross(c - b)
	var d3 := (p - c).cross(a - c)
	var has_neg := d1 < -1e-9 or d2 < -1e-9 or d3 < -1e-9
	var has_pos := d1 > 1e-9 or d2 > 1e-9 or d3 > 1e-9
	return not (has_neg and has_pos)


func _positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var step := 0.7
	var x := Sim.BOUNDS.position.x
	while x <= Sim.BOUNDS.end.x:
		var y := Sim.BOUNDS.position.y
		while y <= Sim.BOUNDS.end.y:
			var p := Vector2(x, y)
			if Sim.resolve_circle(p, Sim.PLAYER_RADIUS) == p:
				out.append(p)
			y += step
		x += step
	return out


## One convex quad per solid EDGE that faces the viewer and is not occluded.
##
## The quad is the sliver of world swept by looking at that edge: the two edge endpoints,
## and where the rays through them stop. For an edge whose endpoints are BOTH within range
## the swept region is bounded by the edge itself, so the quad is:
##
##     viewer, e1, e2, back-toward-viewer
##
## which is a triangle with a duplicated point when the edge is fully visible — harmless,
## and still simple. When an endpoint is beyond range the swept region runs out to the cast
## distance instead, so the far side becomes the two cast points.
static func lit_faces(viewer: Vector2) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for s in Sim.SOLIDS:
		var c: Array[Vector2] = [
			s.position,
			Vector2(s.end.x, s.position.y),
			s.end,
			Vector2(s.position.x, s.end.y),
		]
		for i in 4:
			var e1: Vector2 = c[i]
			var e2: Vector2 = c[(i + 1) % 4]

			# Back-face test: an edge whose outward normal points away from the viewer
			# cannot be seen, and emitting it would light the far side of a wall.
			var mid := (e1 + e2) * 0.5
			var edge := (e2 - e1).normalized()
			var normal := Vector2(edge.y, -edge.x)
			if (mid - s.get_center()).normalized().dot(normal) < 0.0:
				normal = -normal
			if normal.dot((viewer - mid).normalized()) <= 0.0:
				continue
			# NOT tested for occlusion here ON PURPOSE, and the first version of this probe
			# got it wrong: `Sim.los_blocked(viewer, mid)` samples a point that lies exactly
			# ON the wall, so it is trivially blocked and rejected every face — the probe
			# reported "0 wedges emitted, 0 failed", which is a pass-shaped nothing. What
			# this probe has to establish is that the construction is SOUND (simple, always
			# triangulable). Whether a kept face is correctly hidden is a question for an
			# IMAGE, and belongs with the renderer, not here.

			var d1 := (e1 - viewer)
			var d2 := (e2 - viewer)
			if d1.length() < 1e-6 or d2.length() < 1e-6:
				continue
			var n1 := d1.normalized()
			var n2 := d2.normalized()
			# Where each ray stops: at the edge if it is in range, else out at the wall
			# behind it. `ray_cast_px` from the viewer along the edge direction returns the
			# edge's own distance for a visible edge, which is what makes this the silhouette.
			var r1 := minf(MAX_RANGE, Sim.ray_cast_px(viewer, n1, MAX_RANGE))
			var r2 := minf(MAX_RANGE, Sim.ray_cast_px(viewer, n2, MAX_RANGE))
			var p1 := viewer + n1 * r1
			var p2 := viewer + n2 * r2
			if p1.distance_to(p2) < 1e-5:
				continue
			out.append(PackedVector2Array([viewer, p1, p2]))
	return out
