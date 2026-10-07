extends SceneTree

## Which cleanup actually makes the visibility polygon triangulate?
##   godot --headless --path . --script test/probe_triangulation2.gd
##
## NOT a test — the second half of test/probe_triangulation.gd.
##
## That probe established the cause, and it was neither of the two theories on record:
## the polygon is NOT SIMPLE. 212 of 213 failing frames have two edges that properly
## cross, so Godot's ear-clipper is rejecting a self-intersecting outline rather than
## choking on zero-area slivers. That is why the minimum-separation filter changed
## nothing (141 failures in 300 frames, before and after) and why dedup would not either.
##
## The cause of the crossings is the +/-1e-4 rad corner triplets. Three rays fired a
## fraction of a degree apart can land on three DIFFERENT surfaces, and the edges joining
## those landing points then leap across the interior. The triplet is what makes a corner
## exact — and it is also what breaks the outline.
##
## So this probe measures candidate cleanups against each other on the SAME sweep:
##
##   raw          what the minimap uses today
##   dedup        drop consecutive duplicates
##   spacing      drop any point nearer than X to the previous one
##   turn         drop points whose turn from the previous edge is under a threshold —
##                i.e. remove the near-collinear ray cluster instead of the vertices
##
## The one that reaches 0% failures with the fewest points removed is the fix.

const STEP := 0.35


func _positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var x := Sim.BOUNDS.position.x
	while x <= Sim.BOUNDS.end.x:
		var y := Sim.BOUNDS.position.y
		while y <= Sim.BOUNDS.end.y:
			var p := Vector2(x, y)
			if Sim.resolve_circle(p, Sim.PLAYER_RADIUS) == p:
				out.append(p)
			y += STEP
		x += STEP
	return out


func _fails(poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return true
	return Geometry2D.triangulate_polygon(poly).is_empty()


func _dedup(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 1e-9:
			out.append(p)
	# a radial fan's first and last point are adjacent too
	while out.size() > 2 and out[0].distance_to(out[out.size() - 1]) <= 1e-9:
		out.remove_at(out.size() - 1)
	return out


func _spacing(poly: PackedVector2Array, min_d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		if out.is_empty() or out[out.size() - 1].distance_to(p) >= min_d:
			out.append(p)
	return out


## Drop points where the path barely turns. A cluster of rays that all land on one surface
## contributes a run of near-collinear points; the corner triplets make almost no turn at
## all, because 1e-4 rad is 0.006 degrees.
func _turn(poly: PackedVector2Array, min_deg: float) -> PackedVector2Array:
	var n := poly.size()
	if n < 3:
		return poly
	var out := PackedVector2Array()
	for i in n:
		var prev := poly[(i - 1 + n) % n]
		var cur := poly[i]
		var next := poly[(i + 1) % n]
		var a := (cur - prev)
		var b := (next - cur)
		if a.length() < 1e-9 or b.length() < 1e-9:
			continue
		var turn := absf(rad_to_deg(a.angle_to(b)))
		if turn >= min_deg:
			out.append(cur)
	return out


func _init() -> void:
	var positions := _positions()
	print("\npolygon cleanup comparison over %d positions\n" % positions.size())

	var polys: Array[PackedVector2Array] = []
	for p in positions:
		polys.append(Sim.visibility_polygon(p, 30.0))

	var raw_fail := 0
	for poly in polys:
		if _fails(poly):
			raw_fail += 1
	print("  %-28s %5d failed  %6.1f%%   avg pts %.1f"
		% ["raw (current)", raw_fail, 100.0 * raw_fail / polys.size(),
			_avg(polys)])

	var deduped: Array[PackedVector2Array] = []
	for poly in polys:
		deduped.append(_dedup(poly))
	print("  %-28s %5d failed  %6.1f%%   avg pts %.1f"
		% ["dedup", _count_fails(deduped), 100.0 * _count_fails(deduped) / polys.size(),
			_avg(deduped)])

	for d in [0.001, 0.01, 0.05, 0.15, 0.3]:
		var cleaned: Array[PackedVector2Array] = []
		for poly in polys:
			cleaned.append(_spacing(poly, d))
		var f := _count_fails(cleaned)
		print("  %-28s %5d failed  %6.1f%%   avg pts %.1f"
			% ["spacing >= %.3f m" % d, f, 100.0 * f / polys.size(), _avg(cleaned)])

	for deg in [0.01, 0.1, 1.0, 5.0, 15.0]:
		var cleaned: Array[PackedVector2Array] = []
		for poly in polys:
			cleaned.append(_turn(poly, deg))
		var f := _count_fails(cleaned)
		print("  %-28s %5d failed  %6.1f%%   avg pts %.1f"
			% ["turn >= %.2f deg" % deg, f, 100.0 * f / polys.size(), _avg(cleaned)])

	print("")
	quit(0)


func _count_fails(arr: Array[PackedVector2Array]) -> int:
	var n := 0
	for poly in arr:
		if _fails(poly):
			n += 1
	return n


func _avg(arr: Array[PackedVector2Array]) -> float:
	var t := 0
	for poly in arr:
		t += poly.size()
	return float(t) / maxf(1.0, float(arr.size()))
