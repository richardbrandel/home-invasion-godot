extends SceneTree

## Tune the carry pose numerically instead of by rendering.
##
##   godot --headless --path . --script test/probe_carrypose.gd
##
## `scripts/carry_pose.gd` aims each upper arm with a GLOBAL pose override, which
## `test/probe_pose.gd` showed is the only thing strong enough to move a hand. What it needs
## is a direction, and guessing that direction by looking at renders would be a dozen renders
## per guess — and `test/probe_carry.gd` already proved that guessing bone rotations blindly
## produces confident nonsense.
##
## So: sweep candidate directions and print where the HANDS END UP, measured in the model
## root's own space, where the chest is at about (0, 1.2, 0). A carry wants both hands near
## the front of the chest, roughly 0.35-0.5 m apart.

const WANT_Y := 1.05
const WANT_Z := 0.34


func _initialize() -> void:
	var a := Actor.create("res://assets/mixamo/thief", 1.0)
	if a == null or a.root == null:
		print("no actor — the Mixamo assets are absent")
		quit()
		return
	root.add_child(a.root)
	a.attach_weapon()
	a.play(Actor.WALK, 1.0)

	var sk: Skeleton3D = null
	for c in a.root.find_children("*", "Skeleton3D", true, false):
		sk = c as Skeleton3D
		break
	if sk == null:
		print("no skeleton")
		quit()
		return

	var mod := load("res://scripts/carry_pose.gd").new() as SkeletonModifier3D
	sk.add_child(mod)

	# let the skeleton settle, then measure the arms as the animation leaves them
	for i in 20:
		await process_frame
	var rest := _hands(a, sk)
	print("as animated:  right %s   left %s" % [rest[0], rest[1]])
	print("")

	var best := {}
	var best_err := 1e9
	print("sweeping aim directions (hands, in the model root's space):")
	for ax in [-0.35, -0.15, 0.0, 0.15, 0.35]:
		for ay in [-0.55, -0.30, -0.05]:
			for az in [0.75, 0.95]:
				mod.aim_dir = Vector3(ax, ay, az)
				mod.weight = 1.0
				for i in 4:
					await process_frame
				var h := _hands(a, sk)
				var err: float = absf((h[0] as Vector3).y - WANT_Y) \
					+ absf((h[0] as Vector3).z - WANT_Z) \
					+ absf((h[1] as Vector3).y - WANT_Y) \
					+ absf((h[1] as Vector3).z - WANT_Z) \
					+ absf(absf((h[0] as Vector3).x) - 0.20) \
					+ absf(absf((h[1] as Vector3).x) - 0.20)
				if err < best_err:
					best_err = err
					best = {"d": Vector3(ax, ay, az), "h": h, "e": err}
				print("   (%+.2f %+.2f %.2f) right %s  left %s  err %.3f"
					% [ax, ay, az, h[0], h[1], err])
	print("")
	print("best: aim_dir=%s  err %.3f" % [best["d"], best_err])
	print("   right hand %s" % best["h"][0])
	print("   left  hand %s" % best["h"][1])
	print("   wanting both near y=%.2f z=%.2f, about 0.4 m apart in x" % [WANT_Y, WANT_Z])
	quit()


## Both hands, in the model root's own space, so the numbers mean something about the body
## rather than about wherever the character happens to be standing.
func _hands(a: Actor, sk: Skeleton3D) -> Array:
	var out: Array = []
	for suffix in ["RightHand", "LeftHand"]:
		var idx := -1
		for i in sk.get_bone_count():
			if String(sk.get_bone_name(i)).ends_with(suffix):
				idx = i
				break
		var w := sk.global_transform * sk.get_bone_global_pose(idx)
		out.append(a.root.global_transform.affine_inverse() * w.origin)
	return out
