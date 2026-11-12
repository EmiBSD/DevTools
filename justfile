# EmiBSD DevTools: the recipes. Each toolchain lives in its directory (llvm/, rust/) with an
# UPSTREAM.toml, patches/ and build/build.sh; these recipes run over them.

set shell := ["zsh", "-cu"]

export PATH := "/opt/homebrew/opt/rustup/bin:" + env("PATH")
export SOURCE_DATE_EPOCH := `git log -1 --format=%ct 2>/dev/null || echo 0`

# Job count of a build: about half the Mac's cores by default (other builds share it).
export COMP_JOBS := env("COMP_JOBS", "6")

default:
    @just --list

# The STATUS of every toolchain.
status:
    @for d in llvm rust; do printf '%s\t%s\t%s\n' "$(cat $d/STATUS)" "$d" "$(sed -n 's/^version *= *"\([^"]*\)".*/\1/p' $d/UPSTREAM.toml)"; done

# Fetch and verify every upstream named by an UPSTREAM.toml (sparse clones under upstream/). Network; the user's OK.
fetch:
    python3 -I tools/upstream.py fetch

# Check every fetched upstream against its pin (no network).
fetch-check:
    python3 -I tools/upstream.py check

# Check that every pin exists on its mirror and on its origin with the same hash (git ls-remote only).
mirror-check:
    python3 -I tools/mirror.py check

# Is any pin behind its upstream's latest release? Reports only (network: version strings, no sources).
outdated:
    python3 -I tools/watch.py outdated

# Build one toolchain from its fetched source: `just build llvm`, `just build rust`.
build name:
    # under the machine's lock /tmp/emibsd/ci.lock (D-0007): never two heavy builds at once
    python3 -I tools/upstream.py check {{name}} && python3 -I tools/lock.py /tmp/emibsd/ci.lock sh {{name}}/build/build.sh

# The native toolchain (T3b, D-0009): `just native llvm [aarch64|x86_64]` after `just build llvm`, then `just native rust` after `just build rust`.
native name *archs:
    python3 -I tools/upstream.py check {{name}} && python3 -I tools/lock.py /tmp/emibsd/ci.lock sh {{name}}/build/native.sh {{archs}}

# The sysroot by pin: a released userland artifact already on this machine, checked against its sum, unpacked to target/sysroot/<arch>.
sysroot arch artifact sum:
    sh tools/sysroot.sh {{arch}} {{artifact}} {{sum}}

# The artifact of a built toolchain: dist/<name>-<version>-<host>.tar.zst and .sha256, then checked unpacked elsewhere.
dist name:
    python3 -I tools/dist.py {{name}}

# The GitHub release of a toolchain's artifact, from a tagged commit: the maintainer's, from the main session (it publishes).
release name:
    sh tools/release.sh {{name}}

# The licences of the crates a toolchain's build vendored, against docs/POLICIES.md (no network).
crates name:
    python3 -I tools/crates.py {{name}}

# The CVE history of one toolchain from NVD (network; the user's OK).
cve name:
    python3 -I tools/cve.py {{name}}

# The checks that cost nothing: the pins parse, the mirrors hold them, the scripts compile.
check: mirror-check
    python3 -I -m py_compile tools/upstream.py tools/mirror.py tools/cve.py tools/watch.py tools/crates.py tools/dist.py tools/lock.py
    python3 -I tools/crates.py rust
    sh -n tools/sysroot.sh llvm/build/build.sh llvm/build/native.sh llvm/tests/native-check.sh rust/tests/native-check.sh rust/build/build.sh rust/build/native.sh rust/build/llvm-config-native.sh tools/release.sh
    python3 -I -m py_compile rust/build/emibsd-vendor.py
