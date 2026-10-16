# ── Data Sources ──────────────────────────────────────────────────────────────

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

# dathomir boots an Oracle *platform* image. An Always Free tenancy has
# `custom-image-count = 0`, so importing a built NixOS qcow2 as a custom image
# fails with `400-QuotaExceeded ... CreateImage`; a quota policy cannot raise an
# Oracle-imposed service limit. The instance therefore starts as Ubuntu (a
# platform image, which is free) and is converted to NixOS in place — see
# docs/dathomir.md.
data "oci_core_images" "platform" {
  compartment_id           = var.compartment_ocid
  operating_system         = var.platform_image_operating_system
  operating_system_version = var.platform_image_operating_system_version
  shape                    = var.instance_shape
  state                    = "AVAILABLE"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
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
  display_name   = "nixos-egress"

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

# ── Instance ──────────────────────────────────────────────────────────────────

resource "oci_core_instance" "nixos" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain_number].name
  fault_domain        = var.fault_domain
  shape               = var.instance_shape
  display_name        = "dathomir"

  shape_config {
    memory_in_gbs = var.instance_memory_gbs
    ocpus         = var.instance_ocpus
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.platform.images[0].id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    # The instance has no public IP, so the platform-image (Ubuntu) stage is only
    # reachable over Tailscale — the conversion in scripts/dathomir-convert.sh is
    # operator-run and needs to get in before the OS is replaced. On the NixOS
    # side the same key file is preserved across the pivot (see that script); the
    # NixOS config does not use cloud-init.
    user_data = base64encode(<<-EOT
      #cloud-config
      write_files:
        - path: /var/lib/tailscale/authkey
          owner: root:root
          permissions: '0600'
          content: |
            ${var.tailscale_auth_key}
      runcmd:
        - [ bash, -c, "curl -fsSL https://tailscale.com/install.sh | sh" ]
        - [ bash, -c, "for i in $(seq 1 60); do systemctl is-active --quiet tailscaled && break; sleep 2; done; tailscale up --auth-key=$(cat /var/lib/tailscale/authkey) --ssh --hostname dathomir" ]
    EOT
    )
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = var.assign_public_ip
  }

  lifecycle {
    precondition {
      condition     = var.instance_shape == "VM.Standard.A1.Flex" && var.instance_ocpus <= 2 && var.instance_memory_gbs <= 12
      error_message = "Refusing to create non-Always-Free compute: use VM.Standard.A1.Flex with <= 2 OCPUs and <= 12 GB RAM."
    }
  }

  launch_options {
    network_type     = "PARAVIRTUALIZED"
    boot_volume_type = "PARAVIRTUALIZED"
  }
}
