output "instance_ip" {
  description = "Public IP address of the NixOS instance"
  value       = oci_core_instance.nixos.public_ip
}

output "instance_id" {
  description = "OCID of the NixOS instance"
  value       = oci_core_instance.nixos.id
}

output "image_id" {
  description = "OCID of the custom NixOS image"
  value       = oci_core_image.nixos.id
}
