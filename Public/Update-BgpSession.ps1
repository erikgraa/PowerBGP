function Update-BgpSession {
    <#
    .SYNOPSIS
        Changes the stored configuration of a peer. A running peer is restarted (session resets); advertised routes are kept and re-sent.
    .DESCRIPTION
        Name and RemoteAddress cannot be changed; remove and re-add the peer for that. Only the parameters you pass are changed.
        Pass -Password '' to clear the TCP-MD5 password.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [uint32]$RemoteAS,
        [uint32]$LocalAS,
        [ipaddress]$RouterId,
        [uint16]$HoldTime,
        [ValidateRange(1, 65535)][int]$Port,
        [ValidateRange(0, 255)][int]$Ttl,
        [bool]$AutoReconnect,
        [string]$Password,
        [ValidateRange(1, 3600)][int]$ReconnectDelay,
        [ValidateRange(1, 3600)][int]$ReconnectMaxDelay
    )
    $S = (Get-PowerBgpRegistry).Bgp[$Name]
    if (-not $S) { throw "No such peer '$Name'." }
    if ($PSBoundParameters.ContainsKey('Password') -and $Password -and -not $IsLinux) {
        throw '-Password (TCP-MD5) is only supported when PowerShell runs on Linux.'
    }
    $wasRunning = $S.State -ne 'Stopped' -and $S.State -ne 'Idle'
    if ($wasRunning) { Stop-BgpSession -Name $Name }

    foreach ($k in 'RemoteAS', 'LocalAS', 'RouterId', 'HoldTime', 'Port', 'Ttl', 'AutoReconnect', 'Password', 'ReconnectDelay', 'ReconnectMaxDelay') {
        if ($PSBoundParameters.ContainsKey($k)) { $S.Config.$k = $PSBoundParameters[$k] }
    }
    if ($wasRunning) { Resume-BgpSession -Name $Name } else { Get-BgpSession -Name $Name }
}
