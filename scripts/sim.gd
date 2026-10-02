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
const THIEF_FIRE_HUNTING := 1.35
const THIEF_FIRE_CARRYING := 1.9
const THIEF_MAG := 8
const THIEF_RELOAD := 1.5
const GRAB_RANGE := 1.4
const DROP_RANGE := 1.6

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
		"stuck_t": 0.0,
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
	var route: Array = thief["route"]
	var speed_scale: float = thief.get("speed_scale", 1.0)
	while not route.is_empty():
		var wp: Vector2 = route[0]
		if tpos.distance_to(wp) < 0.6:
			route.pop_front()
			continue
		var a := (wp - tpos).angle()
		tpos += Vector2(cos(a), sin(a)) * THIEF_SPEED * speed_scale * dt
		tpos = resolve_circle(tpos, THIEF_RADIUS)
		tpos = clamp_to_world(tpos, THIEF_RADIUS)
		thief["yaw"] = a
		break
	thief["pos"] = tpos

	# ---- stuck detection: re-route rather than stand still forever
	var moved := tpos.distance_to(thief["prev"])
	if moved < THIEF_SPEED * dt * 0.25:
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

	# ---- shoot. Sight is recomputed AFTER moving: the thief can step behind
	# cover during this same step, and firing through a wall would be a bug.
	var can: bool = player["alive"] and \
		tpos.distance_to(ppos) < THIEF_SIGHT and not los_blocked(tpos, ppos)
	if can and thief["reloading"] <= 0.0 and thief["cd"] <= 0.0:
		if thief["mag"] <= 0:
			thief["reloading"] = THIEF_RELOAD
			thief["mag"] = THIEF_MAG
		else:
			thief["mag"] -= 1
			thief["cd"] = THIEF_FIRE_CARRYING if thief["carry"] != "" else THIEF_FIRE_HUNTING
			events.append({"type": "thiefShot", "spread": 0.10, "dmg": THIEF_DAMAGE})
	return can

# -------------------------------------------------------------------- damage
static func damage_thief(thief: Dictionary, dmg: float, events: Array) -> bool:
	if not thief["alive"]:
		return false
	thief["hp"] -= dmg
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
