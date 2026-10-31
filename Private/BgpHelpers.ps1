$script:BgpNotifyErrors = @{
    1 = 'Message Header Error'; 2 = 'OPEN Message Error'; 3 = 'UPDATE Message Error'
    4 = 'Hold Timer Expired'; 5 = 'Finite State Machine Error'; 6 = 'Cease'
}

$script:BgpCapNames = @{
    1 = 'Multiprotocol Extensions'; 2 = 'Route Refresh'; 64 = 'Graceful Restart'
    65 = '4-octet AS'; 69 = 'ADD-PATH'; 70 = 'Enhanced Route Refresh'
}

$script:BgpOrigins = @{ 0 = 'IGP'; 1 = 'EGP'; 2 = 'Incomplete' }

function Get-BgpPeerGracefulRestart {
    param($PeerOpen)
    $cap = @($PeerOpen.Capabilities) | Where-Object Code -EQ 64 | Select-Object -First 1
    if (-not $cap -or $cap.Value.Length -lt 4) { return $null }
    $flags = [Convert]::ToInt32($cap.Value.Substring(0, 4), 16)
    [pscustomobject]@{ RestartTime = $flags -band 0x0FFF; RestartFlag = [bool]($flags -band 0x8000) }
}

# Drops stale routes: all of a family after its End-of-RIB, everything once Restart Time has passed
function Remove-BgpStaleRoute {
    param($State, [ValidateSet('IPv4', 'IPv6')][string]$Family)
    $dummy = $null
    $expired = $State.StaleExpires -and (Get-Date) -ge $State.StaleExpires
    foreach ($kv in @($State.Learned.GetEnumerator())) {
        if (-not $kv.Value.Stale) { continue }
        if ($expired -or ($Family -and (($kv.Key -match ':') -eq ($Family -eq 'IPv6')))) { $null = $State.Learned.TryRemove($kv.Key, [ref]$dummy) }
    }
    if (-not @($State.Learned.Values | Where-Object Stale)) { $State.StaleExpires = $null }
}

function Get-NetUInt {
    param([byte[]]$Bytes, [int]$Offset, [int]$Count)
    $v = [long]0
    for ($i = 0; $i -lt $Count; $i++) { $v = $v * 256 + $Bytes[$Offset + $i] }
    $v
}

function Read-BgpPrefix {
    param([byte[]]$Bytes, [int]$Start, [int]$End, [int]$Afi = 1)
    $size = if ($Afi -eq 2) { 16 } else { 4 }
    $i = $Start
    while ($i -lt $End) {
        $len = $Bytes[$i]
        $n = [int][Math]::Ceiling($len / 8)
        if ($len -gt ($size * 8) -or ($i + 1 + $n) -gt $End) { throw 'Malformed prefix in UPDATE.' }
        $a = [byte[]]::new($size)
        for ($k = 0; $k -lt $n; $k++) { $a[$k] = $Bytes[$i + 1 + $k] }
        '{0}/{1}' -f ([ipaddress]::new($a)), $len
        $i += 1 + $n
    }
}
