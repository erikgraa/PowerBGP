function Remove-BgpSession {
    <#
    .SYNOPSIS
        Stops a peer (Cease NOTIFICATION) and deletes its configuration.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$Name)
    process {
        $reg = Get-PowerBgpRegistry
        $S = $reg.Bgp[$Name]
        if (-not $S) { Write-Error "No such peer '$Name'."; return }
        if ($PSCmdlet.ShouldProcess($Name, 'Remove BGP peer')) {
            Stop-PowerBgpRunspace $S
            $reg.Bgp.Remove($Name)
        }
    }
}
