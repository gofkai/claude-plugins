---
description: Create a pull request (GitHub, gh CLI) or merge request (GitLab, glab CLI), or rewrite the description of an existing one, in a short reviewer-first format: Related issue / Overview / Symptoms & fixes / Test items / Evidence. Use when the user asks to open a PR or MR, write a PR description, or fix the description of an existing one.
argument-hint: "[target branch] [reviewer] [issue id] [evidence files] [PR/MR number to update]"
context: fork
agent: general-purpose
model: sonnet
effort: medium
background: false
---

# Pull request / merge request description

Input: `$ARGUMENTS`: optional notes such as the target branch, reviewer, issue ID, paths to evidence files, or the number of the PR / MR whose description should be updated.

This skill runs in its own subagent (`context: fork`) and cannot see the earlier conversation. Every piece of information (tested cases, evidence paths, target branch) must come from `$ARGUMENTS`, git, or the issue tracker. If required information is missing and cannot be inferred → stop and return the question; don't guess.

## Prerequisites

- Detect the host from `git remote get-url origin`: GitHub → `gh` (check `gh auth status`); GitLab → `glab` (check `glab auth status`). Not installed or not signed in → explain how (`brew install gh` + `gh auth login`, or `brew install glab` + `glab auth login`).
- The current branch is pushed. If not → push the branch (NEVER a protected branch) first.

## Title

```
<type>(#<issue-id>): <imperative subject in English>
```

- `issue-id`: from the branch name (`fix/507-...`). Several issues → `(#608,#625)`. No issue → `<type>: <subject>`.
- `type`: `fix` | `feat` | `refactor` | `chore`...
- The subject describes **the result after merging**, not "fix bug".

Examples:

```
fix(#507): photo card icon alignment and tablet tap handling
feat(#824): save folder rename on blur and follow the renamed node
fix(#608,#625): keep list header mounted so the onboarding spotlight aligns
```

## Description: the standard frame

The whole description is in **English**. Domain terms from another language may be added in parentheses next to the English when reviewers need them. Don't write it bilingually and don't translate screen names.

```markdown
## Related issue

- <issue URL, e.g. https://github.com/<owner>/<repo>/issues/<id> or your tracker's URL>

## Overview

<1–2 sentences: how the system behaves after this PR, and which screens / platforms are in scope. Present tense, describing the state after the fix, not the process.>

## Symptoms & fixes

### 1. <Symptom name, from the user's point of view>

**Current behavior**: <1–2 sentences: the REAL cause at code level (which CSS rule, condition branch or wrong value) that leads to the symptom.>

**Fix** (`<File.ts>`): <1–2 sentences: what changed and why it is correct.>

### 2. <next symptom>

**Current behavior**: ...

**Fix** (`<File.ts>`): ...

### Test items

- [x] <test case, stating the platform / zoom / conditions>
- [x] ...
- [x] Regression: <what must NOT change compared with the target branch>

## Evidence

![web](<uploaded file URL>)
![tablet](<uploaded file URL>)
```

### Variants

| Kind of PR | Body |
| --- | --- |
| Bug fix (several symptoms) | `## Symptoms & fixes` + `### N.` as above |
| Feature / refactor / a single focused change | `## Changes`: short bullets, or one paragraph per file starting with the file name in bold |
| Complicated history (why it used to work) | Insert `## Background` between Overview and the body |
| Several issues | Rename the heading to `## Related issues`, one line each: `- <URL> — <what that issue asks for>` |

Put the checklist under `### Test items` (bug fix) or `### Checklist` (feature). Drop any section with no content; never leave placeholders.

## Short and clean (mandatory)

A reviewer reading the PR for one minute must understand: what changed, why, and what was tested. Everything else is noise.

- **Every sentence carries new information.** Don't repeat the Overview in Fix, don't restate the title, no opening / closing sentences like "This PR aims to...", "In summary...".
- **Length limits**: Overview ≤ 2 sentences; each `Current behavior` / `Fix` ≤ 2 sentences (3 at most if the root cause is genuinely complex); the whole description should fit on one screen.
- **Merge symptoms with the same root cause** into one item. Split into `### N.` only when the cause or the fix location differs.
- **Don't narrate the debugging**, don't list approaches you tried and dropped, don't paste code blocks / diffs (reviewers already have the Files tab).
- **Mention only meaningful changes.** Skip imports, variable renames, formatting, small type fixes, removed console.logs, unless they affect behavior.
- **Test items**: only cases with verification value (usually 3–6 lines), each line one short clause, not a long sentence with explanations.
- Add `## Background` only when reviewers cannot understand the fix without it.
- Prefer short phrases and strong verbs: "Clamp `scrollTop` to 0 on open" instead of "We added logic to make sure that the scrollTop value is clamped to 0 when the dialog is opened".

## Writing rules

1. **Explain in one sentence why other platforms are unaffected** when a bug happens on only one platform; it proves the root cause is understood.
2. **Backticks** for every identifier, CSS class and value: `` `PhotoCard.vue` ``, `` `padding: 2.5px 0.5rem` ``, `` `renamePath` ``.
3. **Test items map 1:1 to the symptoms** via `(1)(2)` prefixes, and there is always at least one `Regression:` line stating what does not change.
4. **Tick `- [x]` only for cases the user has confirmed testing.** Untested → `- [ ]`. Never tick on your own.
5. **Don't make things up.** Every sentence in `Current behavior` / `Fix` must follow from the actual diff; if you're not sure, ask the user instead of guessing.
6. No "Generated by…" lines or emoji in the description.

## Evidence

Images / videos must be uploaded to the host to display in the PR:

- **GitLab**: `glab api --method POST "projects/:fullpath/uploads" --form "file=@/path/to/web.mp4"`. The response contains `url` like `/uploads/<hash>/web.mp4` → insert `![web](/uploads/<hash>/web.mp4)`.
- **GitHub**: there is no CLI upload for PR attachments. Ask the user to drag the files into the PR description in the browser, or link files they have already hosted.

Name files after the platform (`web`, `tablet`, `android`, `iphone`) because the file name becomes the label.

Uploading **writes to the server**: do it only when the user gives file paths or explicitly agrees. No evidence from the user → leave the `## Evidence` section out.

## Process

1. Determine the target branch: ask the user if it is unclear; default to the repository's default branch (`gh repo view --json defaultBranchRef` / `glab repo view`). Many feature branches target an intermediate branch, so don't assume wrongly.
2. Take the issue ID from the branch name; read `git log <target>..HEAD` and `git diff <target>...HEAD` to understand the real changes.
3. Read the linked issue if you need context on the symptoms (`gh issue view <id>` / `glab issue view <id>`, or the tracker the user names), so `Current behavior` matches what was reported.
4. Draft the description into a temp file, e.g. `/tmp/pr-<issue-id>.md`, then **do one trimming pass** per "Short and clean": delete repeated sentences, sentences without new information, and empty sections.
5. Create it:
   ```bash
   # GitHub
   gh pr create --title "<title>" --body-file /tmp/pr-<issue-id>.md --base <target>
   # GitLab
   glab mr create --title "<title>" --description "$(cat /tmp/pr-<issue-id>.md)" --target-branch <target> --yes
   ```
   Add `--reviewer`, `--assignee`, `--label`, `--draft` when the user asks. Never use `--fill` (it overwrites the description with commit messages).
6. Report the PR / MR URL.

## Updating an existing description

```bash
gh pr edit <number> --body-file /tmp/pr-<issue-id>.md                      # GitHub
glab mr update <iid> --description "$(cat /tmp/pr-<issue-id>.md)"          # GitLab
```

Before overwriting: read the current description (`gh pr view <number>` / `glab mr view <iid>`) and keep what the user wrote by hand, especially uploaded evidence links (uploading again creates duplicate files on the server).
