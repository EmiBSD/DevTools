# The toolchains: hosts, targets, the chain, the artifacts

## One LLVM (Governance G-0015)

| | Version | From | Builds |
|---|---|---|---|
| `llvm/` | `llvmorg-22.1.6` | the fork `EmiBSD/llvm-project` at upstream's tag, as upstream ships it | clang, lld, the tools; compiler-rt, libunwind, libc++abi, libc++ for `aarch64-unknown-openbsd` |

It compiles the C and C++ of the system and it is the backend rustc builds against
(rustc 1.98.1 needs LLVM 21 or newer). Nothing of OpenBSD enters DevTools: no LLVM code, no
patches, no build glue. rustc's own `src/llvm-project` submodule is not fetched.

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
| `EMIBSD_SYSROOT` | the target's libc, crt, headers, for LLVM's stage 2 and for linking Rust programs (Userland's tree; until it exists, the OpenBSD sets Kernel boots, by path) | none: the build refuses to guess |
| `COMP_JOBS` | parallel jobs | 6 |
| `SOURCE_DATE_EPOCH` | the commit's time, for reproducible archives | set by the justfile |

Host tools: CMake, Ninja, Python 3, the host's C++ compiler (Apple clang on the Mac).
Installing any of them is the user's.

## The chain

1. **T1.** `llvm/build/build.sh`: stage 1 the host tools, stage 2 the target runtimes
   (`llvm/DESIGN.md`). Proof: a C hello and a C++ hello, compiled for the target and run under
   Kernel in QEMU.
2. **T2.** `rust/build/build.sh` runs `x.py dist` with a `config.toml` that names the host,
   the target `aarch64-unknown-openbsd`, `llvm-config` from T1, the linker (T1's lld), the
   sysroot, and `llvm.download-ci-llvm = false`. `std`'s rlibs need no libc to compile; the
   hello needs the sysroot to link. Needs the `backtrace-rs` mirror first.
3. **T3.** `dist/<name>-<version>-<host>.tar.zst` and `.sha256`, from a tagged commit,
   uploaded as a GitHub release of this repository. A consumer's recipe downloads by version
   and verifies the sum. Signed with signify when Userland ships it.
4. **T4.** The same `x.py` on EmiBSD, stage0 the T3 artifact for `aarch64-unknown-openbsd`.
   From then on each release builds from the previous one; the first cross-built one is the
   root of trust and is recorded here with its hash.

## Versions

`<upstream version>+emibsd.<N>`: the upstream's version and our patch level, as
`UPSTREAM.toml` carries it (`22.1.6+emibsd.1`, `1.98.1+emibsd.1`). A pin bump is its own
commit; `N` resets to 1 on a bump and rises with each change of ours at the same pin.
