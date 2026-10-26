#!/usr/bin/env bash
# tailscale-inventory-check.sh — hosts aliases vs live device inventory.
# The policy tests resolve the same aliases as the grants, so they CANNOT
# catch a stale IP after a host re-registers. This check can. Run alongside
# every apply: set -a; . ~/.config/tailscale-oauth.env; ./scripts/tailscale-inventory-check.sh
set -euo pipefail

: "${TS_CLIENT_ID:?set TS_CLIENT_ID (see ~/.config/tailscale-oauth.env)}"
: "${TS_CLIENT_SECRET:?set TS_CLIENT_SECRET}"

TOK=$(curl -s -d "client_id=${TS_CLIENT_ID}" -d "client_secret=${TS_CLIENT_SECRET}" \
	"https://api.tailscale.com/api/v2/oauth/token" | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])")
trap 'unset TOK' EXIT

DEVICES=$(curl -s -H "Authorization: Bearer $TOK" \
	"https://api.tailscale.com/api/v2/tailnet/-/devices?fields=all")
fail=0
for host in endor s23 coruscant dathomir muse; do
	# configured IP: the quoted IPv4 on the alias line in tailscale.tf

	cfg=$(grep "\"$host\"" infra/tailscale/tailscale.tf | head -1 | grep -oE '"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"')
	live=$(echo "$DEVICES" | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
names={'endor':'enervee-ltqcw2y7pv','s23':'Aaron\\'s S23','coruscant':'coruscant','dathomir':'dathomir','muse':'muse'}
want=names['$host']
for v in d:
  if v.get('hostname')==want:
    print(v['addresses'][0]); break
")
	if [ "$cfg" = "$live" ]; then
		echo "OK   $host $cfg"
	else
		echo "STALE $host config=$cfg live=$live"
		fail=1
	fi
done
exit "$fail"
