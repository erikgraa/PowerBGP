# Changelog

## 0.8.1

- CI: `container.yml` builds, smoke-tests and publishes a multi-arch image to `ghcr.io/erikgraa/powerbgp` on a `v*` tag or a manual run. Adds a `.dockerignore`. No module changes

## 0.8.0

- BFD authentication (RFC 5880 section 6.7): `-AuthType SimplePassword|KeyedSHA1`, `-AuthKeyId`, `-AuthKey` on `Start-/Update-/Resume-BfdSession` and `New-/ConvertFrom-BfdControl`. `Get-BfdSession` shows `AuthType` and `AuthFailures`. Unauthenticated sessions are unchanged
- iBGP: when the peer's AS equals `LocalAS`, `Send-BgpUpdate` sends an empty AS_PATH and a default `LOCAL_PREF` of 100 (override with `-LocalPref`). `Get-BgpSession` shows `Type` (`iBGP` or `eBGP`)
- CI: `publish.yml` builds and pushes to the PowerShell Gallery on a `v*` tag or a manual run (dry run by default)
- README gains a TODO section

## 0.7.1 (not released separately)

- iBGP: when the peer's AS equals `LocalAS`, `Send-BgpUpdate` sends an empty AS_PATH and a default `LOCAL_PREF` of 100 (override with `-LocalPref`). `Get-BgpSession` shows `Type` (`iBGP` or `eBGP`)
- README gains a TODO section

## 0.7.0

- Graceful Restart (RFC 4724): `-GracefulRestart` and `-RestartTime` on `Start-BgpSession` and `Update-BgpSession`; `New-BgpOpen -GracefulRestart -RestartTime -RestartFlag`
- End-of-RIB: `New-BgpUpdate -EndOfRib [-AddressFamily]`; the parser reports `EndOfRib`; sessions send it after the replay
- Learned routes are kept as stale when a Graceful Restart peer drops, and cleared on End-of-RIB or when the peer's restart time expires
- `Get-BgpSession`: `GracefulRestart`, `RestartTime`, `PeerGracefulRestart`, `PeerRestartTime`, `StaleRoutes`; `Get-BgpRoute`: `Stale`
- README lists the RFCs PowerBGP touches

## 0.6.0

- `Start-BgpSession` now reconnects after a drop by default. Use `-AutoReconnect:$false` to stay down. The REST API and UI follow the same default.
- `Export-BgpConfig` always records `AutoReconnect`

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
