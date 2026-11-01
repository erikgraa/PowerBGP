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
  default = "65000"
}

variable "mikrotik_as" {
  type    = string
  default = "65001"
}
