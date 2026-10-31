function New-BgpOpen {
    <#
    .SYNOPSIS
        Builds a BGP OPEN with Multiprotocol (MP-BGP) and 4-octet AS capabilities.
    .PARAMETER AddressFamily
        Address families to advertise as unicast capabilities. Default IPv4; add IPv6 for MP-BGP IPv6 unicast (RFC 4760).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][uint32]$AS,
        [Parameter(Mandatory)][ipaddress]$RouterId,
        [uint16]$HoldTime = 90,
        [ValidateSet('IPv4', 'IPv6')][string[]]$AddressFamily = 'IPv4'
    )
    $myAs = if ($AS -gt 65535) { 23456 } else { $AS }   # AS_TRANS

    # Optional parameters: type 2 (capabilities), each wrapping one capability (code, len, value)
    $fields = @()
    $i = 0
    foreach ($af in $AddressFamily | Select-Object -Unique) {
        $i++
        $fields += New-PacketField "ParamType$i" 2 -Bytes 1
        $fields += New-PacketField "ParamLen$i"  6 -Bytes 1
        $fields += New-PacketField "CapCode$i"   1 -Bytes 1   # Multiprotocol Extensions
        $fields += New-PacketField "CapLen$i"    4 -Bytes 1
        $fields += New-PacketField "Afi$i"       $(if ($af -eq 'IPv6') { 2 } else { 1 }) -Bytes 2
        $fields += New-PacketField "Reserved$i"  0 -Bytes 1
        $fields += New-PacketField "Safi$i"      1 -Bytes 1
    }
    $fields += New-PacketField ParamType2 2 -Bytes 1
    $fields += New-PacketField ParamLen2  6 -Bytes 1
    $fields += New-PacketField CapCode2   65 -Bytes 1  # 4-octet AS
    $fields += New-PacketField CapLen2    4 -Bytes 1
    $fields += New-PacketField Asn4       $AS -Bytes 4
    $caps = New-Packet -Field $fields

    $body = New-Packet -Field @(
        New-PacketField Version   4 -Bytes 1
        New-PacketField MyAs      $myAs -Bytes 2
        New-PacketField HoldTime  $HoldTime -Bytes 2
        New-PacketField BgpId     $RouterId
        New-PacketField OptLen    $caps.Length -Bytes 1
        New-PacketField OptParams $caps
    )
    New-BgpMessage -Type 1 -Body $body
}
