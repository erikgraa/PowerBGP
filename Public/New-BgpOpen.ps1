function New-BgpOpen {
    <#
    .SYNOPSIS
        Builds a BGP OPEN with MP-BGP (IPv4 unicast) and 4-octet AS capabilities.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][uint32]$AS,
        [Parameter(Mandatory)][ipaddress]$RouterId,
        [uint16]$HoldTime = 90
    )
    $myAs = if ($AS -gt 65535) { 23456 } else { $AS }   # AS_TRANS

    # Optional parameters: type 2 (capabilities), each wrapping one capability (code, len, value)
    $caps = New-Packet -Field @(
        New-PacketField ParamType1 2 -Bytes 1
        New-PacketField ParamLen1  6 -Bytes 1
        New-PacketField CapCode1   1 -Bytes 1   # Multiprotocol Extensions
        New-PacketField CapLen1    4 -Bytes 1
        New-PacketField Afi        1 -Bytes 2
        New-PacketField Reserved   0 -Bytes 1
        New-PacketField Safi       1 -Bytes 1
        New-PacketField ParamType2 2 -Bytes 1
        New-PacketField ParamLen2  6 -Bytes 1
        New-PacketField CapCode2   65 -Bytes 1  # 4-octet AS
        New-PacketField CapLen2    4 -Bytes 1
        New-PacketField Asn4       $AS -Bytes 4
    )

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
