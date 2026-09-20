# AI Project Rules — MEHRAN

## Purpose
This repository contains Mehran's trading/EA projects. These rules apply to any AI assistant (including Claude, ChatGPT/Codex, or other coding agents) working on this repository.

## 1. Scope Control
- Do not change project scope without explicit user approval.
- Do not remove, simplify, optimize, professionalize, or refactor existing code unless explicitly requested.
- Do not delete strategy components, functions, inputs, comments, or working logic merely to make code shorter or cleaner.
- Preserve existing behavior unless the requested change explicitly requires behavior to change.

## 2. Patch Discipline
- Make only the requested change.
- Prefer small, isolated patches.
- Before changing anything beyond the requested area, ask the user for permission.
- Never silently change trading rules, entry logic, exit logic, risk rules, lot sizing, or management behavior.
- After every change, clearly report what files and exact areas were changed.

## 3. Trading Safety
- Never add trading functionality unless explicitly requested.
- Never assume that a journal/monitor/recorder EA should trade.
- A recorder or monitoring EA must remain read-only unless the user explicitly requests otherwise.
- Do not modify live orders, SL, TP, lots, or positions unless explicitly requested.

## 4. Arash Assistant
- Arash Assistant is an existing trading EA and must not be modified unless the user explicitly requests a change.
- Do not replace or rewrite Arash logic when working on a separate project.
- Arash Assistant V13.7 uses Magic Number 70013.

## 5. Journal Recorder
The XAU Journal Recorder is a separate passive EA.
It must:
- Never open trades.
- Never close trades.
- Never modify trades.
- Record executed market positions only.
- Ignore pending orders that never activate.
- Record a pending order once it becomes a real market position.
- Preserve Source separately from Close Status.
- Magic 70013 = Arash Assistant.
- Magic 0 = Manual.
- Other non-zero Magic = Other EA.
- Capture original SL/TP when the recorder first observes a trade when technically possible.
- Never invent historical information that cannot be known reliably.

## 6. Code Integrity
- MQL4 code must remain compile-ready.
- Do not introduce duplicate functions.
- Maintain balanced braces and parentheses.
- Preserve strict MQL4 mode where already used.
- Do not introduce DLL dependencies unless explicitly requested.
- Do not claim successful MetaEditor compilation unless it was actually performed in MetaEditor.

## 7. Verification
Before delivering a code change:
- Check that the requested behavior is implemented.
- Check that unrelated behavior was not changed.
- Report any limitation or uncertainty honestly.
- If actual compilation/testing cannot be performed, say so clearly.

## 8. Versioning
- Use clear commit messages.
- Prefer one focused change per commit when practical.
- Never overwrite or delete a working version without explicit approval.
- Preserve the ability to compare/revert versions through Git history.

## 9. User Preference
The user prefers direct technical answers and precise instructions.
Do not flatter or hide problems.
If something is uncertain, say so.
If a requested change is risky, explain the concrete risk before proceeding.

## 10. Golden Rule
NASA rule: stay on the requested scope.
Do exactly what the user asked, no more and no less.
