---
description: Create a commit with a single-line Conventional Commits message, `<type>(#<issue-id>): <description>`, taking the issue ID from the arguments or the branch name. Use when the user asks to commit code.
argument-hint: "[notes about the change] [issue id]"
context: fork
agent: general-purpose
model: sonnet
effort: low
background: false
---

# Commit with a one-line Conventional Commits message

Input: `$ARGUMENTS`: optional notes from the user about the commit, possibly with an issue ID (may be empty).

## Message format

The message is **exactly one line**: no body, no footer.

```
<type>(#<issue-id>): <description>
```

Not linked to an issue → drop the `(#<issue-id>)` part entirely:

```
<type>: <description>
```

Examples:

```
fix(#507): align photo card icon and handle single tap on tablets
feat(#824): save folder rename on blur
fix(#608,#625): keep list header mounted for onboarding spotlight
chore: bump eslint to 9.x
```

- `type`: `feat` | `fix` | `refactor` | `docs` | `test` | `chore` | `style` | `perf`
- `description`: English, present tense, lowercase first letter, no trailing period; the whole line ≤ 72 characters.
- No blank lines, body, `refs #...` or trailers of any kind (including `Co-Authored-By`). Commit with `git commit -m "<one line>"`.

## Finding the issue ID (do NOT ask the user)

In order of priority; stop at the first source that has an ID:

1. An ID the user wrote in `$ARGUMENTS` (`#507`, `507`, `refs 507`...).
2. The first number after the prefix in the branch name: `fix/507-...` → `507`. Several issues stated explicitly by the user → `(#608,#625)`.
3. No ID in either source → use the no-issue format `<type>: <description>`. Don't ask the user.

## Branch naming

Standard branch names: `feature/<issue-id>-<short-description>` | `fix/<issue-id>-<short-description>` | `hotfix/<issue-id>-<short-description>`

## Process

1. `git status` + `git diff` to understand the changes. Stage only the files related to this commit; never `git add -A` blindly when unrelated files are present.
2. If you are on a protected branch (`main` / `master` / `develop`, or the list in `GIT_GUARD_PROTECTED`): stop and suggest creating a new branch following the rules above first.
3. Write the one-line message, commit, and report the message you used.
4. Do NOT push unless the user asks. Pushes to protected branches are blocked by the `git-guard` hook.
