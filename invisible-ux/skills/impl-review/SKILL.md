---
description: Review the UX of code, a branch or a running app AFTER implementation using the "Invisible & Lean" framework, with scores backed by file:line evidence; when the user asks for improvements, fix and re-score over several rounds up to masterpiece (flawless) level. Use when the user wants to review, evaluate or improve the UX of a screen, feature, module or app that has been built. Not for plans that are not built yet (use plan-audit).
argument-hint: "[folder | file | branch | diff | URL] [max rounds]"
---

# Review & improve UX (after implementation)

Input: `$ARGUMENTS`. If the last token is a standalone integer, it is the **maximum number of rounds**; the rest is the target.

## 0. Load the framework

Read `${CLAUDE_PLUGIN_ROOT}/references/ux-framework.md`. All scoring, severities, scale, improvement rounds, the masterpiece gate and stop conditions follow that file exactly. This skill defines only what is specific to code.

## 1. Permission gate: read this before doing anything

Decide the **mode** first, based on the user's exact request:

- **Improve mode**: the request explicitly says to fix / improve / apply (for example "review and fix it", "keep fixing until it passes").
- **Review-only mode**: every other case, including a bare `/invisible-ux:impl-review`.

In review-only mode: **don't use Edit / Write on project files (including the report file), and don't run commands that change project files**. The report is printed in the chat only. After round 0, print the report and end the turn with **one** question: improve everything up to masterpiece level, or only specific finding IDs? Non-interactive run → stop at the report. Once the user agrees → run the rounds without asking again each round.

## 2. Scope, scale, context

| Input | How to handle it |
|---|---|
| None / "diff" / branch name | The changes: `git diff <base>...HEAD` plus uncommitted changes (`git diff HEAD`, `git status --porcelain` for new files), plus the surrounding code needed to understand the flow. |
| File / folder | That module. |
| URL | With a browser tool → try it for real. Only type / submit / delete on **localhost or a dev environment**; any other URL → observe only, never submit data. |
| Screenshot | Evaluate from the image, combined with code if available. |

Pick the Small / Medium / Large scale per framework section 8. Look for an accompanying plan: a path the user gives in the input, otherwise `ux-plan-audit.md` / `plan.md` / a spec in the repo. If there is one, its **UX acceptance criteria** are a mandatory part of the masterpiece gate.

Context (who uses it, device / environment, frequency): infer it from code / plan; if you can't, bundle the question into the permission-gate question, or record assumptions.

Decide how to **verify**: the project's existing lint / type-check / test commands; how to run the app; whether a browser tool is available.

**Report file** (improve mode only): `ux-impl-review.md` in the same folder as the plan if there is one, otherwise at the project root. It is the only file created besides code changes.

## 3. Find evidence in the code

| Pillar | What to look for |
|---|---|
| Smart Defaults | Form initial values (`useState(...)`, `defaultValue`, `initialValues`, `v-model`…): which fields start empty even though they could be derived? Are filters / tabs / views remembered? |
| Forgiving | Delete / submit / overwrite handlers: confirmation or Undo, soft or hard delete. What `catch` / `onError` / interceptors show: do they dump `error.message`, error codes or server responses into the UI? Do validation errors reset the form? Are drafts saved, are requests retried? |
| Frictionless | Number of routes / modals / steps; full-screen blocking loaders; scroll position / filters lost when going back; input `type` / `inputmode`. |
| Zero Cognitive Load | Number of primary buttons per screen; vague labels; system terms leaking into the UI; consistency across screens. |
| Baseline constraints | Saving / offline indicators; confirmation for irreversible actions; touch targets, `aria-label`, color-only status; when permissions are requested. |
| Completeness & microcopy | All states present; long text, large numbers; pressed states, layout shift, focus; i18n files and hard-coded strings against the microcopy rules. |

Every finding has an ID and a `file:line`. Report only what you see in the code or when running it; unconfirmed suspicion → write "needs checking at runtime".

## 4. Round 0 → improvement rounds

Round 0 and the rounds follow framework section 10 exactly. Print the round 0 report and write it to `ux-impl-review.md` **before** the first change. Specific to this skill:

**Editing code safely**
- Before editing: record `git status`. If a file you are about to edit already has uncommitted changes from the user → say so in the report first.
- Revert **only with Edit, on the parts you changed yourself**. Never use `git checkout`, `git restore`, `git reset`, `git stash` or `git clean`. Don't commit.
- Follow the patterns / libraries / components already in the codebase. Don't add new infrastructure or libraries (framework section 8). When editing i18n → keep placeholders and update every language file together.
- Don't change the project's lint / test commands or check configuration. If you need to check a new file, run a separate command and record it in the report.

**Verification**
- Run the existing lint / type-check / tests. Checks that were already failing before your edits → record them in round 0; they don't count as your errors, but the number of failures must not grow.
- Gate #5 requires **running it for real**: run the app (dev server or browser tool), walk through every main task, re-count taps, reproduce each error scenario (network lost, wrong input, back, reload midway…), and record evidence in the report. Reading code without being able to run it → **Excellent** at most; say what is needed to run it.
- If you need a dev server: pick a free port (check with `lsof -i :<port>`), bind to `127.0.0.1`, confirm the page really is this app, and **shut the server down when you finish** (including when stopping midway).

**Fresh eyes** (2 subagents) evaluate the code scope / URL (absolute paths). Tell them explicitly not to edit files and not to submit data.

## 5. Final report

Write the full report to `ux-impl-review.md`; in the chat print: the Result line, the Scores table, Changes made (summary), Remaining gap, Next steps, and the file path. Small scale → ≤ 1 page.

```markdown
# UX review: <name>

**Mode**: <review only / improve> · **Scale**: <Small / Medium / Large> · **Upgrade scope**: <tasks>
**Context**: <users> · <device / environment> · <frequency> — <assumptions>
**Result**: <Round 0: level X> → <after n rounds: level Y> · Stopped because: <stop condition> · Gate #6: <2 independent subagents / self-check → Excellent at most>
**Verification**: <commands run, results>

## Scores (round 0 → final)
| Pillar | Round 0 | Final | Open findings |
|---|---|---|---|
| Zero Cognitive Load | | | |
| Frictionless Flow | | | |
| Smart Defaults & Context | | | |
| Forgiving & Invisible | | | |
| Baseline constraints | | | |
| Completeness checklist | x/n | x/n | |

## Taps per main task
| Task | Round 0 | Final | Minimum (calculation) |
|---|---|---|---|

## Acceptance criteria check (if there is a plan)
| Criterion | Result | Evidence |
|---|---|---|

## Round log
| Round | Scores CL/FF/SD/FI | Open Crit/High/Med/Low | Fixed | Verification |
|---|---|---|---|---|

## Findings
| ID | Severity | Pillar | Location | Current → Improved | Status |
|---|---|---|---|---|---|

## Remaining gap to masterpiece level
## Next steps (backend / infrastructure / product decisions / out of scope)
## Doing well: keep as is
```
