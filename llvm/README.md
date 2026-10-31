# llvm

Upstream LLVM at the pinned release tag, from the fork `EmiBSD/llvm-project`, built with
LLVM's own CMake: clang, lld, LLVM's tools, and the runtimes compiler-rt, libunwind, libc++abi
and libc++ for `aarch64-emibsd-emibsd8.0`, the target our patch series teaches it (decision
D-0004). The one LLVM of EmiBSD: it compiles the C and C++
of the system and it is the backend rustc builds against (decision D-0003 of
`docs/DECISIONS.md`). Nothing of OpenBSD is in it.

| File | What |
|---|---|
| `UPSTREAM.toml` | the pin: the fork at `llvmorg-23.1.4`; the patch series of `patches/` (D-0004) |
| `DEFINITION.md` | what it gives us and what we build of it |
| `DESIGN.md` | the two CMake stages and the flags, with their reasons |
| `DELIVERY.md` | the artifact and the comp set |
| `build/build.sh` | the build: stage 1 the host tools, stage 2 the target runtimes |
| `tests/` | what proves the artifact (T1) |
