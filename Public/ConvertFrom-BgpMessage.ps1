function ConvertFrom-BgpMessage {
    <#
    .SYNOPSIS
        Parses a BGP message byte[] (OPEN with capabilities, UPDATE, NOTIFICATION, KEEPALIVE).
    .PARAMETER TwoOctetAs
        Parse AS_PATH with 2-byte ASNs (peer did not negotiate the 4-octet AS capability).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][byte[]]$Message,
        [switch]$TwoOctetAs
    )
    process {
        if ($Message.Length -lt 19) { throw 'Message shorter than the 19-byte BGP header.' }
        $typeName = switch ([int]$Message[18]) { 1 { 'OPEN' } 2 { 'UPDATE' } 3 { 'NOTIFICATION' } 4 { 'KEEPALIVE' } 5 { 'ROUTE-REFRESH' } default { 'UNKNOWN' } }

        $r = [ordered]@{
            PSTypeName  = 'PowerBGP.Message'
            Type        = $typeName
            Length      = [int](Get-NetUInt $Message 16 2)
            MarkerValid = (@($Message[0..15] | Where-Object { $_ -ne 0xFF }).Count -eq 0)
            Summary     = ''
        }

        if ($typeName -eq 'OPEN' -and $Message.Length -ge 29) {
            $caps = @()
            $o = 29
            $end = [Math]::Min(29 + $Message[28], $Message.Length)
            while ($o + 2 -le $end) {
                $ptype = $Message[$o]; $plen = $Message[$o + 1]
                if ($ptype -eq 2) {
                    $c = $o + 2; $cend = [Math]::Min($c + $plen, $Message.Length)
                    while ($c + 2 -le $cend) {
                        $code = [int]$Message[$c]; $cl = [int]$Message[$c + 1]
                        $val = if ($cl -and ($c + 1 + $cl) -lt $Message.Length) { $Message[($c + 2)..($c + 1 + $cl)] } else { @() }
                        $name = $script:BgpCapNames[$code]; if (-not $name) { $name = "Capability $code" }
                        $caps += [pscustomobject]@{ Code = $code; Name = $name; Value = (($val | ForEach-Object { '{0:X2}' -f $_ }) -join '') }
                        $c += 2 + $cl
                    }
                }
                $o += 2 + $plen
            }
            $r.Version      = [int]$Message[19]
            $r.MyAs         = [int](Get-NetUInt $Message 20 2)
            $r.HoldTime     = [int](Get-NetUInt $Message 22 2)
            $r.RouterId     = [ipaddress]::new([byte[]]$Message[24..27])
            $r.Capabilities = $caps
            $as4 = $caps | Where-Object Code -EQ 65 | Select-Object -First 1
            $r.Asn          = if ($as4 -and $as4.Value.Length -eq 8) { [uint32][Convert]::ToUInt32($as4.Value, 16) } else { [uint32]$r.MyAs }
            $r.Summary      = 'AS {0} hold {1} id {2} caps [{3}]' -f $r.Asn, $r.HoldTime, $r.RouterId, (($caps | ForEach-Object Name) -join ', ')
        }
        elseif ($typeName -eq 'NOTIFICATION' -and $Message.Length -ge 21) {
            $r.ErrorCode    = [int]$Message[19]
            $r.ErrorSubcode = [int]$Message[20]
            $r.ErrorName    = $script:BgpNotifyErrors[[int]$Message[19]]
            $r.Data         = if ($Message.Length -gt 21) { [byte[]]$Message[21..($Message.Length - 1)] } else { [byte[]]@() }
            $r.Summary      = '{0} ({1}/{2})' -f $r.ErrorName, $r.ErrorCode, $r.ErrorSubcode
        }
        elseif ($typeName -eq 'UPDATE' -and $Message.Length -ge 23) {
            $wlen = [int](Get-NetUInt $Message 19 2)
            $wEnd = 21 + $wlen
            $withdrawn = @(Read-BgpPrefix $Message 21 $wEnd)
            $alen = [int](Get-NetUInt $Message $wEnd 2)
            $aStart = $wEnd + 2; $aEnd = $aStart + $alen
            if ($aEnd -gt $Message.Length) { throw 'UPDATE attribute length exceeds message.' }

            $attrs = @()
            $o = $aStart
            while ($o + 3 -le $aEnd) {
                $flags = [int]$Message[$o]; $code = [int]$Message[$o + 1]
                if ($flags -band 0x10) { $vl = [int](Get-NetUInt $Message ($o + 2) 2); $vs = $o + 4 } else { $vl = [int]$Message[$o + 2]; $vs = $o + 3 }
                $val = if ($vl) { [byte[]]$Message[$vs..($vs + $vl - 1)] } else { [byte[]]@() }
                $attrs += [pscustomobject]@{ Flags = $flags; Code = $code; Value = $val }
                $o = $vs + $vl
            }

            $r.Withdrawn  = $withdrawn
            $r.Nlri       = @(Read-BgpPrefix $Message $aEnd $Message.Length)
            $r.Attributes = $attrs
            $r.Origin = $null; $r.AsPath = @(); $r.NextHop = $null; $r.Med = $null; $r.LocalPref = $null; $r.Community = @()
            foreach ($a in $attrs) {
                switch ($a.Code) {
                    1 { if ($a.Value.Length) { $r.Origin = $script:BgpOrigins[[int]$a.Value[0]] } }
                    2 {
                        $w = if ($TwoOctetAs) { 2 } else { 4 }
                        $p = 0; $path = @()
                        while ($p + 2 -le $a.Value.Length) {
                            $cnt = [int]$a.Value[$p + 1]; $p += 2
                            for ($k = 0; $k -lt $cnt; $k++) { $path += [uint32](Get-NetUInt $a.Value $p $w); $p += $w }
                        }
                        $r.AsPath = $path
                    }
                    3 { if ($a.Value.Length -eq 4) { $r.NextHop = [ipaddress]::new($a.Value) } }
                    4 { $r.Med = [uint32](Get-NetUInt $a.Value 0 4) }
                    5 { $r.LocalPref = [uint32](Get-NetUInt $a.Value 0 4) }
                    8 {
                        for ($k = 0; $k + 4 -le $a.Value.Length; $k += 4) {
                            $r.Community += '{0}:{1}' -f (Get-NetUInt $a.Value $k 2), (Get-NetUInt $a.Value ($k + 2) 2)
                        }
                    }
                }
            }
            $parts = @()
            if ($r.Nlri.Count) { $parts += "NLRI $($r.Nlri -join ',')"; $parts += "NH $($r.NextHop)"; $parts += "AS_PATH $($r.AsPath -join ' ')" }
            if ($withdrawn.Count) { $parts += "WD $($withdrawn -join ',')" }
            if (-not $parts) { $parts = 'End-of-RIB / empty' }
            $r.Summary = $parts -join '; '
        }
        [pscustomobject]$r
    }
}
