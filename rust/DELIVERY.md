# rust: delivery

What this toolchain ships, as artifacts a GitHub release carries (milestone T3) and as the
files of the `comp` set OS packages. Measured on the first builds, 2026-10-31.

| | |
|---|---|
| Artifact | `rust-<version>-<host triple>.tar.zst` + `.sha256` (`just dist rust`): 105 MB for about 500 MB installed; a directory `rustup toolchain link` takes; checked unpacked elsewhere by `tests/check.sh` |
| Host triples | aarch64-apple-darwin first (T1/T2); aarch64-emibsd-emibsd at T4 |
| Targets | `aarch64-emibsd-emibsd` (D-0004; `llvm-target` `aarch64-emibsd-emibsd8.0`): `std`, linked by `llvm/`'s clang against the sysroot, static PIE with `+crt-static` or dynamic; `aarch64-unknown-none-softfloat` (D-0006): `core`, `alloc`, `compiler_builtins` |
| In the comp set | |
| Measured build time | about 15 min for rustc (two stages), `std` for the host and for `aarch64-emibsd-emibsd`, the kernel's `core`/`alloc`, cargo, rustdoc, clippy, rustfmt and `rust-src`, 6 jobs on the arm64 Mac, from a warm cargo cache; LLVM is T1's, not rebuilt |
| Size | about 510 MB installed (`target/rust/install-<host>/`); nothing of Homebrew: cargo static (OpenSSL, curl, libgit2 vendored), rustc on the SDK's libraries |
