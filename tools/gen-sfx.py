#!/usr/bin/env python3
"""Generate the game's sound effects procedurally.

The project had NO audio of any kind — no AudioStreamPlayer, no sound file on disk, no
bus layout. Nothing was audible: not a gunshot, not a footstep, not the front door.

There is no sound library to download here either. So these are synthesised. That works
better than it sounds like it should for this particular set, because the sounds a
home invasion is made of are mostly noise transients — a gunshot is a crack with a fast
decay over a low thump, a footstep is a filtered click, an impact is a soft thud. The
one thing synthesis is bad at, a human voice, is not here.

Everything is 16-bit mono 44.1 kHz PCM so Godot imports it with no plugin and no codec.

    python3 tools/gen-sfx.py
"""
import math
import pathlib
import random
import struct
import wave

SR = 44100
OUT = pathlib.Path("assets/audio")


def write(name: str, samples: list) -> None:
    p = OUT / f"{name}.wav"
    p.parent.mkdir(parents=True, exist_ok=True)
    data = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32000)) for s in samples
    )
    with wave.open(str(p), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print(f"  {name:<18} {len(samples) / SR:5.2f}s  {len(data) // 1024:>4} KB")


def gunshot(dur=0.40, crack=52.0, body=95.0, body_decay=15.0, body_amt=0.85,
            lp_k=0.55, tail=0.07, seed=1) -> list:
    """A crack over a low thump, with a short room tail.

    lp_k is the one-pole low-pass coefficient: lower is duller, which is what makes the
    distant (heard-through-a-wall) variant sound far away rather than just quiet.
    """
    rnd = random.Random(seed)
    n = int(SR * dur)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / SR
        white = rnd.uniform(-1, 1)
        lp += (white - lp) * lp_k
        out.append(
            lp * math.exp(-t * crack) * 1.15
            + math.sin(2.0 * math.pi * body * t) * math.exp(-t * body_decay) * body_amt
            + rnd.uniform(-1, 1) * math.exp(-t * 6.0) * tail
        )
    return out


def footstep(seed=7) -> list:
    rnd = random.Random(seed)
    n = int(SR * 0.17)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / SR
        white = rnd.uniform(-1, 1)
        lp += (white - lp) * 0.33
        out.append(
            lp * math.exp(-t * 72.0) * 0.75
            + math.sin(2.0 * math.pi * 115.0 * t) * math.exp(-t * 42.0) * 0.32
        )
    return out


def impact(seed=11) -> list:
    """Flesh. Soft, low, no crack — the opposite of the gunshot."""
    rnd = random.Random(seed)
    n = int(SR * 0.26)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / SR
        white = rnd.uniform(-1, 1)
        lp += (white - lp) * 0.16
        out.append(
            lp * math.exp(-t * 32.0) * 0.65
            + math.sin(2.0 * math.pi * 68.0 * t) * math.exp(-t * 20.0) * 0.55
        )
    return out


def door(seed=23) -> list:
    """A latch giving way, then the slab swinging. Creak is a swept sine."""
    n = int(SR * 0.85)
    out = []
    rnd = random.Random(seed)
    phase = 0.0
    for i in range(n):
        t = i / SR
        # latch: a hard click right at the start
        click = rnd.uniform(-1, 1) * math.exp(-t * 130.0) * 0.9
        # creak: frequency sweeps upward, amplitude wobbles
        f = 240.0 + 600.0 * min(t / 0.6, 1.0)
        phase += 2.0 * math.pi * f / SR
        creak = math.sin(phase) * math.exp(-t * 3.0) * 0.10
        creak *= 0.6 + 0.4 * math.sin(2.0 * math.pi * 11.0 * t)
        # the slab settling
        settle = math.sin(2.0 * math.pi * 55.0 * t) * math.exp(-t * 9.0) * 0.22
        out.append(click + creak + settle)
    return out


def van(seconds=3.0, seed=31) -> list:
    """A diesel idle, built to loop: whole numbers of cycles at the loop frequency."""
    rnd = random.Random(seed)
    n = int(SR * seconds)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / SR
        white = rnd.uniform(-1, 1)
        lp += (white - lp) * 0.05
        # 30 Hz firing order plus its second harmonic — whole cycles across the loop
        base = math.sin(2.0 * math.pi * 30.0 * t) * 0.35
        base += math.sin(2.0 * math.pi * 60.0 * t) * 0.16
        out.append((base + lp * 0.28) * 0.9)
    return out



def siren(dur=3.0, lo=620.0, hi=1180.0, wail=1.4, seed=7) -> list:
    """A two-tone wail: the sound that ends the round if you start shooting.

    Distance does the rest of the work — it is played through an AudioStreamPlayer3D out on
    the street, so it arrives from where the police actually are rather than on top of you.
    """
    rnd = random.Random(seed)
    n = int(SR * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        # a slow triangle sweep between two pitches
        w = 0.5 - 0.5 * math.cos(2.0 * math.pi * t / wail)
        f = lo + (hi - lo) * w
        phase += 2.0 * math.pi * f / SR
        v = math.sin(phase) + 0.35 * math.sin(phase * 2.0)
        # a horn is not a pure tone; a little noise makes it read as a speaker
        v += 0.06 * rnd.uniform(-1.0, 1.0)
        env = min(1.0, t / 0.12) * min(1.0, (dur - t) / 0.35)
        out.append(v * env * 0.42)
    return out


def main() -> None:
    print("writing assets/audio/")
    write("gunshot_pistol", gunshot(dur=0.36, crack=58.0, body=110.0, body_decay=18.0,
                                    body_amt=0.75, seed=1))
    write("gunshot_shotgun", gunshot(dur=0.62, crack=34.0, body=68.0, body_decay=9.0,
                                     body_amt=1.0, lp_k=0.42, tail=0.13, seed=2))
    # No separate "distant" variant: the intruder's shots are played through an
    # AudioStreamPlayer3D, so distance and walls do the attenuating. A second, duller
    # sample would be an unused asset the moment 3D audio worked.
    write("footstep", footstep())
    write("impact", impact())
    write("door", door())
    write("van_idle", van())
    write("siren", siren())
    print("done — these are synthesised, not recorded, and are deliberately short")


if __name__ == "__main__":
    main()
