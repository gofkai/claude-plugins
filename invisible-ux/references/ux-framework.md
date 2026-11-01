# The "Invisible & Lean" UX framework

The shared source of truth for every skill in `invisible-ux`. Every score, finding, improvement round and stop decision must follow this document.

Contents: 1. Spirit · 2. Four pillars · 3. Baseline constraints · 4. Resolving conflicts · 5. Severity & scoring · 6. Flow reduction · 7. Microcopy · 8. Scale · 9. The masterpiece bar · 10. Improvement rounds · 11. Rules for recommendations

## 1. Spirit

People come to **get something done**, not to use software. Every second of thinking, every tap, every input field and every message is a tax. Collect it only when it buys the user clear safety or clear value.

**The 3-question test** (run it before going into detail):

1. Can a newcomer tell where to tap within 5 seconds?
2. Is there a step or field the software could handle itself but makes the user do?
3. If the user taps the wrong thing, can they get it back in one tap?

## 2. Four pillars

### 2.1 Zero Cognitive Load

**Goal**: the next action is obvious at a glance.

- Each screen has **one** primary action, and it is the most visually prominent element. Two buttons with equal weight force the user to deliberate.
- Keep peer choices to about 5 or fewer (Hick's law). More than that → group them, hide some (progressive disclosure), or pre-select one recommendation.
- **Speak the user's language, not the system's.** Domain terms the user already knows are *not* a burden. Violations are developer/system words: internal IDs, status codes, "entity", "sync conflict", table names, enum names.
- Recognition over recall: never make users remember codes or values from a previous screen.
- Consistency: the same action has the same position, label and icon across the whole app.
- An icon without a label is acceptable only when it is universal (close, search, back).
- Users always know where they are: screen title, current step / total steps, saved or not.

Warning signs: several buttons with the same color and size; vague labels ("OK", "Process", "Submit"); long ungrouped forms; the primary action hidden in a "More…" menu; a tooltip needed to understand a button; status told apart only by color.

### 2.2 Frictionless Flow

**Goal**: the fewest steps between intent and result.

- Count taps for each main task and compare with the **theoretical minimum** (section 6).
- Undoable action → drop the confirmation dialog and offer Undo instead.
- Merge intermediate screens; edit in place (inline edit) instead of opening a separate form; offer bulk actions when users repeat the same thing.
- Input: the right keyboard type; a sensible focus order; Enter submits; a picker instead of free typing when the set of values is finite.
- **Speed is friction too**: respond to input in < 100 ms (optimistic UI); any wait > 1 s shows an indicator; avoid full-screen blocking spinners.
- No dead ends: every state (error, empty, done) points to the next step.
- Going back never loses context: keep scroll position, filters, tabs and half-entered data.

Valid exception: **intentional** friction for actions that cannot be undone (section 4).

### 2.3 Smart Defaults & Context Awareness

**Goal**: the software fills things in; the user just confirms or corrects.

Sources of default values, from most to least trustworthy:

1. **What the system knows for certain**: current date and time, the signed-in user, the context that is open (if the user is inside project A, a new record belongs to A).
2. **The user's history**: last value, most frequent value, previously chosen filters / views.
3. **The environment**: GPS location, device, network, language, time zone.
4. **Inference** (business rules, AI): use only as a suggestion while confidence is low.

- For **every input field**: can it be filled in or derived automatically? If yes and it is still left blank for the user → violation.
- Defaults must be **visible** and **changeable with one tap**. Never silently apply a value the user cannot see.
- Safe defaults: when guessing, pick the option with the smallest consequence. Never pre-select an option with external consequences (sending to a customer, publishing, deleting).
- Low confidence → suggest (chips / suggestion list) instead of pre-filling.
- If users keep changing a default, the default is wrong.
- Ask for permissions (location, camera, photos) **at the moment they are needed**, say why, and always provide a way forward if the user declines.

### 2.4 Forgiving & Invisible

**Goal**: mistakes are fine; the system quietly handles the hard parts.

Order of preference: **Prevent errors > Fix them automatically > Allow undo > Report clearly with a way to fix.**

- **Prevent**: constrain at input (pickers, value limits, disabled with a reason); normalize formats automatically (extra whitespace, full-width/half-width characters, dashes).
- **Fix automatically**: retry transient network errors; auto-save drafts; queue offline work when the product must work offline.
- **Undo**: delete / edit / move offers Undo (5–10 seconds) or a trash bin; prefer soft delete.
- **Never lose data the user has entered**: validation errors keep the form intact; losing the network keeps the draft; an expired session keeps the data and returns the user to the same place.
- Validate in place and at the right time (on leaving the field or on submit), right next to the field.
- Error messages follow the microcopy rules (section 7).
- **Invisible ≠ silent**: handle something silently only when the result is certainly correct. If automatic handling still fails, the user must be told, with a way to fix it.

## 3. Baseline constraints

Never trade these away for leanness. Violating any of them → **Critical** finding. A constraint that does not apply to the scope → N/A with a reason.

1. **System status is always visible** (quietly): saving / saved / offline / syncing / not sent. *The work is invisible; the status is not.*
2. **Irreversible actions require confirmation that states the concrete consequence**, and the button names the action instead of "OK".
3. **Accessibility**: touch targets ≥ 44×44 pt (iOS) / 48×48 dp (Android); text contrast ≥ 4.5:1; never convey information by color alone; labels for screen readers. For field use, account for sunlight, gloves and one-handed use.
4. **Privacy & consent**: contextual data (location, photos, history) is collected only with a reason and with consent.
5. **The user stays in control**: every automation is visible and can be overridden.

## 4. Resolving conflicts

| Conflict | Rule |
|---|---|
| Fewer taps ↔ Safety | Undoable → 1 tap + Undo, no second question. Irreversible → one confirmation step stating the consequence. Very large consequence → a deliberate action (type the name, press and hold). |
| Auto-fill ↔ Wrong guess | Defaults are visible and fixable in one tap. Low confidence → suggest, do not pre-fill. |
| Simple ↔ Power users | Simple by default; advanced options behind progressive disclosure or shortcuts. Never remove a feature just to look tidy. |
| Invisible ↔ Transparent | Automation that changes data (auto-fill, auto-fix, auto-merge) leaves a visible trace, e.g. "Filled in from last time". |
| Fewer steps ↔ Fewer choices per step | Pick the option with the lowest total time and error rate. A clear 3-step wizard beats one screen with 30 fields. |

## 5. Severity & scoring

### Finding severity

| Severity | Criteria |
|---|---|
| Critical | Data loss; an irreversible action with no warning; blocks completion of a main task; violates a baseline constraint. |
| High | Clear confusion or friction on a main or high-frequency task. |
| Medium | Friction on a secondary task; a missing default that could be derived; a missing state from the completeness checklist. |
| Low | Polish, consistency, wording. |

Every finding has a **stable ID** (U1, U2…) that stays the same across rounds, with evidence (location on screen, `file:line`, or the section of the plan). Priority = severity × task frequency.

### Pillar score (0–3), derived from the pillar's open findings

| Score | Level | Condition |
|---|---|---|
| 3 | Invisible | No Medium-or-higher findings left. |
| 2 | Good | Medium findings left, no High / Critical. |
| 1 | Friction | High findings left, no Critical. |
| 0 | Blocking | Critical findings left. |

Not enough data to judge a pillar → write "Insufficient data" plus what is needed; **never guess a score**. "Insufficient data" counts as failing the masterpiece gate.

### Overall level

| Level | Condition |
|---|---|
| Blocking | Critical findings left (including baseline violations). |
| Usable | No Critical; High findings left. |
| Good | No Critical / High. |
| Excellent | No Medium-or-higher findings; all 4 pillars 3/3; baseline constraints pass. Low findings remain, or the masterpiece gate's verification is incomplete. |
| **Masterpiece** | Flawless: passes the entire gate in section 9. |

### Doing well

Record what the product / plan already does right. Every improvement must preserve these points; drop any improvement that breaks one.

## 6. Flow reduction

Counting: one tap / click / Enter = 1 tap; every manually typed field is counted separately, never converted into taps.

Give each step of a task exactly one label:

| Label | When |
|---|---|
| **Keep** | The user genuinely has to provide information or make a decision the system cannot know. |
| **Automate** | The value can be derived → pre-fill it; the user changes it only when needed. |
| **Merge** | Adjacent steps can be done on the same screen or with the same tap. |
| **Remove** | The step exists only because of how the system is built (intermediate screen, redundant confirmation). |
| **Replace with Undo** | A confirmation dialog for an undoable action. |
| **Defer** | Information that is not needed yet → ask later or make it optional. |

**Theoretical minimum** = taps of the **Keep** steps + confirmation steps required by baseline constraint #2 + consent steps required by baseline constraint #4. Show the calculation.

Error scenarios to consider for every main flow: network lost midway · wrong / missing input · abandoned and resumed · back pressed mid-flow · session expired · two people editing at once (if possible).

## 7. Microcopy

| Type | Rule |
|---|---|
| Button | Verb + object ("Save item", "Send 3 photos"), never "OK" / "Process" / "Submit". The same action has the same label across the app. |
| Error message | What happened → is the data safe → what to do next (with a button). Error codes go into details / logs, never shown raw. Never blame the user. |
| Validation error | Next to the field, stating the correct value / format. If it can be normalized automatically, drop the message entirely. |
| Confirmation | Only for irreversible actions. State the concrete consequence (count, object); the buttons name the action ("Delete 3 photos" / "Keep them"). |
| Undo | What just happened + an "Undo" button ("Deleted 2 items · Undo"). |
| Empty state | Why it is empty + the first action to take. Empty because of a filter → clear the filter in one tap. |
| System status | Short and calm: "Saved", "Offline — will send when you're back online". |

Localized UI follows the conventions of its language. Example for Japanese: polite です/ます style and short sentences; avoid generic phrases like 「エラーが発生しました」 ("an error occurred") or 「処理に失敗しました」 ("processing failed"). Say specifically what did not succeed and what to do.

## 8. Scale: ceremony proportional to scope

| Scale | How to recognize it | Approach |
|---|---|---|
| **Small** | 1 component / 1 simple screen / diff ≤ ~150 lines / plan ≤ 1 screen | Score only the pillars, constraints and checklist items **that apply**; everything else N/A. Don't invent states to specify. Report ≤ 1 page. ≤ 3 stakeholder questions, only the blocking ones. Default maximum 3 rounds. |
| **Medium** | 1 feature / a few screens | Full process as the skill describes. Default maximum 5 rounds. |
| **Large** | Module / app | Pick the 3–5 highest-frequency tasks to bring to masterpiece level; for the rest, check only baseline constraints and consistency. If subagents are available, delegate evidence gathering per task and take back only conclusions + evidence. Default maximum 5 rounds. |

State the chosen scale at the top of the report. If the user specifies a number of rounds, use it.

**Minimal improvement, within scope**: change only enough to close the finding. New infrastructure (service worker, offline cache, state library, new UI library), architecture rewrites, or backend / API changes → **don't do them yourself**; list them under "Next steps" with a proposal.

## 9. The masterpiece bar

The goal is not "usable", and it does not stop at "excellent". The goal is a **masterpiece, flawless**: users finish their task without ever thinking about the interface, and the best designers, looking closely, **cannot find anything to fix**, however small.

### The "Masterpiece" gate: pass all of these (within the chosen scope)

1. **No open findings at any severity, including Low.** No "kept for a reason" exceptions: a finding that cannot be fixed for external reasons is still open → not a masterpiece.
2. All 4 pillars 3/3; no "Insufficient data". All 5 baseline constraints pass (N/A only when the constraint truly cannot occur in scope, with a reason).
3. **Every detail is optimal**: each main task's tap count equals the theoretical minimum; every derivable field is auto-filled; every undoable action has Undo, every irreversible action has a confirmation stating the consequence.
4. Completeness checklist: **100%** of applicable items pass.
5. **Verified in practice, not only by reasoning**: every main task and every error scenario in section 6 has been verified (the skill defines how: run it for real with code, walk through each step with a plan) with evidence in the report. Not verifiable → Excellent at most.
6. **Two independent fresh eyes** (section 10), two separate subagents scoring the final version, both **find no issues** (any severity) that survive verification. Self-review is never enough to award Masterpiece.
7. UX **acceptance criteria** (if there is a plan) pass at 100%.

### Completeness checklist (each item: Pass / Fail / N/A; report as x / applicable items)

1. **No forgotten states**: first run, empty, loading, error, offline, permission denied, 0 / 1 / very many items, whichever can happen in scope.
2. **Edge content**: very long text, very large numbers, length differences between languages, small / large screens.
3. **Immediate feedback**: every tap has a pressed state; motion is short (~150–300 ms) and purposeful; no layout shift when data finishes loading.
4. **Consistency**: labels, icons, action positions, spacing, date / number formats across all screens.
5. **Keyboard & focus**: initial focus in the right place, sensible tab order, Enter / Esc behave as expected.
6. **Wording**: every UI string follows the microcopy rules.
7. **Perceived speed**: optimistic UI for common actions; no unnecessary waiting.

## 10. Improvement rounds

### Round 0: current state

Score the current state and list findings with IDs. **Print the round 0 report before changing anything.** Round 0 does not count toward the maximum number of rounds.

### Each improvement round

1. **Re-score from scratch** from the current state (re-read files, re-run). Don't rely on memory and don't carry old scores forward.
2. **Pick the work**: open findings by priority Critical → High → Medium → Low (a failed checklist item already counts as a Medium finding).
3. **Improve**, minimally and within scope (section 8).
4. **Verify** with a real check whenever possible. If an improvement worsens another pillar or breaks a "Doing well" point → revert it and find another way.
5. **Log the round in the report file** (the skill defines the file name) as soon as the round ends: 4 pillar scores, baseline constraints, open findings by severity, what was done, verification results. If the session is interrupted, the results survive.

**Progress** = the count of open findings (Critical, High, Medium, Low) decreases in lexicographic order (a drop at a higher severity first, then lower ones), or one more condition of the Masterpiece gate is met. Fixing a Low finding is progress too.

### Fresh eyes (gate #6)

- Run only after self-scoring passes gates 1–5 and 7 (to avoid wasted cost).
- Run **two** new subagents, in parallel and independent of each other. Each can take a different role to look from two sides (for example: a first-time user; a demanding UX expert hunting for the smallest flaw).
- Each subagent is **new** and told explicitly: **read only, don't edit any file, don't run commands that change data**. Give it **only**: the absolute path to this framework file, the target to evaluate (absolute path / URL), the user context and the scale. **Don't** give it conclusions, scores, the findings list or the list of fixes.
- Ask it to return: the 4 pillar scores with evidence, baseline constraints (Pass / Fail / N/A), the completeness checklist, and **every** issue found at **every severity, including Low** (severity, location, description). State that the bar is flawless and that small issues must not be skipped.
- Verify **every** issue they raise, at every severity. Any confirmed issue → gate #6 fails: if rounds remain, start a new round; if not, stop and report it as the remaining gap. Rejected issue → record the reason in the report.
- Any change after a fresh-eyes pass is a new round, and must pass two fresh eyes again before it can be called a Masterpiece.
- No subagent tool → re-score yourself in the role of a first-time user; the result is **Excellent** at most, and state that gate #6 was not independently checked.

### Stop conditions (stop at whichever comes first)

1. The Masterpiece gate is passed.
2. 2 consecutive rounds without progress → analyze why it is stuck.
3. Every remaining finding needs something out of reach: a decision by the user / product owner / customer, a backend change, new infrastructure, out of scope → list them with what is needed to move forward.
4. The maximum number of rounds is reached.

### Non-interactive runs

No one to answer (for example `claude -p`, automation): don't ask a question and wait. Missing context → record assumptions and continue. Anything that needs the user's consent (the skill defines what) → **don't do it**, only report the proposal.

### Honesty about results

Call it a "Masterpiece" only when the full gate passes. "Almost flawless" is still not a Masterpiece. Stopped by conditions 2–4 → report the level actually reached (Excellent, Good…) and the **remaining gap** to masterpiece level. Never inflate scores, downgrade severities, or drop Low findings to end the loop.

## 11. Rules for recommendations

- Recommendations are **concrete enough to act on immediately**: real wording, real positions, real default values, a real Undo mechanism. Generic advice like "improve the experience" is not allowed.
- Each recommendation names the finding ID, the pillar involved and the measurable impact (how many taps or typed fields it removes, which risk it eliminates).
- Proposed default values must be based on data the system actually has, or state what needs to be added.
- The scope is **behavior and flow**, not aesthetics. Comment on color / font / spacing only when it directly affects a pillar, a baseline constraint or the completeness checklist.
- Quote UI text **verbatim** in the product's original language, with an explanation in the report's language.
- Write the report in the language the user writes in.
