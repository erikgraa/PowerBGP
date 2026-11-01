# Terraform examples

Configure the **device side** of a peering with a PowerBGP test peer. Each example is self-contained and lab-oriented (`insecure` TLS, example addresses). Adjust the variables in each `variables.tf`, then:

```bash
terraform init
terraform plan -var ros_password=...   # variable names differ per example
```

| Example | Provider | Notes |
|---|---|---|
| [`mikrotik`](mikrotik/main.tf) | `terraform-routeros/routeros` | RouterOS v7, BGP connection with `use_bfd` and optional BFD timers |
| [`cisco-iosxe`](cisco-iosxe/main.tf) | `CiscoDevNet/iosxe` | `router bgp`, neighbor with `fall-over bfd`, IPv4 unicast activation |
| [`nsx`](nsx/main.tf) | `vmware/nsxt` | One BGP neighbor with BFD on an existing Tier-0 (assumes the edge cluster and uplinks are up) |

The PowerBGP side of each peering is shown in the header comment of each file.

These examples have been checked against the providers' documentation but not yet applied to real devices. Treat them as a starting point.
