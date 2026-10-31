BeforeAll { Import-Module "$PSScriptRoot\..\PowerBGP.psd1" -Force }
AfterAll { Get-BgpSession | Remove-BgpSession -Confirm:$false }

Describe 'MP-BGP IPv6 packets' {
    It 'advertises IPv4 and IPv6 unicast capabilities in OPEN' {
        $o = ConvertFrom-BgpMessage (New-BgpOpen -AS 65001 -RouterId 1.1.1.1 -AddressFamily IPv4, IPv6)
        @($o.Capabilities | Where-Object Code -EQ 1).Value | Should -Be '00010001', '00020001'
    }
    It 'defaults to IPv4 only' {
        $o = ConvertFrom-BgpMessage (New-BgpOpen -AS 65001 -RouterId 1.1.1.1)
        @($o.Capabilities | Where-Object Code -EQ 1).Value | Should -Be '00010001'
    }
    It 'round-trips an IPv6 advertisement through MP_REACH_NLRI' {
        $u = ConvertFrom-BgpMessage (New-BgpUpdate -Nlri 2001:db8:10::/48, 2001:db8:20::/64 -NextHop 2001:db8:ffff::99 -AsPath 65001, 65002)
        $u.Nlri | Should -Be '2001:db8:10::/48', '2001:db8:20::/64'
        "$($u.NextHop)" | Should -Be '2001:db8:ffff::99'
        $u.AsPath | Should -Be 65001, 65002
    }
    It 'round-trips an IPv6 withdrawal through MP_UNREACH_NLRI' {
        $u = ConvertFrom-BgpMessage (New-BgpUpdate -Withdrawn 2001:db8:10::/48)
        $u.Withdrawn | Should -Be '2001:db8:10::/48'
        $u.Nlri.Count | Should -Be 0
    }
    It 'uses extended-length attributes for large IPv6 updates' {
        $nlri = 1..150 | ForEach-Object { '2001:db8:{0:x}::/48' -f $_ }
        $u = ConvertFrom-BgpMessage (New-BgpUpdate -Nlri $nlri -NextHop 2001:db8:ffff::99 -AsPath 65001)
        $u.Nlri.Count | Should -Be 150
    }
    It 'refuses mixed families and wrong next-hop family' {
        { New-BgpUpdate -Nlri 10.0.0.0/24, 2001:db8::/32 -NextHop 192.0.2.1 } | Should -Throw '*separate*'
        { New-BgpUpdate -Nlri 2001:db8::/32 -NextHop 192.0.2.1 } | Should -Throw '*IPv6*'
        { New-BgpUpdate -Nlri 10.0.0.0/24 -NextHop 2001:db8::1 } | Should -Throw '*IPv4*'
    }
    It 'keeps IPv4 UPDATEs unchanged' {
        $u = ConvertFrom-BgpMessage (New-BgpUpdate -Nlri 10.1.0.0/24 -NextHop 192.0.2.1 -AsPath 65001)
        $u.Nlri | Should -Be '10.1.0.0/24'
        "$($u.NextHop)" | Should -Be '192.0.2.1'
    }
}

Describe 'IPv6 inbound filters' {
    BeforeAll {
        $script:u = [pscustomobject]@{ AsPath = @(65002); Community = @() }
        function script:Test-F($rules, $default, $prefix) {
            InModuleScope PowerBGP -Parameters @{ R = $rules; D = $default; P = $prefix; U = $script:u } {
                Test-BgpInboundFilter -Rules $R -Default $D -Prefix $P -Update $U
            }
        }
    }
    It 'accepts IPv6 rules and rejects bad lengths' {
        (New-BgpFilterRule -Action Deny -Prefix 2001:db8::/32).Prefix | Should -Be '2001:db8::/32'
        { New-BgpFilterRule -Action Deny -Prefix 2001:db8::/129 } | Should -Throw '*Invalid*'
    }
    It 'matches IPv6 prefix windows and ignores other families' {
        $r = @(New-BgpFilterRule -Action Deny -Prefix 2001:db8::/32 -Le 64)
        Test-F $r Permit 2001:db8:1::/48 | Should -BeFalse
        Test-F $r Permit 2001:db8:1::/96 | Should -BeTrue
        Test-F $r Permit 2001:db9::/48 | Should -BeTrue
        Test-F $r Permit 10.0.0.0/24 | Should -BeTrue
    }
}

Describe 'IPv6 session over loopback and -LocalAddress' {
    It 'exchanges IPv6 routes over an IPv6 transport' {
        Get-BgpSession | Remove-BgpSession -Confirm:$false
        $null = Start-BgpSession -Name m6l -Passive -Port 12700 -LocalAddress ::1 -AddressFamily IPv6 -LocalAS 65001 -RemoteAS 65002 -RouterId 1.1.1.1
        Start-Sleep 1
        $null = Start-BgpSession -Name m6d -RemoteAddress ::1 -Port 12700 -AddressFamily IPv6 -LocalAS 65002 -RemoteAS 65001 -RouterId 2.2.2.2 -AutoReconnect -ReconnectDelay 1
        $d = (Get-Date).AddSeconds(12); while ((Get-Date) -lt $d -and (Get-BgpSession m6d).State -ne 'Established') { Start-Sleep -Milliseconds 300 }
        (Get-BgpSession m6d).State | Should -Be 'Established'
        Send-BgpUpdate -Name m6d -Nlri 2001:db8:50::/48
        $d = (Get-Date).AddSeconds(8); while ((Get-Date) -lt $d -and (Get-BgpSession m6l).Learned -lt 1) { Start-Sleep -Milliseconds 200 }
        (Get-BgpRoute -Name m6l).Prefix | Should -Be '2001:db8:50::/48'
        Send-BgpUpdate -Name m6d -Withdrawn 2001:db8:50::/48
        $d = (Get-Date).AddSeconds(8); while ((Get-Date) -lt $d -and (Get-BgpSession m6l).Learned -gt 0) { Start-Sleep -Milliseconds 200 }
        (Get-BgpSession m6l).Learned | Should -Be 0
        Get-BgpSession | Remove-BgpSession -Confirm:$false
    }
    It 'binds the outgoing connection to -LocalAddress' {
        $null = Start-BgpSession -Name bl -Passive -Port 12710 -LocalAS 65001 -RemoteAS 65002 -RouterId 1.1.1.1
        Start-Sleep 1
        $null = Start-BgpSession -Name bd -RemoteAddress 127.0.0.1 -Port 12710 -LocalAddress 127.0.0.5 -LocalAS 65002 -RemoteAS 65001 -RouterId 2.2.2.2 -AutoReconnect -ReconnectDelay 1
        $d = (Get-Date).AddSeconds(12); while ((Get-Date) -lt $d -and (Get-BgpSession bd).State -ne 'Established') { Start-Sleep -Milliseconds 300 }
        (Get-BgpSession bd).LocalAddress | Should -Be '127.0.0.5'
        (Get-BgpSession bl).RemoteAddress | Should -Be '127.0.0.5'
        Get-BgpSession | Remove-BgpSession -Confirm:$false
    }
}
