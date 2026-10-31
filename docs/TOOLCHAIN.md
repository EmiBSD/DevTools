# The toolchains: hosts, targets, the chain, the artifacts

## Two LLVMs

| | Version | From | Builds | Why |
|---|---|---|---|---|
| `llvm/` | 18.1.8 at OpenBSD's pin | `OpenBSD-src` `gnu/llvm` + `gnu/usr.bin/clang` + `gnu/lib/libcxx*`, `libclang_rt`, `libcompiler_rt` | clang, lld, libc++, libc++abi, compiler-rt | the C of the base system is built with the compiler OpenBSD builds it with, patches included (RETGUARD, `-fret-clean`, the fixed X18, BTI and PAC) |
| inside `rust/` | 21 at rust's submodule | `llvm-project` (rust-lang's fork) | rustc's backend only | rustc 1.98.1 refuses an LLVM below 21 (`src/bootstrap`, `check_llvm_version`) |

Decided 2026-10-23; nobody reconciles them. The clang of `llvm/` is never used to build
rustc's LLVM and rustc's LLVM never emits the system's C.

## Hosts and targets

| Host | Target | When | Stage0 for `rust/` |
|---|---|---|---|
| `aarch64-apple-darwin` | `aarch64-unknown-openbsd` | T1, T2: the development machine | rustup's 1.98.1 (`rust-toolchain.toml`) |
| `x86_64-unknown-linux-gnu` | `aarch64-unknown-openbsd` | only if a consumer's CI needs it (open decision) | rustup's |
| `aarch64-unknown-openbsd` | itself | T4, after Kernel's N9 | the previous DevTools release |

amd64 as a target waits for Kernel's N10 (Governance G-0007).

## Inputs a build takes

| Variable | Meaning | Default |
|---|---|---|
| `EMIBSD_SYSROOT` | the target's libc, crt, headers (Userland's tree, or the OpenBSD sets Kernel boots) | none: the build refuses to guess |
| `EMIBSD_CC`, `EMIBSD_LLVM_BIN` | the host compiler and LLVM tools that build the toolchains (Apple clang and an LLD 17 or newer with OpenBSD support, as Kernel's `just comp` uses today) | `/usr/bin/clang`, `~/.swiftly/bin` |
| `COMP_JOBS` | parallel jobs | 6 |
| `SOURCE_DATE_EPOCH` | the commit's time, for reproducible archives | set by the justfile |

## The chain

1. **T1.** `llvm/build/build.sh` is Kernel's `xtask comp` moved here: OpenBSD's BSD-make glue
   evaluated the way `bsdmake.rs` does, the ~2,850 C++ files per arch, into
   `target/llvm/<arch>/root`. Kernel's `smoke-cc` boots that root as its comp disk.
2. **T2.** `rust/build/build.sh` runs `x.py dist` with a `config.toml` that names the host,
   the target `aarch64-unknown-openbsd`, the linker (T1's lld), the sysroot, and
   `llvm.download-ci-llvm = false` so the submodule's LLVM is built. `std`'s rlibs need no
   libc to compile; the test program needs the sysroot to link.
3. **T3.** `dist/<name>-<version>-<host>.tar.zst` and `.sha256`, from a tagged commit,
   uploaded as a GitHub release of this repository. A consumer's recipe downloads by version
   and verifies the sum. Signed with signify when Userland ships it.
4. **T4.** The same `x.py` on EmiBSD, stage0 the T3 artifact for `aarch64-unknown-openbsd`.
   From then on each release builds from the previous one; the first cross-built one is the
   root of trust and is recorded here with its hash.

## Versions

`<upstream version>+emibsd.<N>`: the upstream's version and our patch level, as
`UPSTREAM.toml` carries it (`18.1.8+emibsd.1`, `1.98.1+emibsd.1`). A pin bump is its own
commit; `N` resets to 1 on a bump and rises with each patch series change at the same pin.
