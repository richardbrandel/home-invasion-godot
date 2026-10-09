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
const WALL_HEIGHT := 3.0
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

## Decor: drawn, NOT solid. Wall art, plants, books, appliances on a counter.
##
## Deliberately a SEPARATE list from FURNITURE. `_solids()` feeds the intruder's collision,
## so anything added to FURNITURE can block a route and stall a heist — a picture frame or a
## cactus must never do that. Add to DECOR unless you actually want the player to collide
## with it.
##
## `pos` is the CENTRE of the model in x/z (or the mount point for wall art), `y` is the
## height above the floor, and `ground` false means "respect y, do not drop me to the floor".
static var DECOR: Array[Dictionary] = [
	# ---- living room (west of centre, front)
	{"model": ["furniture", "pictureframe_large_A"], "pos": Vector3(-7.84, 1.55, -10.4), "yaw": 90.0, "ground": false},
	{"model": ["furniture", "pictureframe_medium"], "pos": Vector3(-5.6, 1.62, -8.16), "yaw": 180.0, "ground": false},
	{"model": ["furniture", "cactus_medium_A"], "pos": Vector3(-7.5, 0.0, -8.5), "yaw": 0.0},
	{"model": ["furniture", "cactus_small_B"], "pos": Vector3(-4.5, 0.0, -13.4), "yaw": 35.0},
	{"model": ["furniture", "book_set"], "pos": Vector3(-5.9, 0.44, -11.8), "yaw": 20.0},

	# ---- kitchen (east of centre, front)
	{"model": ["restaurant", "stove_multi"], "pos": Vector3(7.1, 0.0, -9.6), "yaw": -90.0},
	{"model": ["restaurant", "pot_A"], "pos": Vector3(6.9, 0.0, -12.4), "yaw": 0.0},

	# ---- bedroom (west, back)
	{"model": ["furniture", "pictureframe_large_B"], "pos": Vector3(-8.0 + 0.16, 1.6, -16.8), "yaw": 90.0, "ground": false},
	{"model": ["furniture", "lamp_table"], "pos": Vector3(-7.15, 0.55, -16.2), "yaw": 0.0, "ground": false},

	# ---- study (east, back)
	{"model": ["furniture", "pictureframe_small_A"], "pos": Vector3(8.0 - 0.16, 1.7, -16.2), "yaw": -90.0, "ground": false},
	{"model": ["furniture", "book_set"], "pos": Vector3(0.9, 1.35, -18.0), "yaw": -7.0, "ground": false},
	{"model": ["furniture", "cactus_small_A"], "pos": Vector3(7.2, 0.0, -18.4), "yaw": 0.0},

	# ---- a second pass at making the rooms lived in. All floor-standing: an item placed at
	# an assumed height to sit on furniture is how three props ended up floating in mid-air,
	# and a floating prop is worse than an empty corner. Everything here is `ground` true.

	# front hall
	{"model": ["furniture", "rug_oval_A"], "pos": Vector3(0.0, 0.0, -11.6), "yaw": 0.0, "scale": 0.7},
	{"model": ["furniture", "pictureframe_small_B"], "pos": Vector3(-1.80, 1.62, -12.6), "yaw": 90.0, "ground": false},
	{"model": ["furniture", "cactus_small_B"], "pos": Vector3(2.1, 0.0, -13.2), "yaw": 12.0},

	# living room
	{"model": ["furniture", "armchair_pillows"], "pos": Vector3(-4.9, 0.0, -13.3), "yaw": -140.0},
	{"model": ["furniture", "rug_rectangle_stripes_A"], "pos": Vector3(-5.7, 0.02, -11.9), "yaw": 0.0, "ground": false, "scale": 0.8},
	{"model": ["furniture", "book_single"], "pos": Vector3(-5.9, 0.0, -12.0), "yaw": 24.0},
	{"model": ["furniture", "pictureframe_standing_A"], "pos": Vector3(-7.0, 0.0, -14.2), "yaw": 58.0},

	# bedroom
	{"model": ["furniture", "shelf_B_small"], "pos": Vector3(-3.2, 0.0, -18.5), "yaw": -90.0},
	{"model": ["furniture", "rug_oval_B"], "pos": Vector3(-6.0, 0.0, -17.4), "yaw": 0.0, "scale": 0.85},
	{"model": ["furniture", "cactus_small_A"], "pos": Vector3(-3.15, 0.0, -15.6), "yaw": 0.0},

	# study
	{"model": ["furniture", "shelf_B_large_decorated"], "pos": Vector3(2.9, 0.0, -18.3), "yaw": -90.0},
	{"model": ["furniture", "chair_C"], "pos": Vector3(6.6, 0.0, -15.4), "yaw": 150.0},
	{"model": ["furniture", "book_single"], "pos": Vector3(4.6, 0.0, -17.9), "yaw": -40.0},

	# kitchen
	{"model": ["restaurant", "kitchencabinet"], "pos": Vector3(2.6, 0.0, -8.6), "yaw": 0.0},
	{"model": ["restaurant", "crate_carrots"], "pos": Vector3(7.4, 0.0, -8.6), "yaw": 20.0},
	{"model": ["restaurant", "pot_B"], "pos": Vector3(2.2, 0.0, -13.4), "yaw": 0.0},
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
## A person does not reach walking speed on the first frame or stop dead on arrival. That
## instant snap was on BOTH characters and is the classic "sliding prop" tell — the audit
## called it the cheapest large win left in the file, and it was. Deceleration exceeds
## acceleration, as it does in a person.
const PLAYER_ACCEL := 20.0
const PLAYER_DECEL := 30.0
## The intruder comes up to speed more slowly and carries more momentum when he stops.
## Deliberately gentle enough not to disturb the stuck detector: at 4 m/s^2 he passes the
## detector's 25%-of-step bar about 0.08 s after starting, far inside its 1.2 s window.
const THIEF_ACCEL := 4.0
const THIEF_DECEL := 6.0
const PLAYER_RADIUS := 0.42
const EYE_HEIGHT := 1.62
const CROUCH_EYE_HEIGHT := 1.05

const THIEF_SPEED := 1.30          # was 2.6, then 1.75 — still too brisk
const THIEF_RADIUS := 0.42
const THIEF_HEALTH := 100
const THIEF_DAMAGE := 7
## The intruder's health. 100 against 26 a pistol round made him a bullet sponge, which is
## the audit's complaint, and it was measured BEFORE hit locations existed. At 78 he takes
## three torso hits (26 each) or one head shot (x4.0) or a face full of shot, which is about
## what a person takes. The HUD reads him against THIS rather than a literal 100.
const THIEF_MAX_HP := 78.0
## Reserve ammunition. Reloads used to conjure a full magazine from nowhere, so ammunition
## was not a resource and the correct play was never to think about it. These are the total
## rounds you own for the round, magazine included.
const RESERVE := {"pistol": 36, "shotgun": 18}
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
## Fear, and what it takes to make him abandon the job. It is raised by being shot at and
## much more by being hit, and decays slowly while nothing is happening. Once he decides to
## run he does not change his mind — the flee mode is sticky.
const FEAR_FLEE := 4.0
const FEAR_DECAY := 0.18
const FEAR_PER_SHOT := 0.7
const FEAR_PER_HIT := 2.0
## The rooms worth searching. `opening`, `frontHub`, `doorIn` and `doorOut` are corridors,
## not places anything is kept. Note `kitchen` is on the list and holds NOTHING: searching
## has to be able to come up empty, or it is not searching.
const SEARCH_NODES := ["living", "kitchen", "bedroom", "study"]
const SEARCH_TIME := 1.5      # seconds spent looking around a room
const SEARCH_RANGE := 1.2     # how close he has to be to search it
## The clock, and it does NOT start on its own. A home invasion is ended by somebody calling
## the police, and the thing that makes somebody call is a GUNSHOT — so the alarm starts on
## the first shot and not before. A quiet homeowner who never fires never starts the clock.
##
## When it runs out he hears sirens and leaves, whether or not he has finished. That is a
## real tactical consequence for firing: you can cut the robbery short, but you cannot use
## the threat of police to win, because they take him away rather than stopping him. He
## simply gets away with less.
const POLICE_TIME := 110.0
## The homeowner's OTHER defensive verb, and at 1-2 m the only sensible one. A home invasion
## at arm's length stops being a shooting problem and becomes a fight for the gun, and the
## only thing this game let you do at that range was pull the trigger — which is a lethal
## answer to a problem that does not have to be one, and part of why the only two endings
## were his death or yours.
##
## It does NO damage. It staggers him, frightens him, and makes him drop what he is holding,
## which is the only way to get a valuable back without killing anybody.
const SHOVE_RANGE := 1.9
const SHOVE_ARC := 0.6        # radians either side of straight ahead
const SHOVE_STAGGER := 1.2
const SHOVE_FEAR := 2.0
const SHOVE_PUSH := 0.45      # metres he is driven back
const SHOVE_CD := 0.8
## At arm's length the intruder does not shoot you, he puts his hands on you. He had NO
## answer at contact range at all — he would stand and fire, which made a man close enough
## to grab you less dangerous than one across the room, and made walking into him the
## correct play. He still will not do it while carrying: his hands are full.
const THIEF_SHOVE_RANGE := 1.5
const THIEF_SHOVE_CD := 2.6
const THIEF_SHOVE_STAGGER := 0.9
const THIEF_SHOVE_PUSH := 0.55
## How long he is off balance and cannot pick anything up again. WITHOUT THIS THE SHOVE IS
## NEARLY POINTLESS: he is shoved 0.45 m and the grab range is 1.4 m, so he re-took the item
## on the very next frame — measured, not guessed. He has to stoop for it.
const REGRAB_TIME := 2.5


## Tell him he is being shot at. Called by the game when the homeowner fires; `loudness`
## scales with how close and how loud, so a shotgun at 3 m is not the same as a pistol
## across the house.
static func alert_thief(thief: Dictionary, from: Vector2, loudness := 1.0) -> void:
	if not thief["alive"] or bool(thief.get("escaped", false)):
		return
	thief["last_seen"] = from
	thief["fear"] = minf(float(thief.get("fear", 0.0)) + FEAR_PER_SHOT * loudness, 8.0)
	if float(thief.get("alarm", -1.0)) < 0.0:
		thief["alarm"] = 0.0
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

## Keep N bodies out of each other. This replaces `separate_bodies` for the
## multi-intruder case, which is why it takes a LIST of positions rather than a pair.
##
## `radii[0]` is the HOMEOWNER and he is the one displaced, exactly as in
## `separate_bodies` — that choice is load-bearing and is documented there. Everyone
## else yields to scenery only.
##
## Two deliberate deviations from the two-body version:
##
## 1. It is iterative (up to PAIR_SWEEPS) rather than a single pass. Resolving the
##    player against intruder A can push him *into* intruder B, so one pass can leave
##    a pair overlapping — and the sim's own collision contract is that no two bodies
##    ever overlap. Three passes is the cap so a cornered cluster cannot hang.
## 2. The whole group is pushed as a unit if it is shoved out of the world bounds.
##    `clamp_to_world` per body could otherwise let a cluster walk the HOMEOWNER
##    through a wall one intruder at a time, which is a net *gain* in displacement
##    over the two-body case and is not something the old code ever had to survive.
static func separate_all(positions: Array[Vector2], radii: Array[float]) -> Array[Vector2]:
	const PAIR_SWEEPS := 3
	var out := positions.duplicate()
	var n := out.size()
	if n < 2:
		return out

	for _sweep in PAIR_SWEEPS:
		var moved := false
		for i in n:
			for j in range(i + 1, n):
				var pi: Vector2 = out[i]
				var pj: Vector2 = out[j]
				var want := radii[i] + radii[j]
				var d := pj - pi
				var dist := d.length()
				if dist >= want:
					continue
				moved = true
				# coincident bodies have no direction to work with; a fixed axis keeps
				# the result repeatable instead of depending on float noise
				var dir := Vector2(1.0, 0.0) if dist < 1e-5 else d / dist
				var push := want - dist
				if i == 0:
					# body 0 is the homeowner: he takes the push, as he does in the
					# two-body case, and is re-resolved against scenery afterwards
					out[0] = clamp_to_world(
						resolve_circle(out[0] - dir * push, radii[0]), radii[0])
					pj = clamp_to_world(resolve_circle(out[j], radii[j]), radii[j])
					out[j] = pj
				else:
					# two intruders: split it evenly so neither is privileged
					var half := push * 0.5
					out[i] = clamp_to_world(resolve_circle(pi - dir * half, radii[i]), radii[i])
					out[j] = clamp_to_world(resolve_circle(pj + dir * half, radii[j]), radii[j])
		if not moved:
			break
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
		"hp": THIEF_MAX_HP, "alive": true, "weapon": "pistol",
		"crouching": false, "sprinting": false, "vel": Vector2.ZERO,
		"mag": 12, "mags": {"pistol": 12, "shotgun": 6}, "shove_cd": 0.0,
		"stagger": 0.0,
		"reserve": RESERVE.duplicate(), "cd": 0.0, "reloading": 0.0,
	}

## Load the current weapon's magazine out of the reserve. Returns true if anything moved.
##
## In sim.gd rather than game.gd so it can be tested headlessly: the reserve is a gameplay
## rule, and the game layer is not reachable from the test harness.
static func load_magazine(player: Dictionary) -> bool:
	var w := String(player["weapon"])
	var want := int(WEAPONS[w]["mag"])
	var have := int((player["reserve"] as Dictionary).get(w, 0))
	if have <= 0 or int(player["mag"]) >= want:
		return false
	var take := mini(want - int(player["mag"]), have)
	player["mag"] = int(player["mag"]) + take
	(player["reserve"] as Dictionary)[w] = have - take
	(player["mags"] as Dictionary)[w] = int(player["mag"])
	return true


static func can_load_magazine(player: Dictionary) -> bool:
	var w := String(player["weapon"])
	return int((player["reserve"] as Dictionary).get(w, 0)) > 0 \
		and int(player["mag"]) < int(WEAPONS[w]["mag"])


## Drive him back and make him drop what he is carrying. Returns true if it landed.
##
## In sim.gd so it is testable: this is a gameplay rule with a range, an arc and a cooldown,
## and the game layer is not reachable from the harness.
static func shove(player: Dictionary, thief: Dictionary, loot: Array, events: Array) -> bool:
	if not thief["alive"] or bool(thief.get("escaped", false)):
		return false
	if float(player["shove_cd"]) > 0.0:
		return false
	var to: Vector2 = (thief["pos"] as Vector2) - (player["pos"] as Vector2)
	if to.length() > SHOVE_RANGE or to.length() < 0.001:
		return false
	# He has to be roughly in FRONT of you; you cannot shove a man behind your own back.
	# (sin, cos) and not (cos, sin): this is the same forward convention the movement code
	# uses, where yaw 0 faces +Z. Getting it round the wrong way would have made the arc
	# ninety degrees out and the shove would land on people beside you.
	var facing := Vector2(sin(float(player["yaw"])), cos(float(player["yaw"])))
	if facing.dot(to.normalized()) < cos(SHOVE_ARC):
		return false

	player["shove_cd"] = SHOVE_CD
	thief["stagger"] = maxf(float(thief["stagger"]), SHOVE_STAGGER)
	thief["aim"] = 0.0
	thief["fear"] = minf(float(thief["fear"]) + SHOVE_FEAR, 8.0)
	thief["pos"] = resolve_circle((thief["pos"] as Vector2) + to.normalized() * SHOVE_PUSH,
		THIEF_RADIUS)
	thief["route"] = []
	# he has to stoop for whatever he just dropped, or he simply picks it straight back up
	thief["regrab"] = REGRAB_TIME

	var dropped := String(thief["carry"])
	drop_carried(thief, loot, events)
	events.append({"type": "shoved", "dropped": dropped})
	return true


## The intruder shoves the homeowner. Returns true if it landed.
##
## He had no answer at contact range: he would simply stand and fire, so a man close enough
## to grab you was LESS dangerous than one across the room and walking into him was the
## correct play. It knocks you back, spoils your aim, and stops you firing for a moment.
## He will not do it while carrying anything — his hands are full.
## Put whatever he is carrying back into the world at his feet, and make him stoop for it.
static func drop_carried(thief: Dictionary, loot: Array, events: Array) -> void:
	var dropped := String(thief["carry"])
	if dropped == "":
		return
	for l in loot:
		if String(l["label"]) == dropped:
			l["taken"] = false
			l["delivered"] = false
			l["pos"] = thief["pos"]
			l["known"] = true
	thief["carry"] = ""
	thief["regrab"] = REGRAB_TIME
	events.append({"type": "dropped", "label": dropped})


static func thief_shove(thief: Dictionary, player: Dictionary, events: Array) -> bool:
	if not thief["alive"] or bool(thief.get("escaped", false)):
		return false
	if String(thief["carry"]) != "":
		return false
	if float(thief.get("shove_cd", 0.0)) > 0.0:
		return false
	var to: Vector2 = (player["pos"] as Vector2) - (thief["pos"] as Vector2)
	if to.length() > THIEF_SHOVE_RANGE or to.length() < 0.001:
		return false
	thief["shove_cd"] = THIEF_SHOVE_CD
	player["stagger"] = maxf(float(player.get("stagger", 0.0)), THIEF_SHOVE_STAGGER)
	player["pos"] = resolve_circle(
		(player["pos"] as Vector2) + to.normalized() * THIEF_SHOVE_PUSH, PLAYER_RADIUS)
	events.append({"type": "thiefShove"})
	return true


static func create_thief() -> Dictionary:
	return {
		"pos": DROP + Vector2(0, 0.5), "prev": DROP + Vector2(0, 0.5), "yaw": PI,
		"hp": float(THIEF_HEALTH), "alive": true,
		"mag": THIEF_MAG, "cd": 1.2, "reloading": 0.0, "think": 2.0,
		"carry": "", "target": "", "route": [], "mode": "hunt",
		"stuck_t": 0.0, "aim": 0.0, "stagger": 0.0, "hits": 0,
		"fear": 0.0, "escaped": false, "last_seen": Vector2.ZERO, "speed": 0.0,
		"searched": [], "alarm": -1.0, "sirens": false, "regrab": 0.0, "shove_cd": 0.0,
		# `id` is the body's identity for event attribution; `step` is the distance he is
		# trying to cover this frame, which the stuck detector compares against.
		"id": 0, "step": 0.0,
	}

## Build `n` intruders, staggered across the driveway so they do not all start inside
## one another. `create_thief()` spawns a single one at the exact DROP point, which was
## fine when there could only ever be one; two bodies at the same coordinate are the
## one case `separate_all` has no direction to resolve, so the spawn has to spread them.
##
## The `id` is what lets `game.gd` tell the bodies apart — it is carried on every event
## the intruder emits, because a sound, a tracer or a death with no source is not
## playable with three of them in the house.
static func create_intruders(n: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var count := maxi(n, 1)
	for i in count:
		var t := create_thief()
		t["id"] = i
		# fan out along the driveway: -1, 0, +1, then wrap for a fourth
		var lane := float(i) - float(count - 1) * 0.5
		var off := Vector2(roundf(lane) * (THIEF_RADIUS * 2.2), -absf(lane) * 0.9)
		t["pos"] = clamp_to_world(DROP + off + Vector2(0, 0.5), THIEF_RADIUS)
		t["prev"] = t["pos"]
		out.append(t)
	return out

## Step every intruder for one frame, then resolve all the bodies against each other.
##
## The per-body separation inside `step_thief` is deliberately skipped here: it only
## knows about the homeowner and one intruder, so running it three times would let each
## thief shove the player in turn. The pairwise pass at the end is the general version.
##
## Returns the indices of the intruders that currently have line of sight to the player.
static func step_intruders(intruders: Array[Dictionary], player: Dictionary,
		loot: Array, events: Array, dt: float) -> Array[int]:
	var seen: Array[int] = []
	var before: Array[Vector2] = [player["pos"] as Vector2]
	for t in intruders:
		before.append(t["pos"] as Vector2)

	# Stamp the source on everything each body emits. With one intruder the game could
	# assume who fired; with three, an unstamped tracer or gunshot is unattributable, and
	# a shot you cannot locate is not a playable game. Tagged at the producer because that
	# is the only place the identity is known — inferring it afterwards from the payload
	# does not work, since a `grabbed` carries a loot label and not a body.
	for idx in intruders.size():
		var t: Dictionary = intruders[idx]
		var mark := events.size()
		if step_thief(t, player, loot, events, dt, false):
			seen.append(idx)
		for i in range(mark, events.size()):
			var ev: Dictionary = events[i]
			var kind := str(ev.get("type", ""))
			# `sirens` and `allStolen` are deliberately global: the police are not a thief,
			# and "everything is gone" is not attributable to one of them either.
			if not ev.has("id") and kind != "sirens" and kind != "allStolen":
				ev["id"] = int(t.get("id", idx))

	var radii: Array[float] = [PLAYER_RADIUS]
	for _t in intruders:
		radii.append(THIEF_RADIUS)

	# THE SEPARATION RUNS ON THE POST-STEP POSITIONS. `before` is the frame-START positions
	# and is still what `prev` is taken from; sending `before` to `separate_all` and writing
	# the result back handed every body its own start position, which is the second half of
	# the same bug as the one in `step_thief` above.
	var stepped: Array[Vector2] = [player["pos"] as Vector2]
	for t in intruders:
		stepped.append(t["pos"] as Vector2)

	var after := separate_all(stepped, radii)
	player["pos"] = after[0]
	for idx in intruders.size():
		var t: Dictionary = intruders[idx]
		var final: Vector2 = after[idx + 1]
		# `prev` was set by `step_thief` to where he stood at the start of the frame, and
		# `before[idx + 1]` is that same position. So the body-push is exactly
		# `final - before[idx + 1]`, and `prev` is re-anchored on the resolved position.
		# Measuring travel across the push instead would read a shove as progress and let
		# the offset accumulate into the next frame, blinding the stuck detector.
		t["pos"] = final
		t["prev"] = before[idx + 1]
	return seen

static func create_loot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in LOOT_SPOTS:
		out.append({"pos": s["pos"], "label": s["label"], "node": s["node"],
			"taken": false, "delivered": false, "known": false})
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
## `separate` is false only when called from `step_intruders`, which does the
## pairwise pass itself — see the note there for why running this one three times
## would be wrong. Default true keeps every existing caller and test unchanged.
static func step_thief(thief: Dictionary, player: Dictionary, loot: Array, events: Array,
		dt: float, separate := true) -> bool:
	if not thief["alive"]:
		return false

	# `prev` is where he was at the START of this frame, and it must be captured before
	# anything moves him. The stuck detector below measures `moved` against it, and
	# `step_intruders` rewrites it after the group has been pushed apart — so if it were
	# written late here, the two would disagree and the difference would accumulate into
	# the travel figure frame after frame.
	thief["prev"] = thief["pos"]

	thief["cd"] -= dt
	if thief["reloading"] > 0.0:
		thief["reloading"] -= dt
	thief["regrab"] = maxf(0.0, float(thief["regrab"]) - dt)
	thief["shove_cd"] = maxf(0.0, float(thief["shove_cd"]) - dt)
	if thief["escaped"]:
		return false

	var tpos: Vector2 = thief["pos"]
	var ppos: Vector2 = player["pos"]

	# fear settles when nothing is happening. It does not un-decide a decision already
	# taken, which is why `mode == "flee"` below is sticky.
	thief["fear"] = maxf(0.0, float(thief["fear"]) - FEAR_DECAY * dt)

	# the clock runs only once somebody has been called
	if float(thief["alarm"]) >= 0.0:
		thief["alarm"] = float(thief["alarm"]) + dt
		if float(thief["alarm"]) >= POLICE_TIME:
			if not bool(thief["sirens"]):
				thief["sirens"] = true
				events.append({"type": "sirens"})
			# he drops everything and runs, exactly as if he had been shot at
			thief["fear"] = maxf(float(thief["fear"]), FEAR_FLEE)

	# At arm's length he grabs rather than shoots. Checked before the fear branch, because
	# a man already close enough to touch you does not first decide whether to run.
	thief_shove(thief, player, events)

	# ---- decide
	#
	# Fear first. A real intruder leaves at the first sign of an armed occupant — certainly
	# once someone starts shooting at him — and this model had none at all: he worked calmly
	# through to the third item while being fired at, which the audit called the highest
	# realism ceiling left anywhere in it.
	if thief["mode"] == "flee" or float(thief["fear"]) >= FEAR_FLEE:
		thief["mode"] = "flee"
		if (thief["route"] as Array).is_empty():
			thief["route"] = route_to(nearest_node(tpos), "van")
		# He is gone once he has finished the route to the van AND is clear of the house.
		# The threshold is the route emptying rather than a distance, because the "van" node
		# sits well short of the van model — at z 4.4 against the van's 7.0 — so a distance
		# test against the van never fires and he stands in the drive forever.
		if (thief["route"] as Array).is_empty() and tpos.y > HOUSE.end.y + 1.0:
			thief["escaped"] = true
			events.append({"type": "escaped", "carried": thief["carry"]})
	elif thief["carry"] != "":
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
		# What does he actually KNOW about? He used to know all three valuables and their
		# exact coordinates from the moment he spawned, which is not a burglary, it is a
		# shopping list. Now an item is unknown until he has stood in the room it is in.
		var known: Array = []
		for l in loot:
			if not l["delivered"] and not l["taken"] and bool(l.get("known", false)):
				known.append(l)
		if not known.is_empty():
			thief["mode"] = "hunt"
			var tgt: Dictionary = {}
			for l in loot:
				if l["label"] == thief["target"]:
					tgt = l
			if tgt.is_empty() or not bool(tgt.get("known", false)) \
					or tgt["delivered"] or tgt["taken"]:
				var best: Dictionary = known[0]
				for l in known:
					if tpos.distance_to(l["pos"]) < tpos.distance_to(best["pos"]):
						best = l
				thief["target"] = best["label"]
				tgt = best
				thief["route"] = route_to(nearest_node(tpos), best["node"])
				(thief["route"] as Array).append(best["pos"])
			if tpos.distance_to(tgt["pos"]) < GRAB_RANGE \
					and float(thief["regrab"]) <= 0.0:
				tgt["taken"] = true
				thief["carry"] = tgt["label"]
				events.append({"type": "grabbed", "label": tgt["label"]})
				thief["route"] = []
				thief["target"] = ""
		else:
			# nothing known: go and look in a room. Nearest unsearched first, which is
			# what a person does — he does not cross the house to a far room while an
			# unexplored one is behind him.
			var rooms: Array = []
			for n in SEARCH_NODES:
				if not (thief["searched"] as Array).has(n):
					rooms.append(n)
			if rooms.is_empty():
				thief["mode"] = "idle"
			else:
				thief["mode"] = "search"
				var room: String = String(rooms[0])
				for n in rooms:
					if tpos.distance_to(NODES[n]["pos"]) \
							< tpos.distance_to(NODES[room]["pos"]):
						room = String(n)
				if thief["target"] != room:
					thief["target"] = room
					thief["route"] = route_to(nearest_node(tpos), room)
				if tpos.distance_to(NODES[room]["pos"]) < SEARCH_RANGE:
					# dwell here while he looks, then anything in this room is known
					thief["think"] = SEARCH_TIME
					(thief["searched"] as Array).append(room)
					thief["route"] = []
					thief["target"] = ""
					for l in loot:
						if String(l["node"]) == room and not l["delivered"]:
							l["known"] = true

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
	var walked := false
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
		var wish := THIEF_SPEED * speed_scale * align
		var cur := float(thief["speed"])
		thief["speed"] = move_toward(cur, wish,
			(THIEF_ACCEL if wish > cur else THIEF_DECEL) * dt)
		# `step` is the distance he ACTUALLY covered, which is what the stuck detector
		# below needs; the intent is `wish`. They were the same thing before he could
		# accelerate.
		thief["step"] = float(thief["speed"]) * dt
		tpos += Vector2(cos(a), sin(a)) * thief["step"]
		tpos = resolve_circle(tpos, THIEF_RADIUS)
		tpos = clamp_to_world(tpos, THIEF_RADIUS)
		walked = true
		break

	# bleed off momentum only on frames he is NOT walking, so a stop is a stop
	if not walked:
		thief["speed"] = move_toward(float(thief["speed"]), 0.0, THIEF_DECEL * dt)

	# ---- solid bodies: neither may stand inside the other. Applied here, once
	# both have moved — the homeowner's step is taken by the caller before this.
	# Skipped when the caller resolves the whole group at once (`step_intruders`).
	# THE STEP'S RESULT IS ALWAYS WRITTEN BACK. This used to sit inside `if separate:`
	# below, which meant `step_thief(t, ..., false)` -- the call `step_intruders` makes --
	# computed a new `tpos` every frame and threw it away. `separate` gates the PAIRWISE
	# SEPARATION, not the movement.
	#
	# Measured 2026-10-09 with test/probe_intruders.gd: through `step_intruders`, an
	# intruder travelled **0.000 m in 180 simulated seconds** and finished at exactly his
	# spawn point, (0.0, 5.0). Through `step_thief` alone he completes the heist. Since
	# `game.gd` only ever calls `step_intruders`, NO INTRUDER HAS MOVED since the
	# three-intruder work landed -- and nothing caught it, because every heist assertion in
	# test_sim.gd drives `step_thief` for a single thief.
	thief["pos"] = tpos

	if separate:
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
	# Only the self-separating path writes this. When `step_intruders` owns the body
	# resolution it writes `prev` itself, AFTER the group has been pushed apart — a push
	# from another body is not travel, and recording it as `prev` would make the next
	# frame's `moved` read as a huge step and blind the stuck detector.
	# `prev` is NOT written here. It belongs to whoever owns body resolution: this
	# function when `separate` is true, and `step_intruders` otherwise — which rewrites
	# it after the group has been pushed apart. Writing it here as well would make the
	# two disagree, and the difference accumulates into the travel figure every frame.

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

	# He cannot fire with his hands full — one hand is on the loot, which is the whole point
	# of the trip. The audit calls this the opposite of realistic and it is, but making him
	# drop the loot whenever the homeowner is close and in view was MEASURED and reverted: an
	# idle homeowner sits on his route, so the drop fires constantly and he delivers nothing.
	# Firing one-handed would need the pistol and a two-handed item in the same hand. It stays
	# a deliberate exception, and it is what makes the loot his vulnerability. `can` still
	# means line of sight, not permission to shoot.
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
	# being hit frightens him far more than being missed
	thief["fear"] = minf(float(thief.get("fear", 0.0)) + FEAR_PER_HIT, 8.0)
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
