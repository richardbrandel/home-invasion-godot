extends RefCounted
class_name Sim

## Pure simulation for Home Invasion. Ported from the JavaScript version.
##
## Imports nothing and touches no node, so it can be driven headlessly under
## `godot --headless --script test/test_sim.gd`. All logic is in the XZ plane;
## Vector2.x is world X and Vector2.y is world Z. Y is height and lives only in
## the renderer.
##
## Units are metres. The player is ~1.8 tall, walls 2.7, the van 2.4.

# --------------------------------------------------------------------- world
const HOUSE := Rect2(-8, -19, 16, 11)          # x, z, width, depth
## Matches House.WALL_TARGET_H, which is KayKit's 4 m wall module at 0.5 scale.
## Changing one without the other makes the collision boxes disagree with the art.
const WALL_HEIGHT := 2.0
const WALL_THICKNESS := 0.25
const DOOR_GAP := Vector2(-1, 1)               # front door, in the south wall
const HALL_GAP := Vector2(-2, 2)               # opening in the interior wall
const INTERIOR_Z := -14.0

const BOUNDS := Rect2(-30, -28, 60, 52)

static func _walls() -> Array[Rect2]:
	var T := WALL_THICKNESS
	var H := HOUSE
	var iz := INTERIOR_Z
	return [
		# exterior
		Rect2(H.position.x, H.position.y, H.size.x, T),                                  # north
		Rect2(H.position.x, H.end.y - T, DOOR_GAP.x - H.position.x, T),                   # south-west of the door
		Rect2(DOOR_GAP.y, H.end.y - T, H.end.x - DOOR_GAP.y, T),                          # south-east of the door
		Rect2(H.position.x, H.position.y, T, H.size.y),                                   # west
		Rect2(H.end.x - T, H.position.y, T, H.size.y),                                    # east
		# interior divider with a central opening
		Rect2(H.position.x, iz - T * 0.5, HALL_GAP.x - H.position.x, T),
		Rect2(HALL_GAP.y, iz - T * 0.5, H.end.x - HALL_GAP.y, T),
	]

static var WALLS: Array[Rect2] = _walls()

## Furniture: Rect2 in XZ, plus h (height), kind, and flat (rugs: drawn, not solid).
static var FURNITURE: Array[Dictionary] = [
	# ---- living room (front west)
	{"rect": Rect2(-7.40, -12.60, 1.20, 3.20), "h": 0.80, "kind": "sofa"},
	{"rect": Rect2(-7.00, -14.10, 0.40, 0.40), "h": 0.45, "kind": "side_table"},
	{"rect": Rect2(-5.60, -11.70, 1.40, 1.40), "h": 0.42, "kind": "coffee_table"},
	{"rect": Rect2(-6.40, -13.60, 2.20, 0.50), "h": 0.50, "kind": "tv_stand"},
	{"rect": Rect2(-7.60, -8.60, 4.40, 1.80), "h": 0.02, "kind": "rug", "flat": true},
	{"rect": Rect2(-7.30, -9.90, 0.45, 0.45), "h": 1.60, "kind": "lamp"},

	# ---- kitchen (front east)
	{"rect": Rect2(6.60, -13.00, 1.15, 4.00), "h": 0.92, "kind": "counter"},
	{"rect": Rect2(6.70, -13.85, 1.00, 0.80), "h": 1.85, "kind": "fridge"},
	{"rect": Rect2(2.60, -12.40, 2.00, 1.50), "h": 0.75, "kind": "dining_table"},
	{"rect": Rect2(3.15, -10.75, 0.55, 0.50), "h": 0.90, "kind": "chair"},
	{"rect": Rect2(3.55, -13.00, 0.55, 0.45), "h": 0.90, "kind": "chair"},

	# ---- bedroom (back west)
	{"rect": Rect2(-7.40, -18.60, 2.40, 2.20), "h": 0.55, "kind": "bed"},
	{"rect": Rect2(-7.40, -16.20, 0.50, 0.50), "h": 0.55, "kind": "nightstand"},
	{"rect": Rect2(-4.60, -18.70, 1.20, 0.60), "h": 2.00, "kind": "wardrobe"},
	{"rect": Rect2(-6.80, -15.60, 3.80, 1.00), "h": 0.02, "kind": "rug", "flat": true},

	# ---- study (back east)
	{"rect": Rect2(5.50, -17.40, 2.00, 1.10), "h": 0.75, "kind": "desk"},
	{"rect": Rect2(5.00, -16.10, 0.60, 0.60), "h": 0.95, "kind": "desk_chair"},
	{"rect": Rect2(0.60, -18.60, 0.80, 2.60), "h": 2.00, "kind": "bookshelf"},
	{"rect": Rect2(0.70, -15.60, 0.60, 0.60), "h": 1.30, "kind": "cabinet"},
]

static func _solids() -> Array[Rect2]:
	var out: Array[Rect2] = []
	out.append_array(WALLS)
	for f in FURNITURE:
		if not f.get("flat", false):
			out.append(f["rect"])
	return out

static var SOLIDS: Array[Rect2] = _solids()

const VAN := Rect2(-2.75, 7.0, 5.5, 2.4)
const DROP := Vector2(0, 4.5)

## Loot sits on the floor at a spot the thief can actually reach, beside the
## furniture it belongs to. Keeping it off the furniture is what lets the
## reachability test stay strict.
static var LOOT_SPOTS: Array[Dictionary] = [
	{"pos": Vector2(-5.30, -12.90), "label": "TV", "node": "living"},
	{"pos": Vector2(6.60, -16.05), "label": "Laptop", "node": "study"},
	{"pos": Vector2(-4.20, -17.60), "label": "Safe", "node": "bedroom"},
]

## Navigation graph. Every edge is a straight line through open floor; the test
## suite asserts none of them crosses a solid.
static var NODES: Dictionary = {
	"van":      {"pos": Vector2(0, 5.0),    "edges": ["doorOut"]},
	"doorOut":  {"pos": Vector2(0, -5.0),   "edges": ["van", "doorIn"]},
	"doorIn":   {"pos": Vector2(0, -9.6),   "edges": ["doorOut", "frontHub"]},
	"frontHub": {"pos": Vector2(0, -11.2),  "edges": ["doorIn", "living", "kitchen", "opening"]},
	"living":   {"pos": Vector2(-3.6, -11.2), "edges": ["frontHub"]},
	"kitchen":  {"pos": Vector2(4.5, -9.6), "edges": ["frontHub"]},
	"opening":  {"pos": Vector2(0, -14.0),  "edges": ["frontHub", "bedroom", "study"]},
	"bedroom":  {"pos": Vector2(-4.4, -15.6), "edges": ["opening"]},
	"study":    {"pos": Vector2(6.5, -15.5), "edges": ["opening"]},
}

# -------------------------------------------------------------------- tuning
const PLAYER_SPEED := 4.2
const PLAYER_SPRINT_SPEED := 6.6
const PLAYER_CROUCH_SPEED := 2.0
const PLAYER_RADIUS := 0.42
const EYE_HEIGHT := 1.62
const CROUCH_EYE_HEIGHT := 1.05

const THIEF_SPEED := 1.30          # was 2.6, then 1.75 — still too brisk
const THIEF_RADIUS := 0.42
const THIEF_HEALTH := 100
const THIEF_DAMAGE := 7
const THIEF_SIGHT := 26.0
## Roughly 200 degrees of awareness, and no reliable sense of what is directly behind
## him. Without this he spotted a player standing at his back and shot him instantly.
const THIEF_FOV_DEG := 200.0
## Radians per second he can turn. A person takes roughly 0.4-0.7 s to come about, and
## snapping the facing in a single frame was the clearest "this is a prop" tell left in
## the model.
const THIEF_TURN_RATE := 4.5
## How much of his pace he keeps while carrying each item. A home safe is a two-person
## job in reality and a laptop is one hand; both used to travel at exactly 1.3 m/s.
const CARRY_SPEED := {"TV": 0.70, "Safe": 0.50, "Laptop": 0.92}
const THIEF_FIRE_HUNTING := 1.35
const THIEF_MAG := 8
const THIEF_RELOAD := 1.5
## Continuous line of sight he needs before he can fire.
##
## Without it he shot on the exact frame you first became visible, so merely glimpsing
## him cost health instantly — and because the tracer is drawn from him to you, what you
## saw was a line arriving through the wall you had just ducked behind. He still fires
## at the same cadence; he just has to settle on you first, the way a person would.
const THIEF_AIM_TIME := 0.45
const GRAB_RANGE := 1.4
const DROP_RANGE := 1.6

## The thief starts giving the homeowner a wide berth this far out, and swings
## this hard when he does. Without it, making the two bodies solid would wall him
## in: the separation push is straight back along the line of approach, so a
## dead-on meeting stalls him permanently instead of letting him round the player.
const AVOID_RANGE := 2.2
const AVOID_TURN := 0.6

const WEAPONS := {
	"pistol":  {"name": "Pistol",  "dmg": 26, "cd": 0.24, "mag": 12, "reload": 1.15, "pellets": 1, "spread": 0.02},
	"shotgun": {"name": "Shotgun", "dmg": 13, "cd": 0.85, "mag": 6,  "reload": 1.60, "pellets": 9, "spread": 0.15},
}

# ------------------------------------------------------------------ geometry
## Liang-Barsky segment vs axis-aligned rect, in XZ.
static func seg_rect(a: Vector2, b: Vector2, r: Rect2, r_radius: float = 0.0) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var dx := b.x - a.x
	var dz := b.y - a.y
	var lo := r.position - Vector2(r_radius, r_radius)
	var hi := r.end + Vector2(r_radius, r_radius)
	var p := [-dx, dx, -dz, dz]
	var q := [a.x - lo.x, hi.x - a.x, a.y - lo.y, hi.y - a.y]
	for i in 4:
		if absf(p[i]) < 1e-9:
			if q[i] < 0.0:
				return false
			continue
		var t: float = q[i] / p[i]
		if p[i] < 0.0:
			if t > t1: return false
			if t > t0: t0 = t
		else:
			if t < t0: return false
			if t < t1: t1 = t
	return true

static func seg_circle(a: Vector2, b: Vector2, c: Vector2, radius: float) -> bool:
	var d := b - a
	var len2 := d.length_squared()
	var t := 0.0
	if len2 > 0.0:
		t = clampf((c - a).dot(d) / len2, 0.0, 1.0)
	var p := a + d * t
	return p.distance_squared_to(c) <= radius * radius

static func los_blocked(a: Vector2, b: Vector2) -> bool:
	for s in SOLIDS:
		if seg_rect(a, b, s):
			return true
	return false

## Distance to the first solid along a unit direction, or max_t when clear.
##
## This is the hottest function in the game — the visibility polygon calls it
## hundreds of times per frame. It is written out longhand with no array
## allocation on purpose: an earlier version built two arrays per solid per ray,
## which cost ~17,600 allocations per polygon and ran 5.1 ms. Inlining the slab
## test brought it under the frame budget.
static func ray_cast_px(from: Vector2, dir: Vector2, max_t := 60.0) -> float:
	var best := max_t
	var ox := from.x
	var oz := from.y
	var dx := dir.x
	var dz := dir.y
	for s in SOLIDS:
		var tmin := 0.0
		var tmax := max_t
		var ok := true

		# --- X slab
		var lo: float = s.position.x
		var hi: float = s.end.x
		if absf(dx) < 1e-9:
			if ox < lo or ox > hi:
				ok = false
		else:
			var t1 := (lo - ox) / dx
			var t2 := (hi - ox) / dx
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			if t1 > tmin:
				tmin = t1
			if t2 < tmax:
				tmax = t2
			if tmin > tmax:
				ok = false

		# --- Z slab (stored in .y)
		if ok:
			lo = s.position.y
			hi = s.end.y
			if absf(dz) < 1e-9:
				if oz < lo or oz > hi:
					ok = false
			else:
				var t3 := (lo - oz) / dz
				var t4 := (hi - oz) / dz
				if t3 > t4:
					var tmp2 := t3
					t3 = t4
					t4 = tmp2
				if t3 > tmin:
					tmin = t3
				if t4 < tmax:
					tmax = t4
				if tmin > tmax:
					ok = false

		if ok and tmin < best:
			best = tmin
	return best

## True only when b is both in range of a AND has unobstructed line of sight.
## This is what keeps the intruder off the minimap behind a wall.
static func can_see(a: Vector2, b: Vector2, max_range := 28.0) -> bool:
	if a.distance_to(b) > max_range:
		return false
	return not los_blocked(a, b)


## What the intruder can actually perceive.
##
## Deliberately NOT folded into can_see(): the minimap uses can_see() to decide whether
## the HOMEOWNER can see him, and a field of view there would blind the player to a man
## standing behind his own back. Human awareness is roughly 200 degrees with no reliable
## rear detection, so this is the intruder's test only.
static func thief_sees(tp: Vector2, t_yaw: float, ppos: Vector2) -> bool:
	if not can_see(tp, ppos, THIEF_SIGHT):
		return false
	var bearing := (ppos - tp).angle()
	return absf(wrapf(bearing - t_yaw, -PI, PI)) <= deg_to_rad(THIEF_FOV_DEG * 0.5)

## Visibility polygon from a point: a ray at every solid corner (with a small
## epsilon either side so corners come out crisp) plus a coarse ring.
static func visibility_polygon(from: Vector2, max_range := 28.0) -> PackedVector2Array:
	var angles: Array[float] = []
	for s in SOLIDS:
		# typed array + typed loop var: an untyped literal yields Variant, and
		# `var a := (c - from).angle()` then fails to infer at parse time.
		var corners: Array[Vector2] = [
			s.position,
			Vector2(s.end.x, s.position.y),
			s.end,
			Vector2(s.position.x, s.end.y),
		]
		for c in corners:
			var a: float = (c - from).angle()
			angles.append(a - 1e-4)
			angles.append(a)
			angles.append(a + 1e-4)
	for i in 64:
		angles.append(float(i) / 64.0 * TAU)
	angles.sort()

	var pts := PackedVector2Array()
	for a in angles:
		var dir := Vector2(cos(a), sin(a))
		pts.append(from + dir * ray_cast_px(from, dir, max_range))
	return pts

## Circle-vs-rect resolution in XZ. Handles a centre that ends up inside a solid.
static func resolve_circle(pos: Vector2, radius: float, solids: Array[Rect2] = SOLIDS) -> Vector2:
	for s in solids:
		var closest := Vector2(
			clampf(pos.x, s.position.x, s.end.x),
			clampf(pos.y, s.position.y, s.end.y))
		var d := pos - closest
		var d2 := d.length_squared()
		if d2 >= radius * radius:
			continue
		if d2 < 1e-9:
			var left := pos.x - s.position.x
			var right := s.end.x - pos.x
			var near := pos.y - s.position.y
			var far := s.end.y - pos.y
			var m: float = minf(minf(left, right), minf(near, far))
			if m == left: pos.x = s.position.x - radius
			elif m == right: pos.x = s.end.x + radius
			elif m == near: pos.y = s.position.y - radius
			else: pos.y = s.end.y + radius
			continue
		var dist := sqrt(d2)
		pos += d * ((radius - dist) / dist)
	return pos

static func clamp_to_world(pos: Vector2, radius: float) -> Vector2:
	return Vector2(
		clampf(pos.x, BOUNDS.position.x + radius, BOUNDS.end.x - radius),
		clampf(pos.y, BOUNDS.position.y + radius, BOUNDS.end.y - radius))

## Keep the homeowner and the intruder out of each other, so neither can walk
## through the other.
##
## The HOMEOWNER is the one displaced, and that choice is load-bearing. If the
## intruder yields instead he can be pinned indefinitely by a player who is simply
## standing there, and rerouting cannot rescue him because the blocker is a body
## rather than scenery. Measured with the intruder yielding: 142 re-routes and
## nothing ever delivered, and a player parked in the 2 m front doorway made the
## house impossible to leave. With the homeowner yielding, six of seven tested
## player behaviours complete the heist with zero re-routes. A nudge costs the
## player little anyway — his position is re-asserted from input every frame.
##
## Scenery still has the final say on both bodies: each is pushed back out of
## anything solid, and if the homeowner cannot be moved because there is scenery
## behind him, the shortfall is taken from the intruder so they never overlap.
## Returns [player_pos, thief_pos].
static func separate_bodies(ppos: Vector2, tpos: Vector2) -> Array[Vector2]:
	var min_dist := PLAYER_RADIUS + THIEF_RADIUS
	var d := tpos - ppos
	var dist := d.length()
	if dist >= min_dist:
		var clear: Array[Vector2] = [ppos, tpos]
		return clear
	# exactly coincident has no direction to work with; pick a fixed axis so the
	# result is repeatable rather than depending on float noise
	var n := Vector2(1.0, 0.0) if dist < 1e-5 else d / dist

	var t := tpos
	var p := clamp_to_world(resolve_circle(ppos - n * (min_dist - dist), PLAYER_RADIUS), PLAYER_RADIUS)

	var gap := t - p
	var gap_len := gap.length()
	if gap_len < min_dist - 1e-4:
		# he is against something immovable, so take the remainder from the intruder
		var bn := n if gap_len < 1e-5 else gap / gap_len
		t = clamp_to_world(resolve_circle(p + bn * min_dist, THIEF_RADIUS), THIEF_RADIUS)

	var out: Array[Vector2] = [p, t]
	return out

## Swing a heading away from the homeowner when he is close and in front. Ties —
## walking straight at him — break to a fixed side, so the thief is predictable
## instead of jittering left and right.
static func steer_around(a: float, from: Vector2, ppos: Vector2) -> float:
	var to_p := ppos - from
	var gap := to_p.length()
	if gap > AVOID_RANGE or gap < 1e-5:
		return a
	var fwd := Vector2(cos(a), sin(a))
	var dir := to_p / gap
	if fwd.dot(dir) <= 0.0:
		return a                       # he is behind; nothing to avoid
	var side := fwd.cross(dir)
	return a - AVOID_TURN if side > 0.0 else a + AVOID_TURN

# ------------------------------------------------------------------- pathing
static func nearest_node(p: Vector2) -> String:
	var best := "frontHub"
	var bd := INF
	for k in NODES:
		var d: float = (NODES[k]["pos"] as Vector2).distance_squared_to(p)
		if d < bd:
			bd = d
			best = k
	return best

static func path_nodes(from_key: String, to_key: String) -> Array:
	if from_key == to_key:
		return []
	var prev := {from_key: ""}
	var queue: Array = [from_key]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for nxt in NODES[cur]["edges"]:
			if prev.has(nxt):
				continue
			prev[nxt] = cur
			if nxt == to_key:
				var out: Array = []
				var k: String = to_key
				while k != from_key and k != "":
					out.push_front(k)
					k = prev[k]
				return out
			queue.append(nxt)
	return []

static func route_to(from_key: String, to_key: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for k in path_nodes(from_key, to_key):
		out.append(NODES[k]["pos"])
	return out

# ------------------------------------------------------------------ entities
static func create_player() -> Dictionary:
	return {
		"pos": Vector2(0, -10.6), "yaw": 0.0, "pitch": 0.24,
		"hp": 100.0, "alive": true, "weapon": "pistol",
		"crouching": false, "sprinting": false,
		"mag": 12, "cd": 0.0, "reloading": 0.0,
	}

static func create_thief() -> Dictionary:
	return {
		"pos": DROP + Vector2(0, 0.5), "prev": DROP + Vector2(0, 0.5), "yaw": PI,
		"hp": float(THIEF_HEALTH), "alive": true,
		"mag": THIEF_MAG, "cd": 1.2, "reloading": 0.0, "think": 2.0,
		"carry": "", "target": "", "route": [], "mode": "hunt",
		"stuck_t": 0.0, "aim": 0.0, "stagger": 0.0, "hits": 0,
	}

static func create_loot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in LOOT_SPOTS:
		out.append({"pos": s["pos"], "label": s["label"], "node": s["node"],
			"taken": false, "delivered": false})
	return out

static func remaining(loot: Array) -> int:
	var n := 0
	for l in loot:
		if not l["delivered"]:
			n += 1
	return n

# ------------------------------------------------------------------ thief AI
## Returns true when the thief currently has line of sight to the player.
## `events` accumulates {type=...} dictionaries the caller drains.
static func step_thief(thief: Dictionary, player: Dictionary, loot: Array, events: Array, dt: float) -> bool:
	if not thief["alive"]:
		return false

	thief["cd"] -= dt
	if thief["reloading"] > 0.0:
		thief["reloading"] -= dt

	var tpos: Vector2 = thief["pos"]
	var ppos: Vector2 = player["pos"]

	# ---- decide
	if thief["carry"] != "":
		thief["mode"] = "carry"
		if (thief["route"] as Array).is_empty():
			thief["route"] = route_to(nearest_node(tpos), "van")
		if tpos.distance_to(DROP) < DROP_RANGE:
			for l in loot:
				if l["label"] == thief["carry"]:
					l["delivered"] = true
			events.append({"type": "delivered", "label": thief["carry"]})
			thief["carry"] = ""
			thief["route"] = []
			if remaining(loot) == 0:
				events.append({"type": "allStolen"})
	else:
		var avail: Array = []
		for l in loot:
			if not l["delivered"] and not l["taken"]:
				avail.append(l)
		if avail.is_empty():
			thief["mode"] = "idle"
		else:
			thief["mode"] = "hunt"
			var tgt: Dictionary = {}
			for l in loot:
				if l["label"] == thief["target"]:
					tgt = l
			if tgt.is_empty() or tgt["delivered"] or tgt["taken"]:
				var best: Dictionary = avail[0]
				for l in avail:
					if tpos.distance_to(l["pos"]) < tpos.distance_to(best["pos"]):
						best = l
				thief["target"] = best["label"]
				tgt = best
				thief["route"] = route_to(nearest_node(tpos), best["node"])
				(thief["route"] as Array).append(best["pos"])
			if tpos.distance_to(tgt["pos"]) < GRAB_RANGE:
				tgt["taken"] = true
				thief["carry"] = tgt["label"]
				events.append({"type": "grabbed", "label": tgt["label"]})
				thief["route"] = []
				thief["target"] = ""

	# ---- move
	#
	# The dwell this model always carried and nothing ever read. An intruder stops at the
	# threshold and listens before committing; without it he starts walking on the first
	# frame of the round, which is the difference between a person and a cursor.
	if float(thief["think"]) > 0.0:
		thief["think"] = maxf(0.0, float(thief["think"]) - dt)

	# Carrying costs pace. The hook below has always existed and nothing ever wrote it,
	# so a safe and a laptop were hauled at the same speed.
	thief["speed_scale"] = float(CARRY_SPEED.get(String(thief["carry"]), 1.0))

	var route: Array = thief["route"]
	var speed_scale: float = thief.get("speed_scale", 1.0)
	thief["step"] = 0.0
	# A hit stops him where he stands. He is not being teleported or paused for the camera:
	# a person who has just been shot breaks stride, and that interruption is the whole
	# reason a firefight reads as a firefight rather than two men standing still trading
	# numbers.
	if float(thief["stagger"]) > 0.0:
		thief["stagger"] = maxf(0.0, float(thief["stagger"]) - dt)
	while not route.is_empty() and float(thief["think"]) <= 0.0 \
			and float(thief["stagger"]) <= 0.0:
		var wp: Vector2 = route[0]
		# The homeowner can stand exactly ON a waypoint, and the two bodies then can
		# never get nearer than the sum of their radii — so the intruder would orbit
		# that waypoint forever, 0.24 m short of the arrival radius, and never
		# re-plan. An occupied waypoint counts as reached once he is as close as the
		# collision allows. Nothing is skipped by that: both interaction ranges,
		# GRAB_RANGE (1.4 m) and DROP_RANGE (1.6 m), exceed the gap.
		var occupied := ppos.distance_to(wp) < PLAYER_RADIUS + THIEF_RADIUS
		if tpos.distance_to(wp) < 0.6 or (occupied and tpos.distance_to(wp) < 1.2):
			route.pop_front()
			continue
		var a := (wp - tpos).angle()
		a = steer_around(a, tpos, ppos)
		# Come about at a finite rate instead of snapping, and lose pace while still
		# turning into the new heading — a person does not walk at full speed sideways.
		var diff := wrapf(a - float(thief["yaw"]), -PI, PI)
		thief["yaw"] = wrapf(float(thief["yaw"])
			+ clampf(diff, -THIEF_TURN_RATE * dt, THIEF_TURN_RATE * dt), -PI, PI)
		var align := clampf(1.0 - absf(diff) / PI, 0.55, 1.0)
		thief["step"] = THIEF_SPEED * speed_scale * align * dt
		tpos += Vector2(cos(a), sin(a)) * thief["step"]
		tpos = resolve_circle(tpos, THIEF_RADIUS)
		tpos = clamp_to_world(tpos, THIEF_RADIUS)
		break

	# ---- solid bodies: neither may stand inside the other. Applied here, once
	# both have moved — the homeowner's step is taken by the caller before this.
	var pair := separate_bodies(ppos, tpos)
	ppos = pair[0]
	tpos = pair[1]
	player["pos"] = ppos
	thief["pos"] = tpos

	# ---- stuck detection: re-route rather than stand still forever
	#
	# Measured against what he was actually trying to do this frame, not against
	# THIEF_SPEED. He legitimately covers less ground with a safe in his arms and mid-turn,
	# and while dwelling at the threshold he does not move at all — a fixed threshold read
	# every one of those as being stuck and re-routed him forever. That cost him the whole
	# delivery leg: he cleared all three items and delivered none.
	var moved := tpos.distance_to(thief["prev"])
	var want := float(thief.get("step", 0.0))
	if want > 0.0 and moved < maxf(want * 0.25, 0.0008):
		thief["stuck_t"] += dt
	else:
		thief["stuck_t"] = 0.0
	thief["prev"] = tpos

	if thief["stuck_t"] > 1.2:
		thief["stuck_t"] = 0.0
		var back := "frontHub"
		if thief["carry"] != "":
			back = "van"
		elif thief["target"] != "":
			for l in loot:
				if l["label"] == thief["target"]:
					back = l["node"]
		thief["route"] = route_to(nearest_node(tpos), back)
		events.append({"type": "reroute"})

	# ---- aim, then shoot. Sight is recomputed AFTER moving: the thief can step behind
	# cover during this same step, and firing through a wall would be a bug.
	var can: bool = player["alive"] and \
		thief_sees(tpos, float(thief["yaw"]), ppos)
	if can:
		thief["aim"] = minf(thief["aim"] + dt, THIEF_AIM_TIME)
	else:
		thief["aim"] = 0.0

	# He cannot fire with his hands full — one hand is on the loot, which is the whole
	# point of the trip. This matches the pistol being holstered while he carries.
	# `can` still means line of sight, not permission to shoot.
	var may_fire: bool = can and thief["carry"] == "" and thief["aim"] >= THIEF_AIM_TIME
	if may_fire and thief["reloading"] <= 0.0 and thief["cd"] <= 0.0:
		if thief["mag"] <= 0:
			thief["reloading"] = THIEF_RELOAD
			thief["mag"] = THIEF_MAG
		else:
			thief["mag"] -= 1
			thief["cd"] = THIEF_FIRE_HUNTING
			events.append({"type": "thiefShot", "spread": 0.10, "dmg": THIEF_DAMAGE})
	return can

# -------------------------------------------------------------------- damage
static func damage_thief(thief: Dictionary, dmg: float, events: Array) -> bool:
	if not thief["alive"]:
		return false
	thief["hp"] -= dmg
	# A gunshot wound is a behavioural event, not just a number going down. Nothing used to
	# consult hp except the lethal check, so a man at 1 hp walked, aimed and fired exactly
	# like a man at 100 — no flinch, no stagger, no reaction of any kind.
	thief["stagger"] = maxf(float(thief.get("stagger", 0.0)),
		clampf(dmg * 0.035, 0.35, 1.4))
	# his sight picture is gone: he has to re-settle before he can shoot again
	thief["aim"] = 0.0
	thief["hits"] = int(thief.get("hits", 0)) + 1
	if thief["hp"] <= 0.0:
		thief["hp"] = 0.0
		thief["alive"] = false
		events.append({"type": "thiefDown"})
		return true
	events.append({"type": "thiefHit"})
	return false

static func damage_player(player: Dictionary, dmg: float, events: Array) -> bool:
	if not player["alive"]:
		return false
	player["hp"] -= dmg
	if player["hp"] <= 0.0:
		player["hp"] = 0.0
		player["alive"] = false
		events.append({"type": "playerDown"})
		return true
	events.append({"type": "playerHit"})
	return false
