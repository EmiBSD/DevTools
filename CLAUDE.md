# EmiBSD DevTools

The toolchains of EmiBSD, both **imported** and both from the forks alone: upstream LLVM at
a release tag (clang, lld, libc++, libc++abi, compiler-rt; Apache-2.0 with the LLVM
exception) and Rust at a pinned stable tag (rustc, cargo, std; Apache-2.0 and MIT), built
once and released as artifacts that the other EmiBSD repositories (the kernel, the userland,
the release assembly) consume. One LLVM for the C and for rustc. **Nothing of OpenBSD enters
this repository** (decision D-0003). Repository `EmiBSD/DevTools`, created 2026-10-31
(decision D-0002). This repository carries every rule that binds it and cites no other
repository's files (decision D-0005): this file is the rules; `docs/DECISIONS.md` the
decisions, `docs/POLICIES.md` the licences, the dependencies and the disclosure of the AI
process, `docs/PROCESS.md` who decides and what a commit needs.

EmiBSD is an experiment by Emilio Navarrete Lineros (enavarre@outlook.com), the maintainer:
the OpenBSD kernel carried into Rust and a userland of its own; the code is written by Claude
Code agents under written rules, and the maintainer takes every decision and approves every
commit. Pre-alpha; boots only in QEMU on arm64. Site https://www.emibsd.org, organisation
https://github.com/EmiBSD. Not affiliated with or endorsed by the OpenBSD, LLVM or Rust
projects.

Everything in this repository (code, comments, docs, commits) is in English. The user is
answered in Spanish.

## Non-negotiables

- **Imported, plus our target series.** No toolchain here is ours: the sources are the
  upstreams at the pins of `llvm/UPSTREAM.toml` and `rust/UPSTREAM.toml`, fetched into
  `upstream/` (read-only, never committed), copied to `target/`, patched from `patches/`,
  built there. What is ours is the patch series that teaches them the EmiBSD target
  (D-0004: ISC, each patch with its reason, re-applied at every pin bump), the build glue
  (`build/build.sh`, `justfile`, `tools/`), and the documents. No source file of a
  toolchain is edited in place, ever.
- **Forks are mirrors.** `EmiBSD/llvm-project`, `EmiBSD/rust` and `EmiBSD/cargo` carry
  only the upstream tags and commits the pins name; no commit of ours lands on them.
  `OpenBSD-src` is not an input of this repository in any form. `tools/mirror.py check` verifies a pin exists on
  the mirror and on the origin with the same hash; pushing a tag to a mirror is the user's,
  from the main session.
- **One LLVM (D-0003, 2026-10-31).** Upstream LLVM at `llvmorg-23.1.4`, from the fork, as
  upstream ships it, built with its own CMake: the compiler of the C and C++ of the system and
  the backend rustc builds against (`llvm-config`; rustc 1.99.1 needs 21 or newer). No patch
  of anyone else's, no build glue of anyone else's; rustc's own LLVM submodule is not fetched.
- **Stable Rust, no nightly.** The `std` for `aarch64-emibsd-emibsd` and `x86_64-emibsd-emibsd` (tier 3; `llvm-target` `<arch>-emibsd-emibsd8.0`) is built with
  `x.py` from the stable release's source as part of the toolchain. Stage0 is rustup's rustc
  on the host; on EmiBSD, the previous DevTools release. `rust-toolchain.toml` pins the host
  toolchain the build glue itself runs under.
- **Each pin is its own.** The LLVM tag and the Rust tag move each in its own commit, by the
  user's decision; the watcher reports newer releases, never bumps.
- **DevTools knows nothing of the consumers' internals.** It takes a sysroot (libc, crt,
  headers) as an input, by path or by pin, and publishes artifacts with SHA-256 sums. It
  never reads another repository's source, rules or logs to decide anything; the other
  repositories are named here only as the consumers of the artifacts and the source of the
  sysroot. A decision taken elsewhere that binds this repository is recorded in
  `docs/DECISIONS.md` in its own words before it is acted on (D-0005).
- **Nothing installed, nothing downloaded without the user's OK.** `just fetch` is the one
  sanctioned download and runs from the main session. The guard hook refuses installs,
  pushes, amends and writes under `upstream/`.
- **The watcher reports, never bumps.** `.github/workflows/upstream-watch.yml` runs
  `tools/watch.py` daily: it compares each `UPSTREAM.toml`'s version with the upstream's
  latest release (version strings only, never sources) and opens one issue per outdated pin,
  labelled `upstream`. A pin moves only by the user's decision, in its own commit.
- **Nothing GPL** enters the tree or the artifacts; the licence table is in `docs/POLICIES.md`.
- **Ours is ISC.** The build glue, the hooks, the documents and the patches are ISC
  (`LICENSE`); a script or a patch of ours starts with the author's block, "Copyright (c) 2026
  Emilio Navarrete Lineros", and nobody else's name replaces it.
- **The maintainer decides, the agents propose.** A pin bump, a host, a target, a flag that
  changes what the compiler emits, a patch, a dependency: handed back with the question,
  never guessed (`docs/PROCESS.md`).
- **arm64 and amd64 (D-0008, superseding D-0001).** Both are built, tested and released:
  `aarch64` and `x86_64` for the system and for the kernel; arm64 stays first (clang's
  default triple). One artifact per host and architecture, each with its own sysroot
  (`EMIBSD_SYSROOT_ARM64`, `EMIBSD_SYSROOT_AMD64`).
- **The target is EmiBSD's own (D-0004).** The toolchains emit for `aarch64-emibsd-emibsd8.0`
  and `x86_64-emibsd-emibsd8.0` (D-0008), carried as our patch series over the pins: LLVM's is
  `llvm/patches/` (applied 2026-10-31); Rust's, the target specs and `std`'s paths, is
  `rust/patches/`.
- Commit on the user's "dale", push on "súbelo"; never push otherwise.

## Directory map

```
llvm/      upstream LLVM from the fork: UPSTREAM.toml, DEFINITION, DESIGN, DELIVERY, STATUS, build/ (CMake), tests/
rust/      rust-lang/rust: the same files; the cargo submodule pinned in UPSTREAM.toml
tools/     upstream.py (fetch and check the pins), mirror.py (the mirrors against the origins), watch.py (newer releases), cve.py (NVD)
docs/      TOOLCHAIN.md (hosts, targets, inputs and outputs, the chain, the artifact format), DECISIONS.md, POLICIES.md, PROCESS.md
upstream/  the fetched sources (gitignored); target/ the builds; dist/ the artifacts
.claude/   settings, rules/, hooks/agent-guard.sh
```

## Milestones

| | Scope | Proof |
|---|---|---|
| T0 | the repository, the pins moved from the userland repository, the tools, the mirror check | `just fetch-check` and `just mirror-check` green; met 2026-10-31 |
| T1 | upstream LLVM 23.1.4 built from the fork with CMake on the macOS host: stage 1 the host tools, stage 2 the target runtimes | a C and a C++ hello compiled for the target run under the EmiBSD kernel in QEMU; built and checked on the host 2026-10-31 (`llvm/tests/check.sh`), the QEMU run pending |
| T2 | rustc with `x.py`, macOS host, targets `aarch64-emibsd-emibsd` and `x86_64-emibsd-emibsd` (D-0004, D-0008: their target specs and `std` paths as `rust/patches/`) and the kernel's `aarch64-emibsd-none-softfloat` and `x86_64-emibsd-none-softfloat` (D-0006, D-0008), the userland's sysroot; cargo, clippy, rustfmt and `rust-src` in the artifact | a static Rust hello runs under the EmiBSD kernel in QEMU; built and checked on the host 2026-10-31 (`rust/tests/check.sh`), the QEMU run pending |
| T3 | GitHub releases: one tarball per host and architecture (`arm64`, `amd64`) with `.sha256`; consumers fetch by pin | a consumer's toolchain recipe installs it from the release |
| T4 | self-hosted: rustc built on EmiBSD with T3 as stage0 | after the kernel's N9, when no inherited tree is left |

`docs/TOOLCHAIN.md` is the plan in detail, with the picture of where the repository sits.

## Working

- `just` at the root: `fetch`, `fetch-check`, `mirror-check`, `outdated`, `status`, `build <llvm|rust>`,
  `cve <llvm|rust>` (network, the user's OK). `PATH=/opt/homebrew/opt/rustup/bin:$PATH`.
- A build is long (LLVM about an hour on the Mac with the cores it gets; rustc longer):
  built once, cached under `target/`, never rebuilt by a check; `just build` takes the
  machine's lock `/tmp/emibsd/ci.lock` (D-0007) so that no two heavy builds run at once. `COMP_JOBS` bounds the jobs.
  CMake, Ninja and Python 3 are the host tools; installing them is the user's.
- Read upstream sources with `sed -n` or `git -C upstream/<mirror> show`, never `cd` into
  `upstream/`. The guard hook refuses both the write and the `cd`.
- A patch is a file in `patches/`, named `NNNN-<what>.patch`, with its reason in the header
  and one line in DESIGN.md; the series is the `[patches] series` of UPSTREAM.toml.
- Commits: `<llvm|rust|tools|docs>: <imperative summary>`, the body says what and why; a pin
  bump is its own commit titled `<llvm|rust>: bump pin to <version>`; then the session's
  `Co-Authored-By:` line. Add paths by name; never `git add -A`, never amend.
- A toolchain bump, a new host, a new target, a flag that changes what the compiler emits:
  the user's decision, handed back with the question.

## Rules

`.claude/rules/imported.md` (what an imported toolchain may and may not do here) and
`.claude/rules/subagents.md` (the contract of the roles, when they exist) are the detail;
`docs/DECISIONS.md`, `docs/POLICIES.md` and `docs/PROCESS.md` are the project's rules as
they apply here. This file points at them; nothing points outside the repository.
