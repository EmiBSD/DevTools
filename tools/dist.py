#!/usr/bin/env python3
#
# Copyright (c) 2026 Emilio Navarrete Lineros <enavarre@outlook.com>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
"""The artifact of a built toolchain: dist/<name>-<version>-<host>.tar.zst and its .sha256.

usage: dist.py <llvm|rust>        pack the install tree, then unpack it elsewhere and run tests/check.sh

The tarball holds one directory, <name>-<version>-<host>/, with the install tree as
build/build.sh left it, plus MANIFEST (the commit, the tag if HEAD carries one, the pins, the
patch series with its sums) and share/doc/emibsd/ (DevTools' ISC LICENSE, the patches, the
upstream licence texts). Reproducible: entries sorted, mtime SOURCE_DATE_EPOCH (the commit's
time), uid and gid 0, modes normalised; two builds of the same tag compare. `zstd` is the
host's (the user's install). Needs EMIBSD_SYSROOT for the check, as the build does.
A release is cut from a tagged commit; without a tag MANIFEST says `tag: none (snapshot)`.
"""
import hashlib
import io
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tomllib
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOSTS = {("Darwin", "arm64"): "aarch64-apple-darwin", ("Linux", "x86_64"): "x86_64-unknown-linux-gnu",
         ("EmiBSD", "arm64"): "aarch64-emibsd-emibsd8.0"}
LICENSES = {  # upstream licence texts to ship beside ours, relative to the source copy
    "llvm": [("llvm/LICENSE.TXT", "LICENSE.llvm"), ("libcxx/LICENSE.TXT", "LICENSE.libcxx"),
             ("compiler-rt/LICENSE.TXT", "LICENSE.compiler-rt")],
    "rust": [("LICENSE-APACHE", "LICENSE-APACHE.rust"), ("LICENSE-MIT", "LICENSE-MIT.rust"), ("COPYRIGHT", "COPYRIGHT.rust")],
}


def run(*cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw).stdout.strip()


def install_tree(name, host):
    if name == "llvm":
        return ROOT / "target" / "llvm" / run("cc", "-dumpmachine")
    return ROOT / "target" / "rust" / f"install-{host}"


def manifest(name, toml, version, host, epoch):
    up = toml["upstream"]
    try:
        tag = run("git", "describe", "--tags", "--exact-match", "HEAD", cwd=ROOT)
    except subprocess.CalledProcessError:
        tag = "none (snapshot)"
    lines = [f"name: {name}", f"version: {version}", f"host: {host}",
             f"commit: {run('git', 'rev-parse', 'HEAD', cwd=ROOT)}", f"tag: {tag}",
             f"date: {datetime.fromtimestamp(epoch, timezone.utc).isoformat()}",
             f"upstream: {up['origin']} {up.get('tag') or up.get('commit')} ({up['commit']}) via {up['repo']}"]
    for sm in toml.get("submodules", []):
        lines.append(f"submodule: {sm['path']} {sm['commit']} via {sm['repo']}")
    for p in toml.get("patches", {}).get("series", []):
        digest = hashlib.sha256((ROOT / name / "patches" / p).read_bytes()).hexdigest()
        lines.append(f"patch: {p} sha256 {digest}")
    lines.append("license: the toolchain keeps its own (share/doc/emibsd/LICENSE.*); DevTools' glue and patches are ISC (share/doc/emibsd/LICENSE)")
    lines.append("not affiliated with or endorsed by the LLVM project or the Rust project")
    return "\n".join(lines) + "\n"


def add_bytes(tar, arcname, data, epoch, mode=0o644):
    info = tarfile.TarInfo(arcname)
    info.size = len(data); info.mtime = epoch; info.mode = mode
    info.uid = info.gid = 0; info.uname = info.gname = ""
    tar.addfile(info, io.BytesIO(data))


def add_tree(tar, top, src: Path, epoch):
    """Every entry under src, sorted, normalised: mtime epoch, uid/gid 0, mode 755 or 644."""
    for path in sorted(src.rglob("*"), key=lambda p: str(p.relative_to(src))):
        arcname = f"{top}/{path.relative_to(src)}"
        info = tar.gettarinfo(str(path), arcname)
        info.mtime = epoch; info.uid = info.gid = 0; info.uname = info.gname = ""
        if info.isdir():
            info.mode = 0o755
        elif info.isreg() or info.islnk():
            info.mode = 0o755 if os.access(path, os.X_OK) else 0o644
        elif info.issym():
            info.mode = 0o777
        if info.isreg():
            with open(path, "rb") as f:
                tar.addfile(info, f)
        else:
            tar.addfile(info)


def pack(name):
    toml = tomllib.load(open(ROOT / name / "UPSTREAM.toml", "rb"))
    version = toml["upstream"]["version"]
    host = HOSTS.get((platform.system(), platform.machine()))
    if not host:
        raise SystemExit(f"dist: unknown host {platform.system()} {platform.machine()}")
    tree = install_tree(name, host)
    if not (tree / "bin").is_dir():
        raise SystemExit(f"dist: {tree.relative_to(ROOT)} is not built (just build {name})")
    epoch = int(os.environ.get("SOURCE_DATE_EPOCH") or run("git", "log", "-1", "--format=%ct", cwd=ROOT))
    top = f"{name}-{version}-{host}"
    out = ROOT / "dist"
    out.mkdir(exist_ok=True)
    tarball = out / f"{top}.tar.zst"
    if shutil.which("zstd") is None:
        raise SystemExit("dist: zstd not found (the user's install)")
    print(f"dist: {top}: packing {tree.relative_to(ROOT)} (SOURCE_DATE_EPOCH {epoch})")
    zstd = subprocess.Popen(["zstd", "-19", "-T0", "-q", "-f", "-o", str(tarball)], stdin=subprocess.PIPE)
    with tarfile.open(fileobj=zstd.stdin, mode="w|", format=tarfile.PAX_FORMAT) as tar:
        add_tree(tar, top, tree, epoch)
        add_bytes(tar, f"{top}/MANIFEST", manifest(name, toml, version, host, epoch).encode(), epoch)
        add_bytes(tar, f"{top}/share/doc/emibsd/LICENSE", (ROOT / "LICENSE").read_bytes(), epoch)
        for p in toml.get("patches", {}).get("series", []):
            add_bytes(tar, f"{top}/share/doc/emibsd/patches/{p}", (ROOT / name / "patches" / p).read_bytes(), epoch)
        src = ROOT / "target" / name / "src"
        for rel, arc in LICENSES[name]:
            if (src / rel).exists():
                add_bytes(tar, f"{top}/share/doc/emibsd/{arc}", (src / rel).read_bytes(), epoch)
    zstd.stdin.close()
    if zstd.wait() != 0:
        raise SystemExit("dist: zstd failed")
    print(f"dist: {tarball.relative_to(ROOT)}: {tarball.stat().st_size // (1 << 20)} MB")
    return top, tarball


def seal(tarball):
    """The .sha256, written only once the unpacked check passed: a failed artifact is not releasable."""
    digest = hashlib.sha256(tarball.read_bytes()).hexdigest()
    (tarball.parent / f"{tarball.name}.sha256").write_text(f"{digest}  {tarball.name}\n")
    print(f"dist: {tarball.name}.sha256: {digest}")


def check(name, top, tarball):
    """Unpack elsewhere and run tests/check.sh there: the artifact works away from target/."""
    where = ROOT / "target" / "dist-check"
    shutil.rmtree(where, ignore_errors=True)
    where.mkdir(parents=True)
    subprocess.run(f"zstd -dc '{tarball}' | tar -xf - -C '{where}'", shell=True, check=True)
    prefix = where / top
    if name == "llvm":
        triple = run(str(prefix / "bin" / "clang"), "-print-target-triple")
        args = [str(prefix), triple]
    else:
        host = run(str(prefix / "bin" / "rustc"), "-vV").split("host: ")[1].splitlines()[0]
        build_sh = (ROOT / "rust" / "build" / "build.sh").read_text()
        kernel = re.search(r"^KERNEL_TARGET=(\S+)", build_sh, re.M).group(1)
        target = re.search(r"^TARGET=(\S+)", build_sh, re.M).group(1)
        args = [str(prefix), host, kernel, target, str(install_tree("llvm", host))]
    print(f"dist: check.sh over the unpacked {top}")
    subprocess.run(["sh", str(ROOT / name / "tests" / "check.sh"), *args], check=True)


def main(argv):
    if len(argv) != 1 or argv[0] not in ("llvm", "rust"):
        print(__doc__); return 2
    top, tarball = pack(argv[0])
    (tarball.parent / f"{tarball.name}.sha256").unlink(missing_ok=True)
    check(argv[0], top, tarball)
    seal(tarball)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
