@{
    RootModule        = 'PowerBGP.psm1'
    ModuleVersion     = '0.5.0'
    GUID              = '6f0d6d0e-6a53-4c1e-9f6e-3b1c5a7d2e41'
    Author            = 'erikgraa'
    Description       = 'Stand up BGP and BFD test peers from PowerShell to test routers, NSX Tier-0 gateways and Windows Server BGP. Advertise and withdraw routes, inject faults, and build or parse BGP and BFD packets with a generic packet builder.'
    CompanyName       = 'erikgraa'
    Copyright         = '(c) erikgraa. All rights reserved.'
    PowerShellVersion = '7.2'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @(
        'New-PacketField', 'New-Packet', 'Format-Packet',
        'New-BgpOpen', 'New-BgpKeepalive', 'New-BgpUpdate', 'New-BgpNotification',
        'ConvertFrom-BgpMessage',
        'Start-BgpPeer', 'Get-BgpPeer', 'Stop-BgpPeer', 'Resume-BgpPeer', 'Remove-BgpPeer', 'Set-BgpPeer', 'Update-BgpPeer',
        'New-BgpPrefixRange', 'Export-BgpConfig', 'Import-BgpConfig',
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
        IconUri      = ''
        ReleaseNotes = '0.5.0: BGP and BFD peers, route advertisement, bulk prefixes, peer and BFD editing, TCP-MD5 (Linux), config export/import, fault injection. Fixes: Format-Packet with pipeline input, ConvertFrom-BgpMessage MarkerValid.'
    } }
}
