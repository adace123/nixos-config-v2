---
name: commit-all
description: Creates a single comprehensive commit for every pending change in a git repository, categorizing them into features and fixes with a conventional-commits style message. Use when asked to commit everything, commit all changes, stage and commit all, or make one commit covering all features and fixes in the diff.
---

# Commit All

Commit every pending change (staged, unstaged, and untracked) in the current repository as one well-structured commit whose message surfaces the features and fixes contained in the diff.

## Workflow

1. **Assess the repository state**:

   ```bash
   git status --short
   git diff --stat
   git diff --cached --stat
   ```

2. **Collect the full change set** — staged, unstaged, and untracked:

   ```bash
   git diff HEAD                                        # tracked changes (staged + unstaged)
   git ls-files --others --exclude-standard             # untracked files
   ```

   If there are untracked files, read them (or their key parts) to understand what they add before staging.

3. **Categorize the changes**:

   - **Features**: new functionality, new files, new options/commands, behavior additions → `feat`
   - **Fixes**: bug fixes, corrections, resolved failures → `fix`
   - **Mixed**: one summary line plus a bulleted body with `feat:` / `fix:` groups
   - Fall back to other conventional types (`refactor`, `docs`, `chore`, `perf`, `test`) only when nothing in the diff is a feature or fix.

4. **Filter out anything that is not part of this change set**:

   A "commit all" request covers the work in flight — not stray artifacts, and
   not someone else's unrelated edits. Leave these out:

   - **Scratch and generated files**: `*.tmp`, `*.bak`, `*~`, `.DS_Store`,
     editor state, one-off text/data dumps, downloaded images or artifacts,
     build output. A *tracked* file that is obviously unrelated scratch (a stray
     data dump, a generated report) keeps its modifications unstaged too — and
     say so, because it probably should not be tracked at all.
   - **Secrets and credentials**: see the Sensitive files edge case below.
   - **Unrelated pending work**: changes that predate the current task and are
     not part of what you were asked to do.

   When in doubt, leave the file out and name it. Reporting an excluded file
   costs one line; committing junk into history costs a rewrite.

   Always report which files you excluded, and why.

5. **Write the commit message** (conventional commits style):

   - Summary line ≤ 72 chars, imperative mood
   - Mixed changes: `feat: <primary feature>` summary, then a body with bullet groups
   - Fixes only: `fix: <primary fix>` summary
   - Body bullets must be concrete — name files, functions, or user-visible behavior, not generic descriptions
   - Never include internal process details (agent prompts, tool calls, reasoning)

6. **Stage the filtered set and commit**:

   Prefer explicit paths over a blanket add, so a file you decided to skip
   cannot slip in:

   ```bash
   git add -- <path> <path> ...
   git commit -F <(printf '%s\n\n%s\n' "<summary>" "<body>")
   ```

   Use `git add -A` only after confirming the tree holds nothing but this change
   set. For longer messages, write the full message to a temp file and commit
   with `git commit -F <file>`.

## Edge Cases

- **No changes**: report that the working tree is clean; do not create an empty commit.
- **Large diffs**: read `git diff --stat` first and sample the diff per directory (`git diff HEAD -- <dir>`) instead of reading everything. Skim generated/lockfiles rather than reading them fully.
- **Only untracked files**: treat them as the change set, then apply the same filter from step 4 before staging them explicitly.
- **Dirty tree with unrelated work**: commit only the change set and name what you left behind. Never reach for `git add -A` just to make the tree clean — a tidy `git status` is not worth committing someone else's half-finished edits.
- **Sensitive files**: never stage files matching typical secret patterns (`.env`, `*secret*`, `*key*.pem`, credentials files). Check `.gitignore` and `git status` first; ask the user if anything looks like a secret.
- **Pre-commit hooks**: this repository runs pre-commit (via `prek`) on staged files. If the commit fails a hook, fix the reported issue (format/lint) and retry — never bypass hooks.
- **Deletions/renames**: mention significant removals or renames in the body so the commit tells the full story.
- **Failed hook blocks unrelated files**: if a pre-existing unrelated file fails a hook, report it and leave it unstaged rather than silently committing a broken state.

## Example

For a diff that adds a new home-manager module and fixes a bug in `core-settings.nix`:

```text
feat: add home-manager module for custom tool

- feat: scaffold module with option defaults and docs
- fix: correct path resolution in core-settings.nix
- chore: document usage in README
```
