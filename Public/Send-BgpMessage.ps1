function Send-BgpMessage {
    <#
    .SYNOPSIS
        Queues raw bytes on a peer's session. Use for crafted or deliberately malformed messages.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][byte[]]$Bytes
    )
    $S = (Get-PowerBgpRegistry).Bgp[$Name]
    if (-not $S) { throw "No such peer '$Name'." }
    if ($S.State -in 'Idle', 'Connect', 'Active') { throw "Peer '$Name' has no open TCP session (state $($S.State))." }
    $S.Outbound.Enqueue($Bytes)
}
