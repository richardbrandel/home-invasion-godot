extends SceneTree

## Can the radial fan be drawn as TRIANGLES instead of as an outline?
##   godot --headless --path . --script test/probe_fan.gd
##
## NOT a test — the fourth step of the minimap investigation, and the one that may make the
## whole problem disappear without touching `Sim.visibility_polygon`.
##
## WHAT IS ESTABLISHED:
##   - `Sim.visibility_polygon` returns a NON-SIMPLE outline. 64% of positions have two
##     edges that properly cross (test/probe_triangulation.gd), which is why Godot's
##     ear-clipper rejects it and prints "Invalid polygon data, triangulation failed".
##   - No point-removal filter fixes that: dedup, spacing and turn-filtering all leave
##     26-78% failing (test/probe_triangulation2.gd).
##   - Rebuilding the lit region from per-edge silhouettes is sound (0 of 287,970 wedges
##     fail) but INCOMPLETE — 93% of the truly visible area would go unlit
##     (test/probe_litfaces.gd). That is a rework, not a patch.
##
## THE IDEA TESTED HERE. The outline is self-intersecting, but the polygon is STAR-SHAPED
## about the viewer by construction: it was built by sorting rays by angle from that exact
## point. So the fan of triangles (viewer, pts[i], pts[i+1]) tiles the union correctly even
## where the outline crosses itself — the crossings come from the EDGE JOINING, and the
## triangles from the apex are unaffected by it.
##
## Ear-clipping operates on the outline and cannot see that. `draw_primitive` never
## triangulates anything: it takes three points and draws a triangle. So this probe asks
## whether per-triangle area culling is enough to draw the fan, which would fix the minimap
## in one file with no change to the sim.
##
## The test: for a sample of positions, compare the union of the fan triangles against
## `Sim.los_blocked` — the same ground truth test/probe_litfaces.gd was measured against, so
## the two numbers are directly comparable.

const MAX_RANGE := 30.0


func _init() -> void:
	print("\nradial fan drawn as triangles\n")
	var positions := _positions()
	print("  positions: %d" % positions.size())

	var deg_tris := 0
	var total_tris := 0
	var polys_that_triangulate := 0

	for p in positions:
		var poly := Sim.visibility_polygon(p, MAX_RANGE)
		if poly.size() >= 3 and not Geometry2D.triangulate_polygon(poly).is_empty():
			polys_that_triangulate += 1
		for i in range(1, poly.size() - 1):
			total_tris += 1
			if _area(p, poly[i], poly[i + 1]) < 1e-7:
				deg_tris += 1

	print("  outlines that ear-clip fine : %d / %d  (%.1f%%)"
		% [polys_that_triangulate, positions.size(),
			100.0 * polys_that_triangulate / positions.size()])
	print("  fan triangles               : %d  (avg %.1f per position)"
		% [total_tris, float(total_tris) / positions.size()])
	print("  of those, degenerate (area < 1e-7): %d  (%.2f%%)"
		% [deg_tris, 100.0 * float(deg_tris) / maxf(1.0, float(total_tris))])
	print("  => culling those is the only step draw_primitive needs")

	_coverage(positions)
	print("")
	quit(0)


## Twice the signed area of the triangle.
static func _area(a: Vector2, b: Vector2, c: Vector2) -> float:
	return absf((b - a).cross(c - a))


## Union of the fan's triangles vs `Sim.los_blocked`. Same metric and same step as
## test/probe_litfaces.gd, so HOLES/LEAKS here and there are directly comparable.
func _coverage(positions: Array[Vector2]) -> void:
	print("\ncoverage vs line-of-sight ground truth")
	var step := 0.9
	var holes := 0
	var leaks := 0
	var lit := 0
	for viewer in positions:
		var poly := Sim.visibility_polygon(viewer, MAX_RANGE)
		var tris: Array = []
		for i in range(1, poly.size() - 1):
			if _area(viewer, poly[i], poly[i + 1]) >= 1e-7:
				tris.append([poly[i], poly[i + 1]])
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
				for t in tris:
					if _point_in_tri(q, viewer, t[0], t[1]):
						covered = true
						break
				if visible and covered:
					lit += 1
				elif visible and not covered:
					holes += 1
				elif covered and not visible:
					leaks += 1
			x += step
	var tot := maxf(1.0, float(lit + holes + leaks))
	print("  samples lit correctly   : %d" % lit)
	print("  HOLES (visible, unlit)  : %d  (%.2f%%)" % [holes, 100.0 * holes / tot])
	print("  LEAKS (blocked, lit)    : %d  (%.2f%%)" % [leaks, 100.0 * leaks / tot])


static func _point_in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p - a).cross(b - a)
	var d2 := (p - b).cross(c - b)
	var d3 := (p - c).cross(a - c)
	var has_neg := d1 < -1e-9 or d2 < -1e-9 or d3 < -1e-9
	var has_pos := d1 > 1e-9 or d2 > 1e-9 or d3 > 1e-9
	return not (has_neg and has_pos)


func _positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var step := 2.0
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
