# EmiBSD DevTools

<p align="center">
  <img src="docs/Ferffy.jpg" alt="Ferffy, the EmiBSD mascot: a centolla, the spiky orange crab of the southern seas, in front of a shield, above the EmiBSD name" width="380">
</p>

<p align="center"><em>Ferffy, the EmiBSD mascot: a <a href="https://en.wikipedia.org/wiki/Lithodes_santolla">centolla</a>, the child of Ferris (Rust's crab) and Puffy (OpenBSD's pufferfish).</em></p>

<p align="center"><strong>The toolchains of EmiBSD, imported from the forks and built once: upstream LLVM for the C and for rustc, a pinned stable Rust, plus the patch series that teaches them the EmiBSD target.</strong></p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-ISC-007ec6" alt="License: ISC"></a>
  <a href="rust-toolchain.toml"><img src="https://img.shields.io/badge/dynamic/toml?url=https%3A%2F%2Fraw.githubusercontent.com%2FEmiBSD%2FDevTools%2Fmain%2Frust-toolchain.toml&query=%24.toolchain.channel&suffix=%20stable&label=rust&color=b7410e" alt="Rust: stable, the version pinned in rust-toolchain.toml"></a>
  <a href="#milestones"><img src="https://img.shields.io/badge/milestone-T1%2C%20T2%20and%20T3%20released%3B%20QEMU%20proof%20pending-007ec6" alt="Milestone: T1, T2 and T3 released; QEMU proof pending"></a>
  <a href="#milestones"><img src="https://img.shields.io/badge/status-experimental-e05d44" alt="Status: experimental"></a>
  <a href="https://www.emibsd.org"><img src="https://img.shields.io/badge/website-emibsd.org-9f9f9f" alt="Website: www.emibsd.org"></a>
</p>

> **Not for production.** EmiBSD is an experiment. It runs only in QEMU, and its crypto,
> network and storage code is unaudited. Do not use it to protect real data or real networks.

The toolchains of [EmiBSD](https://www.emibsd.org), both imported, both from the forks alone,
built once for every repository that needs them:

- **`llvm/`**: upstream LLVM at the tag `llvmorg-22.1.8`, from the fork `EmiBSD/llvm-project`,
  built with its own CMake: clang, lld, the tools, and compiler-rt, libunwind, libc++abi and
  libc++ for `aarch64-emibsd-emibsd8.0`, the target our patch series teaches it (decision
  D-0004). Apache-2.0 with the LLVM exception. The one compiler
  of the system, and the backend of rustc.
- **`rust/`**: rust-lang/rust at the tag `1.98.1`, from the fork `EmiBSD/rust`, built with `x.py`
  against `llvm/`'s LLVM, from the vendored crates of its own `Cargo.lock`, with no network:
  rustc, cargo, rustdoc, clippy, rustfmt and `rust-src`; `std` for the host; `core` and `alloc`
  for the kernel's `aarch64-unknown-none-softfloat`; `std` for `aarch64-emibsd-emibsd`, a tier 3
  target that this way gets its standard library from a stable release's source, without
  nightly (our patch series teaches rustc, std and the libc crate the target). Apache-2.0 and MIT.

No toolchain here is ours, and nothing of it comes from OpenBSD (decision D-0003 of
`docs/DECISIONS.md`). The sources come from the read-only mirrors `llvm-project`, `rust`,
`cargo`, `backtrace-rs` and `libc`, pinned in each `UPSTREAM.toml` to what the stable release
fixes; what is ours is the build glue, the patch series that adds the EmiBSD target (ISC, each
patch with its reason: `llvm/patches/`, `rust/patches/`) and the artifacts.

The build scripts, the documents and the commits of this repository are written by Claude
Code agents under its written rules (`CLAUDE.md`, `.claude/rules/`); the maintainer, Emilio
Navarrete Lineros, takes every decision and approves every commit (`docs/POLICIES.md`).

EmiBSD is not affiliated with or endorsed by the OpenBSD project, the LLVM project or the
Rust project.

## Where it sits

```mermaid
flowchart LR
    llvm["llvm-project (mirror)"] -- "llvmorg-22.1.8" --> dev["DevTools"]
    rust["rust, cargo (mirrors)"] -- "1.98.1" --> dev
    dev -- "clang, lld, libc++; rustc" --> ul["the userland"]
    dev -- "clang, lld; rustc with core and alloc for its target" --> k["the kernel"]
    dev -- "the comp set" --> os["the releases"]
    ul -. "sysroot: libc, crt, headers" .-> dev
```

DevTools knows nothing of its consumers' internals: it takes a sysroot as an input and
publishes artifacts with checksums. `docs/TOOLCHAIN.md` has the inputs, the outputs, the
hosts and the chain; `docs/DECISIONS.md` why the repository exists (D-0002) and why nothing
of OpenBSD is in it (D-0003).

## Milestones

| | Scope | Proof | State |
|---|---|---|---|
| T0 | the repository, the pins, the tools, the mirror check | `just check` green | met 2026-10-31 |
| T1 | upstream LLVM 22.1.8 built from the fork with CMake on the macOS host: the host tools, then the target runtimes | a C and a C++ hello compiled for the target run under the EmiBSD kernel in QEMU | built and checked on the host 2026-10-31 (`llvm/tests/check.sh`); the QEMU run pending |
| T2 | rustc with `x.py` against T1's LLVM, macOS host, target `aarch64-emibsd-emibsd` (decision D-0004: its target spec and `std` paths as `rust/patches/`) and the kernel's `aarch64-unknown-none-softfloat` (D-0006), the userland's sysroot | a static Rust hello runs under the EmiBSD kernel in QEMU | built and checked on the host 2026-10-31 (`rust/tests/check.sh`): rustc, the tools, `std` for the host and for `aarch64-emibsd-emibsd`, `core`/`alloc` for the kernel's target; the QEMU run pending |
| T3 | GitHub releases: one tarball per host with `.sha256`; consumers fetch by pin | a consumer's toolchain recipe installs it from the release | released 2026-10-31: `llvm-22.1.6+emibsd.3` (65 MB: the compiler, the linker and the binutils, `llvm/DESIGN.md`) and `rust-1.98.1+emibsd.2` (140 MB), each with its `.sha256`; the kernel built and booted with them the same day (its own isolated test); next: `llvm-22.1.8+emibsd.1`, the LLVM rustc 1.98.1 was released with, and `rust-1.98.1+emibsd.3` built against it |
| T4 | self-hosted: rustc built on EmiBSD with T3 as stage0 | after the kernel's N9, when no inherited tree is left | |

## Using it

```
just status          # the two toolchains, their STATUS and version
just mirror-check    # every pin exists on its mirror and its origin with the same hash
just outdated        # is any pin behind its upstream's latest release? (the daily workflow files an issue)
just fetch           # clone the pinned sources into upstream/ (network)
just fetch-check     # the fetched sources match the pins
just build llvm      # build one toolchain into target/ (long: built once, cached; under /tmp/emibsd/ci.lock); `just build rust` after it
just crates rust     # the licences of the vendored crates, against docs/POLICIES.md
just dist llvm       # the artifact: dist/<name>-<version>-<host>.tar.zst and .sha256, checked unpacked elsewhere
just release llvm    # the GitHub release from a tagged commit (the maintainer's)
just check           # what costs nothing: pins, mirrors, licences, scripts
```

`docs/TOOLCHAIN.md` has the hosts, the targets, the stage0 chain and the artifact format;
`docs/DECISIONS.md`, `docs/POLICIES.md` and `docs/PROCESS.md` the rules the repository
works under. It carries all of them itself and cites no other repository's files.

## Licence

The build scripts, the patches and the documents are ISC ([LICENSE](LICENSE)). The toolchains
keep their own licences, in their sources and in each artifact's `share/doc/emibsd/`; the
vendored crates are checked against `docs/POLICIES.md` at every pin bump.
