@{
    RootModule        = 'PowerBGP.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = '6f0d6d0e-6a53-4c1e-9f6e-3b1c5a7d2e41'
    Author            = 'erikgraa'
    Description       = 'Generic packet crafting primitives and BGP message builders/parsers for testing BGP peers.'
    PowerShellVersion = '5.1'
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
    PrivateData       = @{ PSData = @{ Tags = @('BGP', 'BFD', 'Networking', 'Packet'); IconUri = '' } }
}
