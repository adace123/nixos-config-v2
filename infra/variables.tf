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
  description = "OpenSSH public key content for instance metadata. Defaults to the primary dathomir access key."
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC6DWf0lf4vWTAUmjkulvvZrhCifTS8eFqkDlHPSawrU"
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key used by cloud-init to join the tailnet."
  type        = string
  sensitive   = true
}

variable "image_path" {
  description = "Local path to the NixOS OCI qcow2 image"
  type        = string
  default     = "./result/nixos.qcow2"
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
    condition     = var.availability_domain_number >= 0 && var.availability_domain_number <= 2
    error_message = "availability_domain_number must be 0, 1, or 2."
  }
}

variable "assign_public_ip" {
  description = "Whether to assign a public IPv4 address. Keep false when accessing through Tailscale."
  type        = bool
  default     = false
}
