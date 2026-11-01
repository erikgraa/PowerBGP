variable "iosxe_host" {
  type    = string
  default = "192.168.88.2" # NETCONF port 830 unless you add :port
}

variable "iosxe_username" {
  type    = string
  default = "admin"
}

variable "iosxe_password" {
  type      = string
  sensitive = true
}

variable "powerbgp_ip" {
  type    = string
  default = "192.168.88.50"
}

variable "powerbgp_as" {
  type    = string
  default = "65000"
}

variable "cisco_as" {
  type    = string
  default = "65002"
}
