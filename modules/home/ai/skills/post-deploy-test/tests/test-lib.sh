# shellcheck shell=sh
# test-lib.sh — shared helpers for post-deploy tests

pass() {
	echo "PASS: $1"
}

fail() {
	echo "FAIL: $1"
}

die() {
	echo "FAIL: $1" >&2
	exit 1
}
