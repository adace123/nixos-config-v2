terraform {
  required_version = ">= 1.0"

  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.21"
    }
  }

  # Local state, deliberate (2026-10-26): this workspace applies laptop-only
  # with creds outside the repo, and the policy text lives in git anyway. The
  # R2 backend can return if CI plans are ever wanted — until then it would
  # only add a dependency on secrets this machine cannot currently decrypt.
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "tailscale" {
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
}
