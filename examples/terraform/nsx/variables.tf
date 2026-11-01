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

# IPs of existing Tier-0 uplink interfaces to peer from (the "Source Addresses" in the NSX UI)
# Empty = NSX uses all uplinks
variable "source_addresses" {
  type    = list(string)
  default = []
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

variable "nsx_as" {
  type        = string
  description = "Local AS the NSX neighbor uses towards PowerBGP"
  default     = "65003"
}

variable "md5_key" {
  type        = string
  description = "TCP-MD5 password for the BGP neighbor (null = no authentication)"
  default     = null
  sensitive   = true
}
