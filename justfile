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

# Build one toolchain from its fetched source: `just build llvm`, `just build rust`.
build name:
    python3 -I tools/upstream.py check {{name}} && sh {{name}}/build/build.sh

# The CVE history of one toolchain from NVD (network; the user's OK).
cve name:
    python3 -I tools/cve.py {{name}}

# The checks that cost nothing: the pins parse, the mirrors hold them, the scripts compile.
check: mirror-check
    python3 -I -m py_compile tools/upstream.py tools/mirror.py tools/cve.py
    sh -n llvm/build/build.sh rust/build/build.sh
