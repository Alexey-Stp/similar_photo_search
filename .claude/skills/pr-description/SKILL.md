---
name: pr-description
description: Use when writing, drafting or updating a GitHub pull request title or description, before running gh pr create or gh pr edit, or when asked to "open a PR" or "write up this branch".
---

# Writing a PR description

## Overview

A PR description is written for the reviewer. It tells them why the change exists, what it does, and where to look. They will read the diff anyway, so the description gives them what the diff can't: intent, decisions and evidence.

## Before writing

1. If `.github/pull_request_template.md` (or `.github/PULL_REQUEST_TEMPLATE/`) exists, fill in that template. It overrides the shape below.
2. Read the project conventions (`CLAUDE.md`, `CONTRIBUTING.md`) for the ticket-key format and any attribution line.
3. Collect the facts: `git log main..HEAD`, `git diff main...HEAD --stat`, the ticket text if the repo has it, and what you actually ran (commands and results).

## Title

`<TICKET-KEY>: <imperative summary>`, at most 72 characters, for example `SPC-3: Add photo library authorization flow`. Drop the key if the repo doesn't use one.

## Body: these sections, in this order

```markdown
## Why
1–3 sentences: the problem or need, in the user's or system's terms. Link the ticket
(`Closes #123` for GitHub issues; a plain link or key for Jira).

## What changed
3–7 bullets about behaviour or capability, each a full sentence. Group by outcome
("Restricted access gets its own screen without a Settings button"), not by file or
layer. Name a type only when the reviewer has to know it.

## Decisions for review
Choices a reviewer might question: deviations from the ticket, rejected alternatives,
renames or API breaks, new dependencies, migrations. One bullet each, with the reason.
Write "None." if there are none.

## Testing
- Run: each command or check you actually ran, with its result.
- Not run: anything not verified, with the reason ("no macOS toolchain; CI is the first build").
- Manual QA: checkboxes for the steps a person still has to do.

## Screenshots
Before/after for any UI change, or "UI change: screenshots pending" if you can't take them.
Leave this section out when nothing in the UI changed.
```

Then add the attribution line, if the project asks for one.

## Length

Aim for under about 300 words, not counting checklists. If a bullet only repeats a file name or a function signature from the diff, cut it.

## Common mistakes

| Mistake | Fix |
|---|---|
| A file-by-file changelog | Rewrite it as behaviour bullets. The diff already shows the files. |
| Decisions buried in the change list | Move them to **Decisions for review**. |
| A "Tests" section that lists test names | Give one line in **What changed** ("Unit tests cover every status transition"). |
| An unchecked command list with no indication of what ran | Split it into **Run** and **Not run**. |
| "All tests pass" without having run them | Report only what you observed. |
| An unverified PR opened as ready for review | Open it with `gh pr create --draft` until CI or the checks pass. |
| A bare `@name` in the body | GitHub notifies that person. Use backticks or leave it out. |

Pass the body to `gh` with `--body-file -` and a heredoc, so that backticks and `$` survive the shell.
