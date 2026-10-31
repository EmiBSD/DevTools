# llvm: integration

## How it is built

`build/build.sh` builds upstream LLVM with its own CMake and Ninja, in two stages, under
`target/llvm/`:

1. **Stage 1, the host tools.** `cmake -S upstream/llvm-project/llvm -B target/llvm/host`
   with `LLVM_ENABLE_PROJECTS=clang;lld`, `LLVM_TARGETS_TO_BUILD=AArch64;X86`,
   `LLVM_DEFAULT_TARGET_TRIPLE=aarch64-unknown-openbsd`, `CMAKE_BUILD_TYPE=Release`,
   `LLVM_ENABLE_ASSERTIONS=OFF`, `LLVM_INSTALL_UTILS=ON`; installed into
   `target/llvm/<host>/`. This is what rustc's `llvm-config` points at.
2. **Stage 2, the target runtimes.** `cmake -S upstream/llvm-project/runtimes -B
   target/llvm/runtimes` with `LLVM_ENABLE_RUNTIMES=compiler-rt;libunwind;libcxxabi;libcxx`,
   the stage-1 clang as the compiler, `CMAKE_SYSROOT=$EMIBSD_SYSROOT`, the triple
   `aarch64-unknown-openbsd`, `LIBCXX_USE_COMPILER_RT=ON`, `LIBCXXABI_USE_LLVM_UNWINDER=ON`,
   sanitizers, xray, fuzzer and profile off; installed into the stage-1 tree.

The install tree is the artifact (T3): `bin/`, `lib/`, `include/`, `lib/clang/22/`.

Flags that differ from upstream's defaults, with the reason:

| Flag | Value | Why |
|---|---|---|
| `LLVM_DEFAULT_TARGET_TRIPLE` | `aarch64-unknown-openbsd` | the system's clang emits for the system by default |
| `LLVM_TARGETS_TO_BUILD` | `AArch64;X86` | arm64 now, amd64 at Kernel's N10 (Governance G-0007); nothing else |
| `COMPILER_RT_BUILD_*` | sanitizers, xray, fuzzer, profile off | only the builtins and the runtimes the system links |
| `LLVM_ENABLE_ASSERTIONS` | `OFF` | a release compiler; assertions are for developing LLVM |

Everything else is upstream's default. There is no patch.

## Patches

None. A patch here would be EmiBSD's own change to LLVM, the user's decision, kept in
`patches/` with its reason and, if it lasts, as a commit on a branch of the fork.

## Concurrency

As upstream has it; Ninja runs `COMP_JOBS` compiles at once.

## Threat model and security

`tests/` proves the artifact: the versions the binaries print, a C hello compiled and linked
static for the target, a C++ hello against libc++; under Kernel in QEMU, that both run
(T1's proof). The CVE watch is `tools/cve.py llvm` over `llvm:llvm`.

## Dependencies

The host's CMake, Ninja, Python 3 and a C++ compiler (Apple clang on the Mac); the sysroot
for stage 2 (Userland's libc, crt and headers; until then the OpenBSD sets Kernel boots,
given by path). No stage0: LLVM bootstraps from the host compiler.
