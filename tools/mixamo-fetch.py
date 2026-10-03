#!/usr/bin/env python3
"""Fetch Mixamo characters and animations.

Reverse-engineered from the MIT-licensed unity-mcp-mixamo server
(https://github.com/HaD0Yun/unity-mcp-mixamo). The token is read from
~/.dsh/mixamo-token and is NEVER printed — not in errors, not in progress.

Mixamo's API needs three headers:
  X-Api-Key: mixamo2        (search works with only this)
  Authorization: Bearer ... (required to export)
  X-Requested-With: XMLHttpRequest

Usage:
  mixamo-fetch.py search  <query> [type]
  mixamo-fetch.py fetch   <outdir>
"""
import json
import os
import pathlib
import sys
import time
import urllib.parse
import urllib.request

API = "https://www.mixamo.com/api/v1"
TOKEN_FILE = pathlib.Path.home() / ".dsh" / "mixamo-token"


def token() -> str:
    return TOKEN_FILE.read_text().strip()


def _headers(with_auth: bool) -> dict:
    h = {
        "X-Api-Key": "mixamo2",
        "X-Requested-With": "XMLHttpRequest",
        "Accept": "application/json, text/javascript, */*",
    }
    if with_auth:
        h["Authorization"] = f"Bearer {token()}"
    return h


def call(method: str, path: str, body=None, with_auth=True, raw=False):
    url = API + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers=_headers(with_auth))
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            payload = r.read()
            return payload if raw else json.loads(payload)
    except urllib.error.HTTPError as e:
        detail = e.read()[:200].decode("utf-8", "replace")
        # never let a token reach the output
        detail = detail.replace(token(), "***")
        raise RuntimeError(f"HTTP {e.code} on {method} {path}: {detail}")


def search(query: str, kind: str = "Motion,MotionPack", limit: int = 12):
    qs = urllib.parse.urlencode({
        "page": 1, "limit": limit, "order": "relevance",
        "type": kind, "query": query,
    })
    return call("GET", f"/products?{qs}", with_auth=False).get("results", [])


def characters(limit: int = 24):
    qs = urllib.parse.urlencode({"page": 1, "limit": limit, "order": "relevance",
                                 "type": "Character", "query": ""})
    return call("GET", f"/products?{qs}", with_auth=False).get("results", [])


def details(anim_id: str, char_id: str) -> dict:
    return call("GET", f"/products/{anim_id}?character_id={char_id}")


def export(char_id: str, anim_id: str, name: str, fmt="fbx7_2019", skin=True) -> str:
    """Queue an export, then poll the CHARACTER monitor for the result URL.

    Two things the first attempt got wrong: the queue response carries a `uuid`
    (not id/job_id), and progress is read from /characters/<id>/monitor, which
    reports `status` and finally `job_result`. Mixamo also rate limits hard, so
    the queue call retries with backoff on 429.
    """
    d = details(anim_id, char_id)
    gms = d.get("details", {}).get("gms_hash", {})
    params = gms.get("params", [])
    if isinstance(params, list):
        pv = [str(p[1]) if isinstance(p, list) else str(p) for p in params]
        pstr = ",".join(pv) if pv else "0"
    else:
        pstr = str(params)
    trim = gms.get("trim", [0, 100])
    if not (isinstance(trim, list) and len(trim) >= 2):
        trim = [0, 100]

    payload = {
        "character_id": char_id,
        "product_name": name,
        "type": d.get("type", "Motion"),
        "preferences": {"format": fmt, "skin": str(skin).lower(), "fps": "30", "reducekf": "0"},
        "gms_hash": [{
            "model-id": gms.get("model-id", 0),
            "mirror": gms.get("mirror", False),
            "trim": [int(trim[0]), int(trim[1])],
            "overdrive": 0,
            "params": pstr,
            "arm-space": gms.get("arm-space", 0),
            "inplace": gms.get("inplace", False),
        }],
    }

    for attempt in range(6):
        try:
            call("POST", "/animations/export", payload)
            break
        except RuntimeError as e:
            if "429" in str(e):
                wait = 20 * (attempt + 1)
                print(f"        rate limited; waiting {wait}s", flush=True)
                time.sleep(wait)
                if attempt == 5:
                    raise
            else:
                raise

    for _ in range(90):
        st = call("GET", f"/characters/{char_id}/monitor")
        status = st.get("status", "")
        if status == "completed":
            url = st.get("job_result")
            if not url:
                raise RuntimeError("completed with no job_result")
            return url
        if status == "failed":
            raise RuntimeError("export failed: " + str(st.get("message"))[:160])
        time.sleep(2)
    raise RuntimeError("export timed out")


def download(url: str, dest: pathlib.Path) -> int:
    # The job_result is a PRE-SIGNED S3 URL. Sending Authorization invalidates
    # the signature and the CDN answers 400 Bad Request — so send no headers.
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=180) as r:
        blob = r.read()
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(blob)
    return len(blob)


# ---------------------------------------------------------------- commands
if len(sys.argv) < 2:
    print(__doc__)
    sys.exit(1)

cmd = sys.argv[1]

if cmd == "search":
    q = sys.argv[2] if len(sys.argv) > 2 else ""
    kind = sys.argv[3] if len(sys.argv) > 3 else "Motion,MotionPack"
    for m in search(q, kind):
        print(f"  {m.get('id')}  {str(m.get('name'))[:48]:<48} {m.get('type')}")

elif cmd == "chars":
    for c in characters():
        print(f"  {c.get('id')}  {c.get('name')}")

elif cmd == "fetch":
    outdir = pathlib.Path(sys.argv[2])
    all_chars = {
        "homeowner": ("Louise", "player"),
        "intruder": ("Romero", "thief"),
    }
    want = sys.argv[3] if len(sys.argv) > 3 else "both"
    chars = {k: v for k, v in all_chars.items()
             if want == "both" or v[1] == want}
    clips = {
        "idle": "Idle",
        "walk": "Walking",
        "run": "Running",
        "crouch_idle": "Idle Crouching",
        "crouch_walk": "Crouched Walking",
        "aim": "Aiming Gun",
        "shoot": "Shooting Pistol",
        "reload": "Reloading",
        "death": "Death",
    }
    # resolve ids by name
    allchars = {c["name"]: c["id"] for c in characters(48)}
    print("  available characters:", ", ".join(sorted(allchars))[:300])
    for role, (cname, tag) in chars.items():
        cid = allchars.get(cname)
        if not cid:
            print(f"  !! no character named {cname!r}")
            continue
        print(f"\n  === {role}: {cname} ({cid}) ===")
        for idx, (clip, q) in enumerate(clips.items()):
            # Mixamo bakes the full character mesh into EVERY export (~48-108 MB).
            # Only the first clip needs it; the rest are exported skin=false,
            # which is the animation alone and a fraction of the size.
            with_skin = (idx == 0)
            try:
                hits = search(q)
                if not hits:
                    print(f"    {clip:<12} no match for {q!r}")
                    continue
                # Prefer an EXACT name match; relevance order happily returns
                # "Walking Left Turn" for the query "Walking". Falling back to
                # the shortest name picks the plainest variant rather than a
                # blended transition like "Fight Idle To Standing Idle".
                exact = [h for h in hits
                         if str(h.get("name", "")).strip().lower() == q.strip().lower()]
                best = exact[0] if exact else min(hits, key=lambda h: len(str(h.get("name", ""))))
                url = export(cid, best["id"], f"{tag}_{clip}", skin=with_skin)
                n = download(url, outdir / tag / f"{clip}.fbx")
                print(f"    {clip:<12} {best['name'][:34]:<34} -> {n//1024:>5} KB  {'mesh+anim' if with_skin else 'anim only'}")
            except Exception as e:
                msg = str(e).replace(token(), "***")
                print(f"    {clip:<12} FAILED: {msg[:120]}")
            time.sleep(4)
else:
    print(__doc__)
