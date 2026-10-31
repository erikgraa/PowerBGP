@{
    RootModule        = 'PowerBGP.psm1'
    ModuleVersion     = '0.8.0'
    GUID              = '6f0d6d0e-6a53-4c1e-9f6e-3b1c5a7d2e41'
    Author            = 'erikgraa'
    Description       = 'Lab-use-only tool to stand up BGP and BFD test peers from PowerShell against routers such as VMware Cloud Foundation (NSX) edge clusters, Windows Server BGP, MikroTik, Cisco or any RFC-compliant BGP engine. Advertise and withdraw routes, inject faults, and build or parse BGP and BFD packets with a generic packet builder.'
    CompanyName       = 'erikgraa'
    Copyright         = '(c) erikgraa. All rights reserved.'
    PowerShellVersion = '7.4'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @(
        'New-PacketField', 'New-Packet', 'Format-Packet',
        'New-BgpOpen', 'New-BgpKeepalive', 'New-BgpUpdate', 'New-BgpNotification',
        'ConvertFrom-BgpMessage',
        'Start-BgpSession', 'Get-BgpSession', 'Stop-BgpSession', 'Resume-BgpSession', 'Remove-BgpSession', 'Set-BgpSession', 'Update-BgpSession',
        'New-BgpPrefixRange', 'New-BgpFilterRule', 'Export-BgpConfig', 'Import-BgpConfig',
        'Send-BgpMessage', 'Send-BgpUpdate', 'Get-BgpEvent', 'Get-BgpRoute',
        'New-BfdControl', 'ConvertFrom-BfdControl',
        'Start-BfdSession', 'Get-BfdSession', 'Stop-BfdSession', 'Resume-BfdSession', 'Update-BfdSession', 'Remove-BfdSession', 'Set-BfdSession'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{
        Tags         = @('BGP', 'BFD', 'Networking', 'Packet', 'NSX', 'Testing', 'Router', 'Linux', 'Windows')
        ProjectUri   = 'https://github.com/erikgraa/PowerBGP'
        LicenseUri   = 'https://github.com/erikgraa/PowerBGP/blob/main/LICENSE'
        IconUri      = 'https://raw.githubusercontent.com/erikgraa/PowerBGP/main/icon.png'
        ReleaseNotes = '0.8.0: BFD authentication (Simple Password, Keyed SHA1), Gallery publish workflow. 0.7.1: iBGP (no AS prepend, default LOCAL_PREF 100). 0.7.0: Graceful Restart (RFC 4724) with End-of-RIB and stale routes. 0.6.0: Sessions reconnect by default (-AutoReconnect:$false to disable). 0.5.2: BFD -MultiHop and -LocalAddress, Final reply to Poll. 0.5.1: Fixes the Gallery package layout (Public and Private folders were flattened in 0.5.0, so no commands were exported). 0.5.0: BGP and BFD peers, route advertisement, bulk prefixes, peer and BFD editing, inbound route filters, IPv6 (MP-BGP) unicast, -LocalAddress, TCP-MD5 (Linux), config export/import, fault injection.'
    } }
}
