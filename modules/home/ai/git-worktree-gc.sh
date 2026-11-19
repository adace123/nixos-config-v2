#!/usr/bin/env bash
# git-worktree-gc: remove linked git worktrees whose work has already landed.
#
# Agent sessions end when they open a merge request, before it merges, so the
# "remove the worktree after merge" step never runs. This sweeps every repo
# directly under each root and removes a linked worktree when ALL of these hold:
#
#   - it lives under one of the roots (worktrees owned by other tools, such as
#     ~/.herdr/worktrees or /tmp checkouts, are left alone)
#   - it is on a branch (not detached) and is not locked
#   - the branch is merged into origin's default branch, or its upstream is
#     gone (GitLab/GitHub delete the source branch on merge, which also covers
#     squash merges)
#   - its HEAD has not moved for GRACE_HOURS (the worktree's HEAD reflog,
#     written on creation, checkout and commit), so a session that has just
#     started, or just committed, is not swept away
#   - `git status` is clean (no modified, staged or untracked files)
#
# The branch is deleted with the worktree. Worktrees that qualify but have
# changes are listed and kept. The script never fetches: run it after a
# `git fetch --prune` (fetch.prune is on globally) for current data.
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: git-worktree-gc [-n|--dry-run] [ROOT...]

Remove clean linked worktrees whose branch has landed, for every repo directly
under each ROOT (default: ~/Projects/work ~/Projects/personal).

  -n, --dry-run   report what would be removed without changing anything
  GRACE_HOURS     env var, default 24: skip worktrees whose HEAD moved more recently
EOF
}

dry_run=0
roots=()
while (($#)); do
	case $1 in
	-n | --dry-run) dry_run=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	-*)
		usage >&2
		exit 2
		;;
	*) roots+=("$1") ;;
	esac
	shift
done
((${#roots[@]})) || roots=("$HOME/Projects/work" "$HOME/Projects/personal")
grace_minutes=$((${GRACE_HOURS:-24} * 60))

removed=0
kept=0

# The ref the default branch is merged into: origin/HEAD, else origin/main or
# origin/master.
default_ref() {
	local repo=$1 ref b
	if ref=$(git -C "$repo" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null); then
		printf '%s\n' "$ref"
		return 0
	fi
	for b in main master; do
		if git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$b"; then
			printf 'refs/remotes/origin/%s\n' "$b"
			return 0
		fi
	done
	return 1
}

under_roots() {
	local path=$1 root
	for root in "${real_roots[@]}"; do
		[[ $path == "$root"/* ]] && return 0
	done
	return 1
}

# Why a branch counts as landed, or nothing when it has not.
landed_reason() {
	local repo=$1 branch=$2 def=$3 track
	if git -C "$repo" merge-base --is-ancestor "refs/heads/$branch" "$def" 2>/dev/null; then
		echo "merged"
		return
	fi
	track=$(git -C "$repo" for-each-ref --format='%(upstream:track)' "refs/heads/$branch")
	[[ $track == *gone* ]] && echo "upstream gone"
	return 0
}

sweep_worktree() {
	local repo=$1 def=$2 path=$3 branch=$4 reason headlog

	under_roots "$path" || return 0
	[[ -d $path ]] || return 0

	reason=$(landed_reason "$repo" "$branch" "$def")
	[[ -n $reason ]] || return 0

	# Not the index: any `git status` (a prompt, an editor) rewrites that.
	headlog=$(git -C "$path" rev-parse --path-format=absolute --git-path logs/HEAD)
	if [[ -e $headlog ]] && [[ -n $(find "$headlog" -mmin "-$grace_minutes" 2>/dev/null) ]]; then
		printf 'recent   %s (%s, %s)\n' "$path" "$branch" "$reason"
		kept=$((kept + 1))
		return 0
	fi

	if [[ -n $(git -C "$path" status --porcelain 2>/dev/null) ]]; then
		printf 'changes  %s (%s, %s)\n' "$path" "$branch" "$reason"
		kept=$((kept + 1))
		return 0
	fi

	printf 'remove   %s (%s, %s)\n' "$path" "$branch" "$reason"
	removed=$((removed + 1))
	((dry_run)) && return 0

	# --force: the tree is verified clean above; force is only needed for
	# submodules and ignored build output (node_modules and the like).
	if git -C "$repo" worktree remove --force "$path"; then
		git -C "$repo" branch -D "$branch" >/dev/null ||
			printf 'warning: could not delete branch %s in %s\n' "$branch" "$repo" >&2
	else
		printf 'warning: could not remove %s\n' "$path" >&2
	fi
}

sweep_repo() {
	local repo=$1 def path="" branch="" locked=0 detached=0 first=1 line

	def=$(default_ref "$repo") || return 0

	# Porcelain records are blank-line separated; the first is the main checkout.
	while IFS= read -r line || [[ -n $path ]]; do
		case $line in
		"worktree "*) path=${line#worktree } ;;
		"branch refs/heads/"*) branch=${line#branch refs/heads/} ;;
		detached) detached=1 ;;
		locked | "locked "*) locked=1 ;;
		"")
			if ((! first && ! locked && ! detached)) && [[ -n $branch ]]; then
				sweep_worktree "$repo" "$def" "$path" "$branch"
			fi
			first=0 path="" branch="" locked=0 detached=0
			;;
		esac
	done < <(git -C "$repo" worktree list --porcelain)

	((dry_run)) || git -C "$repo" worktree prune
}

real_roots=()
for root in "${roots[@]}"; do
	[[ -d $root ]] || continue
	real_roots+=("$(cd "$root" && pwd -P)")
done

printf '%s git-worktree-gc%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$( ((dry_run)) && echo ' (dry run)')"
for root in "${real_roots[@]}"; do
	for gitdir in "$root"/*/.git; do
		# Main checkouts only: a linked worktree's .git is a file.
		[[ -d $gitdir ]] || continue
		sweep_repo "${gitdir%/.git}"
	done
done
printf '%d removed, %d kept\n' "$removed" "$kept"
