#!/usr/bin/env bash
# Detect stale full-metadata packuments in the npm HTTP cache.
#
# Why this exists: npm caches the compressed ("corgi") and the full-metadata
# packument of a package under the SAME cache key, as separate cacache index
# records distinguished only by `vary: accept`. With `prefer-offline=true`
# (npm maps it to HTTP cache mode `force-cache`) both are served without
# revalidation, so the full record can fall behind the compressed one. Tag and
# range resolution then reads a `latest` dist-tag from the fresh compressed
# record, looks that version up in the stale full record, does not find it, and
# npm aborts with:
#
#     npm error code ETARGET
#     npm error notarget No matching version found for <pkg>@<version>
#
# `--prefer-online` does NOT bypass this: npm-registry-fetch's getCacheMode()
# checks `preferOffline` before `preferOnline`. `NPM_CONFIG_PREFER_OFFLINE=false`
# does, because env config outranks the .npmrc files.
#
# The precondition is mechanical and checkable offline: a cache key that has a
# full-metadata record significantly older than its compressed record. That is
# what this script reports. Note it only flags the *split*, not whether a
# publish happened to land in the gap (that would need the registry), so treat a
# hit as "this cache can serve a wrong answer for <pkg>@latest".
#
# Fix when it reports something: `npm cache verify`. It rebuilds the index
# keeping the newest record per key, so the stale variant is dropped and the
# next full-metadata request refetches it. (`npm cache clean --force` also works
# but throws the whole cache away; verify keeps the ~800MB of content.)
#
# Usage: check-npm-cache.sh [npm-cache-dir]   (default: $HOME/.npm)
# Env:   MAX_LAG_SECONDS  minimum age gap that counts as stale (default 3600)
# Exit:  0 = clean, 1 = stale records found, 2 = bad usage/missing dependency
set -euo pipefail

cache_dir="${1:-${npm_config_cache:-$HOME/.npm}}"
index_dir="$cache_dir/_cacache/index-v5"
max_lag="${MAX_LAG_SECONDS:-3600}"

if ! command -v jq >/dev/null 2>&1; then
	echo "ERROR: jq is required (it parses the cacache index records)." >&2
	echo "Install it with: brew install jq  (or add pkgs.jq to home.packages)" >&2
	exit 2
fi

if [ ! -d "$index_dir" ]; then
	echo "OK: no npm cache index at $index_dir — nothing to check"
	exit 0
fi

# Index buckets are newline-delimited "hash\t<json>" records; older records for
# a key stay in the file, which is exactly how the two packument variants can
# drift apart. Malformed/truncated lines are skipped rather than fatal.
records="$(find "$index_dir" -type f -exec cat {} + | cut -f2- | wc -l | tr -d ' ')"

stale="$(
	find "$index_dir" -type f -exec cat {} + | cut -f2- |
		jq -r -R -s --argjson lag "$max_lag" '
			split("\n")
			| map(select(length > 0) | fromjson? // empty)
			| map(select(.key? != null and .metadata.reqHeaders.accept? != null))
			| group_by(.key)
			| map({
				key: .[0].key,
				full: ([.[] | select(.metadata.reqHeaders.accept == "application/json")] | max_by(.time)),
				corgi: ([.[] | select(.metadata.reqHeaders.accept | test("install-v1"))] | max_by(.time))
			})
			| map(select(.full != null and .corgi != null
				and ((.corgi.time - .full.time) / 1000 > $lag)))
			| .[]
			| [
				(.key | sub("^make-fetch-happen:request-cache:"; "")),
				(.full.time / 1000 | todate),
				(.corgi.time / 1000 | todate),
				(((.corgi.time - .full.time) / 1000) | floor | tostring)
			]
			| @tsv
		'
)"

if [ -z "$stale" ]; then
	echo "OK: $records npm cache records checked — no stale full-metadata packuments"
	exit 0
fi

echo "ERROR: stale full-metadata packument(s) in $index_dir" >&2
echo "       Tag/range resolution for these packages can fail with ETARGET." >&2
echo "" >&2
while IFS=$'\t' read -r key full corgi lag; do
	[ -n "$key" ] || continue
	if [ "$lag" -ge 86400 ]; then
		human="$((lag / 86400))d behind"
	else
		human="$((lag / 3600))h behind"
	fi
	printf '  %s\n    full %s  |  compressed %s (%s)\n' "$key" "$full" "$corgi" "$human" >&2
done <<<"$stale"
echo "" >&2
echo "Fix: npm cache verify" >&2
echo "     (keeps cached content; drops superseded index records)" >&2
exit 1
