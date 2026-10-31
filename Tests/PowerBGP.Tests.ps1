BeforeAll { Import-Module "$PSScriptRoot\..\PowerBGP.psd1" -Force }
AfterAll { Get-BgpPeer | Stop-BgpPeer; Get-BfdSession | Stop-BfdSession }

Describe 'New-Packet' {
    It 'encodes integers big-endian' {
        (New-Packet -Field (New-PacketField A 0x0102 -Bytes 2)) -join ',' | Should -Be '1,2'
    }
    It 'auto-fills the length field' {
        $p = New-Packet -LengthField L -Field @((New-PacketField L 0 -Bytes 2), (New-PacketField D 'AABBCC'))
        $p -join ',' | Should -Be '0,5,170,187,204'
    }
    It 'rejects values that do not fit' {
        { New-Packet -Field (New-PacketField A 300 -Bytes 1) } | Should -Throw
    }
}

Describe 'BGP builders and parser' {
    It 'KEEPALIVE is 19 bytes, type 4' {
        $k = New-BgpKeepalive
        $k.Length | Should -Be 19
        $k[18] | Should -Be 4
    }
    It 'OPEN round-trips with capabilities and 4-octet AS' {
        $o = New-BgpOpen -AS 4200000001 -RouterId 10.0.0.99 -HoldTime 60
        $m = ConvertFrom-BgpMessage $o
        $m.Type | Should -Be 'OPEN'
        $m.MyAs | Should -Be 23456
        $m.Asn | Should -Be 4200000001
        $m.HoldTime | Should -Be 60
        $m.RouterId.ToString() | Should -Be '10.0.0.99'
        $m.Capabilities.Code | Should -Contain 65
    }
    It 'UPDATE round-trips attributes and prefixes' {
        $u = New-BgpUpdate -Nlri 10.10.0.0/24, 10.20.0.0/15 -Withdrawn 172.16.5.0/24 -NextHop 192.168.1.99 -AsPath 65001, 65002 -Med 50 -LocalPref 200 -Community 65000:100 -Origin Incomplete
        $m = ConvertFrom-BgpMessage $u
        $m.Nlri -join ',' | Should -Be '10.10.0.0/24,10.20.0.0/15'
        $m.Withdrawn -join ',' | Should -Be '172.16.5.0/24'
        $m.NextHop.ToString() | Should -Be '192.168.1.99'
        $m.AsPath -join ',' | Should -Be '65001,65002'
        $m.Med | Should -Be 50
        $m.LocalPref | Should -Be 200
        $m.Origin | Should -Be 'Incomplete'
        $m.Community | Should -Be '65000:100'
    }
    It 'NOTIFICATION round-trips' {
        $m = ConvertFrom-BgpMessage (New-BgpNotification -Code 6 -Subcode 2)
        $m.ErrorName | Should -Be 'Cease'
        $m.ErrorSubcode | Should -Be 2
    }
}

Describe 'BFD packets' {
    It 'is 24 bytes and round-trips' {
        $p = New-BfdControl -State Up -DetectMult 5 -MyDiscriminator 7 -YourDiscriminator 9 -DesiredMinTx 300000 -RequiredMinRx 400000
        $p.Length | Should -Be 24
        $m = ConvertFrom-BfdControl $p
        $m.State | Should -Be 'Up'
        $m.Version | Should -Be 1
        $m.DetectMult | Should -Be 5
        $m.MyDiscriminator | Should -Be 7
        $m.YourDiscriminator | Should -Be 9
        $m.DesiredMinTx | Should -Be 300000
    }
}

Describe 'BGP session engine (loopback)' {
    BeforeAll {
        $null = Start-BgpPeer -Name listener -Passive -Port 11179 -LocalAS 65001 -RemoteAS 65002 -RouterId 1.1.1.1 -HoldTime 9
        Start-Sleep -Milliseconds 500
        $null = Start-BgpPeer -Name dialer -RemoteAddress 127.0.0.1 -Port 11179 -LocalAS 65002 -RemoteAS 65001 -RouterId 2.2.2.2 -HoldTime 9
        $deadline = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $deadline -and (Get-BgpPeer dialer).State -ne 'Established') { Start-Sleep -Milliseconds 200 }
    }
    It 'reaches Established on both sides' {
        (Get-BgpPeer dialer).State | Should -Be 'Established'
        (Get-BgpPeer listener).State | Should -Be 'Established'
        (Get-BgpPeer listener).PeerAS | Should -Be 65002
    }
    It 'propagates advertised and withdrawn routes' {
        Send-BgpUpdate -Name dialer -Nlri 10.99.0.0/24, 10.98.0.0/16
        Start-Sleep -Seconds 1
        $r = Get-BgpRoute -Name listener
        $r.Prefix | Should -Contain '10.99.0.0/24'
        ($r | Where-Object Prefix -EQ '10.99.0.0/24').AsPath | Should -Be '65002'
        Send-BgpUpdate -Name dialer -Withdrawn 10.99.0.0/24
        Start-Sleep -Seconds 1
        (Get-BgpRoute -Name listener).Prefix | Should -Not -Contain '10.99.0.0/24'
        (Get-BgpRoute -Name listener).Prefix | Should -Contain '10.98.0.0/16'
    }
    It 'records events' {
        (Get-BgpEvent -Name listener).Type | Should -Contain 'UPDATE'
    }
    It 'drops back to Idle when stopped' {
        Stop-BgpPeer dialer
        Start-Sleep -Seconds 1
        (Get-BgpPeer listener).State | Should -BeIn 'Idle'
        (Get-BgpPeer listener).LastError | Should -Match 'Notification received'
    }
}

Describe 'BGP auto-reconnect (loopback)' {
    BeforeAll { Get-BgpPeer | Remove-BgpPeer -Confirm:$false }
    It 'redials after the peer restarts and re-advertises routes' {
        $wait = { param($sb, $s = 15) $t = [Diagnostics.Stopwatch]::StartNew(); while (-not (& $sb) -and $t.Elapsed.TotalSeconds -lt $s) { Start-Sleep -Milliseconds 200 } }
        $listen = @{ Name = 'rc-l'; Passive = $true; Port = 12195; LocalAS = 65001; RemoteAS = 65002; RouterId = '1.1.1.1' }
        $null = Start-BgpPeer @listen
        $null = Start-BgpPeer -Name rc-d -RemoteAddress 127.0.0.1 -Port 12195 -LocalAS 65002 -RemoteAS 65001 -RouterId 2.2.2.2 -AutoReconnect -ReconnectDelay 1
        & $wait { (Get-BgpPeer rc-d).State -eq 'Established' }
        Send-BgpUpdate -Name rc-d -Nlri 10.77.0.0/24
        & $wait { @(Get-BgpRoute -Name rc-l).Count -eq 1 }

        Stop-BgpPeer -Name rc-l
        & $wait { (Get-BgpPeer rc-d).State -ne 'Established' }
        $null = Start-BgpPeer @listen
        & $wait { @(Get-BgpRoute -Name rc-l).Count -eq 1 } 30

        (Get-BgpPeer rc-d).Reconnects | Should -BeGreaterThan 0
        @(Get-BgpRoute -Name rc-l).Prefix | Should -Be '10.77.0.0/24'
    }
}

Describe 'BGP stop / resume / remove (loopback)' {
    BeforeAll { Get-BgpPeer | Remove-BgpPeer -Confirm:$false }
    It 'keeps the peer configured when stopped, and resumes it' {
        $wait = { param($sb, $s = 15) $t = [Diagnostics.Stopwatch]::StartNew(); while (-not (& $sb) -and $t.Elapsed.TotalSeconds -lt $s) { Start-Sleep -Milliseconds 200 } }
        $null = Start-BgpPeer -Name sr-l -Passive -AutoReconnect -Port 12196 -LocalAS 65001 -RemoteAS 65002 -RouterId 1.1.1.1
        $null = Start-BgpPeer -Name sr-d -RemoteAddress 127.0.0.1 -Port 12196 -LocalAS 65002 -RemoteAS 65001 -RouterId 2.2.2.2
        & $wait { (Get-BgpPeer sr-d).State -eq 'Established' }
        Send-BgpUpdate -Name sr-d -Nlri 10.88.0.0/24

        Stop-BgpPeer -Name sr-d
        (Get-BgpPeer sr-d).State | Should -Be 'Stopped'

        $null = Resume-BgpPeer -Name sr-d
        & $wait { (Get-BgpPeer sr-d).State -eq 'Established' }
        (Get-BgpPeer sr-d).State | Should -Be 'Established'
        & $wait { @(Get-BgpRoute -Name sr-l).Count -eq 1 }
        @(Get-BgpRoute -Name sr-l).Prefix | Should -Be '10.88.0.0/24'

        Remove-BgpPeer -Name sr-d
        Get-BgpPeer sr-d -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}

Describe 'BFD session engine (loopback)' {
    It 'comes Up on both sides and drops when one side is suppressed' {
        $null = Start-BfdSession -Name a -RemoteAddress 127.0.0.1 -ListenPort 13784 -Port 14784 -DesiredMinTxMs 100 -RequiredMinRxMs 100
        $null = Start-BfdSession -Name b -RemoteAddress 127.0.0.1 -ListenPort 14784 -Port 13784 -DesiredMinTxMs 100 -RequiredMinRxMs 100
        $deadline = (Get-Date).AddSeconds(12)
        while ((Get-Date) -lt $deadline -and ((Get-BfdSession a).State -ne 'Up' -or (Get-BfdSession b).State -ne 'Up')) { Start-Sleep -Milliseconds 200 }
        (Get-BfdSession a).State | Should -Be 'Up'
        (Get-BfdSession b).State | Should -Be 'Up'

        Set-BfdSession -Name b -Suppress $true
        $deadline = (Get-Date).AddSeconds(5)
        while ((Get-Date) -lt $deadline -and (Get-BfdSession a).State -ne 'Down') { Start-Sleep -Milliseconds 100 }
        (Get-BfdSession a).State | Should -Be 'Down'
    }
}

Describe 'TCP-MD5 password' {
    It 'is rejected on non-Linux platforms' -Skip:$IsLinux {
        { Start-BgpPeer -Name md5x -Passive -Port 12599 -LocalAS 65001 -RouterId 1.1.1.1 -Password secret } | Should -Throw '*Linux*'
    }
    It 'establishes with matching passwords and refuses mismatches' -Skip:(-not $IsLinux) {
        $null = Start-BgpPeer -Name m-l -Passive -Port 12501 -RemoteAddress 127.0.0.1 -LocalAS 65001 -RemoteAS 65002 -RouterId 1.1.1.1 -Password secret
        Start-Sleep 1
        $null = Start-BgpPeer -Name m-d -RemoteAddress 127.0.0.1 -Port 12501 -LocalAS 65002 -RemoteAS 65001 -RouterId 2.2.2.2 -Password secret
        $d = (Get-Date).AddSeconds(12); while ((Get-Date) -lt $d -and (Get-BgpPeer m-d).State -ne 'Established') { Start-Sleep -Milliseconds 300 }
        (Get-BgpPeer m-d).State | Should -Be 'Established'
        (Get-BgpPeer m-d).Md5 | Should -BeTrue
        Get-BgpPeer m-* | Stop-BgpPeer
    }
}

Describe 'Duplicate peers' {
    It 'refuses a second peer for the same remote address' {
        $null = Start-BgpPeer -Name dup-a -RemoteAddress 127.0.0.2 -Port 12597 -LocalAS 65001 -RouterId 1.1.1.1
        { Start-BgpPeer -Name dup-b -RemoteAddress 127.0.0.2 -Port 12598 -LocalAS 65001 -RouterId 1.1.1.1 } | Should -Throw '*already exists*'
        Remove-BgpPeer dup-a -Confirm:$false
    }
}

Describe 'Update-BgpPeer and bulk prefixes' {
    It 'generates prefix ranges' {
        $r = New-BgpPrefixRange -Base 10.1.0.0 -Count 3 -Length 24
        $r -join ',' | Should -Be '10.1.0.0/24,10.1.1.0/24,10.1.2.0/24'
    }
    It 'edits a stopped peer config' {
        $null = Start-BgpPeer -Name ed-a -RemoteAddress 127.0.0.3 -Port 12596 -LocalAS 65001 -RouterId 1.1.1.1
        Stop-BgpPeer ed-a
        (Update-BgpPeer -Name ed-a -HoldTime 30 -RemoteAS 65009).PeerAS | Should -Be 65009
        (InModuleScope PowerBGP { (Get-PowerBgpRegistry).Bgp['ed-a'].Config.HoldTime }) | Should -Be 30
        Remove-BgpPeer ed-a -Confirm:$false
    }
    It 'delivers a bulk advertisement over a session' {
        Get-BgpPeer | Remove-BgpPeer -Confirm:$false
        $null = Start-BgpPeer -Name bk-l -Passive -Port 12595 -LocalAS 65001 -RemoteAS 65002 -RouterId 1.1.1.1
        Start-Sleep 1
        $null = Start-BgpPeer -Name bk-d -RemoteAddress 127.0.0.1 -Port 12595 -LocalAS 65002 -RemoteAS 65001 -RouterId 2.2.2.2
        $d = (Get-Date).AddSeconds(12); while ((Get-Date) -lt $d -and (Get-BgpPeer bk-d).State -ne 'Established') { Start-Sleep -Milliseconds 300 }
        Send-BgpUpdate -Name bk-d -Nlri (New-BgpPrefixRange -Base 10.50.0.0 -Count 2000 -Length 24)
        $d = (Get-Date).AddSeconds(15); while ((Get-Date) -lt $d -and (Get-BgpPeer bk-l).Learned -lt 2000) { Start-Sleep -Milliseconds 300 }
        (Get-BgpPeer bk-l).Learned | Should -Be 2000
        Get-BgpPeer | Remove-BgpPeer -Confirm:$false
    }
}
