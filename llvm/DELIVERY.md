# llvm: delivery

What this toolchain ships, as artifacts a GitHub release carries (milestone T3) and as the
files of the `comp` set OS packages. Measured on the first build, 2026-10-31.

| | |
|---|---|
| Artifact | `llvm-<version>-<host triple>.tar.zst` + `.sha256` |
| Host triples | aarch64-apple-darwin first (T1/T2); aarch64-unknown-emibsd at T4 |
| Targets | aarch64-unknown-emibsd (D-0004); the X86 backend compiled, no x86_64 target until D-0001 lifts |
| In the comp set | |
| Measured build time | stage 1 (clang, lld, the tools) about 30 min and stage 2 (builtins, libunwind, libc++abi, libc++) about 3 min, 6 jobs on the arm64 Mac, from a cold `target/` |
| Size | 2.2 GB installed, unstripped (the T3 tarball strips the binaries); patch series 5 files, about 1,000 lines |
