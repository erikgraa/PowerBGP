function Send-BgpUpdate {
    <#
    .SYNOPSIS
        Advertises and/or withdraws IPv4 or IPv6 prefixes on an Established peer.
    .DESCRIPTION
        Without -AsPath the local AS is used. Without -NextHop the local socket address is used.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$Nlri = @(),
        [string[]]$Withdrawn = @(),
        [ipaddress]$NextHop,
        [uint32[]]$AsPath,
        [ValidateSet('IGP', 'EGP', 'Incomplete')][string]$Origin = 'IGP',
        [uint32]$LocalPref,
        [uint32]$Med,
        [string[]]$Community = @()
    )
    $S = (Get-PowerBgpRegistry).Bgp[$Name]
    if (-not $S) { throw "No such peer '$Name'." }
    if ($S.State -ne 'Established') { throw "Peer '$Name' is $($S.State), not Established." }

    $p = @{} + $PSBoundParameters
    $p.Remove('Name')
    $dummy = $null
    $chunk = 400
    $isV6 = { param($x) "$x" -match ':' }
    $local = [ipaddress]$S.LocalAddress
    $families = @(
        @{ Nlri = @($Nlri | Where-Object { -not (& $isV6 $_) }); Withdrawn = @($Withdrawn | Where-Object { -not (& $isV6 $_) }); V6 = $false; Chunk = 400 }
        @{ Nlri = @($Nlri | Where-Object { & $isV6 $_ }); Withdrawn = @($Withdrawn | Where-Object { & $isV6 $_ }); V6 = $true; Chunk = 150 }
    )
    foreach ($f in $families) {
        $nl = $f.Nlri; $wd = $f.Withdrawn
        if (-not ($nl.Count -or $wd.Count)) { continue }
        $fp = $p.Clone()
        if ($nl.Count) {
            if (-not $fp.ContainsKey('AsPath')) { $fp.AsPath = [uint32[]]@($S.Config.LocalAS) }
            if ($fp.ContainsKey('NextHop')) {
                $isV6Hop = $fp.NextHop.AddressFamily -eq 'InterNetworkV6'
                if ($isV6Hop -ne $f.V6) { throw "-NextHop must be an $(if ($f.V6) { 'IPv6' } else { 'IPv4' }) address to advertise $(if ($f.V6) { 'IPv6' } else { 'IPv4' }) prefixes." }
            }
            elseif ($f.V6) {
                if ($local.AddressFamily -ne 'InterNetworkV6' -or $local.IsIPv4MappedToIPv6) { throw 'The session runs over IPv4, so -NextHop (an IPv6 address) is required to advertise IPv6 prefixes.' }
                $fp.NextHop = $local
            }
            else { $fp.NextHop = $local.MapToIPv4() }
        }
        $batches = [Math]::Max(1, [Math]::Max([Math]::Ceiling($nl.Count / $f.Chunk), [Math]::Ceiling($wd.Count / $f.Chunk)))
        for ($i = 0; $i -lt $batches; $i++) {
            $q = $fp.Clone()
            $q.Nlri = @($nl | Select-Object -Skip ($i * $f.Chunk) -First $f.Chunk)
            $q.Withdrawn = @($wd | Select-Object -Skip ($i * $f.Chunk) -First $f.Chunk)
            $S.Outbound.Enqueue([byte[]](New-BgpUpdate @q))
        }
        foreach ($w in $wd) { $null = $S.Advertised.TryRemove($w, [ref]$dummy) }
        foreach ($n in $nl) { $S.Advertised[$n] = [pscustomobject]@{ Peer = $Name; Prefix = $n; NextHop = "$($fp.NextHop)"; AsPath = ($fp.AsPath -join ' '); Params = $fp } }
    }
}
