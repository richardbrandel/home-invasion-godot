# Home Invasion — animation, characters, audio, textures

Extracted from the monolithic AGENTS.md on 2026-10-08. Read this before touching
`actor.gd`, bones, clips, sound or generated textures.

## Audio

- **There was none at all until 2026-10-04** — no `AudioStreamPlayer`, no sound file, no
  bus layout. Before adding anything, note that **`assets/audio/*.wav` must be imported**
  (`Godot --headless --path . --import`) or `ResourceLoader.exists()` returns false and
  every sound silently fails to load with only a warning.
- The samples are **synthesised**, by `tools/gen-sfx.py`, not recorded. There was no
  library to fetch and the Mixamo token is expired anyway. It suits this set — a gunshot
  is a noise transient over a low thump and a footstep is a filtered click — but it would
  not work for a voice. Regenerate with `python3 tools/gen-sfx.py`.
- **Setting `loop_mode` on an `AudioStreamWAV` is not enough.** The loop region defaults
  to an EMPTY span, so the stream plays nothing at all — the van idle was silently
  absent. `loop_begin` and `loop_end` must be set too
  (`loop_end = int(get_length() * mix_rate)`).
- **You can verify audio without hearing it.** `--write-movie` writes a `.wav` of the mix
  next to the frames. Analyse it: transients, their spacing, and whether any window is
  *exactly* zero. That last test is how the silent van was caught — 211 of 499 windows
  were exactly zero, which nothing continuous can produce. It is the audio equivalent of
  the control-render trick used for screenshots.
- The player's own gun is a plain `AudioStreamPlayer` (it is at the listener); everything
  in the world goes through a pool of `AudioStreamPlayer3D` so the intruder's shots come
  from the intruder and are attenuated by distance.

## Textures

- **The project had exactly ONE texture** (the recoloured wall atlas) until 2026-10-04.
  Everything else was a flat albedo colour, which was the root of the synthetic look — and
  the lighting was originally designed to hide that in darkness, so the switch to daylight
  exposed all of it at once.
- `tools/gen-textures.py` generates the floor, lawn, driveway, ceiling plaster and roof
  shingle. **They must tile**: a floor is one large surface, so a visible seam grid is worse
  than the flat colour it replaces. Tiling comes from building the variation out of
  **integer-frequency sinusoids**, which repeat exactly across the image, plus a
  per-pixel grain too fine to read as a seam. Check any new one by differencing the wrap
  edges, as the generator's verification does.
- Like the audio, **new textures must be imported** (`Godot --headless --path . --import`)
  or `load()` returns null and `_textured()` warns and falls back to grey.

## Posing bones by hand

- **`set_bone_pose_rotation` is nearly useless for posing an arm; use
  `set_bone_global_pose_override`.** Measured by `test/probe_pose.gd`, on the right shoulder
  with the walk clip playing:
  - control, two frames of animation alone: the hand moves **0.023 m**
  - `set_bone_pose_rotation`: the hand moves **0.039 m** — barely above the control
  - `set_bone_global_pose_override`: the hand moves **0.562 m**, 25x the control

  So there IS a route to a carry pose. `Actor.grip()` writing a local rotation is why the
  finger grip has never visibly done anything.
- **Always measure a control.** The walk clip moves the hand every frame on its own; without
  that number every write looks like it worked. This probe's first version reported
  "moved 0.0000 m" for a bone that had plainly moved, because it re-read the baseline every
  frame — and its second version would have called a 0.039 m local nudge a success.
- **A SkeletonModifier3D is the place it has to happen.** The AnimationPlayer rewrites every
  animated bone during its own pass, so a pose written from `_process()` is gone before the
  frame is drawn no matter what `process_priority` says.
- **Do not search blindly for the right local rotation.** `test/probe_carry.gd` did, and kept
  selecting rotations about the bone's own length axis, which move nothing — the "best"
  answer it found was the rest pose, unchanged. Sweep the RESULTING HAND POSITION instead:
  `test/probe_carrypose.gd` tries candidate aim directions and prints where the hands land,
  which is a number you can judge, rather than a rotation you cannot.
- **The global override must be PERSISTENT.** With `persistent = false` the skeleton's own
  update consumes it and the bone CREEPS toward the target over tens of frames instead of
  taking it. Measured: the upper-arm segment moved from (-0.41, -0.91, 0.09) to only
  (-0.39, -0.86, 0.32) after twenty frames of asking for (0.22, -0.30, 0.93). With
  `persistent = true` it lands exactly, on the next frame.
- **`scripts/carry_pose.gd` is the working example**: a `SkeletonModifier3D` that aims both
  upper arms so the hands come in front of the chest. `CARRY_HANG` in `game.gd` was re-tuned
  when it landed — those offsets used to do ALL the work and now double-compensate.

## The characters' appearance

- **The intruder wears a kit: beanie, gloves, holdall** (`Actor.attach_kit()` /
  `update_kit()`), built from primitives and ridden on the bones exactly as the weapons are.
  It lives BESIDE `root`, never under it — a hidden ancestor hides every descendant, and the
  model is hidden when the camera jams behind the player.
- **`update_kit()` must run AFTER the animation writes the pose.** A bone global read earlier
  is last frame's, which makes the hat lag and swim on his head.
- **The body material is darkened, and that is the part that matters.** The mesh is bare skin
  from the collarbones down, so a hat and gloves alone leave a naked man wearing a hat.
  Darkening the material takes the face too, which is what makes it read as a balaclava.
  Only `root` is walked, so the weapons on the holder beside it are untouched, and the
  override is guarded against a second application.
- The homeowner gets NO kit. A man in his own house already looks like one, and the point is
  that the two are not confusable.

## The seven fetched animations — WIRED IN 2026-10-04

Fetched while the Mixamo token was live. They are on disk in `assets/mixamo/<character>/`
and **all seven are now referenced** — they are keys in `CLIP_FILES` in `actor.gd`, and
that list is what makes a clip available.

| File | Animation | Length | Wired to |
|---|---|---|---|
| `carry_walk` | Holding Walk | 1.37 s | the thief walking while laden |
| `carry_idle` | Box Idle | 6.30 s | the thief standing while laden |
| `pickup` | Picking Up Object | 3.43 s | the grab, playing the 1.3 s stoop window |
| `look_around` | Nervously Look Around | 6.27 s | the search dwell and the 2 s threshold pause |
| `push` | Push | 8.00 s | BOTH shoves |
| `shove_react` | Shove Reaction | 3.00 s | being shoved |
| `hit_react` | Hit Reaction | 1.83 s | being shot |

**The carry pose (`scripts/carry_pose.gd`) is now the FALLBACK, not the mechanism.**
`CARRY_WALK`/`CARRY_IDLE` hold the load properly, so `game.gd` only applies the hand-built
pose when `has_clip(Actor.CARRY_WALK)` is false — a fresh clone with no Mixamo assets. Both
at once double-compensates; `CARRY_HANG` was re-tuned when the pose landed for the same
reason.

**`push` is 8 seconds and you want about a quarter of a second of it.** Measured from its
keyframes: the arm thrust is a sharp four-frame window at **t = 0.33–0.43 s**, peaking at
496 deg/s at **t = 0.37 s**, with a second occurrence at 7.33 s. Play the window, exactly as
`SHOOT` seeks to 0.36 s and holds 0.42 s. Do not judge it by its length — I nearly discarded
it as a crate-pushing loop and it is the strongest thrust of every candidate measured.

**Measure more than one joint.** `hit_react` looks dead if you only watch the right forearm
(one keyframe), but 15 of its 53 tracks animate and the busiest is the Hips with 56 keys — it
is a full-body lurch, which is what a hit reaction should be. A single-track probe gave the
wrong answer confidently.

