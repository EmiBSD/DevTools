#!/usr/bin/env python3
"""The organisation's mirrors against their origins: every pin an UPSTREAM.toml names must
exist on the mirror (`repo`) and resolve to the same hash on the origin (`origin`).

usage: mirror.py check [<toolchain dir>...]    ls-remote both sides, compare (no clone)
       mirror.py sync <toolchain dir>          print the commands that push the pinned tag
                                               from the origin to the mirror; never runs them

Forks are mirrors: no commit of ours lands on them, only the upstream tags and commits the
pins name (CLAUDE.md). A pinned commit that is not a tag cannot be checked on the origin by
ls-remote; it is checked on the mirror by fetching that single commit into a temporary,
blob-less clone when `--deep` is given, else only the mirror's existence is checked. Stdlib only.
"""
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def tomls(args):
    dirs = [Path(a).resolve() for a in args] or sorted(
        p.parent for p in ROOT.rglob("UPSTREAM.toml")
        if "upstream" not in p.parts and "target" not in p.parts)
    for d in dirs:
        f = d / "UPSTREAM.toml"
        if f.exists():
            with open(f, "rb") as fh:
                doc = tomllib.load(fh)
            yield d, doc


def ls_remote(url, ref):
    """The hash `ref` resolves to on `url`, dereferencing an annotated tag; None if absent."""
    out = subprocess.run(["git", "ls-remote", url, ref, ref + "^{}"],
                         capture_output=True, text=True, check=False).stdout
    peeled = plain = None
    for line in out.splitlines():
        sha, name = line.split("\t", 1)
        if name.endswith("^{}"):
            peeled = sha
        else:
            plain = sha
    return peeled or plain


def has_commit(url, sha):
    """Whether `url` holds commit `sha`: a blob-less fetch of that one object into a scratch repo."""
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["git", "init", "-q", tmp], check=True)
        r = subprocess.run(["git", "-C", tmp, "fetch", "-q", "--depth=1", "--filter=blob:none", url, sha],
                           capture_output=True, text=True, check=False)
        return r.returncode == 0


def entries(doc):
    up = doc["upstream"]
    yield up["name"], up["repo"], up["origin"], up.get("tag"), up["commit"]
    for sm in doc.get("submodules", []):
        yield "submodule " + sm["path"], sm["repo"], sm["origin"], None, sm["commit"]


def cmd_check(args):
    deep = "--deep" in args
    args = [a for a in args if a != "--deep"]
    bad = 0
    for d, doc in tomls(args):
        for name, mirror, origin, tag, commit in entries(doc):
            if tag:
                on_mirror, on_origin = ls_remote(mirror, "refs/tags/" + tag), ls_remote(origin, "refs/tags/" + tag)
                ok = on_mirror == on_origin == commit
                state = "ok" if ok else f"mirror={on_mirror} origin={on_origin} pin={commit}"
                print(f"{d.name}\t{name}\ttag {tag}\t{state}")
            elif deep:
                ok = has_commit(mirror, commit)
                print(f"{d.name}\t{name}\tcommit {commit[:12]}\t{'ok on mirror' if ok else 'MISSING on mirror'}")
            else:
                # The commit itself needs a clone (--deep); without one, at least the mirror must exist.
                ok = ls_remote(mirror, "HEAD") is not None
                state = "mirror reachable, commit not verified (use --deep)" if ok else f"MISSING mirror {mirror}"
                print(f"{d.name}\t{name}\tcommit {commit[:12]}\t{state}")
            bad += 0 if ok else 1
    return 1 if bad else 0


def cmd_sync(args):
    if len(args) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    for d, doc in tomls(args):
        for name, mirror, origin, tag, commit in entries(doc):
            ref = f"refs/tags/{tag}" if tag else commit
            print(f"# {d.name}: {name}")
            print(f"git fetch {origin} {ref}")
            print(f"git push {mirror} {'FETCH_HEAD:' + ref if tag else 'FETCH_HEAD:refs/heads/emibsd/pin-' + commit[:12]}")
    return 0


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("check", "sync"):
        print(__doc__, file=sys.stderr)
        return 2
    return {"check": cmd_check, "sync": cmd_sync}[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
