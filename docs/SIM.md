# Home Invasion — simulation and gameplay rules

Extracted from the monolithic AGENTS.md on 2026-10-08 so the always-loaded file fits its
context budget. Read this before touching `sim.gd`; these are rules that were expensive
to discover and cheap to break.

## The intruder's behaviour model

- **`hp` was read in exactly one place — the lethal check — until 2026-10-04.** So 1 hp
  behaved identically to 100: no flinch, no stagger, no fear. Anything that reads as
  *reaction* has to be added deliberately; the model will not infer it.
- **A hit staggers him** (`stagger`, 0.35-1.4 s by damage) and **wipes his aim**, so he
  must re-settle before returning fire. The move loop is skipped while staggered.
- **Fear is raised by gunfire and much more by being hit, decays slowly, and the decision to
  run is STICKY.** `Sim.alert_thief()` is called by the game on every shot, scaled by distance
  and multiplied for the shotgun. Past `FEAR_FLEE` he abandons the job and runs for the van
  with whatever he is holding.
- **The escape test is the ROUTE EMPTYING, not a distance.** The `"van"` nav node sits at
  z ≈ 4.4 while the van model is at z 7.0-9.4, so a distance test against the van never
  fires and he stands in the drive forever.
- **A player standing in the doorway can delay his escape a long way** — he has to route
  around a body, and the front door is the only way out. Worth remembering before reading a
  long flee as a bug.

## Momentum, and the stuck detector

- **Both characters carry velocity between frames** (`PLAYER_ACCEL` 20 / `PLAYER_DECEL` 30,
  `THIEF_ACCEL` 4 / `THIEF_DECEL` 6). Before this both snapped to full speed on the frame a
  key went down — the classic "sliding prop" tell.
- **The intruder's speed must NOT be decayed on frames he walks.** The first cut decayed
  before the move loop and ramped inside it, so every frame netted to `(ACCEL - DECEL) * dt`
  and he slowed to a standstill while trying to walk. Every heist stalled with him parked on
  the porch and **ZERO reroutes** — because `thief["step"]` is now the distance he ACTUALLY
  covered, it was uniformly tiny, so the stuck detector's `moved < want * 0.25` never fired.
  A uniform-tiny-value symptom in the probe means a movement bug, not an AI one.
- **`--shot-walk` holds the forward key during a capture**, and the debug line reports the
  homeowner's speed in m/s. Movement was previously unphotographable — no keyboard exists in
  a capture. Verified ramp: 0.33, 0.67, 1.33, 2.33, 3.67, 5.67 m/s over 18 frames.


## Combat

- **The intruder's hitbox is THREE shapes** (legs, torso, head) and the raycast's `shape`
  index selects the damage multiplier via `HIT_ZONES`. The shapes deliberately OVERLAP — a
  gap between zones is a hole a bullet passes through without hitting him at all. Anything
  that changes their order silently re-labels every zone, so use `test/probe_hitzones.gd`
  after touching them.
- **Verifying hit zones by aiming with capture arguments does not work.** He flees the
  moment he is shot at, so by capture time he is somewhere else and the shot misses for
  reasons unrelated to the zones; four swept angles read "head, miss, miss, miss" and looked
  exactly like broken geometry when the geometry was correct. `test/probe_hitzones.gd` casts
  horizontally at the hitbox's OWN position instead, so where he is cannot matter.
- **His rounds are raycasts against `LAYER_WORLD`** and stop at geometry. They used to be a
  probability roll on a line with geometry never consulted.
- **The stance label is clipped at the HUD's width.** Debug values appended to the END of it
  are silently cut off, which made three good shots read as misses. Put anything you need to
  read at the FRONT.

## Ammunition and combat numbers

- **Each weapon keeps its OWN magazine** (`player["mags"]`), and `player["mag"]` is the
  current one. Switching used to hand you a full magazine, which made the reserve
  decorative however tight it was.
- **Reloading lives in `sim.gd`** (`Sim.load_magazine` / `Sim.can_load_magazine`) because
  the reserve is a gameplay rule and the game layer is not reachable from the test harness.
- **`static func reload()` does NOT shadow GDScript's built-in `reload()`.** The call
  resolves to the global one and fails with a type error that reads like a bug in the
  caller. Do not name a static function after a GDScript global — `reload`, `load`,
  `print` and friends.
- **A runtime error inside a SceneTree script's `_init` leaves the tree running FOREVER**
  with no output, which is indistinguishable from a hang. Always run test scripts under an
  alarm, and remember **`timeout` does not exist on macOS** — use
  `perl -e 'alarm shift; exec @ARGV' N cmd`.
- **`--quit-after` counts FRAMES, not seconds.** This scene renders slowly, so a long
  `--shot-after` can take many minutes of wall time and get killed mid-capture by an alarm —
  which looks like a crash but is only impatience.

## Searching

- **The intruder does NOT know where the valuables are.** An item is `known` only once he
  has stood in the room it is in (`SEARCH_RANGE`), and each room is searched once
  (`thief["searched"]`). He used to know all three exact coordinates from spawn.
- **`SEARCH_NODES` deliberately includes `kitchen`, which holds nothing.** Searching that
  cannot come up empty is not searching, it is a delay. Keep at least one decoy room.
- **Every loot spot's `node` must be in `SEARCH_NODES`,** or that item can never be
  discovered and the round cannot be completed. `test/test_sim.gd` checks the mechanic;
  `probe_heist.gd` is what would catch a missing one end-to-end.
- The search dwell reuses `thief["think"]`, which already holds him still — do not confuse
  it with the route logic.

## The clock

- **`Sim.POLICE_TIME` does not start on its own.** It starts on the first shot the homeowner
  fires (`alert_thief` sets `thief["alarm"] = 0.0`), because a gunshot is what makes somebody
  call. A quiet round never starts one, which is why `probe_heist.gd` — which never fires —
  still completes.
- **When it runs out he flees, exactly as if he had been shot at.** It is deliberately NOT a
  win condition: the police take him away rather than stopping him, so he leaves with
  whatever he is holding. You can cut a robbery short by making noise; you pay for it.
- The siren is an `AudioStreamPlayer3D` out on the street, so it arrives from where the
  police are. It needs BOTH `loop_mode` and the loop points set, like every other loop here.

## The shove

- **[F] is the only non-lethal verb.** `Sim.shove()` does no damage: it staggers him 1.2 s,
  raises his fear, drives him back 0.45 m, and makes him drop what he is carrying — the only
  way to take a valuable back without killing anybody. Range 1.9 m, arc 0.6 rad, cooldown 0.8 s.
- **`REGRAB_TIME` is load-bearing.** He is shoved 0.45 m and `GRAB_RANGE` is 1.4 m, so
  without a recovery delay he re-took the item on the very next frame and the shove cost him
  nothing. He cannot pick anything up for 2.5 s after being shoved.
- **The facing vector is `(sin(yaw), cos(yaw))`,** the same convention the movement code uses
  where yaw 0 faces +Z. `(cos, sin)` is ninety degrees out and would land the shove on people
  standing beside you.
- **`--shot-shove` exists** for the same reason `--shot-walk` does: a capture has no keyboard,
  so close-range combat is otherwise unphotographable.
- **A `str.replace()` whose anchor has already been rewritten is a silent no-op.** A whole
  capture session read "the feature does nothing" when in fact the call site had never been
  inserted. When a capture says nothing happened, confirm the code path exists before
  believing the feature is broken.

## The van

- **It drives now** (`_update_van`), arriving from the street at round start and leaving on
  both loss endings. Moved by POSITION, never a tween, so a restart cannot leave it half-way;
  `off` is exactly zero at rest, so it returns to where `place()` built it by construction.
- **Its collision box moves with it.** If it did not, the parked van would go on blocking
  rays somewhere the model no longer is.
- **A guard of `_van_t < 0.1` printed nothing, and the reason was the guard.** The FIRST
  frame's delta is about 0.149 s — the engine's first frame includes load and settle — so it
  already exceeded the threshold. **"No output" from a threshold you chose yourself is not
  evidence until you have checked the threshold.**
- **Avoid regex edits that span a line break in these GDScript files.** A cleanup pass left a
  stray continuation line and a parse error; `sed`-style edits have caused several
  self-inflicted failures. Replace whole statements, or use the edit tool.


## More than one intruder

One defender against up to three intruders is the design target. `sim.gd` holds the bodies;
`game.gd` presents them. The single-intruder API still exists and still works — that is
deliberate, so the old one-thief behaviour stays available for A/B.

- **`Sim.create_intruders(n)`**, not `create_thief()`, builds a round's worth. Thieves get an
  `id` (event attribution) and are fanned across the driveway, because `create_thief()` puts
  one body on the exact DROP point and **two bodies at the same coordinate are the one case
  separation cannot resolve** — there is no direction to push along.
- **`Sim.step_intruders(...)` steps every body with per-body separation DISABLED**, then runs
  `separate_all` once. Calling the two-body `step_thief` three times would let each intruder
  shove the homeowner in turn — a net gain in displacement the one-thief code never had to
  survive. `step_thief`'s `separate` parameter defaults true, which is what keeps every
  existing caller and test unchanged.
- **`separate_all` is ITERATIVE** (up to 3 sweeps). Resolving the homeowner against one
  intruder can push him into another, and "no two bodies ever overlap" is a contract. The
  homeowner is still the body that yields; two intruders split their push evenly.
- **Every per-body event carries the `id` of the body that emitted it**, stamped at the
  producer inside `step_intruders` — that is the only place the identity is known. Inferring
  it afterwards from the payload does not work: a `grabbed` carries a loot label, not a body.
  `sirens` and `allStolen` are deliberately global.
- **`prev` has exactly ONE writer per frame.** `step_thief` sets it to the frame-start
  position at the top, before anything moves the body; `step_intruders` re-anchors it to the
  pre-push position afterwards. Getting this wrong banks the separation push as *travel* and
  the offset compounds every frame, which blinds the stuck detector — the same class of
  failure as the `(ACCEL - DECEL)` bug below.
- **Hitboxes are named by index** — `ThiefHitbox`, `ThiefHitbox1`, … — and
  `_intruder_index_of()` reads the name back off a raycast hit. Index 0 keeps the original
  bare name so nothing that looks for it has to change.
- **`_fire()` used to compare the collider name against the literal `"ThiefHitbox"`.** With a
  second body present that test is false for every new hitbox, so all of them would have been
  bulletproof. Any name-based collider test has to be index-aware now.
- **The round is won only when EVERY intruder is down.** One `thiefDown` was the win, which
  with three of them ends the game on the first man through the door with two still inside.
  `_thieves_down` counts, and `_any_intruder_standing()` gates it.
- **Gunfire alerts EVERY intruder**, each scaled by his own distance. `alert_thief` on the
  primary alone leaves the other two calmly working the house while a shotgun goes off.
- **`_try_shove()` targets the NEAREST living intruder**, not the primary: `Sim.shove` tests
  its own range (1.9 m) and arc (0.6 rad), so a body across the room fails that test and the
  shove silently does nothing while a man stands in front of you.
- **`--thieves=N`** overrides the count (`THIEF_COUNT`, default 3) so a one- and
  three-intruder round can be compared without an edit.
- **`Actor.tint_body()` multiplies the body material only.** The weapons and kit live BESIDE
  `root`, so one man's tint cannot recolour another man's hat. Three identical black
  silhouettes are unplayable — you cannot tell which of them is carrying your television.
- **There are still only THREE valuables (`LOOT_SPOTS`)**, so with three intruders at most one
  can come out ahead. This is a known, unresolved design hole, not a bug — the proposal is a
  shared pot with a value threshold instead of "all three items ends the round".

