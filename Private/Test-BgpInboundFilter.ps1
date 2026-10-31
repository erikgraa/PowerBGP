function ConvertTo-BgpFilterRule {
    # Accepts rule objects as-is and turns hashtables / JSON objects into rules.
    param($InputObject)
    foreach ($r in @($InputObject)) {
        if ($null -eq $r) { continue }
        if ($r.PSObject.TypeNames -contains 'PowerBGP.FilterRule') { $r; continue }
        $p = @{ Action = $r.Action }
        if ($r.Prefix) { $p.Prefix = $r.Prefix }
        if ($null -ne $r.Ge) { $p.Ge = [int]$r.Ge }
        if ($null -ne $r.Le) { $p.Le = [int]$r.Le }
        if ($null -ne $r.AsPathContains) { $p.AsPathContains = [uint32]$r.AsPathContains }
        if ($r.Community) { $p.Community = $r.Community }
        New-BgpFilterRule @p
    }
}

function ConvertTo-BgpAddressInt {
    param([string]$Address)
    $b = ([ipaddress]$Address).GetAddressBytes()
    ([uint64]$b[0] -shl 24) + ([uint64]$b[1] -shl 16) + ([uint64]$b[2] -shl 8) + [uint64]$b[3]
}

function Test-BgpInboundFilter {
    # True when the route is accepted. First matching rule wins; otherwise $Default.
    param($Rules, [string]$Default, [string]$Prefix, $Update)
    $ipText, $lenText = $Prefix -split '/'
    $plen = [int]$lenText
    $pbytes = ([ipaddress]$ipText).GetAddressBytes()
    $maxLen = $pbytes.Length * 8
    foreach ($r in @($Rules)) {
        if ($r.Prefix) {
            $rIp, $rLenText = $r.Prefix -split '/'
            $rbytes = ([ipaddress]$rIp).GetAddressBytes()
            if ($rbytes.Length -ne $pbytes.Length) { continue }
            $rLen = [int]$rLenText
            if ($null -eq $r.Ge -and $null -eq $r.Le) {
                if ($plen -ne $rLen) { continue }
            }
            else {
                $lo = if ($null -ne $r.Ge) { $r.Ge } else { $rLen }
                $hi = if ($null -ne $r.Le) { $r.Le } else { $maxLen }
                if ($plen -lt $lo -or $plen -gt $hi) { continue }
            }
            $inside = $true
            for ($b = 0; $b -lt $rLen -and $inside; $b++) {
                $bit = 0x80 -shr ($b % 8)
                if (($pbytes[[int][Math]::Floor($b / 8)] -band $bit) -ne ($rbytes[[int][Math]::Floor($b / 8)] -band $bit)) { $inside = $false }
            }
            if (-not $inside) { continue }
        }
        if ($null -ne $r.AsPathContains -and @($Update.AsPath) -notcontains [uint32]$r.AsPathContains) { continue }
        if ($r.Community -and @($Update.Community) -notcontains $r.Community) { continue }
        return ($r.Action -eq 'Permit')
    }
    $Default -ne 'Deny'
}
