function Get-BgpRoute {
    [CmdletBinding()]
    param(
        [string]$Name = '*',
        [ValidateSet('Learned', 'Advertised')][string]$Direction = 'Learned'
    )
    foreach ($S in @((Get-PowerBgpRegistry).Bgp.Values)) {
        if ($S.Name -notlike $Name) { continue }
        Remove-BgpStaleRoute $S
        $table = if ($Direction -eq 'Learned') { $S.Learned } else { $S.Advertised }
        $table.Values | Select-Object -ExcludeProperty Params *
    }
}
