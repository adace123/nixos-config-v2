#!/usr/bin/env bash
# Convert a freshly-provisioned dathomir OCI instance from its Oracle platform
# image (Ubuntu) to NixOS in place, then converge it onto the flake config.
#
# Why this exists: an Always Free tenancy has `custom-image-count = 0`, so a
# built qcow2 cannot be imported as a custom image (CreateImage fails with
# 400-QuotaExceeded) and the instance boots a free Oracle platform image
# instead. nixos-infect replaces that OS with NixOS, using the platform image's
# existing filesystems and bootloader, so no custom image and no re-partitioning
# is involved. See docs/dathomir.md.
#
# Run it after `tofu apply` has created the instance, once it answers as
# `ubuntu@<target>` over the tailnet. Re-running is safe: an instance that is
# already NixOS skips straight to the convergence step.
#
# Usage: scripts/dathomir-convert.sh [target]    (default: dathomir)
set -euo pipefail

# Pinned: nixos-infect rewrites the root filesystem in place, so it should not
# change underfoot between runs. The hash is the integrity anchor — the script is
# fetched on this workstation, verified against it, and only then copied to the
# host to run as root. Nothing is piped into a root shell from the network.
NIXOS_INFECT_REV="40f62a680bb0e8f2f607d79abfaaecd99d59401c"
NIXOS_INFECT_SHA256="4354bd68773b41da65c0e815202c43c8549713b3ed3ff6381c71fbc0b0a840ab"
NIXOS_INFECT_URL="https://raw.githubusercontent.com/elitak/nixos-infect/${NIXOS_INFECT_REV}/nixos-infect"

TARGET="${1:-dathomir}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMPORT_MODULE="$REPO_ROOT/infra/dathomir-infect-import.nix"
BOOT_TIMEOUT_SECONDS="${BOOT_TIMEOUT_SECONDS:-900}"

SSH_OPTS=(
	-o BatchMode=yes
	-o StrictHostKeyChecking=accept-new
	-o ConnectTimeout=10
	-o ServerAliveInterval=30
)

log() { printf '\n== %s\n' "$*"; }
die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

# SC2029 is about *unintended* client-side expansion. Here it is the point: callers
# pass fully-formed remote commands, and the arguments are already quoted at each
# call site.
# shellcheck disable=SC2029
ssh_as() { ssh "${SSH_OPTS[@]}" "$1@$2" "${@:3}"; }

# sha256sum on Linux, shasum on macOS (this runs from the workstation).
sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | cut -d' ' -f1
	else
		die "need sha256sum or shasum to verify the nixos-infect download"
	fi
}

# Tailscale names the converted node `dathomir` unless the pre-conversion node
# still holds that name, in which case it becomes `dathomir-1`. Find whichever
# dathomir node is online so the wait and the convergence step follow the box.
online_dathomir_node() {
	command -v tailscale >/dev/null 2>&1 || return 1
	command -v jq >/dev/null 2>&1 || return 1
	tailscale status --json 2>/dev/null |
		jq -r '
      [.Peer[]?
       | select(.HostName | test("^dathomir"))
       | select(.Online == true)]
      | sort_by(.LastSeen)
      | last
      | (.DNSName // empty)' |
		sed 's/\.$//'
}

is_nixos() { ssh_as root "$1" 'test -e /etc/NIXOS' 2>/dev/null; }

# ── Phase 1: convert the platform image to NixOS ──────────────────────────────

if is_nixos "$TARGET"; then
	log "$TARGET is already NixOS — skipping the conversion"
else
	log "Checking $TARGET is the Oracle platform image (Ubuntu)"
	ssh_as ubuntu "$TARGET" 'grep -q Ubuntu /etc/os-release' ||
		die "$TARGET does not look like the Ubuntu platform image; not converting it"

	# The auth key cloud-init wrote must exist *before* the pivot: it is the only
	# way back in, since the instance has no public IP.
	ssh_as ubuntu "$TARGET" 'test -s /var/lib/tailscale/authkey' ||
		die "$TARGET has no /var/lib/tailscale/authkey — did cloud-init run? (tailnet access would be lost on conversion)"

	log "Staging the preserved Tailscale key and the NixOS import module"
	# NIXOS_LUSTRATE carries /etc/nixos across the pivot and discards /var, so the
	# key has to be copied out of /var/lib/tailscale first.
	ssh_as ubuntu "$TARGET" 'sudo install -d -m 700 /etc/nixos && sudo install -m 600 /var/lib/tailscale/authkey /etc/nixos/tailscale-authkey'
	scp "${SSH_OPTS[@]}" "$IMPORT_MODULE" "ubuntu@$TARGET:/tmp/dathomir-import.nix"
	ssh_as ubuntu "$TARGET" 'sudo install -m 600 /tmp/dathomir-import.nix /etc/nixos/dathomir-import.nix && rm -f /tmp/dathomir-import.nix'

	log "Fetching nixos-infect $NIXOS_INFECT_REV and verifying it"
	infect_file="$(mktemp)"
	trap 'rm -f "$infect_file"' EXIT
	curl -fsSL "$NIXOS_INFECT_URL" -o "$infect_file" ||
		die "could not download nixos-infect from $NIXOS_INFECT_URL"
	actual_sha256="$(sha256_of "$infect_file")"
	[[ $actual_sha256 == "$NIXOS_INFECT_SHA256" ]] ||
		die "nixos-infect hash mismatch: expected $NIXOS_INFECT_SHA256, got $actual_sha256 — refusing to run it as root"

	log "Running the verified nixos-infect on $TARGET — this takes a while"
	scp "${SSH_OPTS[@]}" "$infect_file" "ubuntu@$TARGET:/tmp/nixos-infect"
	ssh_as ubuntu "$TARGET" 'sudo env NIXOS_IMPORT=./dathomir-import.nix bash /tmp/nixos-infect'
	ssh_as ubuntu "$TARGET" 'rm -f /tmp/nixos-infect' || true

	# Carry the Tailscale node identity (/var/lib/tailscale) across the pivot, not
	# just the key: nixos-infect writes /etc/NIXOS_LUSTRATE with the paths to keep
	# (etc/nixos, ssh host keys, ...) and discards the rest, so without this the
	# converted box has to authenticate a second time — and a single-use auth key
	# would leave it unreachable, since it has no public IP. With the state kept,
	# tailscaled comes up already logged in and the key in /etc/nixos is only a
	# fallback.
	log "Preserving /var/lib/tailscale across the pivot"
	ssh_as ubuntu "$TARGET" 'grep -qx "var/lib/tailscale" /etc/NIXOS_LUSTRATE || echo "var/lib/tailscale" | sudo tee -a /etc/NIXOS_LUSTRATE'

	log "Rebooting into NixOS"
	ssh_as ubuntu "$TARGET" 'sudo reboot' || true

	log "Waiting up to ${BOOT_TIMEOUT_SECONDS}s for NixOS to come back"
	deadline=$((SECONDS + BOOT_TIMEOUT_SECONDS))
	NODE="$TARGET"
	until is_nixos "$NODE"; do
		((SECONDS < deadline)) || die "$TARGET did not come back as NixOS in ${BOOT_TIMEOUT_SECONDS}s (check the OCI serial console)"
		if [[ $NODE == "$TARGET" ]]; then
			if candidate="$(online_dathomir_node)" && [[ -n $candidate && $candidate != "$TARGET" ]]; then
				printf 'note: node came back as %s — the pre-conversion tailnet node still holds the name %s.\n' "$candidate" "$TARGET"
				printf '      delete the stale node in the Tailscale admin console to get the plain name back.\n'
				NODE="$candidate"
			fi
		fi
		sleep 15
	done
fi

# ── Phase 2: converge onto the flake configuration ────────────────────────────

# The flake config declares the platform image's layout by label. Check it here:
# booting a system whose fileSystems do not match the disk is not a failure you
# can recover from over SSH.
log "Verifying the instance's filesystem labels match the flake configuration"
if ! ssh_as root "$NODE" 'test -e /dev/disk/by-label/cloudimg-rootfs && test -e /dev/disk/by-partlabel/ESP'; then
	ssh_as root "$NODE" 'findmnt -no SOURCE,FSTYPE,TARGET / /boot/efi; ls /dev/disk/by-label /dev/disk/by-partlabel' || true
	die "this instance's labels are above; modules expect by-label/cloudimg-rootfs and by-partlabel/ESP — fix fileSystems before converging"
fi

log "Activating the flake configuration on $NODE (built on the host, no local aarch64 builder needed)"
NHOST=dathomir just --justfile "$REPO_ROOT/justfile" --working-directory "$REPO_ROOT" nixos-deploy "$NODE"

log "Done"
ssh_as root "$NODE" 'nixos-version && tailscale status --peers=false'
