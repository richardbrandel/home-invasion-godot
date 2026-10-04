extends SceneTree

## Scratch diagnostic: does the heist complete when the HOMEOWNER MOVES?
##   godot --headless --path . --script test/probe_heist.gd
##
## Deliberately does NOT apply the intruder's damage to the player. That is
## unrealistic, but it is the point: it removes "the homeowner got shot" as an
## ending, so a thief who cannot reach the van shows up as a stall instead of
## being masked by the player dying.

const DT := 1.0 / 60.0


func _run(label: String, mover: int) -> void:
	var player := Sim.create_player()
	var thief := Sim.create_thief()
	var loot := Sim.create_loot()
	var reroutes := 0
	var t := 0.0
	var events: Array = []
	while t < 180.0 and Sim.remaining(loot) > 0:
		match mover:
			1:
				var d: Vector2 = (thief["pos"] as Vector2) - (player["pos"] as Vector2)
				if d.length() > 0.01:
					var p: Vector2 = (player["pos"] as Vector2) + d.normalized() * Sim.PLAYER_SPEED * DT
					player["pos"] = Sim.clamp_to_world(
						Sim.resolve_circle(p, Sim.PLAYER_RADIUS), Sim.PLAYER_RADIUS)
			2:
				player["pos"] = Vector2(0, -8.6)      # front doorway
			3:
				player["pos"] = Vector2(sin(t * 0.7) * 3.0, -11.0 + cos(t * 0.5) * 2.0)
			4:
				player["pos"] = Vector2(0, -11.2)     # frontHub, mid-house
			5:
				player["pos"] = Vector2(-3.6, -11.2)  # living-room doorway
			6:
				player["pos"] = Vector2(0, 3.0)       # outside, by the van
		events = []
		Sim.step_thief(thief, player, loot, events, DT)
		for ev in events:
			if ev["type"] == "reroute":
				reroutes += 1
		t += DT
	var verdict := "HEIST COMPLETED" if Sim.remaining(loot) == 0 else "STALLED"
	print("%-26s delivered=%d/3  t=%6.1fs  reroutes=%-3d thief=(%5.1f,%5.1f) carry=%-6s %s" % [
		label, 3 - Sim.remaining(loot), t, reroutes,
		(thief["pos"] as Vector2).x, (thief["pos"] as Vector2).y,
		thief["carry"], verdict])


func _init() -> void:
	_run("idle at spawn", 0)
	_run("chases the thief", 1)
	_run("blocks the front doorway", 2)
	_run("wanders the front hall", 3)
	_run("stands at frontHub", 4)
	_run("stands in living room", 5)
	_run("stands outside by the van", 6)
	quit()
