# MikroTik RouterOS v7: BGP peering with a PowerBGP test peer, BFD enabled.
# Provider: https://registry.terraform.io/providers/terraform-routeros/routeros
#
# PowerBGP side:
#   Start-BgpSession -Name mikrotik -RemoteAddress <router IP> -RemoteAS 65000 -LocalAS 65001
#   Start-BfdSession -Name mikrotik-bfd -RemoteAddress <router IP>

terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
  }
}

variable "ros_hosturl" {
  type    = string
  default = "https://192.168.88.1"
}

variable "ros_username" {
  type    = string
  default = "admin"
}

variable "ros_password" {
  type      = string
  sensitive = true
}

variable "powerbgp_ip" {
  type    = string
  default = "192.168.88.50"
}

variable "powerbgp_as" {
  type    = string
  default = "65001"
}

variable "mikrotik_as" {
  type    = string
  default = "65000"
}

provider "routeros" {
  hosturl  = var.ros_hosturl
  username = var.ros_username
  password = var.ros_password
  insecure = true # lab only: self-signed certificate
}

resource "routeros_routing_bgp_connection" "powerbgp" {
  name    = "powerbgp-lab"
  as      = var.mikrotik_as
  use_bfd = true
  connect = true
  listen  = true

  # TCP-MD5 (RFC 2385) needs the Linux/container build of PowerBGP:
  # tcp_md5_key = var.md5_key

  # Add if the peer is more than one hop away (and use Start-BfdSession -MultiHop):
  # multihop = true

  local {
    role = "ebgp"
  }

  remote {
    address = var.powerbgp_ip
    as      = var.powerbgp_as
  }
}

# Optional: tune BFD timers for sessions on this interface
resource "routeros_routing_bfd_configuration" "lab" {
  interfaces = ["bridge"]
  min_rx     = "300ms"
  min_tx     = "300ms"
  multiplier = 3
}
