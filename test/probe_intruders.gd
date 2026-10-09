extends SceneTree
## Diagnostic, not a test: does `step_intruders` actually MOVE a thief?
##
## Written 2026-10-09 because the Unreal port's intruders never move, and the ported
## `step_intruders` applies `separate_all` to the positions captured BEFORE the per-body
## step and then writes that result back -- which discards every step's movement. The
## Godot original has what looks like the same ordering, so the question is whether the
## port diverged from Godot or faithfully reproduced a bug Godot also has.
##
## Prints the distance travelled two ways: through step_thief directly, and through
## step_intruders. If the second is ~0 the original is broken the same way.
##
##   Godot --headless --path . --script test/probe_intruders.gd

const Sim = preload("res://scripts/sim.gd")

func _initialize() -> void:
	var dt := 1.0 / 60.0

	# ---- the single-body path
	var player := Sim.create_player()
	var thief := Sim.create_thief()
	var loot := Sim.create_loot()
	var events: Array = []
	var start: Vector2 = thief["pos"]
	var path := 0.0
	for i in 180 * 60:
		var was: Vector2 = thief["pos"]
		Sim.step_thief(thief, player, loot, events, dt)
		path += was.distance_to(thief["pos"])
		events = []
	var solo := path

	# ---- the group path, which is what game.gd actually calls
	player = Sim.create_player()
	var intruders := Sim.create_intruders(1)
	loot = Sim.create_loot()
	events = []
	var start2: Vector2 = intruders[0]["pos"]
	var path2 := 0.0
	for i in 180 * 60:
		var was2: Vector2 = intruders[0]["pos"]
		Sim.step_intruders(intruders, player, loot, events, dt)
		path2 += was2.distance_to(intruders[0]["pos"])
		events = []
	var group := path2

	printerr("PROBE solo_path=%.1f m  group_path=%.1f m" % [solo, group])
	# Where each path actually ENDS UP, and what each body thinks it is doing.
	var p2 := Sim.create_player()
	var t2 := Sim.create_thief()
	var l2 := Sim.create_loot()
	var e2: Array = []
	for i in 180 * 60:
		Sim.step_thief(t2, p2, l2, e2, 1.0 / 60.0)
		e2 = []
	printerr("PROBE solo_end pos=%s mode=%s target=%s carry=%s route=%d think=%.2f known=%d" % [
		str(t2["pos"]), str(t2["mode"]), str(t2["target"]), str(t2["carry"]),
		(t2["route"] as Array).size(), float(t2["think"]),
		int(l2.filter(func(x): return x["known"]).size())])
	var p3 := Sim.create_player()
	var g3 := Sim.create_intruders(1)
	var l3 := Sim.create_loot()
	var e3: Array = []
	for i in 180 * 60:
		Sim.step_intruders(g3, p3, l3, e3, 1.0 / 60.0)
		e3 = []
	var t3: Dictionary = g3[0]
	printerr("PROBE group_end pos=%s mode=%s target=%s carry=%s route=%d think=%.2f" % [
		str(t3["pos"]), str(t3["mode"]), str(t3["target"]), str(t3["carry"]),
		(t3["route"] as Array).size(), float(t3["think"])])
	printerr("PROBE solo_delivered=%d group_delivered=%d" % [3 - Sim.remaining(loot), 3 - Sim.remaining(loot)])
	quit()
