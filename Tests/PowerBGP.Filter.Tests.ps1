BeforeAll { Import-Module "$PSScriptRoot\..\PowerBGP.psd1" -Force }
AfterAll { Get-BgpSession | Remove-BgpSession -Confirm:$false }

Describe 'New-BgpFilterRule' {
    It 'normalises the prefix' {
        (New-BgpFilterRule -Action Deny -Prefix 10.0.0.0/8).Prefix | Should -Be '10.0.0.0/8'
    }
    It 'rejects bad prefixes' {
        { New-BgpFilterRule -Action Deny -Prefix 10.0.0.0/33 } | Should -Throw '*Invalid*'
        { New-BgpFilterRule -Action Deny -Prefix nonsense } | Should -Throw '*Invalid*'
    }
    It 'needs a prefix for -Ge/-Le and keeps them in range' {
        { New-BgpFilterRule -Action Deny -Le 24 } | Should -Throw '*need -Prefix*'
        { New-BgpFilterRule -Action Deny -Prefix 10.0.0.0/16 -Le 8 } | Should -Throw '*shorter*'
        { New-BgpFilterRule -Action Deny -Prefix 10.0.0.0/8 -Ge 24 -Le 16 } | Should -Throw '*greater*'
    }
}

Describe 'Inbound filter matching' {
    BeforeAll {
        $script:u = [pscustomobject]@{ AsPath = @(65002, 65100); Community = @('65000:100') }
        function script:Test-F($rules, $default, $prefix, $update = $script:u) {
            InModuleScope PowerBGP -Parameters @{ R = $rules; D = $default; P = $prefix; U = $update } {
                Test-BgpInboundFilter -Rules $R -Default $D -Prefix $P -Update $U
            }
        }
    }
    It 'permits everything with no rules' {
        Test-F @() Permit 10.1.0.0/24 | Should -BeTrue
    }
    It 'applies the default action when nothing matches' {
        $r = @(New-BgpFilterRule -Action Permit -Prefix 192.0.2.0/24)
        Test-F $r Deny 10.1.0.0/24 | Should -BeFalse
        Test-F $r Permit 10.1.0.0/24 | Should -BeTrue
    }
    It 'matches a prefix exactly without -Ge/-Le' {
        $r = @(New-BgpFilterRule -Action Deny -Prefix 10.1.0.0/24)
        Test-F $r Permit 10.1.0.0/24 | Should -BeFalse
        Test-F $r Permit 10.1.0.0/25 | Should -BeTrue
        Test-F $r Permit 10.1.1.0/24 | Should -BeTrue
    }
    It 'matches longer prefixes with -Le' {
        $r = @(New-BgpFilterRule -Action Deny -Prefix 10.0.0.0/8 -Le 24)
        Test-F $r Permit 10.5.6.0/24 | Should -BeFalse
        Test-F $r Permit 10.0.0.0/8 | Should -BeFalse
        Test-F $r Permit 10.5.6.0/25 | Should -BeTrue
        Test-F $r Permit 11.0.0.0/16 | Should -BeTrue
    }
    It 'matches a length window with -Ge' {
        $r = @(New-BgpFilterRule -Action Deny -Prefix 0.0.0.0/0 -Ge 25)
        Test-F $r Permit 10.0.0.0/24 | Should -BeTrue
        Test-F $r Permit 10.0.0.0/25 | Should -BeFalse
        Test-F $r Permit 10.0.0.1/32 | Should -BeFalse
    }
    It 'uses the first matching rule' {
        $r = @((New-BgpFilterRule -Action Permit -Prefix 10.1.0.0/16 -Le 32), (New-BgpFilterRule -Action Deny -Prefix 10.0.0.0/8 -Le 32))
        Test-F $r Permit 10.1.2.0/24 | Should -BeTrue
        Test-F $r Permit 10.2.0.0/24 | Should -BeFalse
    }
    It 'matches on AS path and community' {
        Test-F @(New-BgpFilterRule -Action Deny -AsPathContains 65100) Permit 1.1.1.0/24 | Should -BeFalse
        Test-F @(New-BgpFilterRule -Action Deny -AsPathContains 65999) Permit 1.1.1.0/24 | Should -BeTrue
        Test-F @(New-BgpFilterRule -Action Deny -Community 65000:100) Permit 1.1.1.0/24 | Should -BeFalse
        Test-F @(New-BgpFilterRule -Action Deny -Community 65000:200) Permit 1.1.1.0/24 | Should -BeTrue
    }
    It 'requires every condition on a rule to match' {
        $r = @(New-BgpFilterRule -Action Deny -Prefix 10.0.0.0/8 -Le 32 -AsPathContains 65999)
        Test-F $r Permit 10.1.0.0/24 | Should -BeTrue
    }
}

Describe 'Inbound filter on a live session (loopback)' {
    It 'drops denied routes, keeps permitted ones and counts them' {
        Get-BgpSession | Remove-BgpSession -Confirm:$false
        $f = @((New-BgpFilterRule -Action Deny -Prefix 10.66.0.0/16 -Le 32))
        $null = Start-BgpSession -Name fl -Passive -Port 12650 -LocalAS 65001 -RemoteAS 65002 -RouterId 1.1.1.1 -InboundFilter $f
        Start-Sleep 1
        $null = Start-BgpSession -Name fd -RemoteAddress 127.0.0.1 -Port 12650         -LocalAS 65002 -RemoteAS 65001 -RouterId 2.2.2.2 -AutoReconnect -ReconnectDelay 1
        $d = (Get-Date).AddSeconds(12); while ((Get-Date) -lt $d -and (Get-BgpSession fd).State -ne 'Established') { Start-Sleep -Milliseconds 300 }
        Send-BgpUpdate -Name fd -Nlri 10.66.1.0/24, 10.66.2.0/24, 10.77.0.0/24
        $d = (Get-Date).AddSeconds(8); while ((Get-Date) -lt $d -and (Get-BgpSession fl).Learned -lt 1) { Start-Sleep -Milliseconds 200 }
        Start-Sleep -Milliseconds 500
        (Get-BgpRoute -Name fl).Prefix | Should -Be '10.77.0.0/24'
        (Get-BgpSession fl).Filtered | Should -Be 2
    }
    It 'applies -InboundDefault Deny and can be edited with Update-BgpSession' {
        $null = Update-BgpSession -Name fl -InboundFilter @(New-BgpFilterRule -Action Permit -Prefix 10.88.0.0/16 -Le 32) -InboundDefault Deny
        $d = (Get-Date).AddSeconds(15); while ((Get-Date) -lt $d -and ((Get-BgpSession fd).State -ne 'Established' -or (Get-BgpSession fl).State -ne 'Established')) { Start-Sleep -Milliseconds 300 }
        Send-BgpUpdate -Name fd -Nlri 10.88.1.0/24, 10.99.0.0/24
        $d = (Get-Date).AddSeconds(8); while ((Get-Date) -lt $d -and (Get-BgpSession fl).Learned -lt 1) { Start-Sleep -Milliseconds 200 }
        Start-Sleep -Milliseconds 500
        (Get-BgpRoute -Name fl).Prefix | Should -Contain '10.88.1.0/24'
        (Get-BgpRoute -Name fl).Prefix | Should -Not -Contain '10.99.0.0/24'
        Get-BgpSession | Remove-BgpSession -Confirm:$false
    }
}

Describe 'Inbound filter in exported config' {
    It 'round-trips rules and the default action' {
        Get-BgpSession | Remove-BgpSession -Confirm:$false
        $f = @((New-BgpFilterRule -Action Deny -Prefix 10.0.0.0/8 -Ge 16 -Le 24), (New-BgpFilterRule -Action Permit -AsPathContains 65100))
        $null = Start-BgpSession -Name ex -Passive -Port 12660 -LocalAS 65001 -RemoteAS 65002 -RouterId 1.1.1.1 -InboundFilter $f -InboundDefault Deny
        $file = Join-Path ([IO.Path]::GetTempPath()) "powerbgp-$([guid]::NewGuid()).json"
        try {
            Export-BgpConfig -Path $file
            Get-BgpSession | Remove-BgpSession -Confirm:$false
            Import-BgpConfig -Path $file
            $c = InModuleScope PowerBGP { (Get-PowerBgpRegistry).Bgp['ex'].Config }
            $c.InboundDefault | Should -Be 'Deny'
            @($c.InboundFilter).Count | Should -Be 2
            $c.InboundFilter[0].Ge | Should -Be 16
            $c.InboundFilter[0].Le | Should -Be 24
            $c.InboundFilter[1].AsPathContains | Should -Be 65100
        }
        finally { Remove-Item $file -ErrorAction SilentlyContinue; Get-BgpSession | Remove-BgpSession -Confirm:$false }
    }
}
