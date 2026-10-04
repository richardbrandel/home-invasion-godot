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
