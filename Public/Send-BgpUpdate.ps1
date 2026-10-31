function Send-BgpUpdate {
    <#
    .SYNOPSIS
        Advertises and/or withdraws IPv4 prefixes on an Established peer.
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
    if ($Nlri.Count) {
        if (-not $p.ContainsKey('AsPath')) { $p.AsPath = [uint32[]]@($S.Config.LocalAS) }
        if (-not $p.ContainsKey('NextHop')) { $p.NextHop = ([ipaddress]$S.LocalAddress).MapToIPv4() }
    }
    $chunk = 400
    $dummy = $null
    $nl = @($Nlri); $wd = @($Withdrawn)
    $batches = [Math]::Max(1, [Math]::Max([Math]::Ceiling($nl.Count / $chunk), [Math]::Ceiling($wd.Count / $chunk)))
    for ($i = 0; $i -lt $batches; $i++) {
        $q = $p.Clone()
        $q.Nlri = @($nl | Select-Object -Skip ($i * $chunk) -First $chunk)
        $q.Withdrawn = @($wd | Select-Object -Skip ($i * $chunk) -First $chunk)
        $S.Outbound.Enqueue([byte[]](New-BgpUpdate @q))
    }

    foreach ($w in $Withdrawn) { $null = $S.Advertised.TryRemove($w, [ref]$dummy) }
    foreach ($n in $Nlri) { $S.Advertised[$n] = [pscustomobject]@{ Peer = $Name; Prefix = $n; NextHop = "$($p.NextHop)"; AsPath = ($p.AsPath -join ' '); Params = $p } }
}
