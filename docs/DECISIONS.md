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
| D-0001 | 2026-10-18 | superseded by D-0008 | arm64 first; amd64 waits for the kernel's N10 |
| D-0002 | 2026-10-31 | accepted, two points open | DevTools is its own repository: the toolchains from the forks, released as artifacts |
| D-0003 | 2026-10-31 | accepted; pin moved to `llvmorg-23.1.4` 2026-10-31 | One LLVM, upstream's, from the fork; nothing of OpenBSD in DevTools |
| D-0004 | 2026-10-31 | accepted; applied to LLVM and to Rust 2026-10-31 | EmiBSD's own target triple, `aarch64-emibsd-emibsd8.0`, carried as patches of ours |
| D-0005 | 2026-10-31 | accepted | DevTools stands alone: its rules, policies and decisions live here |
| D-0006 | 2026-10-31 | accepted | T2's scope: the kernel's target, the artifact's tools, the crates vendored by `just fetch`, the pins follow the release |
| D-0007 | 2026-10-31 | accepted | A heavy build takes the machine's lock `/tmp/emibsd/ci.lock` |
| D-0008 | 2026-11-02 | accepted | amd64 now: both architectures built, checked and released, one artifact per host and architecture; the kernel's targets carry the vendor emibsd |

---

# D-0001: arm64 first; amd64 waits for the kernel's N10

Date: 2026-10-18 · Status: superseded by D-0008 (2026-11-02)

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
- T1 is a CMake build of the fork. The watcher compares the pinned tag with upstream's
  releases.
- The pin moved on 2026-10-31, each move its own commit, by the maintainer's decision: first
  to `llvmorg-22.1.8`, the LLVM rustc 1.98.1 was released with, because the kernel's
  isolated test with the 22.1.6 artifacts had shown the two compilers emit different code
  (its text 1.5 % smaller) and the kernel asked for the versions to match before it
  switches toolchain, so that its before-and-after measurement compares who built the
  toolchain, not two LLVMs; then, the same day, to `llvmorg-23.1.4` when Rust's pin moved to
  1.99.1 (D-0006: the pins follow the release), which was released with LLVM 23.1 (its
  `src/llvm-project` submodule is at 23.1.1): the one LLVM follows the LLVM series the
  pinned rustc was released with, at that series' latest patch release (the stable releases,
  by the maintainer's decision).

Sources: `EmiBSD/llvm-project` tag `llvmorg-22.1.6` = `fc4aad7b`; `EmiBSD/rust` at 1.98.1,
`src/bootstrap/src/core/build_steps/llvm.rs` (`need >=21`).

---

# D-0004: EmiBSD's own target triple, `aarch64-emibsd-emibsd8.0`, carried as patches of ours

Date: 2026-10-31 · Status: accepted; applied to LLVM (`llvm/patches/0001` to `0005`) and to Rust (`rust/patches/0002` to `0004`) on 2026-10-31, with the documents and the build glue

## Context
With D-0003 DevTools builds upstream LLVM and Rust and nothing of OpenBSD enters it. The
target they emitted for was still named `aarch64-unknown-openbsd`: the triple upstream LLVM
and Rust already carry for the ABI EmiBSD keeps byte-identical to OpenBSD's. Three options
were put to the maintainer: keep that triple as the name of the ABI; a triple of EmiBSD's
own, which is new operating-system support written into LLVM and Rust and carried by us; or
the first now and the second only when EmiBSD's ABI diverges.

## Decision
The maintainer, 2026-10-31: the second. Nothing of OpenBSD enters DevTools; the toolchains
are kept clean of it. The toolchains emit for **`aarch64-emibsd-emibsd`** (`x86_64-emibsd-emibsd` when
amd64 returns, D-0001). The support for that target is written by us as the patch series of
`llvm/patches/` and `rust/patches/` over the pinned upstream tags, each patch with its
reason, regenerated at every pin bump, offered upstream when it is stable. The forks stay
mirrors.

The vendor field, the maintainer, 2026-10-31, offered `unknown` (the convention of the free
systems) or the project's own name: the vendor is `emibsd`, the project's name and mark
(emibsd.org): the triple is `aarch64-emibsd-emibsd`, written in full always, because LLVM reads
a short `aarch64-emibsd` as arch and vendor with no OS (its normaliser claims a component
for the vendor before the OS). `Triple::EmiBSDVendor` is part of patch 0001.

The OS version in the triple, the maintainer, 2026-10-31: this release is 8.0. As OpenBSD
(`openbsd7.6`) and FreeBSD (`freebsd14.0`) do, the triple carries the release the ABI
belongs to: `aarch64-emibsd-emibsd8.0`, `EMIBSD_OS_VERSION` in `llvm/build/build.sh`,
bumped by the maintainer in its own commit. clang names the per-target runtime directories
with the full triple, version included (`lib/aarch64-emibsd-emibsd8.0/`), so the toolchain
is used with its exact default triple. Rust's target keeps the unversioned name
`aarch64-emibsd-emibsd` (as `x86_64-unknown-freebsd`) with
`llvm-target = "aarch64-emibsd-emibsd8.0"`.

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
  sources taught the new OS; a CMake platform file for `CMAKE_SYSTEM_NAME=EmiBSD`; lld
  resolving `-l<name>` to the versioned shared library the system carries
  (`lib<name>.so.<major>.<minor>`, the name its `ld.so` looks up), because the linker that
  cross-links the userland is the system's own linker once installed, and the knowledge
  belongs in it rather than in a `lib<name>.so` link per library (the second of the options,
  chosen by the maintainer, 2026-10-31).
- **Rust** (T2): a target spec `aarch64-emibsd-emibsd` in `rustc_target` with its base
  (`vendor = "emibsd"`, `target_vendor = "emibsd"`);
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

---

# D-0006: T2's scope: the kernel's target, the artifact's tools, the crates vendored by `just fetch`, the pins follow the release

Date: 2026-10-31 · Status: accepted

## Context
T2 builds rustc with `x.py`. The kernel is to compile with these tools too; the kernel
is Rust on `aarch64-unknown-none-softfloat`, stable, no nightly, with `rustfmt`, `clippy`,
`rust-src` and `llvm-tools` in its `rust-toolchain.toml`. `x.py` downloads a stage0, a CI
LLVM, the submodules and the crates of `Cargo.lock` unless told otherwise; the git tag of a
release carries no `vendor/`. `library/backtrace` is a submodule bootstrap requires; the
`libc` crate std links comes from crates.io. Nothing is to be pinned to a commit of our
choosing.

## Decision
The maintainer, 2026-10-31:
- The kernel's target `aarch64-unknown-none-softfloat` is built by DevTools in T2: `core`,
  `alloc` and `compiler_builtins` (`x86_64-unknown-none` when amd64 returns, D-0001).
- The artifact ships rustc, `std`, cargo, clippy, rustfmt and the sources (`rust-src`);
  `llvm-tools` are `llvm/`'s.
- The crates.io dependencies are vendored once by `just fetch` (`cargo vendor --locked`,
  the versions and checksums of the release's `Cargo.lock` files) into
  `upstream/rust-vendor/`, their licences checked by `tools/crates.py` against
  `docs/POLICIES.md`; the build runs with no network. The source tarball of Rust, which
  carries `vendor/`, was not chosen: the sources come from the fork.
- The pins follow the release: the stable tag of Rust is the one pin chosen; its submodules
  (`cargo`, `backtrace`) and the crates are pinned to what that release fixes, never to a
  tag or a commit of our choosing. `backtrace` at `d902726a` has no tag upstream and that is
  right: it is what 1.98.1 ships. The `libc` crate is mirrored at the tag `0.2.185`, the
  version `library/Cargo.lock` of 1.98.1 fixes for std, and EmiBSD's bindings are a patch
  series of ours over it (D-0004).
- Two mirrors created in the organisation by the maintainer, 2026-10-31:
  `EmiBSD/rust-lang-backtrace-rs` and `EmiBSD/rust-lang-libc`.

## Consequences
- `rust/UPSTREAM.toml` carries the three submodules and `[vendor]`; `just check` is red until
  the two mirrors exist, which is the message that they are missing.
- `rust/build/build.sh` and `rust/DESIGN.md` (the plan in three slices and every
  `config.toml` line with its reason); `rust/tests/check.sh` proves slice 1 on the host.
- The kernel's target adds no patch: it is upstream's, tier 2.
- The compiler's own `libc` (0.2.183 in the root `Cargo.lock`) needs EmiBSD only when rustc
  runs on EmiBSD (T4); it is then patched the same way.

---

# D-0007: A heavy build takes the machine's lock `/tmp/emibsd/ci.lock`

Date: 2026-10-31 · Status: accepted

## Context
DevTools and the kernel repository build on the same Mac, and a toolchain build takes the
cores it is given for half an hour or more. The kernel repository's agent asked, through
the maintainer, that DevTools take the lock `/tmp/emibsd/ci.lock` for its heavy builds, as
its own heavy runs do, so that the two never run at once. That is a convention of the
machine, not of any repository's internals; this record is DevTools' own copy of it
(D-0005).

## Decision
The maintainer, 2026-10-31: `just build <name>` runs `build/build.sh` under the lock
`/tmp/emibsd/ci.lock` (`tools/lock.py`; it says when it waits and for how long it waited).
Nothing else of DevTools takes it: `just dist`, the checks and the fetches are light. The
mechanism is the kernel repository's, learned the same day when the two met: the lock is a
**directory** made with `mkdir(2)`, atomic, held while it exists and removed by its holder.
DevTools' first version used `flock(2)` on a file of that name, which left a file in the way
of the kernel's `mkdir`; replaced the same day. A `pid` file inside names a DevTools holder,
and a directory whose DevTools holder is dead is taken over; another repository's holder is
never judged.

## Consequences
- `justfile`'s `build` recipe runs through `tools/lock.py`; `COMP_JOBS` keeps bounding the
  jobs of a build once it runs.
- A build started by hand with `sh <name>/build/build.sh` takes no lock: `just build` is the
  way.

---

# D-0008: amd64 now: both architectures built, checked and released, one artifact per host and architecture; the kernel's targets carry the vendor emibsd

Date: 2026-11-02 · Status: accepted

## Context
D-0001 kept amd64 out of the toolchains until the kernel's milestone N10: the `X86` backend
compiled, no amd64 target built, tested, documented or released. A consumer's pipelines
already run for amd64 and need the toolchain now. The kernel's targets were upstream's,
`aarch64-unknown-none-softfloat` (D-0006), with the vendor `unknown`, while the system's carry
EmiBSD's own vendor (D-0004).

## Decision
The maintainer, 2026-11-02:
- amd64 is a target of DevTools from now on, beside arm64: `x86_64-emibsd-emibsd8.0` for the
  system (LLVM's runtimes and Rust's `std`, against the amd64 sysroot). D-0001 is superseded
  here. arm64 stays first: clang's default triple is arm64's; x86_64 is reached through
  `x86_64-emibsd-emibsd8.0-clang` or `--target`.
- The kernel's targets carry the vendor `emibsd`, as the system's do: `aarch64-emibsd-none-softfloat`
  and `x86_64-emibsd-none-softfloat` (`core`, `alloc` and `compiler_builtins`), upstream's
  `aarch64-unknown-none-softfloat` and `x86_64-unknown-none` with the vendor changed and
  nothing else; LLVM keys nothing on the vendor, so they emit the same code. Both are named
  `-softfloat`: the kernel uses no floating-point or vector registers, and upstream's x86_64
  bare-metal target is softfloat without saying so in its name. This replaces the kernel's
  target of D-0006.
- On x86_64 the driver turns on `-fcf-protection=branch` and `-fno-jump-tables`, as
  DESIGN.md had planned: upstream's driver emits both for OpenBSD on x86_64, and patch 0003
  already lets EmiBSD into that branch; LLVM's series does not change.
- One complete tarball per host and target architecture,
  `<name>-<version>-<host>-<arch>.tar.zst` with `<arch>` `arm64` or `amd64`, each with the
  same host tools and only its own architecture's runtimes and Rust targets.

## Consequences
- The sysroot is given per architecture: `EMIBSD_SYSROOT_ARM64` and `EMIBSD_SYSROOT_AMD64`
  replace `EMIBSD_SYSROOT`; the builds, the checks and `just dist` refuse to run without them.
- `llvm/build/build.sh` runs stage 2 once per triple and installs clang's links
  `<triple>-clang` and `<triple>-clang++` (`CLANG_LINKS_TO_CREATE`): rustc passes no
  `--target` to a cc linker, so a Rust program for a target links through the clang named
  after it.
- `rust/patches/0002` carries the four targets, tier 3: `aarch64-emibsd-emibsd`,
  `x86_64-emibsd-emibsd` (`llvm-target` `<arch>-emibsd-emibsd8.0`), `aarch64-emibsd-none-softfloat`
  (`aarch64-emibsd-none`) and `x86_64-emibsd-none-softfloat` (`x86_64-emibsd-none-elf`). `std` and the
  `libc` crate need nothing more for x86_64: their OpenBSD code, which EmiBSD joins, already
  selects it.
- The kernel's build names the new targets in its `rust-toolchain.toml` and its build when it
  takes this release; the upstream `-unknown-none` targets are no longer built here.
- `tests/check.sh` checks every architecture. On x86_64 the branch protection is read in the
  code (`main` starts with `endbr64`), not in `.note.gnu.property`: the amd64 libc's assembly
  starts with `endbr64` but carries no note, so the note does not survive a static link. That
  is the sysroot's, not DevTools'.
- `tools/dist.py` packs one tarball per architecture and checks each unpacked. The releases
  `llvm-23.1.4+emibsd.1` and `rust-1.99.1+emibsd.1` of 2026-10-31, arm64 alone, were deleted
  with their tags and made again under the same versions from the commit that carries this
  decision, with both architectures; their sums changed.
- T4 (self-hosting) stays arm64 first.
