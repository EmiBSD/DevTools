#!/usr/bin/env python3
"""Watch the upstreams of every UPSTREAM.toml for a newer release. It reports; it never bumps.

usage: watch.py outdated [--json]      compare each pin's version with the upstream's latest
       watch.py issues                  open or update one GitHub issue per outdated upstream (needs `gh`)

`[watch] source` of an UPSTREAM.toml says where to look:
  github-releases   the origin's latest GitHub release (default when `origin` is on github.com)
  github-tags       the origin's newest tag, for upstreams without releases
  url               `url` fetched as text, `pattern` (a regex with one group) extracts the version
  none              nothing to watch, with the reason in a comment (a pin that follows another)

The pinned version is `version` up to the first "+" (our patch level is ours). Only version
strings are fetched, never sources: a bump is the user's decision, made with upstream.py.
`GITHUB_TOKEN` raises the API rate limit when set. Stdlib only.
"""
import json
import os
import re
import subprocess
import sys
import tomllib
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LABEL = "upstream"


def tomls():
    for p in sorted(ROOT.rglob("UPSTREAM.toml")):
        if "upstream" in p.parts or "target" in p.parts:
            continue
        with open(p, "rb") as fh:
            yield p.parent, tomllib.load(fh)


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "emibsd-devtools-watch"})
    if "api.github.com" in url and os.environ.get("GITHUB_TOKEN"):
        req.add_header("Authorization", "Bearer " + os.environ["GITHUB_TOKEN"])
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode()


def github_repo(origin):
    m = re.match(r"https://github\.com/([^/]+)/([^/.]+)", origin)
    return f"{m.group(1)}/{m.group(2)}" if m else None


def latest(doc):
    up, w = doc["upstream"], doc.get("watch", {})
    source = w.get("source") or ("github-releases" if github_repo(up.get("origin", "")) else "none")
    if source == "none":
        return None, None, "not watched"
    if source == "github-releases":
        repo = github_repo(up["origin"])
        rel = json.loads(get(f"https://api.github.com/repos/{repo}/releases/latest"))
        return rel["tag_name"].removeprefix(w.get("prefix", "")), rel["html_url"], None
    if source == "github-tags":
        repo = github_repo(up["origin"])
        tags = json.loads(get(f"https://api.github.com/repos/{repo}/tags?per_page=1"))
        return tags[0]["name"].removeprefix(w.get("prefix", "")), f"https://github.com/{repo}/tags", None
    if source == "url":
        text = get(w["url"])
        m = re.search(w.get("pattern", r"(\S+)"), text)
        return (m.group(1) if m else text.strip()), w["url"], None
    return None, None, f"unknown watch source {source!r}"


def parts(v):
    v = v.lstrip("v").split("+")[0]
    return [int(x) if x.isdigit() else x for x in re.split(r"[.\-]", v)]


def newer(latest_v, pinned_v):
    try:
        return parts(latest_v) > parts(pinned_v)
    except TypeError:
        return latest_v.lstrip("v") != pinned_v


def outdated():
    rows = []
    for d, doc in tomls():
        pinned = doc["upstream"].get("version", "").split("+")[0]
        try:
            lv, url, note = latest(doc)
        except Exception as e:  # network, API: reported, never fatal for the other rows
            lv, url, note = None, None, f"error: {e}"
        rows.append({"name": d.name, "upstream": doc["upstream"]["name"], "pinned": pinned,
                     "latest": lv, "url": url, "note": note,
                     "outdated": bool(lv and pinned and newer(lv, pinned))})
    return rows


def cmd_outdated(args):
    rows = outdated()
    if "--json" in args:
        print(json.dumps(rows, indent=1))
    else:
        for r in rows:
            state = "OUTDATED" if r["outdated"] else (r["note"] or "ok")
            print(f"{r['name']:8} pinned {r['pinned'] or '-':10} latest {r['latest'] or '-':10} {state}")
    return 1 if any(r["outdated"] for r in rows) else 0


def gh(*args, **kw):
    return subprocess.run(["gh", *args], capture_output=True, text=True, check=False, **kw)


def cmd_issues(_):
    gh("label", "create", LABEL, "--color", "0E8A16", "--description", "a pinned upstream has a newer release", "--force")
    for r in outdated():
        if not r["outdated"]:
            continue
        prefix = f"upstream: {r['name']} "
        title = f"{prefix}{r['pinned']} is behind {r['latest']}"
        body = (f"`{r['name']}/UPSTREAM.toml` pins **{r['upstream']} {r['pinned']}**; the upstream's latest release is "
                f"**{r['latest']}** ({r['url']}).\n\nFound by `tools/watch.py` on its daily run. Nothing was changed: a pin "
                f"moves only by the maintainer's decision, in its own commit (`{r['name']}: bump pin to {r['latest']}`), "
                f"after `python3 -I tools/upstream.py fetch {r['name']}` from the main session and the patch series "
                f"re-checked against the new source.\n")
        found = gh("issue", "list", "--state", "open", "--label", LABEL, "--search", f'"{prefix}" in:title',
                   "--json", "number,title")
        existing = [i for i in (json.loads(found.stdout or "[]")) if i["title"].startswith(prefix)]
        if existing:
            n = str(existing[0]["number"])
            if existing[0]["title"] != title:
                gh("issue", "edit", n, "--title", title, "--body", body)
                print(f"updated #{n}: {title}")
            else:
                print(f"open #{n}: {title}")
        else:
            r2 = gh("issue", "create", "--title", title, "--body", body, "--label", LABEL)
            print(f"created: {title} {r2.stdout.strip()}{r2.stderr.strip()}")
    return 0


def main():
    cmds = {"outdated": cmd_outdated, "issues": cmd_issues}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        print(__doc__, file=sys.stderr)
        return 2
    return cmds[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
