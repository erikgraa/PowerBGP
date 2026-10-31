$script:BfdStates = @{ 0 = 'AdminDown'; 1 = 'Down'; 2 = 'Init'; 3 = 'Up' }
$script:BfdDiags = @{
    0 = 'No Diagnostic'; 1 = 'Control Detection Time Expired'; 2 = 'Echo Function Failed'
    3 = 'Neighbor Signaled Session Down'; 4 = 'Forwarding Plane Reset'; 5 = 'Path Down'
    6 = 'Concatenated Path Down'; 7 = 'Administratively Down'; 8 = 'Reverse Concatenated Path Down'
}

function New-BfdControl {
    <#
    .SYNOPSIS
        Builds a 24-byte BFD control packet (RFC 5880). Intervals are in microseconds.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('AdminDown', 'Down', 'Init', 'Up')][string]$State = 'Down',
        [ValidateRange(0, 31)][int]$Diagnostic = 0,
        [ValidateRange(0, 255)][int]$DetectMult = 3,
        [uint32]$MyDiscriminator = 1,
        [uint32]$YourDiscriminator = 0,
        [uint32]$DesiredMinTx = 1000000,
        [uint32]$RequiredMinRx = 1000000,
        [uint32]$RequiredMinEchoRx = 0,
        [switch]$Poll,
        [switch]$Final,
        [switch]$Demand,
        [int]$Version = 1
    )
    $stateCode = @{ AdminDown = 0; Down = 1; Init = 2; Up = 3 }[$State]
    $flags = 0
    if ($Poll)   { $flags = $flags -bor 0x20 }
    if ($Final)  { $flags = $flags -bor 0x10 }
    if ($Demand) { $flags = $flags -bor 0x02 }

    New-Packet -Field @(
        New-PacketField VerDiag    (($Version * 32) + $Diagnostic) -Bytes 1
        New-PacketField StateFlags (($stateCode * 64) + $flags) -Bytes 1
        New-PacketField DetectMult $DetectMult -Bytes 1
        New-PacketField Length     24 -Bytes 1
        New-PacketField MyDisc     $MyDiscriminator -Bytes 4
        New-PacketField YourDisc   $YourDiscriminator -Bytes 4
        New-PacketField DesiredTx  $DesiredMinTx -Bytes 4
        New-PacketField RequiredRx $RequiredMinRx -Bytes 4
        New-PacketField EchoRx     $RequiredMinEchoRx -Bytes 4
    )
}

function ConvertFrom-BfdControl {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)][byte[]]$Packet)
    process {
        if ($Packet.Length -lt 24) { throw 'BFD control packet must be at least 24 bytes.' }
        $stateCode = [int][Math]::Floor($Packet[1] / 64)
        $diag = [int]($Packet[0] % 32)
        [pscustomobject]@{
            PSTypeName        = 'PowerBGP.BfdControl'
            Version           = [int][Math]::Floor($Packet[0] / 32)
            Diagnostic        = $diag
            DiagnosticName    = $script:BfdDiags[$diag]
            State             = $script:BfdStates[$stateCode]
            Poll              = [bool]($Packet[1] -band 0x20)
            Final             = [bool]($Packet[1] -band 0x10)
            Demand            = [bool]($Packet[1] -band 0x02)
            DetectMult        = [int]$Packet[2]
            Length            = [int]$Packet[3]
            MyDiscriminator   = [uint32](Get-NetUInt $Packet 4 4)
            YourDiscriminator = [uint32](Get-NetUInt $Packet 8 4)
            DesiredMinTx      = [uint32](Get-NetUInt $Packet 12 4)
            RequiredMinRx     = [uint32](Get-NetUInt $Packet 16 4)
            RequiredMinEchoRx = [uint32](Get-NetUInt $Packet 20 4)
        }
    }
}
