output "instance_id" {
  description = "OCID of the dathomir instance"
  value       = oci_core_instance.nixos.id
}

output "platform_image_id" {
  description = "OCID of the Oracle platform image the instance booted (the NixOS conversion happens in place after boot)"
  value       = data.oci_core_images.platform.images[0].id
}
