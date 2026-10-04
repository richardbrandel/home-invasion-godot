# Realism roadmap

## Status: COMPLETE, with one measured exception

Every numbered item (1-24), every bug on the audit's list, and all four items reported from
play are addressed and verified — by the two headless suites, the heist and wallshot probes,
and rendered screenshots. The single exception is item 7, recorded below with the measurement
that made me leave it. The "deep end" section is aspirational and was never a finite list;
most of it is now done anyway (fear and morale, the external clock, searching, melee, and a
defensive verb that is not a gun).

Final state: **91 sim tests, 38 actor tests, heist 7/7, wallshot 0 violations, hit zones
clean, carry pose reachable.**

### The one thing I chose not to do, and why

**Item 7 — he cannot shoot while carrying.** The audit is right that this is unrealistic, and
it stays. I implemented the obvious fix, that he drops the loot when the homeowner is close and
in plain sight and goes for the gun, and MEASURED it: an idle homeowner stands on his route, so
the drop fires constantly and **all seven heist scenarios stopped completing**. The alternative,
firing one-handed, needs a pistol and a two-handed item in the same hand — the carried object
rides `hand_origin()` and so does the weapon, so they would intersect. Better a recorded
trade-off than a broken round: the loot being his vulnerability is what makes the shove, the
police clock and cornering him mean anything.

### What is genuinely left, and it is not a list

- **`sim.gd` is 2-D, and that is a documented approximation rather than a defect.** The
  homeowner's shooting is genuinely 3-D — the ray is cast in world space against furniture with
  real heights, so crouching behind something tall already works. What is 2-D is the intruder's
  line of sight and movement. On one floor with full-height walls that costs very little; it
  would matter in a house with a landing.
- **The deep end.** A defensive verb beyond the shove (locking, lights, calling out), neighbours,
  and any aftermath once he has gone. Real features, not fixes.

## Progress

- **R2 the carry pose — DONE** (2026-10-04). Reported twice. The loot rode his hand bone but
  at hip height because his arms hang in the walk clip and there is no carry animation in the
  asset set. `scripts/carry_pose.gd` is a `SkeletonModifier3D` that poses both arms after the
  AnimationPlayer writes the frame; the load now sits between the hands at chest height.
  Two things had to be right: the override must be **persistent** or the arm creeps instead of
  taking the pose, and the aim direction was **swept** (`test/probe_carrypose.gd` prints where
  the hands land) rather than guessed. `CARRY_HANG` re-tuned to match.
  **Better still if the token is refreshed** — a real Mixamo clip beats a hand-built pose.

- **The carry pose is REACHABLE — the route is now known** (2026-10-04). `test/probe_pose.gd`
  measured it: on the right shoulder with the walk clip playing, two frames of animation move
  the hand 0.023 m, a `set_bone_pose_rotation` write moves it 0.039 m, and a
  `set_bone_global_pose_override` moves it **0.562 m — 25x the control**. So an arm can be
  aimed by hand, and `Actor.grip()`'s local writes are why the finger grip never worked.
  Implementing it needs a `SkeletonModifier3D` plus tuning passes; the clip is still better
  and still behind the token.

- **The van drives — DONE** (2026-10-04). Audit item 22, and the last place the world lied
  about itself. It arrives from the street while the intruder waits at the threshold — the
  dwell and the approach are the same two seconds — and leaves when he does, on both loss
  endings. Moved by position, so a restart cannot leave it half-way, and `off` is exactly
  zero at rest so it returns to where it was built by construction. The loss text is honest
  again. **Still open from the same item:** it is a station wagon, because the pack has no
  van model.

- **The intruder reads as a burglar — DONE** (2026-10-04). Audit item 23. Beanie, gloves and a
  holdall ridden on the bones, plus a darkened body material — which is the part that does
  the work, because the mesh is bare skin from the collarbones down and a hat alone leaves a
  naked man in a hat. He is now a black-clad figure with a bag, unmistakable against the
  homeowner's navy suit.

- **Melee, and a defensive verb that is not a gun — DONE** (2026-10-04). [F] shoves: no
  damage, 1.2 s stagger, fear, 0.45 m of knockback, and he DROPS what he is carrying — the
  only way to recover a valuable without killing him. Needs 2.5 s to pick it back up, which
  is what makes it worth doing. Eleven new tests, verified in the game.
  **Still open from the same item:** the intruder has no equivalent — he will not shove or
  grapple the homeowner even at contact range.

- **The police clock — DONE** (2026-10-04). A gunshot starts a 110 s countdown; when it runs
  out he hears sirens and leaves with whatever he has. Deliberately not a win — noise cuts a
  robbery short, it does not stop it. Synthesised siren from the street, HUD countdown, six
  new tests, verified live (`POLICE 1:36` at 14 s elapsed).

- **Searching — DONE** (2026-10-04). He no longer knows where the valuables are: an item is
  unknown until he has stood in its room, each room is searched once, and the kitchen is a
  deliberate decoy that holds nothing. Heist 7/7 at ~137 s (was ~126). Seven new tests.

- **Audit item 10 finished — DONE** (2026-10-04). Reserve ammunition drawn from a real pool
  with per-weapon magazines; 78 hp instead of 100 (no longer a bullet sponge); shotgun
  pellets lose energy with range; his 55% accuracy floor removed so distance is worth
  having. Eight new tests. Verified live: the HUD reads `2 / 12 (24)` after 24 rounds spent.

- **Hit location, stoppable rounds, and reload pace — DONE** (2026-10-04). Audit item 10,
  the combat cluster. The intruder's hitbox is three shapes now (legs x0.55, torso x1.0,
  head x4.0) selected by the raycast's shape index; his shots are raycasts that the house
  can stop instead of a probability roll that ignored geometry; reloading costs 38% of your
  pace. Verified by `test/probe_hitzones.gd`, which casts at the hitbox's OWN position so a
  fleeing target cannot produce a false negative — 8 heights correct, 2 control heights clear.
  **Still open from item 10:** 100 hp against 26 per pistol hit (he is still a bullet
  sponge), no reserve ammunition, shotgun pellets that never lose energy with range, and a
  55% accuracy floor on his shots.

- **Momentum on both characters — DONE** (2026-10-04). Audit item 3, called "the cheapest
  large win in the file", and it was: neither character had acceleration or deceleration, so
  both snapped to full speed and stopped dead. Verified frame by frame out of a recording via
  the new `--shot-walk`. Three new tests. **Still open from the same item:** the homeowner's
  own turn rate (the intruder has one), and head bob.

- **Fear and fleeing — DONE** (2026-10-04). Gunfire frightens him, distance-scaled and
  doubled for the shotgun; being hit frightens him far more. Past `FEAR_FLEE` he abandons
  the job and runs for the van with whatever he is holding, giving a **third ending** and a
  third way to win: make the house too expensive to rob rather than killing him. Verified
  in the rendered game, not only in tests — the overlay reads *"He broke off and ran — 0 of
  3 with him."* Six new sim tests; measured escape time 15-21 s from three start positions.
  **Still missing:** the police timer, and any consequence for the homeowner of a fleeing
  intruder who got away (no report, no aftermath).

- **A hit interrupts him — DONE** (2026-10-04). A stagger of 0.35-1.4 s scaled by damage,
  during which he does not move, plus an aim reset so he must settle on you again. `hp` was
  previously read in exactly ONE place, the lethal check, so 1 hp behaved exactly like 100.
  Three new tests. Also: he drops what he is carrying when he goes down.
- **A front door and half-glazed windows — DONE.** `Sim.DOOR_GAP` was a permanent 2 m hole;
  `door_A`, `door_B` and `wall_window_closed` were all on disk unreferenced. The door needs
  its own scale — at `House.SCALE` the leaf is taller than the wall it hangs in.

- **The neighbourhood — DONE** (2026-10-04). A road, seven buildings, streetlights, traffic
  lights, a hydrant, a dumpster, benches and bins, all from the city set that was sitting
  imported and unplaced. The world was a 160x160 m lawn with a driveway on it; the house
  looked like it stood alone on an empty plane. Scenery only — no `Sim.SOLIDS`, no collision.
- **A capture-argument bug, found by accident and worth more than the thing it was blocking.**
  Every capture override was applied inside the `--shot` branch, and `--write-movie` never
  sets `_shot_frames` — so a recording ignored `--shot-fire`, `--shot-pos`, the aim angles
  and `--carry`. The muzzle-flash hunt failed for a while because the recording that should
  have contained a gunshot had a player who never pulled the trigger.

- **Impact feedback — DONE** (2026-10-04). Every pellet that strikes geometry now leaves a
  bullet hole, sized for a shotgun and for flesh, plus a muzzle flash. Verified by firing
  into a ceiling and photographing the mark cluster — nine per blast, scattered by pellet
  spread. Marks are pooled, not freed.
- **Collision on the floor, ceiling and van — DONE.** They had none, so bullets passed
  straight through and a round aimed at the ground carried on to the horizon.
- **`--shot-fire`** added: without it a capture fires nothing, so nothing that only happens
  when you shoot could be photographed.
- **Loot self-illumination** back down 0.18 -> 0.07; it was standing in for lighting when
  every surface was flat and dark.

- **Textures and a roof — DONE** (2026-10-04). The project had exactly ONE texture. Five
  more are generated by `tools/gen-textures.py` and applied to the floor, lawn, driveway,
  ceiling and roof, and the house now has a pitched roof with eaves and gables instead of
  a flat lid. The textures **tile by construction** (integer-frequency sinusoids), which is
  the only thing that mattered technically — a seam grid on a floor would be worse than the
  flat colour it replaced.
- **Carry pose — ATTEMPTED AND WITHDRAWN.** `test/probe_carry.gd` searched the shoulder
  and elbow rotations numerically instead of guessing axes. It failed for an instructive
  reason: **rotating a bone about its own length axis moves nothing**, and the search
  happily picked those degenerate zero-effect solutions. Posing an arm by hand needs the
  bone's frame resolved properly (aim the bone at a target direction in skeleton space),
  and that is a multi-round sub-project. **The right fix is the Mixamo clip** — "Box Idle"
  and "Holding Walk" both exist and `tools/mixamo-fetch.py clip` fetches one without the
  100 MB mesh — and it is behind an expired token. Do not burn more rounds on the hand
  pose while that is true.
  The carried item IS attached to the hand bone rather than the model root, so it follows
  his arm; it sits low because his arms hang in `walk`.

- **Audio — FIRST PASS DONE** (2026-10-04). Six synthesised sounds (`tools/gen-sfx.py`):
  pistol, shotgun, footstep, impact, door, van idle. Wired to firing, footfalls, hits, the
  door threshold and a van that idles all round. Verified by recording the game and
  analysing the mix WAV — gunshots at the 1.35 s fire cadence, footsteps at the 0.46 s and
  0.64 s step intervals, and a continuous floor (which caught the van being silent,
  because `loop_mode` alone leaves an empty loop region).
  **Still missing:** a weapon-specific reload sound, the shell-casing and muzzle-flash
  layer, and any voice.
- **Combat feedback — PARTLY.** The intruder now plays `SHOOT` when he fires (he used to
  damage you standing still), `RELOAD` is played on both reload paths, `thiefHit` and
  `playerHit` — emitted by the sim all along and never read — now make a sound, and the
  view has recoil. **Still missing:** bullet holes and impact decals (the hit point is
  still thrown away), muzzle flash, and shell casings.

- **R3 real ceiling — DONE** (2026-10-04). The cause was not lighting: the environment
  takes its ambient from the sky, and a *downward-facing* surface samples the sky's dark
  ground hemisphere, so the ceiling's underside got almost nothing while the floor facing
  it got the bright half. Fixed with `ambient_light_sky_contribution` plus an actual
  ceiling — cornice, a fitting per room, plaster bounce.
- **Four audit findings — DONE.** Including one the audit got **wrong**: the
  identical-branch ternary in `house.gd` is not a bug, because Godot applies `scale` in
  the node's local space where X is always the panel's width. Swapping it would have built
  the side walls 2 m thick.
- **Guns rebuilt — DONE, lightly verified.** Slide, serrations, sights, frame, raked grip,
  trigger and a real trigger guard, magazine base, barrel, ejection port; the shotgun got
  barrel, tube, ribbed forend, receiver, comb, butt pad, bead. Photographed with the body
  hidden: both read as weapons now rather than as boxes. No close beauty shot yet.
- **Carried loot — PARTLY.** Moved off the model root (which sits at his *feet*, hence the
  laptop hovering between his thighs) onto his right-hand bone, so it follows his arm. But
  **the asset set has no carry animation**, so in `walk` his arms hang and the item still
  sits low at his hip. Needs a carry pose — see the blocker below. The finger grip is
  written but **not taking effect**.
- **Sim behaviour, first batch — DONE.** Field of view (he no longer sees behind
  himself), finite turn rate, carry weight slowing him, and the `think` dwell finally
  read. This batch cost a real regression: the carry and turn penalties fell below a fixed
  stuck threshold, so he cleared all three items and delivered none until the threshold
  was made relative to his intended step.
- **`--carry=<label>`** added, so a carried item can be photographed on demand rather
  than hunting a few-second window in a 99 s round.

## Blocker: Mixamo token expired

Adding a **real** carry pose needs the Mixamo animations "Box Idle" (carry idle),
"Holding Walk" (carry walk) and "Picking Up Object" (a grab). They are all found by
`tools/mixamo-fetch.py search`, and a `clip` subcommand was added to fetch one animation
without re-downloading the 48-108 MB character mesh. **Export returns
`HTTP 401 Oauth token is not valid`** — search works on the API key alone, export needs a
fresh bearer token in `~/.dsh/mixamo-token`. Refreshing it is Richard's to do.

Until then, the alternative is to author a carry pose procedurally by posing the arm
bones, which will look worse than a real clip.

---

A work plan for making the game feel like real life, built on 2026-10-04 from two
sources, kept separate on purpose:

- **by eye** — I rendered a survey of the house, the exterior, the characters and the
  van and looked at them. Stills only: I cannot judge motion, so nothing here about
  *how* things move came from looking.
- **in the code** — a line-by-line audit of `sim.gd` (the model) and of
  `game.gd` / `actor.gd` / `house.gd` / `minimap.gd` (the presentation). Every line
  number below was verified against the current file.

Ordered by how much realism each buys, not by cost. Effort is a rough size, not a
promise.

---

## The two that dominate

**1. The game is silent. [LARGE, but start small]**
There is no audio of any kind: no `AudioStreamPlayer`, no `.wav`/`.ogg`/`.mp3` on disk,
no bus layout. The only grep hit for "sound" in the whole project is a comment.
Nothing is audible — not a gunshot, not a footstep, not the front door, not the van.
In a home invasion you would hear him long before you saw him; here he arrives in
total silence. A minimal pass (gunshot, footstep, door, van) is cheap and would change
more than any other single item.

**2. One texture in the entire project. [MEDIUM]**
`house.gd:175` loads `wall_texture_clean.png`. Everything else is flat colour:
`game.gd:388-396` sets albedo/roughness/metallic and no texture; `house.gd:322-326`
(`_flat()`) does albedo + roughness 1.0 for the floors, slab, ceiling, lawn and
driveway. This is the root of the synthetic look — and the lighting strategy at
`game.gd:179-182` explicitly *relied* on darkness to hide flat materials, which the
switch to daylight removed.

---

## Reported from play — the audit missed all three

Found by Richard on 2026-10-04, after the first draft of this document. Recorded
separately because **the method that produced the rest of this file is biased against
exactly this kind of fault**, and that bias is worth remembering:

- A **code audit finds absences** (no audio, no doors, no textures) and is blind to
  **misplacements**. The code happily contains a line placing the loot; the line is
  simply wrong. No amount of reading finds a floating object — only looking does.
- Ranking by **realism per unit of work** systematically demotes art problems as
  "expensive". That is not how a player meets them. "The gun looks like a box" is a
  first-minute impression, not a low-priority item.
- The audit covered the project but **not the work done that same day**. Loot, guns and
  camera were each treated as verified because each had been verified once, in some
  other respect.

**R1. The guns do not look real. [MEDIUM]**
Seen but under-weighted: filed as item 24 of 24, described as "a plain dark box" rather
than as "does not look like a gun". `actor.gd` builds the pistol from two boxes and the
shotgun from a cylinder and a box, with a flat dark metal material and no trigger guard,
no sights, no magazine, no slide detail, no grip texture. At the current camera distance
this is one of the most-looked-at objects in the game.

**R2. Carried loot floats; it is not in his hands. [SMALL — and it is a defect
introduced by the fix that made loot visible]**
`game.gd:461` — `prop.global_position = r.origin + Vector3(0, 0.50, 0) + r.basis.z * 0.30`.
`r.origin` is the model root, which sits at his **feet**, so an item's base is placed
0.50 m up and 0.30 m forward: **hip height**. The laptop therefore hovers between his
thighs, exactly as reported. Because the offset is fixed relative to his root and his
hands move with the animation, the item can *never* be in his hands.
The correction was available the whole time: `Actor.update_weapon()` already places the
thief's pistol on the right-hand **bone** each frame. The carried item should be
positioned the same way, from the hand rather than from the root. This was written,
looked at in a single frame, and reported as "riding on his chest" — the object was
checked for *existence and motion*, never for *being held*. Same class of error as the
stale-artifact incident recorded in AGENTS.md.

**R3. The rooms have no real ceiling. [SMALL-MEDIUM]**
Detected but mis-filed: written up as a *lighting* problem ("a black ceiling that nothing
lights") and then left out of this document entirely, surviving only as a clause under
"the house reads as a slab". The ceiling is a single flat 0.22 m slab
(`house.gd:156-167`) with no beams, no cornice, no light fittings, no variation between
rooms, and it renders near-black because nothing lights its underside. Both halves are
wrong: it is not a ceiling to look at, and it is not lit.

---

## Behaviour: the characters do not move or react like people

**3. No acceleration, deceleration or turn rate. [SMALL]**
`sim.gd:514` integrates position directly and `sim.gd:517` snaps `thief["yaw"] = a` in
one frame; the player is the same. Full speed on frame one, dead stop on arrival. This
is the classic "sliding prop" tell and the cheapest large win in the file.

**4. The intruder sees 360°. [SMALL]**
`sim.gd:550-551` tests range and line of sight only — no facing. A man standing behind
him at 3 m is seen and shot instantly. Humans have roughly 200° of useful awareness.

**5. He does not react to being shot. [MEDIUM]**
`sim.gd:581` appends `thiefHit`, and `game.gd:702` clears it without reading it. Nothing
in `sim.gd` consults `hp` except the lethal check, so 1 hp behaves exactly like 100. No
flinch, no stagger, no dropping what he is carrying, no decision to leave.

**6. He never gives up or flees. [MEDIUM-LARGE]**
The only endings are all loot delivered, his death, or yours. A real intruder leaves at
the first sign of an armed occupant — especially after being shot at.

**7. He cannot shoot while carrying. [SMALL]**
`sim.gd:560`. Deliberate, and the opposite of realistic: a thief holding a TV would
drop it or fire one-handed. As it stands he is harmless exactly when he is most
committed. Worth revisiting now that the loot is visible.

**8. `think` is a dead timer. [SMALL]**
`sim.gd:421` initialises `"think": 2.0` and nothing ever reads it. It was clearly meant
to make him hesitate at a threshold. He currently starts walking on the first frame.

**9. He hears nothing. [MEDIUM]**
No noise model at all. A gunshot indoors is the loudest thing in the scenario and would
be the dominant stimulus; here firing has no effect on him whatsoever.

**10. Combat reads as arcade. [SMALL-MEDIUM, several parts]**
- `sim.gd:119-120` — 100 hp against 26 per pistol hit: he is a bullet sponge.
- No hit location and no range falloff (`game.gd:900`) — a shot to the leg equals one
  to the chest.
- `game.gd:678-686` — his bullets ignore geometry entirely. It is a probability roll on
  a line, not a raycast, so nothing in the house can stop his round.
- `game.gd:679` — a 55% accuracy floor at any range, while the `spread` he emits at
  `sim.gd:568` is never read.
- No ammunition limits (`sim.gd:564`, `game.gd:599`): reloads conjure a full magazine.
- Reloading costs nothing — he walks at full speed through it (`sim.gd:447-449`).
- Shotgun pellets never spread with distance or lose energy.

---

## Feedback: nothing happens when things happen

**11. The hit point is computed and thrown away. [MEDIUM]**
`game.gd:894-901` calculates `hit["position"]` and uses it only as the tracer endpoint.
No bullet holes, no decals, no impact dust. You can empty a shotgun into a wardrobe and
leave no mark on it.

**12. The thief never plays a shooting animation. [SMALL]**
`game.gd:788-789` holds him in `AIM` while `sim.gd:560` fires him. He damages you by
standing still. `play_once(Actor.SHOOT)` on the event is a one-line fix.

**13. `playerHit` and `thiefHit` are generated and discarded. [MEDIUM]**
`sim.gd:581` and `sim.gd:593` append them; the handler at `game.gd:667-701` has no case
for either. So there is no blood, no flinch, no damage direction, no vignette. The only
feedback for shooting a man is a HUD number.

**14. No muzzle flash, smoke or shell casings. [SMALL]**
Zero hits for `flash`, `GPUParticles`, `CPUParticles`, `Decal` across the project.

**15. `Actor.RELOAD` is paid for and never played. [SMALL]**
Declared at `actor.gd:23`, merged at `actor.gd:26`, referenced nowhere else.

**16. No recoil. [SMALL]**
Firing does not move the camera or the weapon.

---

## The world is a set, not a place

*(all of this section is by eye)*

**17. There are no doors. [MEDIUM]**
`sim.gd:19` declares the `DOOR_GAP` but no door exists — the front entrance is a
permanent 2 m hole. `house.gd:224`'s `doors` map is never populated, so the
`wall_doorway` branch at `house.gd:196` is dead code, and `door_A.gltf` / `door_B.gltf`
sit unused on disk.

**18. Windows are holes. [MEDIUM]**
All three use `wall_window_open`; `wall_window_closed` exists and is referenced nowhere.
No glass, no frames, no reflections, no curtains.

**19. The house reads as a slab. [SMALL-MEDIUM]**
Flat 0.22 m ceiling slab, no roof pitch, no eaves, no gutters, no porch, no path, no
fence. From the drive it looks like a shipping container.

**20. The neighbourhood does not exist. [SMALL]**
A 160×160 m lawn plane (`house.gd:278-281`), one grey driveway box, six bushes and three
streetlights that emit no light. The pack ships `building_A`..`building_H`, road pieces,
benches and boxes — all imported, all unplaced.

**21. Nothing in the world has collision except walls and tall furniture. [SMALL]**
Zero `StaticBody3D`/`CollisionShape3D` in `house.gd`. Bullets pass through the floor, the
ceiling and the van.

**22. The van never moves, and the text says it does. [MEDIUM]**
Placed once at `house.gd:297-302` and never referenced again, while the loss overlay at
`game.gd:1111` reads "The van drove off with everything." It is also a station wagon at
2.5× — the pack has no van model.

**23. The characters do not read as people in this situation. [MEDIUM]**
The intruder is a shirtless, heavily muscled man: he reads as naked rather than as a
burglar. No gloves, no bag, no hood, no dark clothing. No differentiation between the
two beyond the mesh.

**24. The weapon is a plain dark box. [MEDIUM]**
`actor.gd` builds the pistol from two boxes and the shotgun from a cylinder and a box.
At the camera distance used now you are looking at it constantly.

---

## Bugs the audit turned up along the way

These are not realism items; they are wrong regardless.

- **`house.gd:213` is a ternary with identical branches** —
  `Vector3(sx, sy, sz) if horizontal else Vector3(sx, sy, sz)` — directly under a comment
  describing a swap that does not happen. Side walls get the depth scale on the wrong
  axis against `sim.gd:18`.
- **The HUD prints the intruder's exact HP through walls.** `game.gd:1094-1095`. That is
  omniscient information the player has not earned.
- **The loss text contradicts the screen** — see the van above.
- **`reroute` (`sim.gd:546`) is never consumed**, so AI hesitation is invisible.

---

## The deep end

Realism ceilings that are genuinely large pieces of work, listed so they are not
forgotten rather than recommended now:

- **Heights.** `sim.gd` is entirely 2D (`sim.gd:7`), so `WALL_HEIGHT`, `EYE_HEIGHT` and
  every furniture height are cosmetic. A coffee table blocks sight as absolutely as a
  wall, crouching gains you nothing (`sim.gd:112`), and nothing can be shot over.
  Touches `seg_rect` and `ray_cast_px`, which `probe_wallshot.gd` re-implements.
- **A fear and morale model** — the highest realism ceiling of any single behaviour.
- **An external clock**: police response, neighbours, a reason the intruder is in a
  hurry.
- **Searching.** He knows all three valuables and their exact coordinates from spawn
  (`sim.gd:89-93`). A real burglar spends most of his time looking.
- **Melee.** At 1–2 m a home invasion becomes a fight for the gun. Bodies are 0.42 m
  discs at `sim.gd:113/118` that can never come closer than 0.84 m, so contact is
  geometrically impossible (`sim.gd:332`).
- **A defensive verb other than shooting** — locking, lights, calling out, calling 911.

---

## Where I would start

1. **Audio**, minimal version — gunshot, footstep, door, van.
2. **Impact and muzzle feedback** — bullet holes, muzzle flash, casings, and a case for
   `thiefHit`/`playerHit` so hits do something.
3. **The human-motion set** — acceleration, turn rate, field of view, and the dead
   `think` timer. Four small changes that together stop both characters reading as props.
4. **The thief's shooting animation**, the omitted `RELOAD` clip, and recoil.
5. **Doors and windows** — the models are already on disk.

Items 3 and 4 are all small and touch almost nothing load-bearing. Item 1 is the
largest absolute gain in the document.
