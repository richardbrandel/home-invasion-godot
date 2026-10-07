extends Control
class_name Minimap

## Fog-of-war minimap.
##
## The house layout is the homeowner's own property, so it is always drawn. The
## INTRUDER only appears when Sim.can_see says the homeowner actually has line of
## sight — no seeing through walls. The lit region is a real visibility polygon
## cast from the player, not a circle.
##
## The polygon costs ~2.1 ms, so it is recomputed every POLY_EVERY frames and
## reused in between; at 60 fps that is ~15-20 Hz, which reads as instant.

const VIEW := Rect2(-22, -24, 44, 40)
const POLY_EVERY := 3

var player := {}
var thieves: Array = []
var loot: Array = []

var _poly := PackedVector2Array()
var _frame := 0
var _scale := 1.0
var _off := Vector2.ZERO

const C_BG := Color(0.047, 0.063, 0.075)
const C_FLOOR_DIM := Color(0.106, 0.122, 0.141)
const C_WALL_DIM := Color(0.204, 0.227, 0.255)
const C_FLOOR_LIT := Color(0.227, 0.271, 0.314)
const C_WALL_LIT := Color(0.788, 0.824, 0.863)
const C_FURNITURE := Color(0.482, 0.380, 0.267)
const C_LOOT := Color(0.961, 0.690, 0.165)
const C_LOOT_GONE := Color(0.294, 0.333, 0.388)
const C_PLAYER := Color(0.302, 0.545, 0.961)
const C_THIEF := Color(0.937, 0.267, 0.267)


func _ready() -> void:
	custom_minimum_size = Vector2(250, 210)
	size = Vector2(250, 210)
	_scale = minf(size.x / VIEW.size.x, size.y / VIEW.size.y)
	_off = Vector2((size.x - VIEW.size.x * _scale) * 0.5,
		(size.y - VIEW.size.y * _scale) * 0.5)


## World (x, z) -> minimap pixels.
##
## The Y AXIS IS INVERTED, and that is the point. In the world, +Z runs from the house
## out to the street, and the player spawns on the driveway facing the house (yaw 0 faces
## +Z). Canvas Y grows downward, so mapping +Z to +Y drew the house ABOVE the player while
## they faced it — the whole map read upside-down and it is what Richard reported as "the
## minimap is mirrored". It is not mirrored, it is flipped vertically: a mirror reverses
## handedness, and this only reversed which way was up.
func _to_map(p: Vector2) -> Vector2:
	var local := p - VIEW.position
	return _off + Vector2(local.x, VIEW.size.y - local.y) * _scale


func _rect(r: Rect2, c: Color) -> void:
	draw_rect(Rect2(_to_map(r.position), r.size * _scale), c, true)


## `t` is either one intruder dictionary (the single-intruder case, kept working) or an
## array of them. The minimap used to take exactly one body; with three it drew whichever
## one `game.gd` happened to pass and silently hid the other two.
func update_state(p: Dictionary, t, l: Array) -> void:
	player = p
	thieves = t if t is Array else [t]
	loot = l
	_frame += 1
	if _frame % POLY_EVERY == 0 or _poly.is_empty():
		_poly = Sim.visibility_polygon(p["pos"], 30.0)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BG, true)
	if player.is_empty():
		return
	var ppos: Vector2 = player["pos"]

	# ---- dim layer: the layout as known, unlit
	_rect(Sim.HOUSE, C_FLOOR_DIM)
	for f in Sim.FURNITURE:
		_rect(f["rect"], C_FURNITURE)
	for w in Sim.WALLS:
		_rect(w, C_WALL_DIM)

	# ---- lit layer, clipped to what the player can actually see
	#
	# KNOWN ISSUE: from some player positions Godot refuses to triangulate this
	# polygon ("Invalid polygon data, triangulation failed") and the lit floor is
	# simply not drawn; everything else on the minimap is unaffected. The cause is
	# the +/-1e-4 rad corner pairs in Sim.visibility_polygon producing zero-area
	# sliver triangles, which ear-clipping rejects. Deduplicating coincident
	# points does NOT fix it (tried) — it needs angular decimation, which risks
	# visibly rounding off corners. Left alone deliberately; see AGENTS.md.
	if _poly.size() > 2:
		var pts := PackedVector2Array()
		for p in _poly:
			pts.append(_to_map(p))
		draw_colored_polygon(pts, C_FLOOR_LIT)

		# walls and furniture inside the lit region, drawn bright. Godot has no
		# canvas clip in _draw, so membership is tested per rect centre instead.
		for w in Sim.WALLS:
			if _inside_poly(_to_map(w.position + w.size * 0.5)):
				_rect(w, C_WALL_LIT)
		for f in Sim.FURNITURE:
			if _inside_poly(_to_map(f["rect"].position + f["rect"].size * 0.5)):
				_rect(f["rect"], C_FURNITURE)

	# ---- loot
	for l in loot:
		if l["delivered"]:
			continue
		var col: Color = C_LOOT_GONE if l["taken"] else C_LOOT
		draw_circle(_to_map(l["pos"]), 3.5, col)

	# ---- THE REQUIREMENT: the intruder only with line of sight. Every one of them:
	# `can_see` is the homeowner's own sight, so a man behind a wall stays hidden even
	# when two of his friends are in plain view.
	for t in thieves:
		var it: Dictionary = t
		if not bool(it.get("alive", false)):
			continue
		if Sim.can_see(ppos, it["pos"], 30.0):
			var tp := _to_map(it["pos"])
			draw_circle(tp, 5.0, C_THIEF)
			draw_arc(tp, 5.0, 0.0, TAU, 16, Color(1, 1, 1, 0.8), 1.4)

	# ---- the homeowner, always, with a facing wedge
	var mp := _to_map(ppos)
	draw_circle(mp, 5.0, C_PLAYER)
	draw_arc(mp, 5.0, 0.0, TAU, 16, Color(1, 1, 1, 0.9), 1.4)
	var yaw: float = player.get("yaw", 0.0)
	# yaw 0 faces +Z, so the facing vector is (sin yaw, cos yaw) in the world — the same
	# convention Sim's movement and the shove use. `(cos, sin)` was 90 degrees out. The
	# screen Y is negated to match the flipped mapping above, so the wedge agrees with the
	# map instead of pointing into the lawn.
	var fwd := Vector2(sin(yaw), -cos(yaw)) * 6.0 * _scale
	draw_line(mp, mp + fwd, Color(1, 1, 1, 0.55), 1.4)

	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.16), false, 1.0)


## Even-odd point-in-polygon over the cached visibility polygon.
func _inside_poly(pt: Vector2) -> bool:
	var inside := false
	var n := _poly.size()
	if n < 3:
		return false
	var j := n - 1
	for i in n:
		var a := _to_map(_poly[i])
		var b := _to_map(_poly[j])
		if ((a.y > pt.y) != (b.y > pt.y)) \
		and (pt.x < (b.x - a.x) * (pt.y - a.y) / (b.y - a.y) + a.x):
			inside = not inside
		j = i
	return inside
