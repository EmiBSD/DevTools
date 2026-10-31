# rust: delivery

What this toolchain ships, as artifacts a GitHub release carries (milestone T3) and as the
files of the `comp` set OS packages. Measured on the first build, slice 1 of T2 (the host and
the kernel's target; the system's target follows in slice 2), 2026-10-31.

| | |
|---|---|
| Artifact | `rust-<version>-<host triple>.tar.zst` + `.sha256` |
| Host triples | aarch64-apple-darwin first (T1/T2); aarch64-emibsd-emibsd at T4 |
| Targets | aarch64-emibsd-emibsd (D-0004; llvm-target aarch64-emibsd-emibsd8.0) |
| In the comp set | |
| Measured build time | about 17 min for rustc (two stages), `std`, the kernel's `core`/`alloc`, cargo, rustdoc, clippy, rustfmt and `rust-src`, 6 jobs on the arm64 Mac, from a warm cargo cache; LLVM is T1's, not rebuilt |
| Size | about 510 MB installed (`target/rust/install-<host>/`); nothing of Homebrew: cargo static (OpenSSL, curl, libgit2 vendored), rustc on the SDK's libraries |
