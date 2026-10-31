# llvm (imported; Governance G-0012, G-0015)

STATUS: see `STATUS`. Compiled from upstream LLVM at the pin of `UPSTREAM.toml`, never
rewritten, never patched with anyone else's changes.

## What it gives us

One compiler for the whole system: clang and clang++ for the C and C++ of the base system
and of the imported programs, lld to link everything, the LLVM tools (`llvm-ar`,
`llvm-objcopy`, `llvm-nm`, ...), the runtimes the target needs (compiler-rt's builtins,
libunwind, libc++abi, libc++), and `libLLVM` with `llvm-config`, which is what rustc builds
against (`rust/`).

## What we build of it

Projects `clang` and `lld`; runtimes `compiler-rt`, `libunwind`, `libcxxabi`, `libcxx`;
backend `AArch64` (and `X86`, for Kernel's N10). Not built: lldb (open in G-0012), the
other backends, the tests, the documentation.

## Constraints

Stage 1 runs on the host and emits for `aarch64-unknown-openbsd`; stage 2 cross-compiles the
runtimes against the sysroot it is given (`EMIBSD_SYSROOT`: libc, crt, headers). The build
refuses to run without a sysroot rather than guess one.

## Compatibility

Upstream's defaults for the `*-unknown-openbsd` triple, which upstream clang and lld
support. What the base system's C expects of a compiler beyond upstream (flags of OpenBSD's
own clang) is settled in Userland, where that C is built, not here.

## Performance budget

Upstream's `Release` build; a flag that changes the emitted code is a decision in DESIGN.

## Security history

Tracked against the upstream (`UPSTREAM.toml` `[security] cpe`): open advisories at the
pin, what the pin bump that closes them is, and `tests/cve/` for anything of ours.

| CVE | Upstream fix | Here |
|---|---|---|

## Open questions

- lldb in or out (G-0012).
- The host matrix: macOS arm64 first; Linux x86_64 only if a consumer's CI needs it.
