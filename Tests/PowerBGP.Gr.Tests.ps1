BeforeAll { Import-Module "$PSScriptRoot\..\PowerBGP.psd1" -Force }
AfterAll { Get-BgpSession | Remove-BgpSession -Confirm:$false }

Describe 'Graceful Restart (RFC 4724) packets' {
    It 'OPEN carries the capability with restart time, R bit and per-AF flags' {
        $o = ConvertFrom-BgpMessage (New-BgpOpen -AS 65001 -RouterId 1.1.1.1 -GracefulRestart -RestartTime 90 -RestartFlag -AddressFamily IPv4, IPv6)
        $cap = $o.Capabilities | Where-Object Code -EQ 64
        $cap.Name | Should -Be 'Graceful Restart'
        $cap.Value | Should -Be '805A0001018000020180'
    }
    It 'OPEN has no capability 64 unless asked' {
        (ConvertFrom-BgpMessage (New-BgpOpen -AS 65001 -RouterId 1.1.1.1)).Capabilities.Code | Should -Not -Contain 64
    }
    It 'builds and parses End-of-RIB for both families' {
        $v4 = ConvertFrom-BgpMessage (New-BgpUpdate -EndOfRib)
        $v4.EndOfRib | Should -Be 'IPv4'
        $v6 = ConvertFrom-BgpMessage (New-BgpUpdate -EndOfRib -AddressFamily IPv6)
        $v6.EndOfRib | Should -Be 'IPv6'
        $v6.Summary | Should -Be 'End-of-RIB (IPv6)'
    }
}

Describe 'Graceful Restart session' {
    It 'negotiates, keeps routes stale after a drop, and clears them on End-of-RIB' {
        $null = Start-BgpSession -Name gr-a -Passive -Port 12900 -LocalAddress 127.0.0.1 -LocalAS 65001 -RemoteAS 65002 -RouterId 1.1.1.1 -GracefulRestart -RestartTime 60
        $null = Start-BgpSession -Name gr-b -RemoteAddress 127.0.0.1 -Port 12900 -LocalAS 65002 -RemoteAS 65001 -RouterId 2.2.2.2 -GracefulRestart -RestartTime 60 -AutoReconnect:$false
        $d = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $d -and (Get-BgpSession gr-b).State -ne 'Established') { Start-Sleep -Milliseconds 200 }
        $null = Send-BgpUpdate -Name gr-b -Nlri 10.9.0.0/24 -NextHop 192.0.2.2
        $d = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $d -and -not (Get-BgpRoute gr-a)) { Start-Sleep -Milliseconds 200 }
        (Get-BgpSession gr-a).PeerGracefulRestart | Should -BeTrue
        (Get-BgpSession gr-a).PeerRestartTime | Should -Be 60

        Stop-BgpSession -Name gr-b
        $d = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $d -and (Get-BgpSession gr-a).State -eq 'Established') { Start-Sleep -Milliseconds 200 }
        (Get-BgpSession gr-a).StaleRoutes | Should -Be 1
        (Get-BgpRoute gr-a).Stale | Should -BeTrue

        $null = Resume-BgpSession -Name gr-b
        $d = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $d -and (Get-BgpSession gr-a).StaleRoutes -gt 0) { Start-Sleep -Milliseconds 200 }
        (Get-BgpSession gr-a).StaleRoutes | Should -Be 0
    }
    It 'round-trips through export and import' {
        $f = Join-Path ([IO.Path]::GetTempPath()) 'pb-gr.json'
        Export-BgpConfig -Path $f
        Get-BgpSession | Remove-BgpSession -Confirm:$false
        Import-BgpConfig -Path $f
        (Get-BgpSession gr-a).GracefulRestart | Should -BeTrue
        (Get-BgpSession gr-a).RestartTime | Should -Be 60
        Remove-Item $f -ErrorAction SilentlyContinue
    }
}
