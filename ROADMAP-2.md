# Improvement list 2

Started 2026-10-04, after v1.4 shipped. Same process as last time: I list, Richard
adds.

**How this list was made.** Last round I audited the *code* first and ranked by
"realism per unit of work", which systematically demoted art problems — and I
found absences rather than misplacements. So this time I rendered six
representative views, looked at them, measured two of the complaints, and only
then read the source. Items 1-10 are all things a code audit would not have
surfaced. Sizes are my estimate of effort, not importance.

---

## A. Why it still looks like a game rather than a place

**1. The ceilings are too low, and it dominates every interior view. [SMALL]**
Measured: the flat ceiling band fills **66% / 57% / 54%** of the upper frame in
three different rooms. The walls are `WALL_TARGET_H = 2.0 m` against a 1.65 m
eye — the ceiling is 35 cm above your head, so at a 68° field of view most of
what you see is ceiling. A real house is 2.4-2.7 m. **One constant, and it would
change every interior shot in the game.** This is the highest-value item here.

**2. The characters are shiny mannequins. [LARGE]**
The homeowner is a low-poly mesh with a **specular blob for hair** and no facial
detail; the intruder is a featureless black silhouette. This is the "looks like
Roblox" complaint and it is the thing you look at most. Materials (hair, skin)
are the cheap half; a properly clothed mesh is the expensive half.

**3. The walls are one flat colour with a stripe. [SMALL-MEDIUM]**
The KayKit wall pieces stack with a visible horizontal seam running the length of
every room at eye level. No skirting boards, no picture rail, no door architraves,
no trim of any kind.

**4. The living room floor is a black-and-white checkerboard. [SMALL]**
It reads as a missing texture even if it is deliberate. Nothing else in the house
uses it.

**5. The windows are holes with pale interiors. [MEDIUM]**
No exterior frames, no sills, no glazing catch, no curtains or blinds. From
outside they are flat inset rectangles; inside they are bright rectangles.

**6. The outside is a slab with a heavy lid. [MEDIUM]**
The eaves overhang far too much and the roof is a thick dark cap. No porch, no
gutter or downpipe, no path to the door, no fence, no plinth where the wall meets
the ground.

**7. Interior light is flat. [SMALL-MEDIUM]**
Everything reads at the same brightness. The practicals glow but throw almost no
contrast, so rooms have no depth.

**8. Sockets, switches, thermostats, light fittings — none. [SMALL]**
Nothing on the walls at all except the windows.

## B. It is a house, but not yet a home

**9. The rooms are sparsely furnished. [MEDIUM]**
The living room has a sofa, a lamp, a cabinet and a TV. No bookshelf, rug, plants,
wall art, shelves, photographs, or clutter. It reads as a show home, which makes
"steal three valuables" feel arbitrary.

**10. The valuables don't read as valuable. [SMALL]**
The TV is a small dark slab. Nothing about it says "this is worth carrying out of
the house".

**11. No small props at all: coats, shoes by the door, keys, a kettle, a phone. [SMALL]**
Nothing that says a person lives here.

## C. The people still do not move like people

**12. The seven fetched animations are not wired in. [SMALL-MEDIUM]**
`carry_walk`, `carry_idle`, `pickup`, `look_around`, `push`, `shove_react`,
`hit_react` are downloaded and verified but referenced nowhere. This immediately
replaces my hand-built carry pose, animates the search, and gives both shoves and
the hit reaction real clips. Cheapest real improvement on this list.

**13. No animation blending. [MEDIUM-LARGE]**
`AnimationTree` is absent: clips cut rather than blend. The `_strip_to_upper_body`
hack is why — a proper blend tree would let aim and shoot overlay locomotion
instead of replacing it.

**14. Feet skate, and there is no foot IK. [MEDIUM]**
The walk clip plays at a speed matched to movement, but feet do not plant on
stair-edges or stop against walls.

**15. No idle variation. [SMALL]**
He stands in exactly one pose.

**16. No voice at all. [MEDIUM]**
A real home invasion is *loud* — shouting, a challenge, a shouted answer. There is
no speech and no barks. Synthesised audio cannot do voices; this needs either
recording or a barking system with a different source.

## D. Things you cannot do

**17. Only one non-lethal verb (the shove). [MEDIUM]**
No locking or barricading a door, no turning lights on or off, no calling out, no
calling the police deliberately rather than by firing.

**18. The simulation is 2-D. [LARGE]**
`sim.gd` has no elevation, so the intruder cannot see over or under anything.
Your own shooting is already genuinely 3-D, so this mostly costs the AI. Would
matter in a house with a landing.

## E. Feedback and polish

**19. No blood or wounds. [SMALL-MEDIUM]**
A hit produces a bullet hole and a stagger. Nothing on the person.

**20. No audio mixing. [SMALL]**
Everything plays on Master — no buses, no indoor reverb versus outdoor, no ducking.

**21. No reflections or global illumination. [MEDIUM]**
Flat ambient only.

**22. The minimap is crude. [SMALL]**
A dark rectangle with a small map in it, and it has a known triangulation warning
from some positions.

---

# Richard's additions (2026-10-04)

**23. The guns don't look like real guns. [MEDIUM]**
They were rebuilt from primitives once and read better than two boxes, but they
are still boxes and cylinders.

**24. The thief is now all black with no detail. [SMALL-MEDIUM]**
He "looked like a zombie, which was OK" before; darkening the whole body material
to make him read as a burglar went too far and threw away all his detail. Needs
dark clothing that still SHOWS something — form, seams, a bit of contrast —
rather than a uniform silhouette.

**25. The front door is a green thing hanging in the middle of the doorway. [SMALL]**
Confirmed by eye: the leaf is too narrow and too tall, sits centred instead of on
a hinge, has no frame, and its colour is wrong.

**26. The previous round's result shows up in the next round, in big letters. [BUG]**
Suspect the end-of-round overlay or the banner is not being cleared by `reset()`.

**27. The gun hangs off the homeowner's wrist; it should be gripped by the fingers. [MEDIUM]**
The finger grip has never worked — `Actor.grip()` writes `set_bone_pose_rotation`,
which was MEASURED to move a bone 0.039 m against a 0.023 m control. The route
that works is a persistent global override, as `scripts/carry_pose.gd` now proves.

**Ceilings: raise to 3.0 m.** Confirmed by Richard, and higher than the 2.4-2.7 m
I proposed. Note this also relaxes the `CAM_UP` cap described in `AGENTS.md`,
which was bounded by the 2.0 m wall height.

---

# Status, 2026-10-04 end of session

Twelve commits since v1.4. Latest build `Home Invasion.app` 21:15, **not published** —
Richard has asked for local test builds only for now. Suite state: **91 sim, 41 actor,
heist 7/7, wallshot clean.**

## Done

| # | Item | Notes |
|---|---|---|
| 1 | Ceilings 3 m | `WALL_TARGET_H` + `Sim.WALL_HEIGHT`. Ceiling went from 54-66% of the frame to a strip. |
| 4 | Checkerboard floors | TWO of them. `rug_rectangle_A`'s own texture, and KayKit's `floor_kitchen`. New generated `floor_tile.png` for the kitchen. |
| 6 | Exterior | Fascia + gutter (the overhang was never the problem), plinth, path to the door. |
| 7 | Interior lighting | Every practical was at the OLD 2 m ceiling, hanging in mid-air. Raised to 2.7-2.8; floor lamp tightened from energy 5.0/range 4.5. |
| 12 | Animations wired | All seven. Carry pose is now the fallback, not the mechanism. |
| 23 | Guns | Material CONTRAST (blued slide vs polymer frame vs rubber grip), slide corrected 32x46 -> 25x30 mm, controls added. |
| 24 | Thief detail | Body multiplier 0.24 -> 0.34. Kit pieces given different tones. |
| 25 | Front door | Was 55 x 95 CM. Measured the model: 1.60 x 2.80 m at source. Now 0.96 x 2.04, hinged at the edge, own material, lintel above (3 m walls had left a 3 m hole). |
| 26 | Overlay text | The labels were children of `layer`, not of `_overlay`, so hiding the panel left "FAILURE" burned on screen into the next round. |
| 27 | Finger grip | LOCAL finger rotation. A global override per joint breaks the chain and stretches the fingers into noodles. |
| 3 | Skirting | A board around every wall run, footprint + 3 cm so it reads on both faces. |
| 9/11 | Furnishing | 15 floor-standing decor pieces in `Sim.DECOR`, which is NOT solid. |

## Partly done

- **2** characters are shiny mannequins. The intruder is better; the HOMEOWNER is still a low-poly mesh with a specular blob for hair. The real fix is a clothed mesh.
- **3** walls still carry the KayKit horizontal seam. Skirting helped; no picture rail or architraves.
- **5** windows have sills, heads and curtains now. The glazing is still a pale opaque panel from outside.
- **10** the TV reads better but the valuables are still primitive shapes.
- **11** some props; not coats, keys, phones, kettles.

## Not started

**8** sockets/switches, **13** animation blending (the `_strip_to_upper_body` hack is the blocker),
**14** foot IK, **15** idle variation, **16** voice, **17** more non-lethal verbs,
**18** the 2-D simulation, **19** blood, **20** audio buses, **21** reflections.

## 22 - the minimap, and it is also BACKWARDS

Richard reported on 2026-10-04 that the minimap is mirrored, and asked to leave it for now.
It ALSO throws `Invalid polygon data, triangulation failed` on about half of all frames.

A fix was attempted and REVERTED: a minimum-separation filter on the polygon points, on the
theory that `Sim.visibility_polygon`'s `a +/- 1e-4` corner triplets create zero-area slivers.
It made no difference (141 failures in 300 frames, unchanged). So sliver removal is NOT the
cause. The next move is to DUMP THE ACTUAL POLYGON on a failing frame and find which edges
cross, rather than theorising from the generator. A radial fan built from a sorted angle list
can also contain duplicate angles from shared corners.

## How to resume

Read `AGENTS.md` first — it carries every expensive-to-rediscover invariant. Then this file.
Then `git log --oneline v1.4..HEAD` for what the twelve commits actually did.

Do NOT trust v1.4 or the published release as a description of the current game.
