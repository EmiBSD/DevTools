# Policies: licences, dependencies, the AI process

What binds the whole EmiBSD project, in the form it takes for this repository. `CLAUDE.md`
has the non-negotiables; `docs/DECISIONS.md` the decisions; `docs/PROCESS.md` how the work
is done.

## Licences

**Our files.** The build glue (`build/build.sh`, `justfile`, `tools/`), the hooks, the
documents and the patches are ISC, the text of `LICENSE`. A script or a patch of ours
starts with the author's block, "Copyright (c) 2026 Emilio Navarrete Lineros
<enavarre@outlook.com>", followed by the ISC permission notice (`.claude/hooks/agent-guard.sh`
has the header to copy). Nobody else's name replaces it.

**The toolchains.** They keep their own licences, in their sources; the families are recorded
in each `UPSTREAM.toml` (`license`). A patch of ours over an upstream file is ISC and says
so in its header; the upstream's notices in the patched file stay whole.

| Licence | Status |
|---|---|
| ISC, MIT, BSD-2, BSD-3, Apache-2.0 (with or without the LLVM exception), Zlib, Unicode-3.0 | acceptable |
| MPL-2.0 | with a written reason in DESIGN.md |
| GPL, LGPL, AGPL | never: not in the tree, not in the artifacts, not even a build tool that links |

LLVM is Apache-2.0 with the LLVM exception; Rust is Apache-2.0 and MIT; their vendored
dependencies are checked against this table at each pin bump (`UPSTREAM.toml`'s `license`
lists every family found).

**Nothing of OpenBSD.** No code, patch or build glue of OpenBSD's enters this repository
(decision D-0003); so no OpenBSD licence notice ever appears here.

**Trademarks.** EmiBSD is not affiliated with or endorsed by the OpenBSD project, the LLVM
project or the Rust project, and says so wherever it presents itself (the README, the
release notes). Their names appear only where their code is compiled or their behaviour is
named.

## Dependencies, toolchains and tools

- **Stable Rust only**, pinned in `rust-toolchain.toml` for the glue that runs under it and
  in `rust/UPSTREAM.toml` for the toolchain that is built. A bump is its own commit and the
  maintainer's decision. No nightly features, not even for a tool; `std` for the target is
  built from the stable release's source.
- **Upstream pins** are commits or tags in the organisation's mirrors, recorded in
  `UPSTREAM.toml` with the origin, the licence families and the CPE for the CVE watch. The
  mirrors are read-only: no commit of ours lands on them, only the upstream tags the pins
  name; our patches live in `patches/` with their reason.
- **Nothing installed, nothing downloaded** by an agent without the maintainer's OK. The
  guard hook refuses `cargo install`, `rustup`, `brew`, `pip`, `npm`, `curl` and `wget`;
  the one sanctioned download is `just fetch` (`tools/upstream.py fetch`), run from the
  main session. The host tools (CMake, Ninja, Python 3, a C++ compiler) are installed by the
  maintainer.
- **The tools are stdlib only.** `tools/*.py` import nothing outside Python's standard
  library; a new dependency of the glue is the maintainer's decision.
- **Artifacts are consumed by pin and checksum**, never by "latest": a consumer names a
  version and verifies the `.sha256` before it unpacks.

## Disclosure of the AI process

The code, tests, documents and commit messages of EmiBSD are written by Claude Code agents
under the written rules of each repository. The maintainer, Emilio Navarrete Lineros, takes
every decision, approves every commit in conversation and orders every push; nothing lands
otherwise. This is stated in the README and in every public post about the project.

- Every commit carries the session's `Co-Authored-By:` line naming the model.
- The rules the agents work under are public: `CLAUDE.md`, `.claude/rules/` and, when they
  exist, `.claude/agents/` and `.claude/agent-memory/`.
- In public, the verification comes first: the tests that prove an artifact, the versions
  the binaries print, the checksums. Readers judge an AI-written project by its checks.
- A post on a forum is written by the maintainer, never generated, states the process in
  its first lines, and asks a concrete technical question.

What the process does not claim: that a build is right because a model drove it. The claim
is narrower: the sources are the upstreams at a pin anyone can check, the patches are small
and listed, and every artifact is proven by a test that ran it.
