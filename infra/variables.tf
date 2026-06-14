variable "compartment_ocid" {
  description = "OCID of the compartment to deploy resources into (set via TF_VAR_compartment_ocid from just get-secret)"
  type        = string
}

variable "private_key_path" {
  description = "Path to the OCI API private key PEM file (set via TF_VAR_private_key_path from just get-secret)"
  type        = string
}

variable "ssh_public_key" {
  description = "Public SSH key content for the nixos user"
  type        = string
  sensitive   = true
}

variable "image_path" {
  description = "Local path to the NixOS OCI qcow2 image"
  type        = string
  default     = "./result/nixos.qcow2"
}
