"""Git facts about a card's worktree, read before anything is removed.

The board removes a checkout only when doing so cannot lose work, and "cannot
lose work" is a git question: is anything uncommitted in the checkout, and are
there commits on its branch that no base branch has? This module answers those
questions, and deletes a branch only with `git branch -d` — the safe delete,
which itself refuses an unmerged branch. There is no `--force` anywhere here, by
design: a checkout the board is unsure about is kept and named, never destroyed.

Everything is best-effort. A missing `git`, a path that is not a repository, or
a base branch the board cannot identify all come back as "do not remove" for the
things that matter (a dirty or unmerged checkout) and as "nothing to protect"
for a path that is not there — which is the honest answer in both cases, because
a path with no checkout in it cannot be holding uncommitted work.
"""

from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass

# Generous next to any `git status` on a checkout a person is working in; the
# board calls this on the UI thread only when a card is being archived/deleted.
GIT_TIMEOUT = 20.0

# Bases a branch may have been merged into, tried in order: the remote's own
# default branch first (what "merged" almost always means), then the local
# main/master. A base none of these name is treated as *unmerged* — see
# `_unmerged` — because the point of the check is to keep work the board is
# unsure about.
_BASE_CANDIDATES = ("origin/HEAD", "main", "master")


@dataclass(frozen=True)
class WorktreeState:
    """What a checkout looks like before the board decides to remove it."""

    path: str
    branch: str
    # True when `path` is a git worktree the board could inspect. A path that is
    # not there, or is not a repository, is `False` — and removable, because
    # there is no checkout in it to lose work from.
    exists: bool
    # The main checkout that owns the branch, so the branch can be deleted from
    # the repository it belongs to; "" when it could not be determined.
    repo_root: str = ""
    dirty: bool = False  # uncommitted or untracked changes
    unmerged: bool = False  # commits on `branch` that the base branch does not have
    reason: str = ""  # the detail behind `dirty` / `unmerged`

    @property
    def removable(self) -> bool:
        """Nothing here would be lost by removing the checkout and branch."""
        if not self.exists:
            return True
        return not self.dirty and not self.unmerged


def _git(args: list[str], cwd: str = "") -> tuple[int, str, str]:
    """Run git, returning (code, stdout, stderr); a failure is never raised."""
    try:
        proc = subprocess.run(
            ["git", *args],
            cwd=cwd or None,
            capture_output=True,
            text=True,
            timeout=GIT_TIMEOUT,
            check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError) as exc:
        return 127, "", str(exc)
    return proc.returncode, proc.stdout, proc.stderr


def _line(text: str) -> str:
    stripped = text.strip()
    return stripped.splitlines()[0].strip() if stripped else ""


def inspect(path: str, branch: str = "") -> WorktreeState:
    """Inspect the worktree at `path` for work that removing it would lose."""
    branch = (branch or "").strip()
    if not path or not os.path.isdir(path):
        return WorktreeState(path=path, branch=branch, exists=False)
    code, out, _ = _git(["rev-parse", "--is-inside-work-tree"], path)
    if code != 0 or out.strip() != "true":
        return WorktreeState(path=path, branch=branch, exists=False)

    branch = branch or _current_branch(path)
    repo_root = _repo_root(path)
    changes = _dirty(path)
    unmerged, why = _unmerged(path, branch)
    if changes:
        reason = f"it has {changes} uncommitted change(s)"
    elif unmerged:
        reason = why
    else:
        reason = ""
    return WorktreeState(
        path=path,
        branch=branch,
        exists=True,
        repo_root=repo_root,
        dirty=bool(changes),
        unmerged=unmerged,
        reason=reason,
    )


def delete_branch(repo_root: str, branch: str) -> tuple[bool, str]:
    """Delete a *merged* branch with `git branch -d`; never `-D`.

    Returns `(ok, detail)`: `detail` is the branch name on success, or the
    reason git refused on failure. The safe delete is the second lock — even a
    branch `inspect` thought was merged is left alone if git disagrees.
    """
    if not repo_root or not branch:
        return False, "no branch to delete"
    code, _, err = _git(["branch", "-d", branch], repo_root)
    if code != 0:
        return False, _line(err) or f"git branch -d {branch} failed"
    return True, branch


def _current_branch(path: str) -> str:
    code, out, _ = _git(["rev-parse", "--abbrev-ref", "HEAD"], path)
    name = out.strip() if code == 0 else ""
    return name if name and name != "HEAD" else ""


def _repo_root(path: str) -> str:
    """The main checkout's root, not this worktree's, or "" if unknown.

    `--git-common-dir` is the shared `.git` a linked worktree points into, so
    its parent is the repository the branch belongs to. Resolved while the
    checkout still exists — after `worktree remove` there is nothing left to ask.
    """
    code, out, _ = _git(["rev-parse", "--path-format=absolute", "--git-common-dir"], path)
    if code != 0:
        code, out, _ = _git(["rev-parse", "--git-common-dir"], path)
    common = out.strip() if code == 0 else ""
    if not common:
        return ""
    if not os.path.isabs(common):
        common = os.path.join(path, common)
    common = os.path.realpath(common)
    # `<repo>/.git` -> `<repo>`; a bare repo or an odd layout keeps the common
    # dir itself, where `git branch -d` still works.
    return os.path.dirname(common) if os.path.basename(common) == ".git" else common


def _dirty(path: str) -> int:
    code, out, _ = _git(["status", "--porcelain"], path)
    if code != 0:
        return 0
    return sum(1 for line in out.splitlines() if line.strip())


def _unmerged(path: str, branch: str) -> tuple[bool, str]:
    if not branch:
        return True, "the checkout is on no branch"
    base = _base_ref(path)
    if not base:
        return True, "no base branch (main, master, or origin) was found to compare against"
    code, out, _ = _git(["rev-list", "--count", f"{base}..HEAD"], path)
    if code != 0:
        return True, f"could not compare {branch} against {base}"
    try:
        count = int(out.strip() or "0")
    except ValueError:
        return True, f"could not read the commit count against {base}"
    if count > 0:
        return True, f"{count} commit(s) on {branch} are not in {base}"
    return False, ""


def _base_ref(path: str) -> str:
    for candidate in _BASE_CANDIDATES:
        if candidate == "origin/HEAD":
            code, out, _ = _git(
                ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], path
            )
            if code == 0 and out.strip():
                return out.strip()
            continue
        code, _, _ = _git(["rev-parse", "--verify", "--quiet", candidate], path)
        if code == 0:
            return candidate
    return ""


__all__ = ["WorktreeState", "delete_branch", "inspect"]
