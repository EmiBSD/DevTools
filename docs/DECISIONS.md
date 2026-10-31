# Decision log

The decisions that shape this repository, one entry each, numbered in the order they were
recorded, never renumbered, never deleted. The documents and rules of this repository cite
them as `decision D-0003`. A decision is the maintainer's; the agents propose and record.

The first four were recorded here on 2026-10-31, when this repository stopped citing the
project-wide log and took its own copy of what binds it (D-0005); there they were G-0007,
G-0012, G-0015 and G-0016. The date is the day the decision was taken.

## Format

```
# D-NNNN: <title>

Date: YYYY-MM-DD · Status: proposed | accepted | superseded by D-MMMM

## Context      what was the question, and the options
## Decision     what was decided, by the maintainer, in one or two sentences
## Consequences what it changes here, what it rules out
```

## Index

| Id | Date | Status | Title |
|---|---|---|---|
| D-0001 | 2026-10-18 | accepted | arm64 first; amd64 waits for the kernel's N10 |
| D-0002 | 2026-10-31 | accepted, two points open | DevTools is its own repository: the toolchains from the forks, released as artifacts |
| D-0003 | 2026-10-31 | accepted | One LLVM, upstream's, from the fork; nothing of OpenBSD in DevTools |
| D-0004 | 2026-10-31 | accepted, not yet applied | EmiBSD's own target triple, `aarch64-unknown-emibsd`, carried as patches of ours |
| D-0005 | 2026-10-31 | accepted | DevTools stands alone: its rules, policies and decisions live here |

---

# D-0001: arm64 first; amd64 waits for the kernel's N10

Date: 2026-10-18 · Status: accepted

## Context
Keeping two architectures green doubled every slice's cost while the design questions were
the same on both.

## Decision
Only arm64 is built, booted and measured until the kernel's milestone N10 homologates amd64.

## Consequences
The toolchains target `aarch64` first; the first releases are arm64 only. LLVM's backends
are `AArch64` and `X86`, so that amd64 needs no rebuild when it returns; no amd64 target is
tested, documented or released before then.

---

# D-0002: DevTools is its own repository: the toolchains from the forks, released as artifacts

Date: 2026-10-31 · Status: accepted, two points open

## Context
The toolchains were defined under the userland repository as imported programs with nothing
built, and the only working toolchain build lived in the kernel repository's recipes. The
maintainer's sketch of 2026-10-31 put the toolchain in a repository of its own, fed by the
forks, consumed by the kernel, the userland and the release repository.

## Decision
The repository `EmiBSD/DevTools`, created by the maintainer on 2026-10-31, holds the
toolchains: it fetches the pinned upstreams from the organisation's mirrors, builds them once
and releases them as artifacts with checksums. Milestones T0 to T4 (`CLAUDE.md`). The
pins were copied from the userland repository's `compiler/` on the same day (T0).

## Consequences
- The forks `EmiBSD/llvm-project`, `EmiBSD/rust` and `EmiBSD/cargo` stay read-only mirrors;
  our patches live here, in `patches/`, each with its reason.
- DevTools knows nothing of its consumers' internals: it takes a sysroot as an input and
  publishes artifacts; it never reads another repository to decide anything.
- The kernel repository keeps its own clang build for the inherited userland it boots; it is
  not moved here (D-0003).

## Open (the maintainer's)
- lldb in or out of the LLVM build.
- The hosts beyond macOS arm64: Linux x86_64 only if a consumer's CI needs it; arm64 EmiBSD
  at T4.

---

# D-0003: One LLVM, upstream's, from the fork; nothing of OpenBSD in DevTools

Date: 2026-10-31 · Status: accepted

## Context
An earlier design (2026-10-23) took "LLVM as OpenBSD ships it" from `gnu/llvm` inside the
OpenBSD tree, with OpenBSD's patches and BSD-make glue, and kept a second LLVM for rustc
because OpenBSD's was believed to be 18.1.8. At the pin it is 22.1.6. The agent then
proposed, in sequence, the fork's code with OpenBSD's patches and glue, then without the
glue; each kept a piece of OpenBSD in DevTools against the maintainer's instruction.

## Decision
The maintainer, 2026-10-31, stated three times: **DevTools takes nothing from OpenBSD.** Not
LLVM's code, not OpenBSD's patches to it, not OpenBSD's build glue. DevTools' LLVM is
upstream LLVM at the tag `llvmorg-22.1.6`, from the mirror `EmiBSD/llvm-project`, built with
LLVM's own CMake for the host and for the target. One LLVM: it compiles the C and the C++ of
the system and it is the backend rustc 1.98.1 builds against (`llvm-config`; rustc needs 21
or newer). `OpenBSD-src` is not an input of DevTools in any form.

## Consequences
- `rust/UPSTREAM.toml` pins no `src/llvm-project` submodule: rustc builds against this
  LLVM. `llvm/UPSTREAM.toml` pins the mirror at the upstream tag with
  `origin = llvm/llvm-project`.
- OpenBSD's compiler changes (RETGUARD, `-fret-clean`, the reserved X18, BTI and PAC
  defaults) are not in this compiler. Whatever the base system's C needs of them is the
  userland repository's matter, where that C is built; if the maintainer ever wants such
  hardening here, it is EmiBSD's own patch, decided then, never taken from OpenBSD's tree.
- T1 is a CMake build of the fork. The watcher compares `llvmorg-22.1.6` with upstream's
  releases.

Sources: `EmiBSD/llvm-project` tag `llvmorg-22.1.6` = `fc4aad7b`; `EmiBSD/rust` at 1.98.1,
`src/bootstrap/src/core/build_steps/llvm.rs` (`need >=21`).

---

# D-0004: EmiBSD's own target triple, `aarch64-unknown-emibsd`, carried as patches of ours

Date: 2026-10-31 · Status: accepted, not yet applied to this repository's documents and build glue

## Context
With D-0003 DevTools builds upstream LLVM and Rust and nothing of OpenBSD enters it. The
target they emitted for was still named `aarch64-unknown-openbsd`: the triple upstream LLVM
and Rust already carry for the ABI EmiBSD keeps byte-identical to OpenBSD's. Three options
were put to the maintainer: keep that triple as the name of the ABI; a triple of EmiBSD's
own, which is new operating-system support written into LLVM and Rust and carried by us; or
the first now and the second only when EmiBSD's ABI diverges.

## Decision
The maintainer, 2026-10-31: the second. "No quiero nada de OpenBSD en DevTools; son tools
sanas." The toolchains emit for **`aarch64-unknown-emibsd`** (`x86_64-unknown-emibsd` when
amd64 returns, D-0001). The support for that target is written by us as the patch series of
`llvm/patches/` and `rust/patches/` over the pinned upstream tags, each patch with its
reason, regenerated at every pin bump, offered upstream when it is stable. The forks stay
mirrors.

## Consequences
- **DevTools stops being imported-only.** The target support is written code, ISC, in
  `patches/`. Its size is counted in each release's DELIVERY.md and the series is the first
  thing a pin bump must re-apply. `CLAUDE.md`'s "imported class only" is to be reworded
  when the series exists.
- **LLVM** (T1): the OS `EmiBSD` in `llvm/lib/TargetParser/Triple.cpp`; a clang toolchain
  driver `clang/lib/Driver/ToolChains/EmiBSD.cpp` (the crt files, PIE by default, lld,
  compiler-rt, libc++, the `ld.so` path, `-z` defaults: what the ABI needs, written from the
  ABI, not copied from OpenBSD's driver); the target info in
  `clang/lib/Basic/Targets/OSTargets.h` defining `__EmiBSD__`; the runtimes' CMake and
  sources taught the new OS; a CMake platform file for `CMAKE_SYSTEM_NAME=EmiBSD`.
- **Rust** (T2): a target spec `aarch64-unknown-emibsd` in `rustc_target` with its base;
  `std`'s `target_os = "emibsd"` paths; the `libc` crate's bindings for the new OS, which
  rust vendors, as a patch here too. Tier 3 by upstream's rules; `std` still built from the
  stable release's source, no nightly.
- What the compiler defines for the inherited C of the userland (`__OpenBSD__`,
  `__EmiBSD__` or both) is decided in the userland repository, not here.
- Upstreaming: an OS target needs a maintainer upstream; until EmiBSD is one, the series is
  carried, and its re-application is the cost of each pin bump.

---

# D-0005: DevTools stands alone: its rules, policies and decisions live here

Date: 2026-10-31 · Status: accepted

## Context
`CLAUDE.md`, the rules under `.claude/rules/` and the documents cited a project-wide
repository of rules and decisions by relative path and by decision number, and the subagent
contract cited the userland repository's. A reader of this repository alone could not know
what bound it, and a session working here was pulled into another repository's files.

## Decision
The maintainer, 2026-10-31: DevTools cuts the relation. Everything it needs is copied into
this repository and nothing here references another repository's files. What binds the
whole project is restated here in the form it takes for a toolchain repository:
`docs/POLICIES.md` (licences, dependencies, the disclosure of the AI process),
`docs/PROCESS.md` (who decides, what a commit needs), this log, and `.claude/rules/`.

## Consequences
- Other repositories are named only as what they are to this one: the consumers of the
  artifacts (the kernel, the userland, the release repository) and the source of the sysroot.
  No path into them, no citation of their rules or logs.
- A decision taken elsewhere that binds this repository is recorded here, in this log, in its
  own words, before it is acted on.
