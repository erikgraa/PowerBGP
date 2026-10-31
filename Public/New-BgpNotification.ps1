function New-BgpNotification {
    <#
    .SYNOPSIS
        Builds a BGP NOTIFICATION (e.g. 6/0 Cease, 4/0 Hold Timer Expired).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte]$Code,
        [byte]$Subcode = 0,
        [byte[]]$Data = [byte[]]::new(0)
    )
    $body = New-Packet -Field @(
        New-PacketField Code    $Code -Bytes 1
        New-PacketField Subcode $Subcode -Bytes 1
        New-PacketField Data    $Data
    )
    New-BgpMessage -Type 3 -Body $body
}
