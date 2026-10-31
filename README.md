# PowerBGP

PowerShell module for standing up BGP and BFD test peers against physical routers, NSX Tier-0 gateways and Windows Server BGP, plus generic packet-crafting cmdlets.

```powershell
Import-Module ./PowerBGP.psd1
Start-BgpPeer -Name lab -LocalAS 65001 -RemoteAS 65000 -RouterId 10.0.0.5 -RemoteAddress 10.0.0.1
Send-BgpUpdate -Name lab -Nlri 10.10.0.0/24 -NextHop 10.0.0.5
Get-BgpPeer
```

- Packet builders: `New-Packet`, `New-BgpOpen`, `New-BgpUpdate`, `New-BgpKeepalive`, `New-BgpNotification`, `New-BfdControl`, `Format-Packet`
- Sessions: `Start/Stop/Resume/Update/Remove-BgpPeer`, `Start/Stop/Resume/Update/Remove-BfdSession`
- TCP-MD5 (RFC 2385) passwords work on Linux only.
- Limits: IPv4 unicast, no BFD authentication.

Tests: `Invoke-Pester ./Tests`

Web UI and REST API: see PowerBGP.Pode.
