#!/usr/bin/env bash
set -euo pipefail

secret() {
	local value
	local name

	for name in "$@"; do
		value="$(printenv "$name" 2>/dev/null || true)"
		if [ -n "$value" ]; then
			printf '%s' "$value"
			return 0
		fi
	done

	printf 'ERROR: missing required secret/env var; tried:' >&2
	printf ' %s' "$@" >&2
	printf '\n' >&2
	return 1
}

yq_secret() {
	yq -r ".[\"$1\"]" "$2"
}

load_secrets_file() {
	local secrets_file="$1"
	local decrypted_file

	decrypted_file="$(mktemp "${TMPDIR:-/tmp}/oci-secrets.XXXXXX")"
	sops -d "$secrets_file" >"$decrypted_file"

	R2_ACCESS_KEY_ID="$(yq_secret r2-access-key-id "$decrypted_file")"
	R2_SECRET_ACCESS_KEY="$(yq_secret r2-secret-access-key "$decrypted_file")"
	R2_ACCOUNT_ID="$(yq_secret r2-account-id "$decrypted_file")"
	R2_BUCKET_NAME="$(yq_secret r2-bucket-name "$decrypted_file")"
	OCI_TENANCY_OCID="$(yq_secret oci-tenancy-id "$decrypted_file")"
	OCI_COMPARTMENT_OCID="$(yq_secret oci-compartment-ocid "$decrypted_file")"
	OCI_USER_OCID="$(yq_secret oci-user-ocid "$decrypted_file")"
	OCI_FINGERPRINT="$(yq_secret oci-fingerprint "$decrypted_file")"
	OCI_REGION="$(yq_secret oci-region "$decrypted_file")"
	OCI_PUBLIC_KEY="$(yq_secret oci-public-key "$decrypted_file")"
	OCI_PRIVATE_KEY="$(yq_secret oci-private-key "$decrypted_file")"
	TF_VAR_tailscale_auth_key="$(yq_secret ts-auth-key "$decrypted_file")"
	export R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_ACCOUNT_ID R2_BUCKET_NAME
	export OCI_TENANCY_OCID OCI_COMPARTMENT_OCID OCI_USER_OCID OCI_FINGERPRINT
	export OCI_REGION OCI_PUBLIC_KEY OCI_PRIVATE_KEY
	export TF_VAR_tailscale_auth_key

	rm -f "$decrypted_file"
}

if [ "$#" -eq 0 ]; then
	printf 'Usage: %s init|tofu|<command> [args...]\n' "$0" >&2
	exit 64
fi

if [ -n "${OCI_SECRETS_FILE:-}" ]; then
	load_secrets_file "$OCI_SECRETS_FILE"
fi

compartment_ocid="${TF_VAR_compartment_ocid:-${OCI_COMPARTMENT_OCID:-$(secret oci-compartment-ocid)}}"
tenancy_ocid="${OCI_TENANCY_OCID:-$(printenv oci-tenancy-ocid 2>/dev/null || true)}"
if [ -z "$tenancy_ocid" ]; then
	tenancy_ocid="$(printenv oci-tenancy-id 2>/dev/null || true)"
fi
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
if [ -n "${OCI_SSH_PUBLIC_KEY:-}" ]; then
	export TF_VAR_ssh_public_key="${TF_VAR_ssh_public_key:-$OCI_SSH_PUBLIC_KEY}"
fi

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
plan-apply)
	shift
	tofu plan -input=false -out=tfplan "$@"
	tofu apply -input=false tfplan
	;;
tofu)
	shift
	tofu "$@"
	;;
*)
	"$@"
	;;
esac
