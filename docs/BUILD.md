# Home Invasion — environment, builds, releases, Unreal

Extracted from the monolithic AGENTS.md on 2026-10-08. The two machines, how to reach
them, how to build and ship, and the Unreal setup.

## Development environment — TWO machines

This project is developed from a Mac and, since 2026-10-07, a Linux box that exists to be a
second target. **The game has been run and tested on both; a fresh clone on either works.**

| | Mac | Linux box |
|---|---|---|
| Access | local shell | `ssh ubuntu-dev` (wired) / `ssh ubuntu-dev-wifi` (fallback) |
| Godot | `~/.dsh/tools/godot/Godot.app/Contents/MacOS/Godot` | `~/.local/bin/godot` |
| Repo | `default-workspace/home-invasion-godot` | `~/dev/home-invasion-godot` |
| Assets | Mixamo present | **absent** (gitignored) — the actor suite skips |

**Linux box:** Ubuntu 26.04.1, kernel 7.0.0-38, Intel i3-8100 (4 cores), 22 GiB RAM,
938 GB disk, **RTX 5060 Ti 16 GB** on driver 610.57.04.

### The Mac's display session is fragile — know this before diagnosing a "crash"

**On 2026-10-08 the Mac looked like it had crashed overnight. It had not.** `uptime` still
read 7 days: **`WindowServer` aborted**, which black-screens the desktop and looks exactly
like a reboot, while the kernel, filesystem and every process kept running.

```
/Library/Logs/DiagnosticReports/WindowServer-2026-10-08-091357.ips
exception : EXC_CRASH, SIGABRT
asi       : CoreAnimation: failed to set internal panel mode!  abort() called
```

**The trigger is a display mode change, and the likely source is the KVM switch.** Richard
uses a KVM to move one monitor between machines; switching away detaches the display and
switching back makes macOS re-set the mode — the operation that aborted. **So a desktop
reset when switching BACK to the Mac is expected, not alarming.** Richard's mitigation is to
switch the KVM to a non-Mac machine when he leaves, so the unattended window is not spent
holding a fragile display session. The KVM is old and has no EDID emulation; that is accepted.

- **Nothing that matters lives in the display session.** The DSH GUI is served over HTTP on
  `127.0.0.1:3080`, so agent work continues through a WindowServer crash — demonstrated: the
  session kept working while the window server was still restarting.
- **The Mac keeps running with no display attached**, because `sleep 0` is set on AC power.
  "No monitor" is not a sleep trigger for this setting.
- **Do not reach for `log show` / `pmset -g log` on this machine without a limit.** A plain
  `log show --last 24h` ran 4+ minutes at ~99% of a core and pushed load average to ~10,
  which then looks like the machine is in trouble. It was self-inflicted. Kill it rather than
  let it finish, and prefer narrow predicates.

### The network, and the hour it cost

- **It is WIRED now, and that is a ~9x difference.** The wired port is an Intel I219-V
  (`e1000e`) at **1000 Mbit/s full duplex**. Measured 2026-10-07:
  **internet 51-58 MB/s wired against 5.7 MB/s on the old WiFi**, and
  **Mac→Ubuntu 94 MB/s against 1.9 MB/s**. That is what makes a ~120 GB Unreal download an
  hour instead of an overnight job, and it is why the wire is worth keeping.
- **The WiFi was a USB dongle, not onboard, and it was the whole bottleneck.** Interface
  `wlxe84e068926f3` — the `wlx` + MAC form is what Linux gives a **USB** adapter; an onboard
  chip would be `wlp*`. It is a **Ralink MT7601U (`mt7601u`), 2.4 GHz ONLY, 20 MHz**, so
  ~46 Mbit/s was its ceiling however good the signal looked. `lspci` shows **no PCI wireless
  device**, so there is no onboard radio being wasted. A dual-band dongle would be the
  upgrade if the wire ever goes away; the wire made it unnecessary.
- **THE TRAP: `netplan-eno1` shipped as `ipv4.method link-local`.** The installer never
  configured DHCP on the wired port, so plugging a cable in gave a **169.254.x.x address
  with no gateway and no route to anywhere**. NetworkManager then moved onto that interface,
  dropped WiFi, and the machine became completely unreachable — not at a new address, not
  answering at all. It needed a keyboard to recover. **A live link light and a working
  network are not the same thing.**
- **Fixed by `ipv4.method auto` on `netplan-eno1`.** Both profiles autoconnect with wired
  preferred and WiFi as fallback: `netplan-eno1` **metric 100**, `rb2` **metric 600**. Note
  the box's WiFi profile is genuinely named `rb2` (the SSID), not `netplan-*`.
- **Amber at the host end and green at the router is NOT a fault.** This NIC does that at
  gigabit — `dmesg` confirmed `NIC Link is Up 1000 Mbps Full Duplex` while the lights
  disagreed. Do not diagnose a link from its LEDs.
- Addresses: **wired `192.168.1.135`** for MAC `e0:d5:5e:d9:a2:11`, **WiFi `192.168.1.43`**.
  A **DHCP reservation** for the wired MAC was added on the router (`sax2v1s.lan`,
  `https://192.168.1.1`, an ASUS). **NOT PROVEN** — the box already held that address, so
  the reservation's effect has never been observed. If the address ever moves, that is why.
- **`ssh ubuntu-dev`** is an alias in the Mac's `~/.ssh/config`, keyed on
  `~/.ssh/id_ed25519_ubuntu`; **`ubuntu-dev-wifi`** points at the WiFi address. The WiFi
  alias times out while the wire is up, which is expected — WiFi is inactive then.
- **GENERAL RULE, learned the hard way: never change the network path you are reaching a
  remote machine by without a way back that does not need that network.** The failure mode
  is not "it might be slower" — it is a machine that needs physical hands.

### Remote access and sudo

- **`ssh ubuntu-dev`** is an alias written into the Mac's `~/.ssh/config`, keyed on
  `~/.ssh/id_ed25519_ubuntu`.
- **Passwordless sudo is installed** at `/etc/sudoers.d/010-richard-agent`. Without it no
  package can be installed from this Mac, because `sudo`'s password prompt cannot be
  answered non-interactively.
- **The Blackwell card needs the OPEN kernel modules.** Installing `nvidia-driver-610`
  produced `NVRM: ... requires use of the NVIDIA open kernel modules` and
  `RmInitAdapter failed` with `nvidia-smi` reporting no devices, on a card `lspci` could
  see. `nvidia-driver-610-open` is the fix. **A prebuilt module package built for a
  different kernel ABI can be silently loaded** — the box booted kernel 7.0.0-38 while
  the only installed modules were for 7.0.0-30, and the driver loaded and failed to find
  the card. Check `uname -r` against the module package version before believing a GPU is
  broken.
- Godot on Linux is the **same 4.7.2 build hash** (`ed1daf0bf`) as the Mac, so a test that
  passes on one is meaningful on the other.
- **Verified cross-platform on 2026-10-07**: sim 100/100 and heist 7/7 on BOTH machines,
  with identical reroute counts. The actor suite skips on Linux for want of Mixamo assets.

**Publishing state.** The public repo was **14 commits behind this Mac** until
2026-10-07 — the ceilings, door, skirting, all seven animations, the grip work and the
furnishing had never been pushed, so a fresh clone got a 2 m-ceiling build from the
evening of 2026-10-04. Both are level now (`87c5c44`). **After any work session, check
`git status` / `git log origin/main..HEAD` before assuming the remote has it** — the
habit that caused this was committing locally and never pushing.

**Unreal is a second, deferred target — and the spike is DONE.** Richard asked for the game
to be built in Unreal as well; the agreed order is to finish proving the design in Godot
first, because the port discards the test suites and the probe-based verification loop that
catch the bugs above, and because a port is much cheaper once the rules have stopped moving.
The Linux box is the Unreal machine. **It works, and a headless verify loop exists** — see
the next section. The old `glibc 2.43 is too new` worry was WRONG and is recorded below.

## Unreal Engine on the Linux box — measured 2026-10-08

| | |
|---|---|
| Engine | **UE 5.8.3**, `release` branch, at `/data/UnrealEngine` |
| Path | reached as `/home/richard/UnrealEngine` via a **bind mount** (paths unchanged) |
| Compiler | **clang 20.1.8** — the exact version Epic specifies, from the Ubuntu repos |
| Editor build | **4 h 37 min** (16,638 s), 5,718 actions, 4 cores balanced (load 4.2) |
| Project build | **74 s** for a 4-file module — so *iteration* is cheap, only the engine is slow |
| Disk | engine 160 GB on `/data`; `sda` holds only 22 GB |

**The glibc fear was wrong.** Epic's own docs say `Setup.sh` "automatically downloads a
native toolchain... you compile against a **fixed sysroot**", so the host's glibc is
irrelevant. Required: kernel 4.18+, **glibc 2.28+**, clang 20.1.8. This box has glibc 2.43
and kernel 7.0 — comfortably inside. Verified in the
[Linux development requirements](https://dev.epicgames.com/documentation/en-us/unreal-engine/linux-development-requirements-for-unreal-engine).

### Four traps, all hit for real

- **`Build.sh` does NOT build UnrealBuildTool by default.** It only does so when `-buildubt`
  is passed. Without a prebuilt UBT the build dies with
  `dotnet ...UnrealBuildTool.dll does not exist`. Run it once as
  `Build.sh UnrealEditor Linux Development -buildubt`, or build UBT directly.
- **`-FromMsBuild` SKIPS the UBT compile step.** Passing it early just fails. It is only
  valid once UBT exists.
- **A direct `dotnet build` of UBT puts the output in the project's `bin/`**, but `Build.sh`
  reads `Engine/Binaries/DotNET/UnrealBuildTool/`. The output folder is self-contained
  (90 files), so copying `Engine/Source/Programs/UnrealBuildTool/bin/Development/net10.0/`
  into `Engine/Binaries/DotNET/UnrealBuildTool/` fixes it.
- **`-TestExit` HARDCODES exit status 1.** `LogCore: FUnixPlatformMisc::RequestExit(1, ...)`.
  Measured: a run with one failing test and a run with only passing tests **both returned 1**.
  The editor's exit code is therefore NOT a verdict, and anything that trusts it is wrong.

### The verify loop — `~/tools/ue-run-tests.sh` on the Linux box

```sh
run_tests.sh <uproject> <test-filter>
```

`-ExecCmds="Automation RunTests <filter>" -unattended -nopause -NullRHI -nosplash
-TestExit="Automation Test Queue Empty" -stdout -abslog=...`, then it **parses the log** for
`Result={Success}` / `Result={Fail}` and exits accordingly. Measured on a purpose-built
project with one passing and one deliberately failing test:

| case | tests | exit |
|---|---|---|
| one passing, one failing | 2 | **1**, and it names the failing test |
| passing only | 1 | **0** |
| **filter matches nothing** | **0** | **1** |

**That last row is the point.** Zero tests is a FAILURE, so a typo'd filter cannot produce a
green tick. This project has repeatedly been burned by "pass-shaped nothing" — the
`draw_primitive` parse error that made the minimap stop loading, the `pgrep` matching its own
command — so the wrapper refuses it by construction.

**Two quoting rules, learned the hard way over ssh:** inner quotes on an argument containing
spaces (`-TestExit="Automation Test Queue Empty"`) do NOT survive the trip through `ssh` and
must be escaped; and nested heredocs through `ssh` silently truncate — write files locally and
`scp` them instead.

**`pgrep -f <pattern>` MATCHES THE COMMAND CONTAINING THE PATTERN.** This bit three times in
one session: `pgrep -f "GitDependencies"`, `pgrep -f "UnrealEditor-Cmd"` and
`pgrep -f "UnrealBuildTool"` all reported a live process that was in fact the `ssh` invocation
carrying that string — once leading to a false "WARNING: deps still running" and an
unnecessary aborted copy. **Use `ps -eo comm | grep -x` (exact name) or a size/mtime comparison
instead.** A check that cannot fail is not a check.

## Assets and licensing

`assets/mixamo/` is **not committed**. Mixamo's terms permit commercial use *in a
game* but forbid redistributing the raw assets, and `idle.fbx` is 106 MB — over
GitHub's 100 MB per-file limit, so it could not be pushed anyway.

A fresh clone therefore runs with no characters: exit 0 and two self-describing
errors. That is the expected state, not a bug. The *published builds* legitimately
contain the assets.

Restore them with Richard's own free Mixamo account:

```sh
python3 tools/mixamo-fetch.py fetch assets/mixamo both
```

The token lives at `~/.dsh/mixamo-token` (mode 600). Never print it.

Characters are built from one mesh-carrying file plus eight animation-only files
merged at runtime, which took the asset set from 1.3 GB to 161 MB.

## Releases

`export_presets.cfg` holds preset 1 (Windows Desktop, embedded PCK) and preset 0
(macOS). Both `import_etc2_astc` and `import_s3tc_bptc` must stay enabled in
`project.godot`, or the macOS export fails with *"Cannot export for universal or
arm64 if ETC2 ASTC texture format is disabled"*.

Build outputs are far over GitHub's 100 MB file limit and ship as **Release
assets**, never as commits. The engine is embedded, so players need no Godot.

Builds are unsigned. macOS needs right-click → Open once; Windows shows a
SmartScreen warning. **Never name the outside playtester in this public repository** — the
pre-commit hook refuses any staged addition that does, and that hook exists because the rule
was already broken once and had to be scrubbed from history.

**A copied build goes stale, and someone will end up playing the wrong one.** On
2026-10-03 that happened: a report came back that body collision still did not work,
and the cause was that the app being launched was a copy made **20 minutes before the
collision fix existed**. The fix was correct and already covered by tests — the
artifact was simply old.

Two mechanical fixes, so this cannot recur:

- The workspace-root `Home Invasion.app` is a **symlink** into `build/`, so a rebuild
  updates what gets double-clicked automatically. It was a real copy before.
- For anything interactive prefer `./run.sh`, which runs the *project* rather than an
  export and so is never stale by construction.

The general rule: after any behavioural fix, **refresh every artifact a human might
launch**, not just the one the release pipeline produces.

