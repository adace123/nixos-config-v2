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
  description = "Public SSH key content for the nixos user (set by infra/tofu-env.sh via TF_VAR_ssh_public_key)"
  type        = string
}

variable "image_path" {
  description = "Local path to the NixOS OCI qcow2 image"
  type        = string
  default     = "./result/nixos.qcow2"
}
