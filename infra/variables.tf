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
