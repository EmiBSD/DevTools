# Imported toolchains: the practice

Everything in this repository is someone else's compiler, compiled, plus the patch series
that teaches it the EmiBSD target (decision D-0004). This is what that allows and forbids; `CLAUDE.md` has the non-negotiables, `docs/POLICIES.md` the licences and
dependencies, `docs/DECISIONS.md` the decisions.

## The source

- The source of truth for a toolchain is `UPSTREAM.toml`: `repo` the mirror in the EmiBSD
  organisation (always), `origin` what the mirror is fed from, `commit` or `tag` the pin,
  `path` the subdirectories taken (LLVM: the projects and runtimes its CMake build reads),
  `version` the human version with our patch level `+emibsd.N`, `license` the families,
  `[security] cpe` for the CVE watch, `[patches] series` in order, `[[submodules]]` with
  their own mirrors.
- `tools/upstream.py fetch` clones sparse and blob-less into `upstream/<mirror>/`, checks
  out the pin, records it in `.pin`, and makes the tree read-only. `check` verifies the pin.
  The main session runs `fetch`; an agent only `check`.
- `upstream/` is never edited, never `cd`ed into, never committed. A source line is read with
  `sed -n` on the path or `git -C upstream/<mirror> show <commit>:<path>`.

## The build

- `build/build.sh` copies the pinned source into `target/<name>/src`, applies the patches of
  the series in order with `patch -p1`, and builds in `target/<name>/build`; it never writes
  outside `target/`. It takes the sysroot and the host tools from the environment
  (`EMIBSD_SYSROOT`, `EMIBSD_CC`, `EMIBSD_LLVM_BIN`, `COMP_JOBS`), with the defaults
  `docs/TOOLCHAIN.md` lists; it refuses to run when the sysroot is missing rather than
  guessing one.
- A flag that differs from how the upstream builds the same thing is a line in
  DESIGN.md with its reason. The default is the upstream's build, unchanged.
- `tests/` holds what proves the artifact: a hello world compiled and run under the EmiBSD
  kernel in QEMU, the
  target's `std` linking, the versions the binaries print. A build with no test that ran it
  is not done.

## The patches

- A patch exists only when the upstream cannot carry the change (something EmiBSD-specific,
  an EmiBSD path, the EmiBSD target of decision D-0004). It is the smallest diff that does
  it, its header says why and carries the author's ISC block (`docs/POLICIES.md`), and
  DESIGN.md lists it. A patch that upstream later takes is dropped at the next pin bump.
- Patches are never applied to `upstream/`; the series is applied to the copy in `target/`.

## The artifacts (T3)

- A release is a tarball per host triple with its `.sha256`, named
  `<name>-<version>-<host>.tar.zst`, built from a tagged commit, with `SOURCE_DATE_EPOCH`
  set to the commit's time so two builds of the same tag compare.
- A consumer fetches by version and checks the sum before it unpacks; nothing is fetched as
  "latest".

## Never

- Edit a file under `upstream/`, or a toolchain source outside `target/`.
- Commit anything under `upstream/`, `target/` or `dist/`.
- Install a tool, bump a pin, add a host or a target, or change an emitted-code flag
  without the user's decision.
- Push a commit to a mirror; only the user pushes a tag there, from the main session.
- Build with nightly, or build `std` from anything but the pinned stable release's source.
