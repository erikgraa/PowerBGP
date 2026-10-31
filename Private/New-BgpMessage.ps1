function New-BgpMessage {
    <#
    .SYNOPSIS
        Wraps a body in the 19-byte BGP header (marker, length, type).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateRange(1, 255)][byte]$Type,
        [byte[]]$Body = [byte[]]::new(0)
    )
    New-Packet -LengthField Length -Field @(
        New-PacketField Marker ([byte[]](, [byte]0xFF * 16))
        New-PacketField Length 0 -Bytes 2
        New-PacketField Type $Type -Bytes 1
        New-PacketField Body $Body
    )
}
