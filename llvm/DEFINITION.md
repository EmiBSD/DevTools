# llvm (imported; decisions D-0002, D-0003)

STATUS: see `STATUS`. Compiled from upstream LLVM at the pin of `UPSTREAM.toml`, never
rewritten, never patched with anyone else's changes; patched with ours, the EmiBSD target
(`patches/`, D-0004).

## What it gives us

One compiler for the whole system: clang and clang++ for the C and C++ of the base system
and of the imported programs, lld to link everything, the LLVM tools (`llvm-ar`,
`llvm-objcopy`, `llvm-nm`, ...), the runtimes the target needs (compiler-rt's builtins,
libunwind, libc++abi, libc++), and `libLLVM` with `llvm-config`, which is what rustc builds
against (`rust/`).

## What we build of it

Projects `clang` and `lld`; runtimes `compiler-rt`, `libunwind`, `libcxxabi`, `libcxx`;
backend `AArch64` (and `X86`, for amd64 when it returns, D-0001). Not built: lldb (open in
D-0002), the
other backends, the tests, the documentation.

## Constraints

Stage 1 runs on the host and emits for `aarch64-emibsd-emibsd8.0` (D-0004); stage 2
cross-compiles the runtimes against the sysroot it is given (`EMIBSD_SYSROOT`: libc, crt,
headers). The build refuses to run without a sysroot rather than guess one.

## Compatibility

The `*-emibsd-emibsd` target is ours (`patches/`, D-0004): upstream LLVM knows no EmiBSD.
The compiler predefines `__EmiBSD__` and nothing of any other system; what the base
system's inherited C expects beyond that (the macro it tests, the flags it was built with)
is settled in the userland repository, where that C is built, not here. The ABI the target
emits for is the one the kernel presents: `DESIGN.md`, "Patches".

## Performance budget

Upstream's `Release` build; a flag that changes the emitted code is a decision in DESIGN.

## Security history

Tracked against the upstream (`UPSTREAM.toml` `[security] cpe`): open advisories at the
pin, what the pin bump that closes them is, and `tests/cve/` for anything of ours.

| CVE | Upstream fix | Here |
|---|---|---|

## Open questions

- lldb in or out (D-0002).
- The host matrix: macOS arm64 first; Linux x86_64 only if a consumer's CI needs it.
