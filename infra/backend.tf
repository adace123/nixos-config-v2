# ── Remote State (Cloudflare R2) ──────────────────────────────────────────────
#
# Bucket and endpoint are passed via -backend-config on init:
#   just init
#
# Credentials come from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
# (set by `sops exec-env` from secrets/oci.yaml, or via GitHub Secrets in CI).
#
# One-time manual step: create the R2 bucket before first init.
# You can do this via the Cloudflare dashboard or rclone:
#   nix run nixpkgs#rclone -- mkdir r2:<bucket-name>
#
terraform {
  backend "s3" {
    key = "infra/terraform.tfstate"

    # R2 ignores the region field but requires it be set
    region                      = "auto"
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}
