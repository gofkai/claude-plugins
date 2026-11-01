---
description: Audit the UX of a plan, spec, requirement or mockup BEFORE implementation using the "Invisible & Lean" framework, then improve the plan over several rounds up to masterpiece (flawless) level, with UX acceptance criteria. Use when the user wants to audit, critique or raise the UX quality of a plan or design that has not been built yet. Not for code that already exists (use impl-review).
argument-hint: "[plan file | folder | mockup | description] [max rounds]"
---

# Audit & improve the UX of a plan (before implementation)

Input: `$ARGUMENTS`. If the last token is a standalone integer, it is the **maximum number of rounds**; the rest is the target. Empty input → ask the user where the plan is (non-interactive run → stop and report the missing input).

## 0. Load the framework

Read `${CLAUDE_PLUGIN_ROOT}/references/ux-framework.md`. All scoring, severities, scale, improvement rounds, the masterpiece gate and stop conditions follow that file exactly. This skill defines only what is specific to plans.

## 1. Read the plan, pick the scale, establish context

- Plan / spec / requirement file → read all of it.
- A folder (for example an issue-analysis folder with `requirement.md`, `plan.md`, `mockup.html`) → read the plan-related files in it.
- Related existing code → skim it to learn what data the system **already has** (raw material for defaults) and which UI patterns are in use (to stay consistent).

Pick the Small / Medium / Large scale per framework section 8.

You need to know: **who** uses it, **device / environment**, and **how often** each task happens. If the plan doesn't say → ask the user once (bundle every question); if you can't ask or the user skips → record assumptions and continue.

**Working file**: `ux-plan-audit.md`
- Input is a file → put it in the same folder as that file. Input is a folder → put it in that folder.
- Input is only a description → put it in the current working directory.
- Don't write any other file. Don't edit the original plan while iterating.

## 2. Round 0: audit the original plan

Score **what the plan commits to**, not its intentions. For each task in scope:

1. Goal: "<Who> wants <outcome> when <situation>".
2. Lay out the flow the plan describes; count taps / typed fields; assign flow-reduction labels; compute the theoretical minimum (framework section 6).
3. Each input field: does it have a source for a default value?
4. Each action that changes data: can it be undone, and what mechanism does the plan provide?

Then sweep for **what the plan leaves out**, usually the most valuable findings at the plan stage: states and edge content that **can occur in scope** (completeness checklist), error scenarios, key wording, the 5 baseline constraints. If the plan omits something necessary, that is a finding (missing specification), not "Insufficient data".

Print the round 0 report (short: level, scores, list of findings with IDs) and write it to `ux-plan-audit.md`.

## 3. Improvement rounds

Follow framework section 10 exactly. Specific to this skill:

- **Improve** = rewrite the **"Improved plan"** section of `ux-plan-audit.md`: new flow steps, a table of default values, how undo works, state specifications, concrete wording. Detailed enough that a developer can build it without making UX decisions. The improved plan lives only in this file; don't paste it in full into the chat.
- **Verify** (gate #5) = walk through **every step** of every task and **every error scenario** on the improved plan, recording evidence (which step, what the plan says), re-count taps; check that no baseline constraint is violated; every default is based on data the system really has, or the plan states what must be added.
- **Fresh eyes** (2 subagents) read `ux-plan-audit.md`. Tell each subagent to evaluate only the "Improved plan" section and ignore the rest of the file.
- Issues that need a product owner / customer decision → don't decide them yourself; put them under "Open questions" and improve the rest. If a requirement contradicts the framework (for example a double confirmation for an undoable action) → don't delete the requirement; propose the alternative as a question.

## 4. Final report

Write it to `ux-plan-audit.md`. In the chat print only: the Result line, the Scores table, the Remaining gap (if any), Open questions, and the file path. Small scale → the whole file ≤ 1 page.

```markdown
# UX plan audit: <name>

**Scale**: <Small / Medium / Large> · **Upgrade scope**: <tasks>
**Context**: <users> · <device / environment> · <frequency> — <assumptions>
**Result**: <Round 0: level X> → <after n rounds: level Y> · Stopped because: <stop condition> · Gate #6: <2 independent subagents / self-check → Excellent at most>

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
| Task | Original plan | Improved | Minimum (calculation) |
|---|---|---|---|

## Round log
| Round | Scores CL/FF/SD/FI | Open Crit/High/Med/Low | Improved |
|---|---|---|---|

## Findings
| ID | Severity | Pillar | Original plan | Improved | Status |
|---|---|---|---|---|---|

## Remaining gap to masterpiece level
## UX acceptance criteria
A measurable checklist; `/invisible-ux:impl-review` checks against it after implementation.
## Open questions
## Improved plan
```

## 5. Apply to the original plan

**Never overwrite the original plan without consent.** Ask the user once: apply all of it or part of it. Non-interactive run → don't apply; leave only `ux-plan-audit.md`. When applying: keep the structure and formatting of the original plan.
