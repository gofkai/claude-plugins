# claude-plugins

[![CI](https://github.com/gofkai/claude-plugins/actions/workflows/ci.yml/badge.svg)](https://github.com/gofkai/claude-plugins/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Two [Claude Code](https://docs.claude.com/en/docs/claude-code) plugins I use every day:

| Plugin | What it gives your agent |
| --- | --- |
| **[invisible-ux](#invisible-ux)** | A strict UX framework and two skills: audit a plan *before* building it, review the code *after*. Both can iterate until nothing is left to fix. |
| **[git-guard](#git-guard)** | A hook that stops the agent from pushing to protected branches, plus skills for one-line commits and short, reviewer-first PR / MR descriptions. |

## Install

```text
/plugin marketplace add gofkai/claude-plugins
/plugin install invisible-ux@gofkai
/plugin install git-guard@gofkai
```

---

## invisible-ux

People open an app to get something done, not to use software. Every tap, typed field, dialog and second of thinking is a tax. The **"Invisible & Lean"** framework ([`ux-framework.md`](invisible-ux/references/ux-framework.md)) makes the agent measure that tax and remove it.

**Four pillars**, scored 0–3 from open findings:

- **Zero Cognitive Load**: one primary action per screen, the user's language instead of the system's.
- **Frictionless Flow**: tap counts compared against a computed theoretical minimum, Undo instead of "Are you sure?".
- **Smart Defaults & Context**: every field that can be derived is pre-filled, visibly and editable in one tap.
- **Forgiving & Invisible**: prevent errors, then auto-fix, then undo, then explain. Never lose what the user typed.

**Five baseline constraints** that leanness is never allowed to trade away: visible system status, confirmation for irreversible actions, accessibility, privacy and consent, and user control over every automation.

### Skills

| Skill | When | Output |
| --- | --- | --- |
| `/invisible-ux:plan-audit <plan> [rounds]` | Before implementation: a spec, requirement, mockup or plain description | `ux-plan-audit.md` with findings, an improved plan detailed enough to build without UX guesswork, and measurable **UX acceptance criteria** |
| `/invisible-ux:impl-review <path\|branch\|URL> [rounds]` | After implementation: a diff, a module or a running app | A scored review with `file:line` evidence. Review-only by default; it edits code only when you ask it to improve |

```text
/invisible-ux:plan-audit docs/checkout-plan.md
/invisible-ux:impl-review src/features/checkout 3
```

### How a run works

1. **Round 0** scores the current state and prints it *before* anything changes. Findings get stable IDs (`U1`, `U2`…) with severity and evidence.
2. **Improvement rounds** fix findings by priority (Critical → High → Medium → Low), re-score from scratch every round, and revert any fix that hurts another pillar.
3. **Verification** means running it for real: the app on a local dev server, every main task, every error case (network lost, wrong input, back mid-flow, expired session).
4. **Fresh eyes**: two independent read-only subagents review the final version without seeing the previous scores. A finding either of them confirms sends the work into another round.

The top level, **Masterpiece**, needs zero open findings at every severity, all pillars at 3/3, tap counts at the theoretical minimum and both fresh-eye reviewers coming back clean. The framework forbids inflating scores to finish a loop: a run that stops early reports the level it actually reached and the remaining gap.

---

## git-guard

### Push guard hook

A `PreToolUse` hook on the Bash tool. It parses each command with real shell semantics instead of grepping for `git push`, so it catches indirect pushes and ignores text that only mentions a push:

| Command the agent tries | Decision |
| --- | --- |
| `git push origin main`, `git push origin HEAD:main`, `git push --all` | **block** |
| `git push` while `main` is checked out, or after `cd` into such a repo | **block** |
| `git pu""sh origin main`, `sh -c 'git push origin main'`, `eval "git push origin develop"` | **block** |
| `git push origin "$BRANCH"`, `git -c remote.origin.push=… push`, `… \| xargs git push` | **ask you** |
| `git push -u origin feature/42-login` | allow |
| `echo "git push origin main"`, `git commit -m "push to main later"`, a heredoc written to a file | allow |

Real output:

```console
$ git add . && git commit -m wip && git push origin main
git-guard: pushing to protected branch 'main' is blocked. Create a branch and open a PR/MR instead.

$ git push origin "$BRANCH"
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask",
 "permissionDecisionReason":"git-guard: target branch uses a variable or $(...): '$BRANCH' — please confirm this push command."}}
```

Protected branches default to `main master develop`. Override them with a space-separated list:

```bash
export GIT_GUARD_PROTECTED="main release production"
```

The hook needs `jq`. Without it, it fails closed and blocks every command that contains `push`. It is a client-side seatbelt: keep branch protection on the server as well.

### Skills

| Skill | What it does |
| --- | --- |
| `/git-guard:commit [notes]` | Stages only the related files and commits with exactly one line: `fix(#507): align photo card icon on tablets`. The issue ID comes from your notes or the branch name (`fix/507-…`). It never pushes. |
| `/git-guard:pr [target] [issue]` | Opens a GitHub PR (`gh`) or a GitLab MR (`glab`) with a description a reviewer can read in one minute: Overview, Symptoms & fixes with the real root cause, Test items mapped 1:1 to the symptoms, and Evidence. It never ticks a test you haven't confirmed. |

Both skills run in a forked subagent on `sonnet` to keep your main context clean.

---

## Development

```bash
bash git-guard/tests/run.sh          # 45 hook cases: block / ask / allow
shellcheck -S error git-guard/hooks/*.sh
```

CI runs the same checks on every push and pull request.

## License

[MIT](LICENSE) © Truong Le (Kai)
