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
"""The artifacts of a built toolchain: dist/<name>-<version>-<host>-<arch>.tar.zst and their .sha256,
one per target architecture (arm64, amd64: D-0008).

usage: dist.py <llvm|rust>        pack the install tree once per architecture, then unpack each
                                  elsewhere and run tests/check.sh over it
       dist.py <llvm|rust> --native [arm64|amd64 ...]
                                  the native toolchain (T3b, D-0009): pack build/native.sh's tree of
                                  each architecture, <name>-<version>-<EmiBSD host>-<arch>, whose usr/
                                  is laid over the system's, and run tests/native-check.sh over it

Each tarball holds one directory, <name>-<version>-<host>-<arch>/, with the install tree as
build/build.sh left it, less what belongs to the other architecture's targets (their runtimes,
their std, the clang named after their triple), plus MANIFEST (the commit, the tag if HEAD carries one, the pins, the
patch series with its sums) and share/doc/emibsd/ (DevTools' ISC LICENSE, the patches, the
upstream licence texts). Reproducible: entries sorted, mtime SOURCE_DATE_EPOCH (the commit's
time), uid and gid 0, modes normalised; two builds of the same tag compare. `zstd` is the
host's (the user's install). Needs EMIBSD_SYSROOT_ARM64 and _AMD64 for the check, as the build does.
A release is cut from a tagged commit; without a tag MANIFEST says `tag: none (snapshot)`.
"""
import hashlib
import io
import os
import platform
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
ARCHS = {"arm64": "aarch64", "amd64": "x86_64"}  # the system's names of the target architectures, and LLVM's
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


def target_arch(part):
    """The LLVM architecture a path component belongs to, when it names an EmiBSD or kernel target
    (lib/x86_64-emibsd-emibsd8.0, lib/rustlib/aarch64-emibsd-none-softfloat, bin/x86_64-...-clang,
    manifest-rust-std-x86_64-emibsd-emibsd); None for what every architecture shares, the host's too."""
    part = part.removeprefix("manifest-rust-std-")
    if "-emibsd" not in part:
        return None
    return part.split("-", 1)[0]


def targets_of(tree, arch):
    """The targets this architecture's tarball carries, as the tree names them."""
    found = set()
    for d in (tree / "lib", tree / "lib" / "rustlib"):
        if d.is_dir():
            found |= {p.name for p in d.iterdir() if p.is_dir() and target_arch(p.name) == ARCHS[arch]}
    return sorted(found)


def manifest(name, toml, version, host, arch, targets, epoch):
    up = toml["upstream"]
    # The tag of this toolchain among those on HEAD (llvm's and rust's may share a commit).
    tags = [t for t in run("git", "tag", "--points-at", "HEAD", cwd=ROOT).splitlines() if t.startswith(f"{name}-")]
    tag = tags[0] if tags else "none (snapshot)"
    lines = [f"name: {name}", f"version: {version}", f"host: {host}", f"arch: {arch}",
             f"targets: {' '.join(targets)}",
             f"commit: {run('git', 'rev-parse', 'HEAD', cwd=ROOT)}", f"tag: {tag}",
             f"date: {datetime.fromtimestamp(epoch, timezone.utc).isoformat()}",
             f"upstream: {up['origin']} {up.get('tag') or up.get('commit')} ({up['commit']}) via {up['repo']}"]
    # The sysroot the build took for this architecture: its pin when tools/sysroot.sh made it
    # from a released userland artifact, else only that it was given by path.
    var = os.environ.get({"arm64": "EMIBSD_SYSROOT_ARM64", "amd64": "EMIBSD_SYSROOT_AMD64"}[arch], "")
    pin = Path(var) / ".pin" if var else None
    lines.append(f"sysroot: {pin.read_text().strip() if pin and pin.is_file() else 'given by path, not pinned'}")
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


def add_tree(tar, top, src: Path, arch, epoch):
    """Every entry under src but the other architectures' targets, sorted, normalised: mtime epoch,
    uid/gid 0, mode 755 or 644. rust-installer's list of components names this architecture's only."""
    for path in sorted(src.rglob("*"), key=lambda p: str(p.relative_to(src))):
        rel = path.relative_to(src)
        if any(target_arch(part) not in (None, ARCHS[arch]) for part in rel.parts):
            continue
        # rust-installer's records name the build machine's paths and mean nothing elsewhere.
        if rel.parent.name == "rustlib" and (rel.name in ("install.log", "uninstall.sh", "rust-installer-version")
                                             or rel.name.startswith("manifest-")):
            continue
        arcname = f"{top}/{rel}"
        if rel == Path("lib/rustlib/components"):
            kept = [c for c in path.read_text().splitlines() if target_arch(c.removeprefix("rust-std-")) in (None, ARCHS[arch])]
            add_bytes(tar, arcname, ("\n".join(kept) + "\n").encode(), epoch)
            continue
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


def native_host(name, arch):
    """The EmiBSD host of a native tree: LLVM's triple for llvm/, Rust's name for rust/."""
    return f"{ARCHS[arch]}-emibsd-emibsd8.0" if name == "llvm" else f"{ARCHS[arch]}-emibsd-emibsd"


def pack(name, arch, native=False):
    for var in ("EMIBSD_SYSROOT_ARM64", "EMIBSD_SYSROOT_AMD64"):
        if not os.environ.get(var):
            raise SystemExit(f"dist: set {var} (that architecture's libc, crt and headers): the unpacked check "
                             "links programs against it, as the build does; nothing is packed without it")
    toml = tomllib.load(open(ROOT / name / "UPSTREAM.toml", "rb"))
    version = toml["upstream"]["version"]
    if native:
        host = native_host(name, arch)
        tree = ROOT / "target" / name / f"native-{host}" / "root"
        if not (tree / "usr" / "bin").is_dir():
            raise SystemExit(f"dist: {tree.relative_to(ROOT)} is not built (just native {name} {ARCHS[arch]})")
    else:
        host = HOSTS.get((platform.system(), platform.machine()))
        if not host:
            raise SystemExit(f"dist: unknown host {platform.system()} {platform.machine()}")
        tree = install_tree(name, host)
        if not (tree / "bin").is_dir():
            raise SystemExit(f"dist: {tree.relative_to(ROOT)} is not built (just build {name})")
    epoch = int(os.environ.get("SOURCE_DATE_EPOCH") or run("git", "log", "-1", "--format=%ct", cwd=ROOT))
    top = f"{name}-{version}-{host}-{arch}"
    out = ROOT / "dist"
    out.mkdir(exist_ok=True)
    tarball = out / f"{top}.tar.zst"
    if shutil.which("zstd") is None:
        raise SystemExit("dist: zstd not found (the user's install)")
    print(f"dist: {top}: packing {tree.relative_to(ROOT)} (SOURCE_DATE_EPOCH {epoch})")
    zstd = subprocess.Popen(["zstd", "-19", "-T0", "-q", "-f", "-o", str(tarball)], stdin=subprocess.PIPE)
    with tarfile.open(fileobj=zstd.stdin, mode="w|", format=tarfile.PAX_FORMAT) as tar:
        add_tree(tar, top, tree, arch, epoch)
        targets = targets_of(tree / "usr" if native else tree, arch)
        add_bytes(tar, f"{top}/MANIFEST", manifest(name, toml, version, host, arch, targets, epoch).encode(), epoch)
        # The licences travel with what is installed: under usr/ for a native tree, laid over the system's.
        doc = f"{top}/usr/share/doc/emibsd/{name}" if native else f"{top}/share/doc/emibsd"
        add_bytes(tar, f"{doc}/LICENSE", (ROOT / "LICENSE").read_bytes(), epoch)
        for p in toml.get("patches", {}).get("series", []):
            add_bytes(tar, f"{doc}/patches/{p}", (ROOT / name / "patches" / p).read_bytes(), epoch)
        src = ROOT / "target" / name / "src"
        for rel, arc in LICENSES[name]:
            if (src / rel).exists():
                add_bytes(tar, f"{doc}/{arc}", (src / rel).read_bytes(), epoch)
    zstd.stdin.close()
    if zstd.wait() != 0:
        raise SystemExit("dist: zstd failed")
    print(f"dist: {tarball.relative_to(ROOT)}: {tarball.stat().st_size / 1e6:.0f} MB")
    return top, tarball


def seal(tarball):
    """The .sha256, written only once the unpacked check passed: a failed artifact is not releasable."""
    digest = hashlib.sha256(tarball.read_bytes()).hexdigest()
    (tarball.parent / f"{tarball.name}.sha256").write_text(f"{digest}  {tarball.name}\n")
    print(f"dist: {tarball.name}.sha256: {digest}")


def check(name, arch, top, tarball, native=False):
    """Unpack elsewhere and run tests/check.sh there: the artifact works away from target/."""
    where = ROOT / "target" / "dist-check"
    shutil.rmtree(where, ignore_errors=True)
    where.mkdir(parents=True)
    subprocess.run(f"zstd -dc '{tarball}' | tar -xf - -C '{where}'", shell=True, check=True)
    prefix = where / top
    if native:
        print(f"dist: native-check.sh over the unpacked {top}")
        subprocess.run(["sh", str(ROOT / name / "tests" / "native-check.sh"), str(prefix), native_host(name, arch)], check=True)
        return
    if name == "llvm":
        args = [str(prefix), ARCHS[arch]]
    else:
        host = run(str(prefix / "bin" / "rustc"), "-vV").split("host: ")[1].splitlines()[0]
        args = [str(prefix), host, str(install_tree("llvm", host)), ARCHS[arch]]
    print(f"dist: check.sh over the unpacked {top}")
    subprocess.run(["sh", str(ROOT / name / "tests" / "check.sh"), *args], check=True)


def main(argv):
    if not argv or argv[0] not in ("llvm", "rust") or (len(argv) > 1 and argv[1] != "--native"):
        print(__doc__); return 2
    native = len(argv) > 1
    archs = argv[2:] or list(ARCHS)
    if any(a not in ARCHS for a in archs):
        print(__doc__); return 2
    for arch in archs:
        top, tarball = pack(argv[0], arch, native)
        (tarball.parent / f"{tarball.name}.sha256").unlink(missing_ok=True)
        check(argv[0], arch, top, tarball, native)
        seal(tarball)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
