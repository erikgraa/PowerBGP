function Stop-BgpPeer {
    <#
    .SYNOPSIS
        Sends a Cease NOTIFICATION and closes the session. The peer stays configured (State 'Stopped')
        so Resume-BgpPeer can bring it back; use Remove-BgpPeer to delete it.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$Name)
    process {
        $S = (Get-PowerBgpRegistry).Bgp[$Name]
        if (-not $S) { Write-Error "No such peer '$Name'."; return }
        Stop-PowerBgpRunspace $S
        $S.State = 'Stopped'
    }
}
