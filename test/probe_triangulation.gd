extends SceneTree

## Why does Godot refuse to triangulate the minimap's visibility polygon?
##   godot --headless --path . --script test/probe_triangulation.gd
##
## NOT a test. A diagnostic, in the tradition of test/anim_probe.gd: it exists to produce a
## NUMBER and a GEOOMETRY that can be judged, rather than a theory about the generator.
##
## The recorded history matters, because two theories have already been tried and one was
## reverted:
##
##   - "zero-area slivers from the +/-1e-4 rad corner triplets". A minimum-separation filter
##     was implemented, measured, and REVERTED: 141 failures in 300 frames, unchanged.
##   - "it needs angular decimation". Not tried, because decimating the fan visibly rounds
##     off corners.
##
## So neither the sliver theory nor simple dedup is established. This probe stops guessing
## at what the polygon is and asks what it actually IS on a failing frame:
##
##   1. Sweep thousands of positions the player can legitimately stand in.
##   2. For each, build `Sim.visibility_polygon` exactly as the minimap does.
##   3. Feed it to the SAME call the minimap fails on: `Geometry2D.triangulate_polygon`.
##   4. On failure, find WHICH TWO EDGES CROSS by brute force, and print them.
##
## Duplicate points and collinear runs are reported separately, so a passing/failing
## difference can be attributed to a real cause instead of the first anomaly noticed.

const EPS := 1e-9


func check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  PASS  ", label)
	else:
		print("  FAIL  ", label)
		if detail != "":
			print("        ", detail)


## Do segments a1-a2 and b1-b2 properly cross? Endpoints touching does NOT count — shared
## vertices are legitimate in a radial fan and would otherwise report thousands of false
## positives.
func seg_cross(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	var d1 := a2 - a1
	var d2 := b2 - b1
	var den := d1.cross(d2)
	if absf(den) < 1e-12:
		return false                      # parallel or collinear: not a *proper* crossing
	var t := (b1 - a1).cross(d2) / den
	var u := (b1 - a1).cross(d1) / den
	return t > 1e-7 and t < 1.0 - 1e-7 and u > 1e-7 and u < 1.0 - 1e-7


## The first pair of non-adjacent edges that properly cross, as "i/j" or "".
func find_crossing(pts: PackedVector2Array) -> String:
	var n := pts.size()
	for i in n:
		var a1 := pts[i]
		var a2 := pts[(i + 1) % n]
		for j in range(i + 1, n):
			# skip adjacent edges, which legitimately share a vertex
			if j == i or (j + 1) % n == i or (i + 1) % n == j:
				continue
			if seg_cross(a1, a2, pts[j], pts[(j + 1) % n]):
				return "%d/%d" % [i, j]
	return ""


func _init() -> void:
	print("\nvisibility polygon triangulation probe")
	var solids := Sim.SOLIDS
	print("  solids: %d   BOUNDS: %s" % [solids.size(), Sim.BOUNDS])

	# Sweep a grid over the walkable world. Step 0.35 m is finer than the player radius
	# (0.42), so no pocket of the map is skipped.
	var step := 0.35
	var tried := 0
	var failed := 0
	var failures: Array = []
	var dup_fail := 0
	var dup_ok := 0
	var cross_seen := 0

	var x := Sim.BOUNDS.position.x
	while x <= Sim.BOUNDS.end.x:
		var y := Sim.BOUNDS.position.y
		while y <= Sim.BOUNDS.end.y:
			var p := Vector2(x, y)
			y += step
			# only where a body can actually be: inside the world and not inside scenery
			if Sim.resolve_circle(p, Sim.PLAYER_RADIUS) != p:
				continue
			tried += 1
			var poly := Sim.visibility_polygon(p, 30.0)
			if poly.size() < 3:
				continue
			var tris := Geometry2D.triangulate_polygon(poly)
			var bad := tris.is_empty()

			# duplicates, counted for both outcomes so they can be attributed
			var dups := 0
			for i in poly.size():
				if poly[i].distance_to(poly[(i + 1) % poly.size()]) < 1e-6:
					dups += 1
			if bad:
				dup_fail += 1
			else:
				dup_ok += 1

			if bad:
				failed += 1
				var cross := find_crossing(poly)
				if cross != "":
					cross_seen += 1
				if failures.size() < 4:
					failures.append({
						"from": p, "n": poly.size(), "dups": dups, "cross": cross,
						"poly": poly,
					})
			x += step

	print("\n  positions sampled      : %d" % tried)
	print("  triangulation FAILURES : %d  (%.1f%%)" % [failed, 100.0 * float(failed) / maxf(1.0, float(tried))])
	print("  of those, self-crossing: %d" % cross_seen)
	print("  frames with a duplicate-adjacent pair: %d of %d failing, %d of %d passing"
		% [dup_fail, failed, dup_ok, tried - failed])

	check("the probe actually reproduced the failure", failed > 0,
		"no failures found — the sweep may not cover the failing region")

	for f in failures:
		var poly: PackedVector2Array = f["poly"]
		print("\n  --- failing polygon ---")
		print("  from %s, %d points, %d duplicate-adjacent, crossing edges: '%s'"
			% [f["from"], f["n"], f["dups"], f["cross"] if f["cross"] != "" else "NONE"])
		# the vertex list, so the geometry can be read rather than described
		for i in mini(poly.size(), 40):
			print("    [%2d] %8.4f %8.4f" % [i, poly[i].x, poly[i].y])
		if poly.size() > 40:
			print("    ... %d more" % (poly.size() - 40))

	print("\ndone\n")
	quit(0)
