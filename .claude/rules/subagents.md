# Subagents

No role is defined yet: T0 and T1 are driven by the main session, because the work is
moving existing build glue and running long builds the user watches. When a role is needed
(the first candidate: a `builder` that runs `build/build.sh` in a worktree and reports the
log), it follows the contract of `../Userland/.claude/rules/subagents.md` in force on
2026-10-31: defined in `.claude/agents/`, model and `effort` fixed in its frontmatter, the
guard hook `.claude/hooks/agent-guard.sh` on every writing role, a launching prompt that
gives the scope, the base commit, the scratchpad, what else runs on the machine, the user's
authorisation quoted, and the block "Rules that apply to this work" naming this repository's
`CLAUDE.md` and `imported.md`.

The guard hook is Userland's, unchanged: it refuses `git push`, `--amend`, any force, any
write or `cd` under `upstream/` or a `reference/` tree, and every install or download.
