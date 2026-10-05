extends RefCounted
class_name House

## Builds the playable world out of KayKit CC0 models.
##
## KayKit is authored at 2x scale, so every model is placed at SCALE = 0.5 to
## land in real metres — which is what Sim's collision rects are in. A character
## measuring 3.31 m as shipped becomes 1.66 m, and a 4x4 m wall panel becomes the
## 2x2 m module the layout assumes.
##
## Models are auto-grounded: the mesh AABB is measured after parenting and the
## node is dropped so its lowest point sits on y = 0. Hand-tuned y offsets rot
## the moment an asset is swapped.

const SCALE := 0.5
## The city vehicles are authored at roughly 1x, not the 2x of the other KayKit sets,
## so they need their own multiplier on top of SCALE or they come out toy-sized.
const VAN_SCALE := 2.5
## The city set is authored at roughly 1x, like the vehicles, so anything else taken from
## it needs the same multiplier rather than the 0.5 used for the restaurant and characters.
const CITY_SCALE := 2.5
## How far to sink the city road tiles so their running surface sits on the lawn rather
## than on top of their own raised base.
const ROAD_SINK := 0.22
## The restaurant door leaf needs its own scale: at House.SCALE it comes out taller than the
## 2 m wall it hangs in.
## The door model MEASURED, not guessed. `door_A` is 1.60 x 2.80 x 0.77 m at source, so the
## old uniform DOOR_SCALE of 0.34 built a leaf 55 cm wide and 95 cm tall — a doll's-house door
## hanging in the opening, which is exactly what Richard described.
const DOOR_SRC := Vector3(1.60, 2.80, 0.77)
## What a front door actually measures. Non-uniform on purpose: the model's own proportions
## are 1:1.75 and a real door is nearer 1:2.2.
const DOOR_WANT := Vector3(0.96, 2.04, 0.20)
## The head of the opening. The gap between the two south wall runs is FULL HEIGHT, so at a
## 3 m ceiling the doorway was a 3 m hole with a 2 m door in it. A real opening is about this
## with wall above.
const DOOR_TOP := 2.10
const A := "res://assets/kaykit/"

# KayKit's modular wall panel is 4.00 x 4.00 x 0.50 m at source scale.
const WALL_SRC_W := 4.0
const WALL_SRC_H := 4.0
const WALL_SRC_D := 0.5

const WALL_TARGET_H := 3.0     # must match Sim.WALL_HEIGHT
## Was 2.0. At 2.0 m the ceiling is only 35 cm above a 1.62 m eye, so at a 68-degree
## field of view the ceiling filled 54-66% of the upper frame in EVERY room — measured
## across three views. 3.0 m is a real ceiling height and is Richard's call.
##
## Note the wall module is scaled NON-UNIFORMLY (sx fits the bay, sy is this height,
## sz is the thickness), so raising this stretches each panel vertically by 1.5x and the
## windows with it.
const WALL_TARGET_D := 0.25    # must match Sim.WALL_THICKNESS
## Where the ceiling lights hang, one per room, matching the practical lights in
## game.gd's _setup_environment so the fitting sits where the light is coming from.
const CEILING_FITTINGS := [
	Vector2(-5.4, -11.0), Vector2(5.4, -11.0), Vector2(0, -11.6),
	Vector2(-5.5, -17.0), Vector2(5.4, -17.0),
]


static func _exists(path: String) -> bool:
	return ResourceLoader.exists(path)


static func place(parent: Node3D, folder: String, model: String,
		at: Vector3, rot_y := 0.0, ground := true,
		scale := Vector3(SCALE, SCALE, SCALE)) -> Node3D:
	var path := A + folder + "/" + model + ".gltf"
	if not _exists(path):
		push_warning("House: missing model " + path)
		return null
	var packed: PackedScene = load(path)
	if packed == null:
		push_warning("House: could not load " + path)
		return null
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null
	inst.scale = scale
	inst.position = at
	inst.rotation.y = rot_y
	parent.add_child(inst)
	if ground:
		ground_node(inst)
	return inst


## Measure the world-space mesh bounds. Accepts an optional extra offset.
static func world_aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in node.find_children("*", "MeshInstance3D", true, false):
		var m := c as MeshInstance3D
		if m.mesh == null:
			continue
		var box := m.get_aabb()
		for i in 8:
			var p: Vector3 = m.global_transform * box.get_endpoint(i)
			if first:
				out = AABB(p, Vector3.ZERO)
				first = false
			else:
				out = out.expand(p)
	return out


## Drop a model so its lowest point rests on y = 0.
static func ground_node(inst: Node3D) -> void:
	inst.force_update_transform()
	var box := world_aabb(inst)
	if box.size == Vector3.ZERO:
		return
	inst.position.y -= box.position.y


# --------------------------------------------------------------- floors
static func build_floors(parent: Node3D) -> void:
	var house := Sim.HOUSE
	# Interior floor: one warm wood surface. KayKit ships only a black-and-white
	# checkerboard kitchen tile, which reads as a chessboard across a whole house
	# — so it is used only where a kitchen actually is, below.
	var f := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(house.size.x, 0.1, house.size.y)
	f.mesh = fbox
	# top face at +0.02 rather than 0.0: the exterior lawn is a plane at y = 0 over the
	# same footprint, and once the scene went daylight the two z-fought into a jagged
	# green/brown mess across every interior floor
	f.position = Vector3(house.position.x + house.size.x * 0.5, -0.03,
		house.position.y + house.size.y * 0.5)
	f.material_override = _textured("res://assets/textures/floor_wood.png", 5.0, 4.0)
	parent.add_child(f)

	# foundation slab under everything
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(house.size.x + 1.0, 0.3, house.size.y + 1.0)
	slab.mesh = box
	slab.position = Vector3(house.position.x + house.size.x * 0.5, -0.28,
		house.position.y + house.size.y * 0.5)
	slab.material_override = _flat(Color(0.30, 0.24, 0.18))
	parent.add_child(slab)

	# Kitchen tiles: front-east only (x 2..8, z -14..-8). The range must start at
	# the kitchen's own wall — deriving it from HOUSE.position.x tiled the entire
	# house in checkerboard, which is what the first render showed.
	var tile := 2.0
	var kx0 := 2.0
	var kx1 := house.end.x
	var kz0 := Sim.INTERIOR_Z
	var kz1 := house.end.y
	var nx := int(ceil((kx1 - kx0) / tile))
	var nz := int(ceil((kz1 - kz0) / tile))
	for ix in nx:
		for iz in nz:
			var x := kx0 + (float(ix) + 0.5) * tile
			var z := kz0 + (float(iz) + 0.5) * tile
			var kf := place(parent, "restaurant", "floor_kitchen", Vector3(x, 0.015, z), 0.0, false)
			# NOT KayKit's own checkerboard tile. See tools/gen-textures.py kitchen_tile().
			if kf != null:
				var km := _textured("res://assets/textures/floor_tile.png", 3.0, 3.0, 0.85)
				for c in kf.find_children("*", "MeshInstance3D", true, false):
					(c as MeshInstance3D).material_override = km


# ---------------------------------------------------------------- walls
## Tile a wall run with modular panels, replacing specific bays with window or
## doorway variants. `run` is the collision rect; panels exactly fill it.
##
## NOTE: KayKit's restaurant wall panels carry a saturated teal wainscot baked
## into the ALBEDO TEXTURE, not into albedo_color. An earlier version of this
## file tried to re-tint materials by colour matching; it compiled, ran, and did
## nothing, because every wall material's albedo_color is white. Removing the
## band means editing the texture or using a different interior pack — an art
## decision, not a code one.

## KayKit's restaurant atlas paints the wall panels half teal. Every wall model is
## a single surface sharing that atlas, with no transparency — so overriding the
## material outright would also erase the painted window frames. Instead the atlas
## was recoloured offline into wall_texture_clean.png (teal pixels only), and the
## walls point at that copy. Everything else still samples the original.
static var _wall_mat: StandardMaterial3D


## Ceilings.
##
## This used to be one flat slab with no lighting response, and it rendered almost black.
## Two causes, both fixed: the environment takes its ambient from the sky, and a
## DOWNWARD-facing surface samples the sky's dark ground hemisphere — so the ceiling's
## underside received almost nothing while the floor facing it received the bright half
## (see `_setup_environment`); and there was nothing up there to look at.
##
## Now there is a cornice where the ceiling meets the walls and a light fitting in every
## room, so it reads as a ceiling rather than a lid.
static func build_ceiling(parent: Node3D) -> void:
	var house := Sim.HOUSE
	var plaster := _textured("res://assets/textures/ceiling_plaster.png", 7.0, 5.0, 1.0)
	# a little self-illumination, standing in for the bounce a real room has
	plaster.emission_enabled = true
	plaster.emission = Color(0.86, 0.84, 0.80) * 0.26

	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(house.size.x, 0.22, house.size.y)
	slab.mesh = box
	slab.position = Vector3(house.position.x + house.size.x * 0.5,
		WALL_TARGET_H + 0.11,
		house.position.y + house.size.y * 0.5)
	slab.material_override = plaster
	slab.name = "Ceiling"
	parent.add_child(slab)

	var trim := _flat(Color(0.93, 0.91, 0.87))
	var cw := 0.09
	var inner := Rect2(house.position.x + Sim.WALL_THICKNESS,
		house.position.y + Sim.WALL_THICKNESS,
		house.size.x - Sim.WALL_THICKNESS * 2.0,
		house.size.y - Sim.WALL_THICKNESS * 2.0)
	for run in [
		Rect2(inner.position.x, inner.position.y, inner.size.x, cw),
		Rect2(inner.position.x, inner.end.y - cw, inner.size.x, cw),
		Rect2(inner.position.x, inner.position.y, cw, inner.size.y),
		Rect2(inner.end.x - cw, inner.position.y, cw, inner.size.y),
	]:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(run.size.x, 0.09, run.size.y)
		m.mesh = b
		m.position = Vector3(run.position.x + run.size.x * 0.5, WALL_TARGET_H - 0.045,
			run.position.y + run.size.y * 0.5)
		m.material_override = trim
		parent.add_child(m)

	for spot in CEILING_FITTINGS:
		var rose := MeshInstance3D.new()
		var rb := CylinderMesh.new()
		rb.top_radius = 0.09
		rb.bottom_radius = 0.09
		rb.height = 0.04
		rose.mesh = rb
		rose.position = Vector3(spot.x, WALL_TARGET_H - 0.02, spot.y)
		rose.material_override = trim
		parent.add_child(rose)

		var shade := MeshInstance3D.new()
		var sb := CylinderMesh.new()
		sb.top_radius = 0.05
		sb.bottom_radius = 0.17
		sb.height = 0.13
		sb.radial_segments = 16
		shade.mesh = sb
		shade.position = Vector3(spot.x, WALL_TARGET_H - 0.11, spot.y)
		shade.material_override = _flat(Color(0.96, 0.94, 0.88))
		parent.add_child(shade)

	# --- roof. Without one the house read as a slab from the drive: a flat lid with no
	#     pitch, no eaves and nothing above the walls, which is a shipping container.
	#     Two slopes, a ridge cap and an overhang is enough to stop that.
	var shingle := "res://assets/textures/roof_shingle.png"
	var roof := _textured(shingle, 7.0, 2.0, 0.9)
	var over := 0.45
	var rise := 1.6
	var eave_y := WALL_TARGET_H + 0.22
	var half := house.size.y * 0.5 + over
	var slope := sqrt(half * half + rise * rise)
	var tilt := atan2(rise, half)
	var mid_x := house.position.x + house.size.x * 0.5
	var mid_z := house.position.y + house.size.y * 0.5
	for s in [-1.0, 1.0]:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(house.size.x + over * 2.0, 0.12, slope)
		m.mesh = b
		m.position = Vector3(mid_x, eave_y + rise * 0.5, mid_z + s * half * 0.5)
		# rotating about X tips the +Z end down, so the sign follows the side
		m.rotation.x = tilt * s
		m.material_override = roof
		parent.add_child(m)

	# FASCIA AND GUTTER along each eave edge.
	#
	# The overhang was never the problem — 0.45 m is an ordinary eave. What was missing is
	# the fascia, the trim board along the edge, and without it the roof is just the dark
	# underside of a box: a heavy lid rather than a roof. A pale board catches the light and
	# gives the eave a line, and the gutter under it finishes the read.
	var fascia := _flat(Color(0.90, 0.89, 0.86))
	var gutter := _flat(Color(0.52, 0.53, 0.55))
	for s2 in [-1.0, 1.0]:
		var f := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(house.size.x + over * 2.0 + 0.06, 0.15, 0.05)
		f.mesh = fb
		f.position = Vector3(mid_x, eave_y - 0.055, mid_z + s2 * half)
		f.material_override = fascia
		parent.add_child(f)

		var g := MeshInstance3D.new()
		var gb := BoxMesh.new()
		gb.size = Vector3(house.size.x + over * 2.0 + 0.06, 0.075, 0.10)
		g.mesh = gb
		g.position = Vector3(mid_x, eave_y - 0.165, mid_z + s2 * (half + 0.035))
		g.material_override = gutter
		parent.add_child(g)

	var cap := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(house.size.x + over * 2.0 + 0.1, 0.16, 0.34)
	cap.mesh = cb
	cap.position = Vector3(mid_x, eave_y + rise + 0.02, mid_z)
	cap.material_override = _textured(shingle, 7.0, 0.4, 0.9)
	parent.add_child(cap)

	# gable ends: the triangular infill between the wall head and the slopes, which would
	# otherwise be an open gap seen from the east or west. Stepped rather than a true
	# triangle — at this scale the steps are smaller than the roof shingles.
	var gable := _textured("res://assets/textures/ceiling_plaster.png", 2.0, 1.0, 1.0)
	for s in [-1.0, 1.0]:
		var steps := 8
		for i in steps:
			var t := float(i) / float(steps)
			var h := rise * t
			if h < 0.03:
				continue
			var g := MeshInstance3D.new()
			var gb := BoxMesh.new()
			gb.size = Vector3(0.24, h, half * 2.0 * (1.0 - t) * 0.98)
			g.mesh = gb
			g.position = Vector3(mid_x + s * (house.size.x * 0.5 + 0.02),
				eave_y + h * 0.5, mid_z)
			g.material_override = gable
			parent.add_child(g)


## The front door's own material.
##
## The restaurant atlas paints the door leaf the same teal as the window frames, which is
## exactly why Richard described it as "a green thing hanging in the middle of the doorway".
## The leaf needs its own colour, not the trim's.
static var _door_mat: StandardMaterial3D


static func use_door_texture(inst: Node3D) -> void:
	if inst == null:
		return
	if _door_mat == null:
		_door_mat = StandardMaterial3D.new()
		# a painted front door rather than bare wood: it reads as a door at a glance
		_door_mat.albedo_color = Color(0.86, 0.84, 0.80)
		_door_mat.roughness = 0.62
		_door_mat.metallic = 0.0
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).material_override = _door_mat


static func wall_material() -> StandardMaterial3D:
	if _wall_mat == null:
		_wall_mat = StandardMaterial3D.new()
		var tex := load("res://assets/kaykit/restaurant/wall_texture_clean.png")
		if tex != null:
			_wall_mat.albedo_texture = tex
		_wall_mat.roughness = 0.93
		_wall_mat.metallic = 0.0
	return _wall_mat


static func use_clean_wall_texture(inst: Node3D) -> void:
	if inst == null:
		return
	var m := wall_material()
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).material_override = m
	# find_children walks DESCENDANTS only, so a bare MeshInstance3D would be missed
	if inst is MeshInstance3D:
		(inst as MeshInstance3D).material_override = m

static func build_wall_run(parent: Node3D, run: Rect2, open_bays := {}) -> void:
	var horizontal := run.size.x >= run.size.y
	var length: float = run.size.x if horizontal else run.size.y
	var bays := maxi(1, int(round(length / (WALL_SRC_W * SCALE))))
	var step := length / float(bays)
	var sx := step / WALL_SRC_W
	var sy := WALL_TARGET_H / WALL_SRC_H
	var sz := WALL_TARGET_D / WALL_SRC_D
	var thickness: float = run.size.y if horizontal else run.size.x

	for i in bays:
		# There is no doorway model in play here. The front door is a GAP between two
		# separate wall runs (Sim.DOOR_GAP), not a bay inside one, so a `wall_doorway`
		# branch here could never be reached — it was dead code until 2026-10-04. An
		# actual door is ROADMAP item 17.
		# Alternate the glazing. A hole in every window is a large part of why the exterior
		# read as a film set; `wall_window_closed` has been on disk unreferenced. Odd bays
		# stay open so you can still see through some of them.
		var model := "wall"
		if open_bays.has(i):
			model = "wall_window_open" if (i % 2) == 1 else "wall_window_closed"

		var t := (float(i) + 0.5) * step
		var x: float
		var z: float
		var rot: float
		if horizontal:
			x = run.position.x + t
			z = run.position.y + run.size.y * 0.5
			rot = 0.0
		else:
			x = run.position.x + run.size.x * 0.5
			z = run.position.y + t
			rot = PI * 0.5
		# No orientation swap here, and that is deliberate: Godot applies `scale` in the
		# node's LOCAL space. A wall panel is wide in local X and thin in local Z whatever
		# its rotation, so sx always scales the run length and sz always the thickness. A
		# branch that swapped them on a Z run would build the side walls 2 m thick.
		var sc := Vector3(sx, sy, sz)
		use_clean_wall_texture(place(parent, "restaurant", model, Vector3(x, 0, z), rot, false, sc))

		if open_bays.has(i) and model == "wall_window_closed":
			_window_trim(parent, Vector3(x, 0, z), horizontal, step, thickness)


## A window sill and head, plus curtains behind the glass.
##
## Placed here because this is the only function that knows where the bays are. The sill and
## head span the FULL wall thickness plus 6 cm, so one box protrudes on both faces at once and
## this does not have to know which side of the wall is inside — the same trick the skirting
## uses. The curtains DO need to know, and get it by pointing at the middle of the house.
##
## Heights are measured off a render rather than read from the model: the window sits in the
## upper half of the panel, roughly 1.0-2.0 m up.
const WINDOW_SILL_Y := 1.02
const WINDOW_HEAD_Y := 2.06


static func _window_trim(parent: Node3D, at: Vector3, horizontal: bool, bay: float,
		thickness: float) -> void:
	var trim := _flat(Color(0.94, 0.93, 0.91))
	# Lighter and narrower than the first cut, which read as a drawn curtain. A panel about a
	# fifth of the bay, pushed to the edge, is fabric gathered at the side of the window
	# rather than a curtain pulled across it — and it leaves the middle of the glass doing its
	# job, which is the thing that stops the facade looking like a film set.
	var cloth := _flat(Color(0.56, 0.52, 0.53))
	var w := bay * 0.92
	var deep := thickness + 0.06

	for spec in [[WINDOW_SILL_Y, 0.07], [WINDOW_HEAD_Y, 0.06]]:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(w, float(spec[1]), deep) if horizontal \
			else Vector3(deep, float(spec[1]), w)
		m.mesh = b
		m.position = Vector3(at.x, float(spec[0]), at.z)
		m.material_override = trim
		parent.add_child(m)

	# curtains hang just inside the inner face
	var house := Sim.HOUSE
	var centre := Vector3(house.position.x + house.size.x * 0.5, 0.0,
		house.position.y + house.size.y * 0.5)
	var inward := (centre - Vector3(at.x, 0.0, at.z))
	inward.y = 0.0
	if inward.length_squared() < 0.0001:
		return
	inward = inward.normalized() * (thickness * 0.5 + 0.05)

	var drop := WINDOW_HEAD_Y - WINDOW_SILL_Y
	for side in [-1.0, 1.0]:
		var c := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(bay * 0.22, drop, 0.032) if horizontal \
			else Vector3(0.032, drop, bay * 0.22)
		c.mesh = cb
		var off: float = float(side) * bay * 0.37
		var p := Vector3(at.x + (off if horizontal else 0.0), WINDOW_SILL_Y + drop * 0.5,
			at.z + (0.0 if horizontal else off)) + inward
		c.position = p
		c.material_override = cloth
		parent.add_child(c)


static func build_walls(parent: Node3D) -> void:
	# front door is the gap in the south wall, between the two south runs
	for w in Sim.WALLS:
		var horiz := w.size.x >= w.size.y
		var run_len: float = w.size.x if horiz else w.size.y
		var bays := maxi(1, int(round(run_len / (WALL_SRC_W * SCALE))))
		var opens := {}
		if run_len > 5.0:
			# a couple of windows on the long exterior runs
			opens[0] = true
			if bays > 2:
				opens[bays - 1] = true
		build_wall_run(parent, w, opens)


# ------------------------------------------------------------ furniture
## Maps the simulation's logical furniture kind onto a concrete KayKit model.
const FURNITURE_MODEL := {
	"sofa":         ["furniture", "couch"],
	"side_table":   ["furniture", "table_small"],
	"coffee_table": ["furniture", "table_low"],
	"tv_stand":     ["furniture", "cabinet_medium"],
	"rug":          ["furniture", "rug_rectangle_A"],
	"lamp":         ["furniture", "lamp_standing"],
	"counter":      ["restaurant", "kitchencounter_straight_A"],
	"fridge":       ["restaurant", "fridge_A"],
	"dining_table": ["furniture", "table_medium"],
	"chair":        ["furniture", "chair_A_wood"],
	"bed":          ["furniture", "bed_double_A"],
	"nightstand":   ["furniture", "cabinet_small"],
	"wardrobe":     ["furniture", "cabinet_medium"],
	"desk":         ["furniture", "table_medium_long"],
	"desk_chair":   ["furniture", "chair_B_wood"],
	"bookshelf":    ["furniture", "shelf_A_big"],
	"cabinet":      ["furniture", "cabinet_medium_decorated"],
}


static var _rug_mat: StandardMaterial3D


static func use_rug_texture(inst: Node3D) -> void:
	if inst == null:
		return
	if _rug_mat == null:
		_rug_mat = StandardMaterial3D.new()
		_rug_mat.albedo_color = Color(0.36, 0.30, 0.31)
		_rug_mat.roughness = 1.0
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).material_override = _rug_mat


## A skirting board around every wall run.
##
## A box the footprint of the wall plus 3 cm in each direction, so it protrudes 1.5 cm past
## each FACE of the wall and reads as a baseboard on both sides at once. One node per run
## rather than two per wall, and it follows the door gap for free because the south wall is
## already split into two runs either side of it.
static func build_skirting(parent: Node3D) -> void:
	var m := _flat(Color(0.94, 0.93, 0.91))
	for w in Sim.WALLS:
		var sk := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(w.size.x + 0.03, 0.11, w.size.y + 0.03)
		sk.mesh = b
		sk.position = Vector3(w.position.x + w.size.x * 0.5, 0.055,
			w.position.y + w.size.y * 0.5)
		sk.material_override = m
		parent.add_child(sk)


## Wall art, plants, books and appliances. NOT solid — see Sim.DECOR for why this is a
## separate list from FURNITURE.
static func build_decor(parent: Node3D) -> void:
	for d in Sim.DECOR:
		var spec: Array = d["model"]
		var sc := SCALE * float(d.get("scale", 1.0))
		var inst := place(parent, spec[0], spec[1], d["pos"], deg_to_rad(float(d.get("yaw", 0.0))),
			bool(d.get("ground", true)), Vector3(sc, sc, sc))
		if inst == null:
			continue
		# A picture frame owns no material of its own worth keeping, and several of them are
		# the same atlas as the walls; leave them be, they read fine.


static func build_furniture(parent: Node3D) -> void:
	for f in Sim.FURNITURE:
		var kind: String = f["kind"]
		if not FURNITURE_MODEL.has(kind):
			push_warning("House: no model mapped for kind '" + kind + "'")
			continue
		var spec: Array = FURNITURE_MODEL[kind]
		var r: Rect2 = f["rect"]
		var centre := Vector3(r.position.x + r.size.x * 0.5, 0.0,
			r.position.y + r.size.y * 0.5)
		if kind == "rug":
			# flat: sits just above the floor, no grounding
			var rug := place(parent, spec[0], spec[1], Vector3(centre.x, 0.02, centre.z), 0.0, false)
			# `rug_rectangle_A`'s own texture is a black-and-white CHECKERBOARD, which reads as
			# a missing texture rather than a rug. Richard spotted it immediately.
			use_rug_texture(rug)
		else:
			place(parent, spec[0], spec[1], centre)


# ------------------------------------------------------------- exterior
static func build_exterior(parent: Node3D) -> void:
	var house := Sim.HOUSE
	# The front door itself. Sim.DOOR_GAP is a 2 m hole in the south wall and there was
	# nothing in it — door_A and door_B have been on disk unreferenced from the start, and
	# the house's only entrance was a rectangular gap. Left standing open, because the
	# intruder has already come through it.
	# DOOR_SCALE is not House.SCALE: at 0.5 the leaf comes out taller than the 2 m wall it
	# hangs in and sticks up above the eaves.
	# HINGED at the edge of the opening, not centred in it. Placed at the middle the leaf
	# floats in the gap; a door belongs on a hinge at one side, standing open.
	var dscale := Vector3(DOOR_WANT.x / DOOR_SRC.x, DOOR_WANT.y / DOOR_SRC.y,
		DOOR_WANT.z / DOOR_SRC.z)
	var hinge := deg_to_rad(-74.0)
	var leaf_w := DOOR_WANT.x
	var door := place(parent, "restaurant", "door_A",
		Vector3(Sim.DOOR_GAP.x + cos(hinge) * leaf_w * 0.5, 0,
			house.end.y - Sim.WALL_THICKNESS * 0.5 - sin(hinge) * leaf_w * 0.5),
		hinge, true, dscale)
	if door != null:
		door.name = "FrontDoor"
		use_door_texture(door)

	# The head of the opening. Without this the doorway is a hole all the way to the ceiling,
	# which a 3 m wall makes glaring. Filled with wall so the opening is a door-shaped hole.
	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(Sim.DOOR_GAP.y - Sim.DOOR_GAP.x,
		WALL_TARGET_H - DOOR_TOP, Sim.WALL_THICKNESS)
	head.mesh = hb
	head.position = Vector3((Sim.DOOR_GAP.x + Sim.DOOR_GAP.y) * 0.5,
		DOOR_TOP + (WALL_TARGET_H - DOOR_TOP) * 0.5,
		house.end.y - Sim.WALL_THICKNESS * 0.5)
	parent.add_child(head)
	# FLAT, not the atlas. `wall_texture_clean.png` is an atlas with coloured regions in it,
	# and a BoxMesh maps the whole of it 0..1 across every face — so the lintel rendered as a
	# red-and-white slab. Colour sampled from the wall beside the opening in a render.
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.612, 0.582, 0.603)
	head_mat.roughness = 0.93
	head.material_override = head_mat

	# PLINTH: the skirt where the wall meets the ground. Without it the wall grows straight
	# out of the grass, which is one of the things that made it read as a set piece.
	var plinth := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(house.size.x + 0.20, 0.36, house.size.y + 0.20)
	plinth.mesh = pb
	plinth.position = Vector3(house.position.x + house.size.x * 0.5, -0.10,
		house.position.y + house.size.y * 0.5)
	plinth.material_override = _flat(Color(0.42, 0.41, 0.39))
	parent.add_child(plinth)

	# PATH from the drive to the front door. The drive stops a metre short of the house, so
	# the door opened onto bare grass.
	var path := MeshInstance3D.new()
	var pab := BoxMesh.new()
	pab.size = Vector3(1.70, 0.05, 2.60)
	path.mesh = pab
	path.position = Vector3(0.0, 0.025, house.end.y + 1.20)
	path.material_override = _textured("res://assets/textures/driveway.png", 1.2, 2.0)
	parent.add_child(path)

	# lawn
	var lawn := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	lawn.mesh = plane
	lawn.material_override = _textured("res://assets/textures/lawn.png", 48.0, 48.0, 1.0)
	parent.add_child(lawn)

	# driveway
	var drive := MeshInstance3D.new()
	var dbox := BoxMesh.new()
	dbox.size = Vector3(9, 0.06, 26)
	drive.mesh = dbox
	drive.position = Vector3(0, 0.03, 6)
	drive.material_override = _textured("res://assets/textures/driveway.png", 3.0, 9.0)
	parent.add_child(drive)

	# the van — the loot has to go somewhere.
	# NOTE: the city set is NOT authored at the same 2x scale as the restaurant and
	# character sets. At House.SCALE = 0.5 the station wagon measures about 0.94 m
	# long — a shoebox, invisible from the house even in daylight — so it carries its
	# own multiplier.
	var van := place(parent, "city", "car_stationwagon",
		Vector3(Sim.VAN.position.x + Sim.VAN.size.x * 0.5, 0,
			Sim.VAN.position.y + Sim.VAN.size.y * 0.5), PI * 0.5, true,
		Vector3(VAN_SCALE, VAN_SCALE, VAN_SCALE))
	if van != null:
		van.name = "Van"

	# planting and street furniture
	for s in [
		Vector3(-14, 0, 8), Vector3(14, 0, 10), Vector3(-17, 0, -12),
		Vector3(16, 0, -14), Vector3(-12, 0, 20), Vector3(11, 0, 21),
	]:
		place(parent, "city", "bush", s)
	for s in [Vector3(-10, 0, -6), Vector3(10, 0, -6), Vector3(0, 0, 14)]:
		place(parent, "city", "streetlight", s, 0.0)


static func build_all(parent: Node3D) -> void:
	build_exterior(parent)
	build_neighbourhood(parent)
	build_floors(parent)
	build_walls(parent)
	build_ceiling(parent)
	build_furniture(parent)
	build_skirting(parent)
	build_decor(parent)


## The street and the houses around it.
##
## The world outside was a 160x160 m lawn with a driveway on it. The pack ships eight
## buildings, road pieces, benches, a hydrant, a dumpster and traffic lights — all
## imported, all unplaced — so the "neighbourhood" was six bushes and three streetlights,
## which is why the house looked like it was standing alone on an empty plane.
##
## Scenery only: none of it enters Sim.SOLIDS and none of it has collision, so it changes
## what the front door looks out at and nothing else.
static func build_neighbourhood(parent: Node3D) -> void:
	var s := Vector3(CITY_SCALE, CITY_SCALE, CITY_SCALE)
	var street_z := 17.0

	# the road itself, east-west, laid tile by tile.
	# Sunk by the model's own raised base: `place()` grounds a model so its lowest point is
	# at y = 0, but the city road tile is authored as a slab sitting ON a base, so grounding
	# it leaves the running surface proud of the lawn and it reads as a floating tile.
	var x := -44.0
	while x <= 44.0:
		var tile := place(parent, "city", "road_straight", Vector3(x, 0, street_z),
			PI * 0.5, true, s)
		if tile != null:
			tile.position.y -= ROAD_SINK
		x += 8.0

	# houses on the far side, facing back across the street at ours
	var far := ["building_A", "building_C", "building_E", "building_B", "building_D"]
	var bx := -28.0
	for m in far:
		place(parent, "city", m, Vector3(bx, 0, street_z + 15.0), PI, true, s)
		bx += 15.0

	# and two on this side further along, so the street reads as a street
	place(parent, "city", "building_F", Vector3(-30.0, 0, street_z - 14.0), 0.0, true, s)
	place(parent, "city", "building_G", Vector3(30.0, 0, street_z - 14.0), 0.0, true, s)

	# furniture along the kerb
	for p in [
		["streetlight", -13.0, street_z + 4.5],
		["streetlight", 13.0, street_z + 4.5],
		["trafficlight_A", -22.0, street_z + 4.0],
		["firehydrant", -5.5, street_z - 4.2],
		["dumpster", 8.0, street_z - 4.6],
		["bench", -16.0, street_z - 3.6],
		["trash_A", 4.0, street_z - 3.6],
		["trash_B", -8.5, street_z - 3.6],
	]:
		place(parent, "city", String(p[0]), Vector3(p[1], 0, p[2]), 0.0, true, s)


## A material carrying one of the generated textures, tiled across the surface.
##
## `grep -c albedo_texture scripts/` used to find exactly ONE texture in the whole project
## — the recoloured wall atlas — and every other surface was a flat albedo colour. That is
## the root of the synthetic look, and the lighting strategy explicitly relied on darkness
## to hide flat materials until the scene went daylight. Generated by
## tools/gen-textures.py, which makes them tile.
static func _textured(path: String, tile_x: float, tile_y: float,
		rough := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex = load(path)
	if tex == null:
		push_warning("House: missing texture " + path)
		m.albedo_color = Color(0.5, 0.5, 0.5)
	else:
		m.albedo_texture = tex
	m.roughness = rough
	m.uv1_scale = Vector3(tile_x, tile_y, 1.0)
	return m


static func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m
