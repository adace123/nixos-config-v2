variable "tenancy_ocid" {
  description = "OCI tenancy OCID (set by infra/tofu-env.sh via TF_VAR_tenancy_ocid)"
  type        = string
}

variable "user_ocid" {
  description = "OCI user OCID (set by infra/tofu-env.sh via TF_VAR_user_ocid)"
  type        = string
}

variable "fingerprint" {
  description = "OCI API key fingerprint (set by infra/tofu-env.sh via TF_VAR_fingerprint)"
  type        = string
}

variable "region" {
  description = "OCI region (set by infra/tofu-env.sh via TF_VAR_region)"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID of the compartment to deploy resources into (set by infra/tofu-env.sh via TF_VAR_compartment_ocid)"
  type        = string
}

variable "private_key_path" {
  description = "Path to the OCI API private key PEM file (temp file set by infra/tofu-env.sh via TF_VAR_private_key_path)"
  type        = string
}

variable "ssh_public_key" {
  description = "OpenSSH public key(s) for instance metadata. Defaults to the primary dathomir access key. A newline-separated list works here, but note OCI refuses to change ssh_authorized_keys on a live instance — adding the other two hosts/dathomir keys means replacing the instance, and therefore re-running the conversion."
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC6DWf0lf4vWTAUmjkulvvZrhCifTS8eFqkDlHPSawrU"
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key used by cloud-init to join the tailnet."
  type        = string
  sensitive   = true
}

variable "platform_image_operating_system" {
  description = "Oracle platform image family to boot. The instance is converted to NixOS in place; custom images are unavailable on Always Free."
  type        = string
  default     = "Canonical Ubuntu"
}

variable "platform_image_operating_system_version" {
  description = "Version of platform_image_operating_system. Keep in the plain-release form ('24.04'), not the variants ('24.04 Minimal')."
  type        = string
  default     = "24.04"
}

variable "instance_shape" {
  description = "OCI instance shape. Must remain Always Free eligible."
  type        = string
  default     = "VM.Standard.A1.Flex"

  validation {
    condition     = var.instance_shape == "VM.Standard.A1.Flex"
    error_message = "Only VM.Standard.A1.Flex is allowed to keep this deployment inside Always Free compute."
  }
}

variable "instance_ocpus" {
  description = "A1 Flex OCPUs. Always Free-only tenancies include 2 total A1 OCPUs."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_ocpus > 0 && var.instance_ocpus <= 2
    error_message = "instance_ocpus must be <= 2 for Always Free A1 compute."
  }
}

variable "instance_memory_gbs" {
  description = "A1 Flex memory. Always Free-only tenancies include 12 GB total A1 memory."
  type        = number
  default     = 12

  validation {
    condition     = var.instance_memory_gbs > 0 && var.instance_memory_gbs <= 12
    error_message = "instance_memory_gbs must be <= 12 for Always Free A1 compute."
  }
}

variable "availability_domain_number" {
  description = "Index into the availability domains list to try. Bump this if the current AD is out of host capacity (only useful in multi-AD regions)."
  type        = number
  default     = 0

  validation {
    condition     = var.availability_domain_number >= 0
    error_message = "availability_domain_number must be >= 0."
  }
}

variable "fault_domain" {
  description = "Optional OCI fault domain to try when automatic placement reports insufficient capacity."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.fault_domain == null || can(regex("^FAULT-DOMAIN-[1-3]$", var.fault_domain))
    error_message = "fault_domain must be FAULT-DOMAIN-1, FAULT-DOMAIN-2, or FAULT-DOMAIN-3."
  }
}

variable "assign_public_ip" {
  description = "Whether to assign a public IPv4 address. Keep false when accessing through Tailscale."
  type        = bool
  default     = false
}

# ── DNS (infra/dns.tf) ────────────────────────────────────────────────────────
# The token, zone id and hostnames come from secrets/oci.yaml via
# infra/tofu-env.sh, so none of them need to appear in this public repo.

variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS edit rights for the zone below (set by infra/tofu-env.sh via TF_VAR_cloudflare_api_token)"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone holding the HA and beszel records (set via TF_VAR_cloudflare_zone_id)"
  type        = string
}

variable "home_assistant_domain" {
  description = "Public name for Home Assistant on coruscant (set via TF_VAR_home_assistant_domain)"
  type        = string
}

variable "beszel_domain" {
  description = "Public name for the beszel hub (set via TF_VAR_beszel_domain). Lives with Caddy on whatever host serves the hub — dathomir."
  type        = string
}

variable "pocket_id_domain" {
  description = "Public name for Pocket ID, the passkey identity provider the hub delegates its logins to (set via TF_VAR_pocket_id_domain). Served from dathomir too."
  type        = string
}

variable "gatus_domain" {
  description = "Public name for the Gatus status page (set via TF_VAR_gatus_domain). Served from dathomir too."
  type        = string
}

variable "home_assistant_tailnet_ip" {
  description = "Coruscant's Tailscale address. The record points here deliberately: the name resolves publicly but is routable only from inside the tailnet. Update it if that node ever re-registers."
  type        = string
  default     = "100.66.226.84"
}

variable "dathomir_tailnet_ip" {
  description = "dathomir's Tailscale address — where the beszel hub lives. Same reasoning as above, same maintenance note."
  type        = string
  default     = "100.89.136.120"
}
