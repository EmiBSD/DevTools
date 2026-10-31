# Subagents: the contract

No role is defined yet: T0 and T1 are driven by the main session, because the work is
moving existing build glue and running long builds the user watches. When a role is needed
(the first candidate: a `builder` that runs `build/build.sh` in a worktree and reports the
log; the second, a read-only `reviewer` of a patch series), it is defined in
`.claude/agents/<role>.md` under this contract. The rules it summarises stay authoritative in
`CLAUDE.md`, `imported.md` beside it and `docs/PROCESS.md`; when they change, this file
follows.

## Roles, when they exist

- **Model and effort fixed in the frontmatter.** Every definition names its `model` and its
  `effort`, so a run never inherits the main session's level: `medium` for a role whose value
  is completeness (a builder, a surveyor), `high` for a reviewer or a designer. The launching
  session may raise one run to `xhigh` when the task justifies it (a patch that changes what
  the compiler emits, a pin bump) and says so in the prompt; it never lowers one.
- **Designing is Fable's, running is Opus's.** A role that writes documents or plans a series
  runs on Fable as a subagent; the roles that build, patch and review run on Opus; the main
  session stays on Opus. A role that repeats one change over many files may run on Sonnet.
  When unsure, the delicate choice (Opus) wins.
- **One at a time, from the main session.** The main session launches each run with the
  Agent tool and sees every plan and every commit; at most four runs at once; a build never
  runs twice on the machine at the same time (`COMP_JOBS` is sized for one). There is no
  batch workflow.
- **Read-only roles carry `maxTurns`** as a spending stop (300). At the limit the output comes
  back marked partial; the launching session resumes the run once with `SendMessage` if the
  work is worth finishing; a second partial return is a stop: the user decides. Worktree
  roles carry none: a stop in the middle leaves commits unmade.
- **The guard hook on every writing role.** `.claude/hooks/agent-guard.sh` is the `PreToolUse`
  hook of every role that writes (the `hooks:` field of its frontmatter). It refuses before it
  runs: `git push`, `git commit --amend`, a force of anything, any write or `cd` under
  `upstream/` or a `reference/` tree, `cargo install`, `rustup`, `brew`, `pip`, `npm`, and
  `curl` or `wget`. Nothing is installed and nothing is downloaded without the user's OK;
  `just fetch` is the one sanctioned download and runs from the main session. A refusal is a
  "STOP" like any other: the agent reports it, never routes around it. It is a belt against a
  slip, not a wall.
- **Reviews.** One reviewer run per unit of work before its merge; its findings go back to
  the **same** implementer with `SendMessage`, never to a fresh agent; a second review only
  when the first found something blocking, or when the change touches what the compiler
  emits. The main session checks every other fix itself and writes that check in the merge
  message.

## Memory (`memory: project`)

A role with memory keeps `.claude/agent-memory/<role>/MEMORY.md`: lessons that outlive one
run (a CMake variable that took two attempts, an `x.py` pitfall, a host quirk), one line
each, in English, appended at the end. It is committed with the tree; a worktree role's lines
travel on its branch and merge by git's `union` driver; whoever merges drops exact
duplicates. Task state (branches, hashes, what is left) goes in `HANDOFF.md` in the
scratchpad, never in memory. A reviewer has none on purpose: fresh eyes.

## What the launching prompt must give

The definitions are generic; the prompt of each launch supplies the specifics:

1. the toolchain and the scope: the directory (`llvm/`, `rust/`), the STATUS it starts at
   and the one it must reach, what is explicitly out;
2. the base commit or the branch to merge first;
3. the scratchpad directory for `HANDOFF.md`, the logs and the test output;
4. what else runs on the machine at the same time (another build, another repository's
   agents), because a toolchain build takes the cores it is given;
5. any authorisation the user gave for this launch, quoted ("dale" and what it answered);
6. the block "Rules that apply to this work": the 10-15 lines that bind the task (the pin,
   the sysroot, what may not change, what is forbidden) and the files the agent reads whole:
   always `CLAUDE.md`, `imported.md` and this file; a reviewer reads `docs/POLICIES.md` too.

A prompt that misses one of these gets a question back, not a guess.

## Setup in a worktree

- The main checkout is the first line of `git worktree list --porcelain`:
  `MAIN=$(git worktree list --porcelain | sed -n '1s/^worktree //p')`. `upstream/` (the
  fetched sources, gitignored) lives only there: `ln -s "$MAIN/upstream" upstream`, unlinked
  before the worktree is removed. The worktree has its own `target/`; the main checkout's is
  never used by a role, because the main session's build may be running in it.
- `PATH=/opt/homebrew/opt/rustup/bin:$PATH` before `cargo` or `just`. Install nothing.
- Read the "Rules that apply to this work" block of your prompt and the files it names
  before writing anything.

## While working

- Everything in the repository is in English. A script or a patch of ours starts with the
  author's ISC block (`docs/POLICIES.md`; copy the header of `.claude/hooks/agent-guard.sh`).
- Upstream sources are read with `sed -n` on the path or `git -C upstream/<mirror> show`,
  never from inside `upstream/`; they are never edited there. A change to a toolchain is a
  patch in `patches/`, applied to the copy in `target/`.
- Commit early: each piece that passes `just check` is committed at once, `<llvm|rust|tools|docs>:
  <imperative summary>`, the body says what and why, then the session's `Co-Authored-By:`
  line. Never push, never amend, never touch `main`, never `git add -A` or `git add .`: add
  paths by name.
- Read cheaply: `grep`, `sed -n 'a,bp'`, long output (a build log) redirected to scratchpad
  files; the log's tail and its errors are what the report quotes.

## Stopping

- A "STOP" refusal or a permission denial: stop at once, commit nothing more, report it.
- Anything that is the user's decision: a pin bump, a new host or target, a flag that changes
  what the compiler emits, a new patch, a download, an install, anything outside the
  repository, a change to the rules: stop and hand back with the question.
- Low on context: stop in a committed state, update `HANDOFF.md` (done with hashes, left, the
  build's state), then hand back naming its path.

## Final report

Branch and tip, commits in order, the evidence (`just check` output, the build log's path
and its last lines, the versions the binaries print, the test that ran the artifact), the
STATUS reached, deviations from DESIGN.md with their reason, what is left, the `HANDOFF.md`
path.
