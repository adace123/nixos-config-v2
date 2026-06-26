# ── Data Sources ──────────────────────────────────────────────────────────────

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_ocid
}

# ── Networking ────────────────────────────────────────────────────────────────

resource "oci_core_vcn" "nixos" {
  compartment_id = var.compartment_ocid
  display_name   = "nixos-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = "nixos"
}

resource "oci_core_internet_gateway" "nixos" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.nixos.id
  display_name   = "nixos-igw"
  enabled        = true
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.nixos.id
  display_name   = "nixos-public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.nixos.id
  }
}

resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.nixos.id
  display_name   = "nixos-ssh"

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.nixos.id
  display_name               = "nixos-public-subnet"
  cidr_block                 = "10.0.1.0/24"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public.id]
  dns_label                  = "public"
  prohibit_public_ip_on_vnic = false
}

# ── Object Storage ────────────────────────────────────────────────────────────

resource "oci_objectstorage_bucket" "nixos_images" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = "nixos-images"
  access_type    = "NoPublicAccess"
}

resource "oci_objectstorage_object" "nixos_image" {
  bucket    = oci_objectstorage_bucket.nixos_images.name
  namespace = data.oci_objectstorage_namespace.ns.namespace
  object    = "nixos-aarch64.qcow2"
  source    = var.image_path
}

# ── Custom Image ──────────────────────────────────────────────────────────────

resource "oci_core_image" "nixos" {
  compartment_id = var.compartment_ocid
  display_name   = "NixOS ARM64"

  image_source_details {
    source_type    = "objectStorageTuple"
    namespace_name = data.oci_objectstorage_namespace.ns.namespace
    bucket_name    = oci_objectstorage_bucket.nixos_images.name
    object_name    = oci_objectstorage_object.nixos_image.object
  }

  launch_mode = "PARAVIRTUALIZED"

  timeouts {
    create = "60m"
  }
}

# ── Shape Compatibility (A1.Flex) ─────────────────────────────────────────────

resource "oci_core_shape_management" "nixos_a1_compat" {
  compartment_id = var.compartment_ocid
  image_id       = oci_core_image.nixos.id
  shape_name     = "VM.Standard.A1.Flex"
}

# ── Image Capabilities ────────────────────────────────────────────────────────

resource "oci_core_compute_image_capability_schema" "nixos_caps" {
  compartment_id                                      = var.compartment_ocid
  image_id                                            = oci_core_image.nixos.id
  compute_global_image_capability_schema_version_name = "2024-03-27"

  schema_data = {
    "Compute.Firmware" = jsonencode({
      descriptorType = "enumstring"
      source         = "IMAGE"
      defaultValue   = "UEFI_64"
      values         = ["UEFI_64"]
    })

    "Compute.LaunchMode" = jsonencode({
      descriptorType = "enumstring"
      source         = "IMAGE"
      defaultValue   = "PARAVIRTUALIZED"
      values         = ["PARAVIRTUALIZED", "EMULATED", "CUSTOM", "NATIVE"]
    })

    "Storage.BootVolumeType" = jsonencode({
      descriptorType = "enumstring"
      source         = "IMAGE"
      defaultValue   = "PARAVIRTUALIZED"
      values         = ["PARAVIRTUALIZED", "ISCSI", "SCSI", "IDE", "NVME"]
    })

    "Network.AttachmentType" = jsonencode({
      descriptorType = "enumstring"
      source         = "IMAGE"
      defaultValue   = "PARAVIRTUALIZED"
      values         = ["PARAVIRTUALIZED", "E1000", "VFIO", "VDPA"]
    })
  }
}

# ── Instance ──────────────────────────────────────────────────────────────────

resource "oci_core_instance" "nixos" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  shape               = "VM.Standard.A1.Flex"
  display_name        = "dathomir"

  shape_config {
    memory_in_gbs = 12
    ocpus         = 2
  }

  source_details {
    source_type = "image"
    source_id   = oci_core_image.nixos.id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
  }

  launch_options {
    network_type     = "PARAVIRTUALIZED"
    boot_volume_type = "PARAVIRTUALIZED"
  }

  depends_on = [
    oci_core_shape_management.nixos_a1_compat,
    oci_core_compute_image_capability_schema.nixos_caps,
  ]
}
