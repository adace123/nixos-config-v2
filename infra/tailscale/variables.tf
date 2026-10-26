variable "tailscale_oauth_client_id" {
  description = "Tailscale OAuth client ID (Policy File write + Devices Core read). Outside the repo: TF_VAR_tailscale_oauth_client_id or ~/.config/tailscale-oauth.env."
  type        = string
  sensitive   = false
}

variable "tailscale_oauth_client_secret" {
  description = "Tailscale OAuth client secret. Outside the repo, never committed."
  type        = string
  sensitive   = true
}
