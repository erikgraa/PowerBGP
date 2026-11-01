# NSX (VCF) Tier-0: add one BGP peering to a PowerBGP test peer, BFD enabled.
# Assumes the Tier-0 gateway, its edge cluster, an external uplink interface and BGP are already configured.
# Provider: https://registry.terraform.io/providers/vmware/nsxt
#
# PowerBGP side (bind to an address in the uplink subnet; it must match the neighbor_address below):
#   Start-BgpSession -Name nsx -RemoteAddress <T0 uplink IP> -RemoteAS 65003 -LocalAS 65000 -LocalAddress <powerbgp_ip>
#   Start-BfdSession -Name nsx-bfd -RemoteAddress <T0 uplink IP> -LocalAddress <powerbgp_ip>

terraform {
  required_providers {
    nsxt = {
      source = "vmware/nsxt"
    }
  }
}

provider "nsxt" {
  host                 = var.nsx_host
  username             = var.nsx_username
  password             = var.nsx_password
  allow_unverified_ssl = true # lab only
}

data "nsxt_policy_tier0_gateway" "t0" {
  display_name = var.tier0_name
}

data "nsxt_policy_gateway_locale_service" "t0" {
  gateway_path = data.nsxt_policy_tier0_gateway.t0.path
  display_name = var.locale_service_name
}

resource "nsxt_policy_bgp_neighbor" "powerbgp" {
  display_name     = "powerbgp-lab"
  description      = "PowerBGP test peer"
  bgp_path         = data.nsxt_policy_gateway_locale_service.t0.bgp_path
  neighbor_address = var.powerbgp_ip
  remote_as_num    = var.powerbgp_as
  hold_down_time   = 90
  keep_alive_time  = 30

  # Graceful restart: PowerBGP supports RFC 4724 (-GracefulRestart)
  graceful_restart_mode = "HELPER_ONLY"

  # TCP-MD5 (RFC 2385) needs the Linux/container build of PowerBGP:
  # password = var.md5_key

  bfd_config {
    enabled  = true
    interval = 1000
    multiple = 3
  }
}
