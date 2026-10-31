# EmiBSD DevTools

The toolchains of EmiBSD, both **imported**: LLVM as OpenBSD ships it (clang, lld, libc++,
libc++abi, compiler-rt; Apache-2.0 with the LLVM exception) and Rust at a pinned stable tag
(rustc, cargo, std; Apache-2.0 and MIT), built once and released as artifacts that Userland,
Kernel and OS consume. Repository `EmiBSD/DevTools`, created 2026-10-31 under Governance's
decision G-0012; its definitions came from `Userland/compiler/`, its first working build is
Kernel's `just comp`. The rules that cross repositories are in `../Governance`
(`docs/invariants.md`, `decisions/`); this file is the rules inside this one.

Everything in this repository (code, comments, docs, commits) is in English. The user is
answered in Spanish.

## Non-negotiables

- **Imported class only.** Nothing here is written code: the sources are the upstreams at
  the pins of `llvm/UPSTREAM.toml` and `rust/UPSTREAM.toml`, fetched into `upstream/`
  (read-only, never committed), copied to `target/`, patched from `patches/`, built there.
  What is ours is the build glue (`build/build.sh`, `justfile`, `tools/`), the patches, and
  the documents. No source file of a toolchain is edited in place, ever.
- **Forks are mirrors.** `EmiBSD/OpenBSD-src`, `EmiBSD/rust`, `EmiBSD/llvm-project`
  (rust-lang's fork) and `EmiBSD/cargo` carry only the upstream tags and commits the pins
  name; no commit of ours lands on them. `tools/mirror.py check` verifies a pin exists on
  the mirror and on the origin with the same hash; pushing a tag to a mirror is the user's,
  from the main session.
- **Two LLVMs, by decision (2026-10-23).** rustc 1.98.1 builds the LLVM of its
  `src/llvm-project` submodule (22.1.8, rust-lang's fork); OpenBSD's `gnu/llvm` 22.1.6 at the
  pin stays the compiler of the C, with OpenBSD's patches (RETGUARD, `-fret-clean`, the fixed X18, BTI and PAC
  defaults). Nobody reconciles them.
- **Stable Rust, no nightly.** The `std` for `aarch64-unknown-openbsd` (tier 3) is built with
  `x.py` from the stable release's source as part of the toolchain. Stage0 is rustup's rustc
  on the host; on EmiBSD, the previous DevTools release. `rust-toolchain.toml` pins the host
  toolchain the build glue itself runs under.
- **The pin follows LandingZone.** `llvm/UPSTREAM.toml`'s commit of OpenBSD-src is
  LandingZone's pin (`../LandingZone/reference/PINNED.md`, the same Kernel keeps); it moves
  only when they move. The Rust pin is its own, bumped as its own commit.
- **DevTools knows nothing of the consumers' internals.** It takes a sysroot (libc, crt,
  headers) as an input, by path or by pin, and publishes artifacts with SHA-256 sums. It
  never reads `../Userland` or `../Kernel` source to decide anything.
- **Nothing installed, nothing downloaded without the user's OK.** `just fetch` is the one
  sanctioned download and runs from the main session. The guard hook refuses installs,
  pushes, amends and writes under `upstream/`.
- **The watcher reports, never bumps.** `.github/workflows/upstream-watch.yml` runs
  `tools/watch.py` daily: it compares each `UPSTREAM.toml`'s version with the upstream's
  latest release (version strings only, never sources) and opens one issue per outdated pin,
  labelled `upstream`. A pin moves only by the user's decision, in its own commit.
- **Nothing GPL** enters the tree or the artifacts (`../Governance/policies/licences.md`).
- Commit on the user's "dale", push on "súbelo"; never push otherwise.

## Directory map

```
llvm/      OpenBSD's LLVM: UPSTREAM.toml, DEFINITION, DESIGN, DELIVERY, STATUS, patches/, build/, tests/
rust/      rust-lang/rust: the same files; the two submodules pinned in UPSTREAM.toml
tools/     upstream.py (fetch and check the pins), mirror.py (the mirrors against the origins), watch.py (newer releases), cve.py (NVD)
docs/      TOOLCHAIN.md: hosts, targets, the stage0 chain, the artifact format
upstream/  the fetched sources (gitignored); target/ the builds; dist/ the artifacts
.claude/   settings, rules/, hooks/agent-guard.sh
```

## Milestones

| | Scope | Proof |
|---|---|---|
| T0 | the repository, the pins moved from Userland, the tools, the mirror check | `just fetch-check` and `just mirror-check` green |
| T1 | OpenBSD's LLVM built here for arm64 on the macOS host; Kernel's `just comp` glue moved | Kernel's `smoke-cc` and `smoke-install` pass with this clang |
| T2 | rustc with `x.py`, macOS host, target `aarch64-unknown-openbsd`, Userland's sysroot | a static Rust hello runs under Kernel in QEMU |
| T3 | GitHub releases: one tarball per host with `.sha256`; consumers fetch by pin | Userland's `just toolchain` installs it |
| T4 | self-hosted: rustc built on EmiBSD with T3 as stage0 | after Kernel's N9 |

`docs/TOOLCHAIN.md` is the plan in detail; `../Governance/docs/architecture.md` the picture.

## Working

- `just` at the root: `fetch`, `fetch-check`, `mirror-check`, `outdated`, `status`, `build <llvm|rust>`,
  `cve <llvm|rust>` (network, the user's OK). `PATH=/opt/homebrew/opt/rustup/bin:$PATH`.
- A build is long (OpenBSD's LLVM: about 2,850 C++ files per arch, half an hour on the Mac
  with the cores it gets; rustc longer): built once, cached under `target/`, never rebuilt
  by a check. `COMP_JOBS` bounds the jobs.
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
`.claude/rules/subagents.md` (the roles, when they exist) are the detail; this file points
at them.
