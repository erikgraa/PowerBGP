BeforeAll { Import-Module "$PSScriptRoot\..\PowerBGP.psd1" -Force }
AfterAll { Get-BgpSession | Remove-BgpSession -Confirm:$false; Get-BfdSession | Remove-BfdSession }

Describe 'Format-Packet' {
    It 'prints offset, hex and ASCII' {
        $out = [byte[]](0x41, 0x42, 0x00) | Format-Packet
        $out | Should -Be '0000  41 42 00                                         AB.'
    }
    It 'wraps at 16 bytes per row' {
        @([byte[]](1..40) | Format-Packet).Count | Should -Be 3
    }
}

Describe 'UPDATE prefix encoding' {
    It 'masks host bits' {
        (ConvertFrom-BgpMessage (New-BgpUpdate -Nlri 10.1.2.3/24 -NextHop 1.1.1.1 -AsPath 65001)).Nlri | Should -Be '10.1.2.0/24'
    }
    It 'handles /0 and /32' {
        $m = ConvertFrom-BgpMessage (New-BgpUpdate -Nlri 0.0.0.0/0, 192.0.2.1/32 -NextHop 1.1.1.1 -AsPath 65001)
        $m.Nlri -join ',' | Should -Be '0.0.0.0/0,192.0.2.1/32'
    }
    It 'builds a withdraw-only UPDATE without path attributes' {
        $m = ConvertFrom-BgpMessage (New-BgpUpdate -Withdrawn 10.9.0.0/16)
        $m.Withdrawn | Should -Be '10.9.0.0/16'
        @($m.Nlri).Count | Should -Be 0
    }
    It 'rejects an invalid prefix length' {
        { New-BgpUpdate -Nlri 10.0.0.0/33 -NextHop 1.1.1.1 } | Should -Throw
    }
    It 'encodes 4-octet AS numbers in the path' {
        (ConvertFrom-BgpMessage (New-BgpUpdate -Nlri 10.0.0.0/8 -NextHop 1.1.1.1 -AsPath 4200000001, 65001)).AsPath -join ',' | Should -Be '4200000001,65001'
    }
}

Describe 'NOTIFICATION and OPEN' {
    It 'carries code, subcode and data' {
        $m = ConvertFrom-BgpMessage (New-BgpNotification -Code 6 -Subcode 2 -Data ([byte[]](1, 2)))
        $m.Type | Should -Be 'NOTIFICATION'
        $m.ErrorCode | Should -Be 6
        $m.ErrorSubcode | Should -Be 2
    }
    It 'OPEN with a 2-octet AS keeps the AS in the header' {
        $m = ConvertFrom-BgpMessage (New-BgpOpen -AS 65001 -RouterId 10.0.0.1)
        $m.MyAs | Should -Be 65001
        $m.RouterId.ToString() | Should -Be '10.0.0.1'
    }
    It 'flags a message with a bad marker' {
        $k = New-BgpKeepalive
        $k[0] = 0
        (ConvertFrom-BgpMessage $k).MarkerValid | Should -BeFalse
    }
    It 'rejects a truncated message' {
        { ConvertFrom-BgpMessage ([byte[]](1..5)) } | Should -Throw
    }
}

Describe 'BFD control packets' {
    It 'round-trips every state' {
        foreach ($s in 'AdminDown', 'Down', 'Init', 'Up') {
            (ConvertFrom-BfdControl (New-BfdControl -State $s)).State | Should -Be $s
        }
    }
    It 'round-trips diagnostic codes' {
        (ConvertFrom-BfdControl (New-BfdControl -State Down -Diagnostic 1)).DiagnosticName | Should -Match 'Detection Time'
    }
    It 'rejects a detect multiplier above 255' {
        { New-BfdControl -DetectMult 300 } | Should -Throw
    }
}

Describe 'New-BgpPrefixRange' {
    It 'aligns the base to the prefix length' {
        (New-BgpPrefixRange -Base 10.1.2.77 -Count 2 -Length 24) -join ',' | Should -Be '10.1.2.0/24,10.1.3.0/24'
    }
    It 'steps correctly for shorter prefixes' {
        (New-BgpPrefixRange -Base 10.0.0.0 -Count 2 -Length 16) -join ',' | Should -Be '10.0.0.0/16,10.1.0.0/16'
    }
    It 'steps by one address for /32' {
        (New-BgpPrefixRange -Base 192.0.2.254 -Count 3 -Length 32) -join ',' | Should -Be '192.0.2.254/32,192.0.2.255/32,192.0.3.0/32'
    }
    It 'refuses to run past the end of the address space' {
        { New-BgpPrefixRange -Base 255.255.255.0 -Count 2 -Length 24 } | Should -Throw
    }
}

Describe 'Update-BfdSession' {
    It 'edits a stopped session, converting ms to the stored units' {
        $null = Start-BfdSession -Name ub -RemoteAddress 127.0.0.9 -ListenPort 15784 -Port 15785
        Stop-BfdSession ub
        $s = Update-BfdSession -Name ub -DesiredMinTxMs 250 -RequiredMinRxMs 400 -DetectMult 7
        $s.TxMs | Should -Be 250
        $s.RxMs | Should -Be 400
        $s.DetectMult | Should -Be 7
        $s.State | Should -Be 'Stopped'
        Remove-BfdSession ub
    }
    It 'keeps unspecified fields' {
        $null = Start-BfdSession -Name ub2 -RemoteAddress 127.0.0.9 -ListenPort 15786 -Port 15787 -DetectMult 4
        Stop-BfdSession ub2
        (Update-BfdSession -Name ub2 -DesiredMinTxMs 120).DetectMult | Should -Be 4
        Remove-BfdSession ub2
    }
    It 'throws for an unknown session' {
        { Update-BfdSession -Name nope -DetectMult 3 } | Should -Throw '*No such*'
    }
}

Describe 'Peer lifecycle guards' {
    It 'refuses to advertise on a peer that is not Established' {
        $null = Start-BgpSession -Name g1 -RemoteAddress 127.0.0.8 -Port 12610 -LocalAS 65001 -RouterId 1.1.1.1
        { Send-BgpUpdate -Name g1 -Nlri 10.0.0.0/24 } | Should -Throw '*not Established*'
        Remove-BgpSession g1 -Confirm:$false
    }
    It 'throws for an unknown peer' {
        { Send-BgpUpdate -Name nope -Nlri 10.0.0.0/24 } | Should -Throw '*No such peer*'
    }
    It 'removes a peer from the registry' {
        $null = Start-BgpSession -Name g2 -RemoteAddress 127.0.0.7 -Port 12611 -LocalAS 65001 -RouterId 1.1.1.1
        Remove-BgpSession g2 -Confirm:$false
        Get-BgpSession g2 -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}

Describe 'Config export and import' {
    It 'round-trips peer settings' {
        Get-BgpSession | Remove-BgpSession -Confirm:$false
        $null = Start-BgpSession -Name cfg1 -Passive -RemoteAddress 127.0.0.6 -Port 12620 -LocalAS 65001 -RemoteAS 65002 -RouterId 1.1.1.1 -HoldTime 45
        $f = Join-Path ([IO.Path]::GetTempPath()) "powerbgp-$([guid]::NewGuid()).json"
        try {
            Export-BgpConfig -Path $f
            Get-BgpSession | Remove-BgpSession -Confirm:$false
            Get-BgpSession | Should -BeNullOrEmpty
            Import-BgpConfig -Path $f
            $p = Get-BgpSession cfg1
            $p | Should -Not -BeNullOrEmpty
            $p.PeerAS | Should -Be 65002
            (InModuleScope PowerBGP { (Get-PowerBgpRegistry).Bgp['cfg1'].Config.HoldTime }) | Should -Be 45
        }
        finally { Remove-Item $f -ErrorAction SilentlyContinue; Get-BgpSession | Remove-BgpSession -Confirm:$false }
    }
}

Describe 'Get-BgpRoute directions (loopback)' {
    It 'shows what we advertise and what the neighbour learned' {
        Get-BgpSession | Remove-BgpSession -Confirm:$false
        $null = Start-BgpSession -Name rl -Passive -Port 12630 -LocalAS 65001 -RemoteAS 65002 -RouterId 1.1.1.1
        Start-Sleep 1
        $null = Start-BgpSession -Name rd -RemoteAddress 127.0.0.1 -Port 12630 -LocalAS 65002 -RemoteAS 65001 -RouterId 2.2.2.2
        $d = (Get-Date).AddSeconds(12); while ((Get-Date) -lt $d -and (Get-BgpSession rd).State -ne 'Established') { Start-Sleep -Milliseconds 300 }
        Send-BgpUpdate -Name rd -Nlri 10.77.0.0/24 -AsPath 65002, 65100
        $d = (Get-Date).AddSeconds(8); while ((Get-Date) -lt $d -and -not (Get-BgpRoute -Name rl)) { Start-Sleep -Milliseconds 200 }

        (Get-BgpRoute -Name rd -Direction Advertised).Prefix | Should -Be '10.77.0.0/24'
        $l = Get-BgpRoute -Name rl -Direction Learned
        $l.Prefix | Should -Be '10.77.0.0/24'
        $l.AsPath | Should -Be '65002 65100'
        @(Get-BgpRoute -Name rd -Direction Learned).Count | Should -Be 0

        Send-BgpUpdate -Name rd -Withdrawn 10.77.0.0/24
        $d = (Get-Date).AddSeconds(8); while ((Get-Date) -lt $d -and (Get-BgpRoute -Name rl)) { Start-Sleep -Milliseconds 200 }
        @(Get-BgpRoute -Name rl).Count | Should -Be 0
        @(Get-BgpRoute -Name rd -Direction Advertised).Count | Should -Be 0
        Get-BgpSession | Remove-BgpSession -Confirm:$false
    }
}
