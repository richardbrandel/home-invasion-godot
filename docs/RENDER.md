# Home Invasion — minimap, camera, HUD, effects, verification

Extracted from the monolithic AGENTS.md on 2026-10-08. Read this before touching
`minimap.gd`, the camera, the HUD, or running a capture.

## Effects

- **Impact marks are pooled, never freed.** A shotgun blast is nine of them, so a long
  round would churn dozens of nodes per trigger pull. `MARK_MAX` of them are created once
  and reused oldest-first.
- A mark is a `QuadMesh` facing `+Z`, oriented with `Basis.looking_at(-normal, up)` — the
  minus because `QuadMesh`'s visible face is +Z — and offset 12 mm along the normal with
  `DEPTH_DRAW_ALWAYS` so it can never z-fight the surface it sits on.
- **`--shot-fire` holds the trigger during a capture.** Capture mode has no mouse, so
  without it nothing that only happens when you shoot — marks, the flash, recoil — can be
  photographed at all.

## Capture and verification arguments

- **They apply whenever asked for, whatever the capture mode.** They used to be applied
  inside the `--shot` branch, and `--write-movie` never sets `_shot_frames` — so a movie
  recording silently ignored `--shot-fire`, `--shot-pos`, `--shot-yaw`, `--shot-pitch`,
  `--shot-aim` and `--carry`. A whole hunt for the muzzle flash was invalidated by this:
  the recording that was supposed to contain a gunshot had a player who never fired.
  **If a capture shows nothing where you expected something, check the argument applied at
  all before doubting the feature.**
- **`--write-movie` is the systematic way to catch a transient.** A 45 ms muzzle flash
  against a 240 ms fire cadence is a 19% chance per screenshot and a certainty in a
  recording. Record a couple of seconds, then rank the frames by how much they change from
  the previous one — the shot stands out by an order of magnitude.
- Godot writes a `.wav` of the mix alongside the frames, so the same recording verifies
  audio too.

## The minimap was upside-down

- **`_to_map` maps world +Z to screen −Y, and the minus is the point.** Canvas Y grows
  DOWNWARD, and +Z runs from the house out to the street. Mapping +Z to +Y drew the house
  ABOVE the player while they stood on the driveway facing it, so the whole map read
  inverted and the facing wedge pointed into the lawn.
- **This was reported as "the minimap is mirrored" and it never was.** A mirror reverses
  handedness; this only reversed which way was up. Worth knowing before the next session
  goes hunting for a flip that is not there. The Y axis is flipped and the wedge follows it
  with `Vector2(sin yaw, -cos yaw)`. Verified by capture: player at spawn, house above them,
  wedge pointing into it, a seen intruder drawn inside the lit cone.
- **The facing wedge was also 90° out** — `(cos yaw, sin yaw)` where yaw 0 faces +Z, so the
  vector is `(sin yaw, cos yaw)`. Same mistake as the shove's facing vector.
- **`update_state()` takes the whole ARRAY of intruders now.** It used to take one dictionary;
  with three, it drew whichever one it was handed and silently hid the other two.
- **The lit floor is a TRIANGLE FAN, not a filled polygon, and that is the fix for what
  the file used to call its KNOWN ISSUE.** `draw_colored_polygon` hands the outline to
  Godot's ear-clipper, which REJECTS it: `Sim.visibility_polygon` returns a NON-SIMPLE
  outline — measured over 24,715 positions, 64% have two edges that properly cross — so the
  lit floor vanished on **238 of 240 frames** of a real run, with *"Invalid polygon data,
  triangulation failed"* in the console. The crossings come from the EDGE JOINING
  consecutive rays. The triangles sharing the viewer as their apex are unaffected by them,
  and the outline is star-shaped about the viewer **by construction** (rays sorted by angle
  from that exact point). `draw_primitive` triangulates nothing — three points, one
  triangle — so the clipper is bypassed. Verified against `Sim.los_blocked` as ground truth
  (`test/probe_fan.gd`): **98.85% of the visible area lit, 0.14% leaking through walls.**
- **Nothing that removes POINTS from the outline helps, and that is now measured, not
  assumed.** `test/probe_triangulation2.gd` over 24,715 positions: raw 64.4% failing,
  dedup 64.1%, minimum-spacing 0.01 m 64.4%, turn-filter at 1 deg 31.7%. The reverted
  minimum-separation filter changed nothing because it was fixing the wrong thing — the
  problem is the ORDER of the points, not their spacing.
- **The per-solid-edge alternative was BUILT AND MEASURED WORSE — do not rediscover it.**
  Emitting one convex wedge per visible solid edge is sound (0 of 287,970 wedges fail to
  triangulate) but **INCOMPLETE: 93% of the truly visible area goes unlit**
  (`test/probe_litfaces.gd`), because a ray stops at the nearest wall rather than at the
  intended edge. It is a rework of the lit region, not a patch, and it lost to the fan.
- **`draw_primitive(points, colors, uvs, texture=null)` — UVs are REQUIRED.** The signature
  needs three arguments, and passing only points and colours is a PARSE error. That matters
  more than it sounds: **a parse error in `minimap.gd` stops the whole script loading, so the
  minimap silently draws nothing while the game runs on.** Chasing the triangulation error
  count to zero read as success when in fact nothing was calling `draw_colored_polygon` any
  more. Check for `SCRIPT ERROR` before trusting the disappearance of an error you were
  hunting — a pass-shaped nothing is the failure mode this project keeps producing.


