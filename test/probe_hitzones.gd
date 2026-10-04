extends SceneTree

## Verify the intruder's hit zones against the REAL hitbox in the REAL scene.
##
##   godot --headless --path . --script test/probe_hitzones.gd
##
## Aiming at him by capture argument turned out to be a bad way to check this: he flees the
## moment he is shot at, so by the time a screenshot is taken he is somewhere else and the
## shot misses for reasons that have nothing to do with the zones. This casts horizontally
## at the hitbox's OWN position, so where he is does not matter, and reports which shape the
## ray struck at each height. That is the whole question: are the zones where they claim to
## be, and does the index come back the way the damage code assumes?

var _game: Node = null
var _frames := 0


func _initialize() -> void:
	_game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 30:
		return false
	var box: StaticBody3D = _game.get_node_or_null("ThiefHitbox")
	if box == null:
		print("FAIL: no ThiefHitbox in the scene")
		return true

	var origin := box.global_position
	var space: PhysicsDirectSpaceState3D = _game.get_world_3d().direct_space_state
	# the same table the damage code indexes
	var names := ["legs", "torso", "head"]
	print("hit zones, raycast at the hitbox's own position (%.2f, %.2f):"
		% [origin.x, origin.z])
	var expect := {
		0.15: "legs", 0.45: "legs", 0.75: "legs",
		1.00: "torso", 1.20: "torso", 1.45: "torso",
		1.60: "head", 1.72: "head",
	}
	var bad := 0
	for y in [0.15, 0.45, 0.75, 1.00, 1.20, 1.45, 1.60, 1.72]:
		var q := PhysicsRayQueryParameters3D.create(
			Vector3(origin.x, y, origin.z - 3.0),
			Vector3(origin.x, y, origin.z + 3.0))
		q.collision_mask = box.collision_layer
		var h: Dictionary = space.intersect_ray(q)
		if h.is_empty():
			print("   y=%.2f  MISS  (expected %s)" % [y, expect[y]])
			bad += 1
			continue
		var idx := int(h["shape"])
		var got: String = names[idx] if idx >= 0 and idx < names.size() else "index %d" % idx
		var ok: bool = got == expect[y]
		if not ok:
			bad += 1
		print("   y=%.2f  shape %d -> %-5s  expected %-5s  %s"
			% [y, idx, got, expect[y], "ok" if ok else "WRONG"])
	# the gap checks: nothing above his head, nothing below his feet
	for y in [2.05, -0.10]:
		var q2 := PhysicsRayQueryParameters3D.create(
			Vector3(origin.x, y, origin.z - 3.0),
			Vector3(origin.x, y, origin.z + 3.0))
		q2.collision_mask = box.collision_layer
		var h2: Dictionary = space.intersect_ray(q2)
		var clear: bool = h2.is_empty()
		if not clear:
			bad += 1
		print("   y=%.2f  %s (expected clear)"
			% [y, "MISS" if clear else "HIT — the box is taller than he is"])
	print("VERDICT: ", "clean" if bad == 0 else "%d wrong" % bad)
	return true
