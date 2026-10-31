$script:BgpNotifyErrors = @{
    1 = 'Message Header Error'; 2 = 'OPEN Message Error'; 3 = 'UPDATE Message Error'
    4 = 'Hold Timer Expired'; 5 = 'Finite State Machine Error'; 6 = 'Cease'
}

$script:BgpCapNames = @{
    1 = 'Multiprotocol Extensions'; 2 = 'Route Refresh'; 64 = 'Graceful Restart'
    65 = '4-octet AS'; 69 = 'ADD-PATH'; 70 = 'Enhanced Route Refresh'
}

$script:BgpOrigins = @{ 0 = 'IGP'; 1 = 'EGP'; 2 = 'Incomplete' }

function Get-NetUInt {
    param([byte[]]$Bytes, [int]$Offset, [int]$Count)
    $v = [long]0
    for ($i = 0; $i -lt $Count; $i++) { $v = $v * 256 + $Bytes[$Offset + $i] }
    $v
}

function Read-BgpPrefix {
    param([byte[]]$Bytes, [int]$Start, [int]$End)
    $i = $Start
    while ($i -lt $End) {
        $len = $Bytes[$i]
        $n = [int][Math]::Ceiling($len / 8)
        if ($len -gt 32 -or ($i + 1 + $n) -gt $End) { throw 'Malformed prefix in UPDATE.' }
        $a = [byte[]]::new(4)
        for ($k = 0; $k -lt $n; $k++) { $a[$k] = $Bytes[$i + 1 + $k] }
        '{0}/{1}' -f ([ipaddress]::new($a)), $len
        $i += 1 + $n
    }
}
