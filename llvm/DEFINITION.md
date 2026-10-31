# llvm (imported; moved from Userland/compiler/llvm on 2026-10-31, Governance G-0012)

STATUS: see `STATUS`. Compiled from its upstream at the pin of `UPSTREAM.toml`, never
rewritten (the user's decision of 2026-10-23). OpenBSD's `gnu/llvm, gnu/usr.bin/clang, gnu/lib/libcxx, gnu/lib/libcxxabi, gnu/lib/libclang_rt, gnu/lib/libcompiler_rt`; manual llvm(1).

## What it gives us

## What we build of it

The targets, libraries and tools taken from the source; what is left out and why.

## Constraints

Which libc, libtls and other libraries of this repository it must link; static or dynamic;
privileges.

## Compatibility

Who in the base system depends on it and how (flags, output, exit codes, configuration
paths). Our patches, if any, never change what callers see.

## Configuration we ship

The defaults installed under /etc, and how they differ from upstream's.

## Performance budget

As OpenBSD builds it, on the same machine and input; a build flag that changes it is a
decision in DESIGN.

## Security history

Tracked against the upstream (`UPSTREAM.toml` `[security] cpe`): open advisories at the pin,
what the pin bump that closes them is, and `tests/cve/` for what we patched ourselves.

| CVE | Upstream fix | Here |
|---|---|---|

## Open questions

- The version at the pin is 22.1.6 (`gnu/usr.bin/clang/include/clang/Basic/Version.inc`,
  OpenBSD's `Version.inc,v 1.16 2026/05/29`), not the 18.1.8 the two-LLVMs decision of
  2026-10-23 assumed: rustc 1.98.1 (which needs 21 or newer) could build against it. Whether
  one LLVM should serve both is the maintainer's to revisit; `docs/TOOLCHAIN.md`.

- OpenBSD's patches (RETGUARD, -fret-clean, the fixed X18, BTI and PAC defaults) and its BSD-make build glue come with the tree; Kernel's `just comp` builds it this way today. The longest build of the repository: built once, cached.
