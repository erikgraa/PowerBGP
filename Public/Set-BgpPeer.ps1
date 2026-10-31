function Set-BgpPeer {
    <#
    .SYNOPSIS
        Fault injection toggles on a running peer.
    .PARAMETER SuppressKeepalives
        Stop sending KEEPALIVEs (the remote should expire its hold timer).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [bool]$SuppressKeepalives
    )
    $S = (Get-PowerBgpRegistry).Bgp[$Name]
    if (-not $S) { throw "No such peer '$Name'." }
    if ($PSBoundParameters.ContainsKey('SuppressKeepalives')) { $S.SuppressKeepalives = $SuppressKeepalives }
}
