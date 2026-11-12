output "instance_id" {
  description = "OCID of the dathomir instance"
  value       = oci_core_instance.nixos.id
}

output "platform_image_id" {
  description = "OCID of the Oracle platform image the instance booted (the NixOS conversion happens in place after boot)"
  # Read from the instance, not the `oci_core_images` data source: Oracle keeps
  # publishing newer builds of the same release, so the data source's newest id
  # stops describing what this instance actually booted.
  value = oci_core_instance.nixos.source_details[0].source_id
}
