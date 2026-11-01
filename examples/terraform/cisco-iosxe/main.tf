# Cisco IOS-XE: BGP peering with a PowerBGP test peer, BFD enabled.
# Provider: https://registry.terraform.io/providers/CiscoDevNet/iosxe (NETCONF over SSH: enable "netconf-yang" on the device)
#
# PowerBGP side:
#   Start-BgpSession -Name cisco -RemoteAddress <router IP> -RemoteAS 65002 -LocalAS 65000
#   Start-BfdSession -Name cisco-bfd -RemoteAddress <router IP>
#
# BFD timers are configured per interface on IOS-XE (bfd interval ... min_rx ... multiplier ...)
# and are not part of this example.

terraform {
  required_providers {
    iosxe = {
      source = "CiscoDevNet/iosxe"
    }
  }
}

provider "iosxe" {
  host     = var.iosxe_host
  username = var.iosxe_username
  password = var.iosxe_password
}

resource "iosxe_bgp" "this" {
  asn                  = var.cisco_as
  default_ipv4_unicast = false
  log_neighbor_changes = true
}

resource "iosxe_bgp_neighbor" "powerbgp" {
  asn                      = iosxe_bgp.this.asn
  ip                       = var.powerbgp_ip
  remote_as                = var.powerbgp_as
  description              = "PowerBGP lab peer"
  log_neighbor_changes     = true
  fall_over_bfd            = true
  fall_over_bfd_single_hop = true # use fall_over_bfd_multi_hop for a multihop peer

  # TCP-MD5 (RFC 2385) needs the Linux/container build of PowerBGP:
  # password_type = 0
  # password      = var.md5_key
}

# Required: with default_ipv4_unicast = false the neighbor exchanges no IPv4 routes until activated
resource "iosxe_bgp_ipv4_unicast_neighbor" "powerbgp" {
  asn      = iosxe_bgp.this.asn
  ip       = var.powerbgp_ip
  activate = true
}
