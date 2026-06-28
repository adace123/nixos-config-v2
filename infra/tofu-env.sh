#!/usr/bin/env bash
set -euo pipefail

_env_variants() {
	printf '%s\n' "$1"
	printf '%s\n' "$1" | sed 's/-/_/g'
	printf '%s\n' "$1" | tr '[:lower:]' '[:upper:]' | sed 's/-/_/g'
}

_secret_try() {
	local name="$1"
	printenv "$name" 2>/dev/null || true
}

secret() {
	local value name variant

	for name in "$@"; do
		while IFS= read -r variant; do
			value="$(_secret_try "$variant")"
			if [ -n "$value" ]; then
				printf '%s' "$value"
				return 0
			fi
		done < <(_env_variants "$name")
	done

	printf 'ERROR: missing required secret/env var; tried:' >&2
	for name in "$@"; do
		while IFS= read -r variant; do
			printf ' %s' "$variant" >&2
		done < <(_env_variants "$name")
	done
	printf '\n' >&2
	return 1
}

if [ "$#" -eq 0 ]; then
	printf 'Usage: %s init|tofu|<command> [args...]\n' "$0" >&2
	exit 64
fi

compartment_ocid="${TF_VAR_compartment_ocid:-${OCI_COMPARTMENT_OCID:-$(secret oci-compartment-ocid)}}"
tenancy_ocid="${OCI_TENANCY_OCID:-}"
while IFS= read -r variant; do
	value="$(_secret_try "$variant")"
	[ -n "$value" ] && {
		tenancy_ocid="$value"
		break
	}
done < <(printf '%s\n' oci-tenancy-ocid oci-tenancy-id | while IFS= read -r n; do _env_variants "$n"; done | sort -u)
if [[ $tenancy_ocid != ocid1.tenancy.oc1* && $compartment_ocid == ocid1.tenancy.oc1* ]]; then
	tenancy_ocid="$compartment_ocid"
fi
if [[ $tenancy_ocid != ocid1.tenancy.oc1* ]]; then
	printf 'ERROR: OCI tenancy must be a tenancy OCID (ocid1.tenancy.oc1...). ' >&2
	printf 'Set OCI_TENANCY_OCID or secrets/oci.yaml key oci-tenancy-ocid.\n' >&2
	exit 1
fi

user_ocid="${OCI_USER_OCID:-$(secret oci-user-ocid)}"
fingerprint="${OCI_FINGERPRINT:-$(secret oci-fingerprint)}"
region="${OCI_REGION:-$(secret oci-region)}"

export OCI_TENANCY_OCID="$tenancy_ocid"
export OCI_USER_OCID="$user_ocid"
export OCI_FINGERPRINT="$fingerprint"
export OCI_REGION="$region"
export TF_VAR_tenancy_ocid="${TF_VAR_tenancy_ocid:-$tenancy_ocid}"
export TF_VAR_user_ocid="${TF_VAR_user_ocid:-$user_ocid}"
export TF_VAR_fingerprint="${TF_VAR_fingerprint:-$fingerprint}"
export TF_VAR_region="${TF_VAR_region:-$region}"
export TF_VAR_compartment_ocid="$compartment_ocid"
export TF_VAR_ssh_public_key="${TF_VAR_ssh_public_key:-${OCI_SSH_PUBLIC_KEY:-${OCI_PUBLIC_KEY:-$(secret oci-public-key)}}}"

r2_account_id="${R2_ACCOUNT_ID:-$(secret r2-account-id)}"
r2_access_key_id="${R2_ACCESS_KEY_ID:-$(secret r2-access-key-id)}"
r2_secret_access_key="${R2_SECRET_ACCESS_KEY:-$(secret r2-secret-access-key)}"
export R2_ACCOUNT_ID="$r2_account_id"
export R2_BUCKET_NAME="${R2_BUCKET_NAME:-$(secret r2-bucket-name)}"
export R2_ENDPOINT="${R2_ENDPOINT:-https://${r2_account_id}.r2.cloudflarestorage.com}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-$r2_access_key_id}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-$r2_secret_access_key}"
export AWS_ENDPOINT_URL_S3="${AWS_ENDPOINT_URL_S3:-$R2_ENDPOINT}"

private_key="${OCI_PRIVATE_KEY:-$(secret oci-private-key)}"
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/oci-key.XXXXXX")"
key_file="$temp_dir/key.pem"
cleanup() {
	rm -rf "$temp_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s\n' "$private_key" >"$key_file"
chmod 600 "$key_file"
export TF_VAR_private_key_path="$key_file"

case "$1" in
init)
	shift
	tofu init \
		-input=false \
		-backend-config="bucket=$R2_BUCKET_NAME" \
		-backend-config="endpoint=$R2_ENDPOINT" \
		"$@"
	;;
tofu)
	shift
	tofu "$@"
	;;
*)
	"$@"
	;;
esac
