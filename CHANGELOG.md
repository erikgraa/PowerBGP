# Changelog

## 0.5.2

- BFD: `-MultiHop` (RFC 5883, UDP 4784) and `-LocalAddress` on `Start-BfdSession` and `Update-BfdSession`; `Get-BfdSession` shows `LocalAddress`
- BFD: reply with the Final bit when the peer sends a Poll

## 0.5.1

- Fix the Gallery package: the `Public` and `Private` folders were flattened in 0.5.0, so the module exported nothing. 0.5.0 is unlisted.

## 0.5.0

First Gallery release.

- BGP-4 and BFD session engines, each peer in its own runspace
- Generic packet builder (`New-Packet`, `New-PacketField`, `Format-Packet`) and BGP/BFD message builders and parsers
- Route advertisement, withdrawal and bulk prefix ranges; learned and advertised route views
- Inbound route filters (`New-BgpFilterRule`, `-InboundFilter`, `-InboundDefault`)
- IPv6 unicast via MP-BGP (`-AddressFamily IPv6`, `MP_REACH_NLRI` / `MP_UNREACH_NLRI`)
- `-LocalAddress` to bind a session to a source IP (several sessions to one router, ECMP tests)
- Peer and BFD editing, fault injection, TCP-MD5 (Linux), config export/import
- Peer cmdlets are named `*-BgpSession` to avoid clashing with the Windows Server RemoteAccess `*-BgpPeer` cmdlets
- `Containerfile` and GitHub Actions tests

Fixes: `Format-Packet` with pipeline input, `ConvertFrom-BgpMessage` `MarkerValid`, passive peer `RemoteAddress` including the port.
