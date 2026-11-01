variable "nsx_host" {
  type    = string
  default = "nsx.lab.local"
}

variable "nsx_username" {
  type    = string
  default = "admin"
}

variable "nsx_password" {
  type      = string
  sensitive = true
}

variable "tier0_name" {
  type    = string
  default = "t0-gw"
}

# Leave null if the Tier-0 has a single locale service
variable "locale_service_name" {
  type    = string
  default = null
}

variable "powerbgp_ip" {
  type        = string
  description = "PowerBGP address, in the same subnet as the Tier-0 uplink"
  default     = "192.168.88.50"
}

variable "powerbgp_as" {
  type    = string
  default = "65000"
}
