# rust: integration

## How it is built

The source at the pin (`UPSTREAM.toml`: rust-lang/rust 1.98.1 from the fork, with the
`cargo` and `backtrace` submodules it fixes, and the crates.io dependencies `just fetch`
vendored from its `Cargo.lock` files into `upstream/rust-vendor/`), copied to
`target/rust/src`, `patches/` applied, built by `build/build.sh` with Rust's own `x.py`,
against `llvm/`'s LLVM and the sysroot it is given (`EMIBSD_SYSROOT`: the userland's libc,
crt and headers). Nothing is downloaded by the build: stage0 is the host's pinned rustc and
cargo (`rust-toolchain.toml`), the crates come from the vendor directory, no submodule is
updated, no CI LLVM is fetched.

The plan of T2 (the maintainer, 2026-10-31, D-0006), in three slices:

1. **Glue, no patches.** `build.sh` and its `config.toml`; `x.py install` of rustc, cargo,
   clippy, rustfmt and the sources for the host, `std` for the host, `core` and `alloc` for
   the kernel's target `aarch64-unknown-none-softfloat`. Proof, `tests/check.sh`: the versions,
   `rustc -vV` naming `llvm/`'s LLVM, a host hello that runs, a `no_std` crate for the
   kernel's target.
2. **The target.** `patches/`: the spec `aarch64-emibsd-emibsd` (`llvm-target`
   `aarch64-emibsd-emibsd8.0`, vendor `emibsd`), `std`, `unwind` and `backtrace` with
   `emibsd` beside `openbsd` where the libc interface is the same, the `libc` crate from its
   mirror with EmiBSD's bindings, wired with `[patch.crates-io]`. `std` for the target;
   proof: a static Rust hello linked by `llvm/`'s clang against the sysroot.
3. **The artifact.** The install tree as `rustup toolchain link` takes it, DELIVERY.md
   measured, STATUS `built`. The run under the kernel in QEMU is the kernel repository's.

## Flags that differ from upstream's defaults, with the reason

`build.sh` writes `target/rust/config.toml`; every line is here.

| Key | Value | Why |
|---|---|---|
| `build.rustc`, `build.cargo` | the host's pinned 1.98.1 (`rustup which`) | stage0 without the download of `src/stage0`'s beta; real paths, because the rustup proxies pick a toolchain by the directory x.py runs cargo in |
| `build.local-rebuild` | `true` | stage0 is the same version as the source, not the previous beta |
| `build.submodules` | `false` | the submodules come from the mirrors at the pins; x.py never runs git against upstream URLs |
| `build.vendor`, `build.locked-deps` | `true` | cargo reads `.cargo/config.toml` of the copy, which points at `upstream/rust-vendor/`; `--frozen`: nothing resolves anew |
| `build.target` | the host, `aarch64-unknown-none-softfloat` (slice 2: `aarch64-emibsd-emibsd`) | the kernel's target gets `core` and `alloc` from here (D-0006); the system's target gets `std` |
| `build.extended`, `build.tools` | `true`; `cargo`, `clippy`, `rustfmt`, `src` | what the kernel's `rust-toolchain.toml` asks of a toolchain; `llvm-tools` come from `llvm/` |
| `build.docs`, `build.compiler-docs` | `false` | not shipped |
| `build.optimized-compiler-builtins` | the path of `target/llvm/src/compiler-rt` | the C builtins from the pinned, patched LLVM source rather than the unfetched `src/llvm-project` submodule |
| `build.patch-binaries-for-nix` | `false` | not Nix |
| `install.prefix` | `target/rust/<host>/` | the artifact's tree |
| `llvm.download-ci-llvm` | `false` | one LLVM (D-0003) |
| `llvm.link-shared` | `false` | rustc carries its LLVM statically, as the T1 install provides the static libraries |
| `rust.channel` | `stable` | the source is a stable release; nightly features stay off |
| `rust.description` | `EmiBSD DevTools` | `rustc --version` says where it came from |
| `rust.download-rustc` | `false` | nothing downloaded |
| `rust.jemalloc` | `false` | the system's malloc |
| `rust.llvm-tools` | `true` | `llvm-tools` component from `llvm/`'s LLVM, as rustup ships it |
| `rust.lld` | `false` | the linker is `llvm/`'s lld through its clang driver, not a bundled `rust-lld` |
| `target.<host>.llvm-config` | `target/llvm/<host>/bin/llvm-config` | rustc's backend is `llvm/`'s LLVM (D-0003) |
| `target.aarch64-unknown-none-softfloat.cc`, `.ar` | `llvm/`'s clang and llvm-ar | the C sources of `compiler_builtins` for the kernel's target |

## Licences of the vendored crates (docs/POLICIES.md)

`tools/crates.py` (`just crates rust`, part of `just check`) reads every crate of
`upstream/rust-vendor/`: 978 at 1.98.1, nothing GPL (`self_cell` is Apache-2.0 OR
GPL-2.0-only; the Apache side applies). Six are MPL-2.0, the family POLICIES.md admits with a
written reason, which is this: MPL-2.0 is a file-level copyleft, it obliges to keep the source
of those files available under MPL, which the vendor directory, made from the release's
`Cargo.lock` by `just fetch`, does; it reaches none of our code nor the toolchains'.
- `im-rc`, with `bitmaps` and `sized-chunks` (MPL-2.0+): cargo's persistent collections, inside
  the cargo binary as upstream ships it.
- `option-ext`: through `dirs-sys`, cargo's and rustfmt's home directories.
- `fortanix-sgx-abi`: a dependency of `std` for the SGX target only; not compiled for ours.
- `colored`: used by `compiletest`, `miri` and `ui_test`, test tools neither built nor shipped.

## Patches

One line per patch of `patches/`: what it changes and why it could not stay upstream.
None yet: slice 2 of T2 writes the series of the target (D-0004).

## Concurrency

As upstream has it; nothing added.

## Threat model and security

What the upstream restricts and the proof we kept it: the tests that run it under our kernel.

## Dependencies

The sysroot it links against (`EMIBSD_SYSROOT`), the stage0 it bootstraps from (the host's
pinned toolchain; on EmiBSD, the previous DevTools release), `llvm/`'s `llvm-config`, the
submodules and crates `UPSTREAM.toml` pins; their licences checked by `tools/crates.py`
against `docs/POLICIES.md` at every pin bump.
