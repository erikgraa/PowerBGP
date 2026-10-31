function New-BgpUpdate {
    <#
    .SYNOPSIS
        Builds a BGP UPDATE (4-octet AS_PATH) advertising and/or withdrawing IPv4 prefixes.
    .EXAMPLE
        New-BgpUpdate -Nlri 10.10.0.0/24,10.10.1.0/24 -NextHop 192.168.1.99 -AsPath 65001
    #>
    [CmdletBinding()]
    param(
        [string[]]$Nlri = @(),
        [string[]]$Withdrawn = @(),
        [ipaddress]$NextHop,
        [uint32[]]$AsPath = @(),
        [ValidateSet('IGP', 'EGP', 'Incomplete')][string]$Origin = 'IGP',
        [uint32]$LocalPref,
        [uint32]$Med,
        [string[]]$Community = @()
    )

    function ConvertTo-PrefixBytes([string]$Cidr) {
        $ip, $len = $Cidr -split '/'
        $len = [int]$len
        if ($len -lt 0 -or $len -gt 32) { throw "Invalid prefix length in '$Cidr'." }
        $addr = ([ipaddress]$ip).GetAddressBytes()
        $n = [int][Math]::Ceiling($len / 8)
        $out = [byte[]]::new(1 + $n)
        $out[0] = [byte]$len
        for ($i = 0; $i -lt $n; $i++) { $out[1 + $i] = $addr[$i] }
        if ($n -gt 0 -and ($len % 8)) { $out[$n] = [byte]($out[$n] -band (0xFF -shl (8 - ($len % 8)))) }
        , $out
    }

    function New-PathAttribute([byte]$Flags, [byte]$Code, [byte[]]$Value) {
        New-Packet -Field @(
            New-PacketField Flags $Flags -Bytes 1
            New-PacketField Code  $Code -Bytes 1
            New-PacketField Len   $Value.Length -Bytes 1
            New-PacketField Value $Value
        )
    }

    $attrs = [System.Collections.Generic.List[byte]]::new()

    if ($Nlri.Count) {
        $originCode = @{ IGP = 0; EGP = 1; Incomplete = 2 }[$Origin]
        $attrs.AddRange([byte[]](New-PathAttribute 0x40 1 ([byte[]]@($originCode))))

        $segment = [byte[]]@()
        if ($AsPath.Count) {
            $fields = @(
                New-PacketField SegType 2 -Bytes 1   # AS_SEQUENCE
                New-PacketField SegLen  $AsPath.Count -Bytes 1
            )
            $fields += foreach ($a in $AsPath) { New-PacketField Asn $a -Bytes 4 }
            $segment = New-Packet -Field $fields
        }
        $attrs.AddRange([byte[]](New-PathAttribute 0x40 2 $segment))

        if (-not $NextHop) { throw '-NextHop is required when advertising -Nlri.' }
        $attrs.AddRange([byte[]](New-PathAttribute 0x40 3 $NextHop.GetAddressBytes()))

        if ($PSBoundParameters.ContainsKey('Med')) {
            $attrs.AddRange([byte[]](New-PathAttribute 0x80 4 (New-Packet -Field (New-PacketField V $Med -Bytes 4))))
        }
        if ($PSBoundParameters.ContainsKey('LocalPref')) {
            $attrs.AddRange([byte[]](New-PathAttribute 0x40 5 (New-Packet -Field (New-PacketField V $LocalPref -Bytes 4))))
        }
        if ($Community.Count) {
            $cf = foreach ($c in $Community) {
                $hi, $lo = $c -split ':'
                New-PacketField C ([uint32](([uint32]$hi -shl 16) -bor [uint32]$lo)) -Bytes 4
            }
            $attrs.AddRange([byte[]](New-PathAttribute 0xC0 8 (New-Packet -Field $cf)))
        }
    }

    $wd = [System.Collections.Generic.List[byte]]::new()
    foreach ($p in $Withdrawn) { $wd.AddRange([byte[]](ConvertTo-PrefixBytes $p)) }
    $nl = [System.Collections.Generic.List[byte]]::new()
    foreach ($p in $Nlri) { $nl.AddRange([byte[]](ConvertTo-PrefixBytes $p)) }

    $body = New-Packet -Field @(
        New-PacketField WithdrawnLen $wd.Count -Bytes 2
        New-PacketField Withdrawn    $wd.ToArray()
        New-PacketField AttrLen      $attrs.Count -Bytes 2
        New-PacketField Attributes   $attrs.ToArray()
        New-PacketField Nlri         $nl.ToArray()
    )
    New-BgpMessage -Type 2 -Body $body
}
