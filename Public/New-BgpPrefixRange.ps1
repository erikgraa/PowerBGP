function New-BgpPrefixRange {
    <#
    .SYNOPSIS
        Generates consecutive IPv4 prefixes, e.g. for bulk advertisement.
    .EXAMPLE
        Send-BgpUpdate -Name r1 -Nlri (New-BgpPrefixRange -Base 10.1.0.0 -Count 1000 -Length 24)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ipaddress]$Base,
        [Parameter(Mandatory)][ValidateRange(1, 1000000)][int]$Count,
        [ValidateRange(1, 32)][int]$Length = 24
    )
    $b = $Base.GetAddressBytes(); [Array]::Reverse($b)
    $n = [uint64][BitConverter]::ToUInt32($b, 0)
    $step = [uint64][Math]::Pow(2, 32 - $Length)
    $n = $n - ($n % $step)
    for ($i = 0; $i -lt $Count; $i++) {
        $v = $n + $i * $step
        if ($v -gt [uint32]::MaxValue) { throw 'Range runs past 255.255.255.255.' }
        $o = [BitConverter]::GetBytes([uint32]$v); [Array]::Reverse($o)
        '{0}/{1}' -f ([ipaddress]::new($o)), $Length
    }
}
