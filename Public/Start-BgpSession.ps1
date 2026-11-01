function Start-BgpSession {
    <#
    .SYNOPSIS
        Starts a BGP peer in a background runspace (active: connects out; -Passive: listens).
        The session reconnects after a drop by default; use -AutoReconnect:$false to stay down.
        -LocalAddress binds the session to a specific source IP (useful for several sessions to one router, e.g. ECMP tests).
        -Password (TCP-MD5, Linux only) takes a SecureString or a plain string.
    .EXAMPLE
        Start-BgpSession -Name nsx-t0 -RemoteAddress 192.168.1.1 -RemoteAS 65000 -LocalAS 65001 -RouterId 10.0.0.99
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$RemoteAddress,
        [uint32]$RemoteAS,
        [ipaddress]$LocalAddress,
        [ValidateSet('IPv4', 'IPv6')][string[]]$AddressFamily = 'IPv4',
        [Parameter(Mandatory)][uint32]$LocalAS,
        [Parameter(Mandatory)][ipaddress]$RouterId,
        [uint16]$HoldTime = 90,
        [ValidateRange(1, 65535)][int]$Port = 179,
        [switch]$Passive,
        [ValidateRange(1, 255)][int]$Ttl,
        [switch]$AutoReconnect = $true,
        [switch]$GracefulRestart,
        [ValidateRange(0, 4095)][int]$RestartTime = 120,
        [ValidateScript({ $_ -is [string] -or $_ -is [securestring] })][object]$Password,
        [ValidateRange(1, 3600)][int]$ReconnectDelay = 5,
        [ValidateRange(1, 3600)][int]$ReconnectMaxDelay = 60,
        [object[]]$InboundFilter = @(),
        [ValidateSet('Permit', 'Deny')][string]$InboundDefault = 'Permit'
    )
    $Password = ConvertFrom-BgpPassword $Password
    $rules = @(ConvertTo-BgpFilterRule $InboundFilter)
    if (-not $Passive -and -not $RemoteAddress) { throw '-RemoteAddress is required unless -Passive.' }
    if ($Password -and -not $IsLinux) { throw '-Password (TCP-MD5) is only supported when PowerShell runs on Linux (the Windows TCP stack has no TCP_MD5SIG).' }
    if (-not $Name) { $Name = if ($RemoteAddress) { $RemoteAddress } else { "passive-$Port" } }

    $reg = Get-PowerBgpRegistry
    if ($RemoteAddress) {
        $dup = @($reg.Bgp.Values) | Where-Object { $_.Name -ne $Name -and $_.Config.RemoteAddress -eq $RemoteAddress } | Select-Object -First 1
        if ($dup) { throw "A peer for $RemoteAddress already exists ('$($dup.Name)'). Remove it first." }
    }
    $existing = $reg.Bgp[$Name]
    if ($existing) {
        if ($existing.State -notin 'Idle', 'Stopped') { throw "Peer '$Name' already exists and is $($existing.State)." }
        Stop-PowerBgpRunspace $existing 1
    }

    $S = [hashtable]::Synchronized(@{
            Name               = $Name
            Config             = [pscustomobject]@{
                RemoteAddress = $RemoteAddress; RemoteAS = $RemoteAS; LocalAddress = $(if ($LocalAddress) { "$LocalAddress" }); LocalAS = $LocalAS; RouterId = $RouterId
                HoldTime = $HoldTime; Port = $Port; Passive = [bool]$Passive; Ttl = $Ttl
                GracefulRestart = [bool]$GracefulRestart; RestartTime = $RestartTime
                AutoReconnect = [bool]$AutoReconnect; ReconnectDelay = $ReconnectDelay; ReconnectMaxDelay = $ReconnectMaxDelay
                Password = $Password; AddressFamily = @($AddressFamily | Select-Object -Unique); InboundFilter = $rules; InboundDefault = $InboundDefault
            }
            Filtered           = 0
            Reconnects         = 0
            NextRetry          = $null
            LastEstablished    = $false
            State              = 'Idle'
            Stop               = $false
            SuppressKeepalives = $false
            Outbound           = [System.Collections.Concurrent.ConcurrentQueue[byte[]]]::new()
            Events             = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
            Learned            = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
            Advertised         = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()
            Sent               = 0
            Received           = 0
            Established        = $null
            StaleExpires       = $null
            PeerOpen           = $null
            PeerFourOctet      = $true
            HoldTime           = 0
            LastError          = $null
            RemoteEndpoint     = $null
            LocalAddress       = $null
            PowerShell         = $null
            Handle             = $null
        })
    $reg.Bgp[$Name] = $S
    Start-PowerBgpRunspace -State $S -Entry 'Invoke-BgpPeerLoop'
    Get-BgpSession -Name $Name
}
