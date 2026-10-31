# Process

How the work in this repository is done. `CLAUDE.md` has the rules of the repository;
`.claude/rules/subagents.md` the contract of the roles, when they exist; `docs/DECISIONS.md`
the decisions.

## Who does what

- **The maintainer** (Emilio Navarrete Lineros) decides and approves. Every decision that
  shapes the toolchains is theirs: a pin bump, a new host or target, a flag that changes what
  the compiler emits, a patch, a dependency, a licence, a milestone's order, a name. Every
  commit is approved in conversation ("dale") and every push ordered ("súbelo"). Nothing is
  pushed otherwise; nothing is pushed to a mirror but by the maintainer, from the main
  session.
- **The agents** (Claude Code, under this repository's rules) write the build glue, the
  patches, the tests, the documents and the commits. They propose, never decide: a question
  that is the maintainer's is handed back with the options, not guessed.
- **The main session** drives the work. It runs `just fetch`, the long builds and the
  commits; when a role exists (`.claude/rules/subagents.md`), it launches each run with the
  Agent tool and sees every plan and every commit. There is no batch workflow: a session, not
  a script, drives a migration or a build.

## The languages

Everything inside the repository (code, comments, documents, commit messages) is in English.
The maintainer is answered in Spanish.

## What a commit needs

- `just check` green: the pins parse, the mirrors hold them with the origins' hashes, the
  scripts compile. A build is never rerun by a check; a change to a build script is proven by
  the build it was made for, and the log is cited in the commit body.
- A message `<llvm|rust|tools|docs>: <imperative summary>`, a body that says what and why,
  then the session's `Co-Authored-By:` line. A pin bump is its own commit, titled
  `<llvm|rust>: bump pin to <version>`.
- Paths added by name; never `git add -A`, never amend, never a push. Nothing under
  `upstream/`, `target/` or `dist/` is ever committed.
- A fixed bug in the glue leaves a test or a check that failed before the fix, in the same
  commit.

## Milestones

T0 to T4, in `CLAUDE.md`. A milestone opens with a plan the maintainer approves, runs as
slices, and closes with its proof: a toolchain is done when the artifact it produces compiled
and ran a program under the EmiBSD kernel in QEMU (`tests/`), and the milestone's state is
recorded in the README and in `STATUS`.

## Decisions

A decision that shapes this repository is recorded in `docs/DECISIONS.md` in the format it
gives, proposed by the agent, accepted by the maintainer, then cited as `decision D-NNNN`
from the documents it binds. A decision taken in the project at large that binds this
repository is recorded there too, in its own words, before it is acted on.

## Reviews

One review per unit of work before its merge, by the main session or by a reviewer role;
findings go back to the same implementer. A second review only when the first found
something blocking, or when the change touches what the compiler emits. The maintainer may
request external reviews and records what was adopted in the decision log.
