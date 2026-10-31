BeforeAll { Import-Module "$PSScriptRoot\..\PowerBGP.psd1" -Force }
AfterAll { Get-BgpSession | Remove-BgpSession -Confirm:$false }

Describe 'iBGP' {
    It 'advertises without AS prepend and with LOCAL_PREF, and reports the session type' {
        $null = Start-BgpSession -Name ib-a -Passive -Port 12910 -LocalAddress 127.0.0.1 -LocalAS 65001 -RemoteAS 65001 -RouterId 1.1.1.1
        $null = Start-BgpSession -Name ib-b -RemoteAddress 127.0.0.1 -Port 12910 -LocalAS 65001 -RemoteAS 65001 -RouterId 2.2.2.2
        $d = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $d -and (Get-BgpSession ib-b).State -ne 'Established') { Start-Sleep -Milliseconds 200 }
        (Get-BgpSession ib-b).Type | Should -Be 'iBGP'

        Send-BgpUpdate -Name ib-b -Nlri 10.7.0.0/24 -NextHop 192.0.2.2
        Send-BgpUpdate -Name ib-b -Nlri 10.7.1.0/24 -NextHop 192.0.2.2 -LocalPref 250
        $d = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $d -and @(Get-BgpRoute ib-a).Count -lt 2) { Start-Sleep -Milliseconds 200 }
        $r = Get-BgpRoute ib-a
        ($r | Where-Object Prefix -EQ 10.7.0.0/24).AsPath | Should -BeNullOrEmpty
        ($r | Where-Object Prefix -EQ 10.7.0.0/24).LocalPref | Should -Be 100
        ($r | Where-Object Prefix -EQ 10.7.1.0/24).LocalPref | Should -Be 250
    }
    It 'still prepends on eBGP' {
        $null = Start-BgpSession -Name eb-a -Passive -Port 12911 -LocalAddress 127.0.0.2 -LocalAS 65001 -RemoteAS 65002 -RouterId 1.1.1.1
        $null = Start-BgpSession -Name eb-b -RemoteAddress 127.0.0.2 -Port 12911 -LocalAS 65002 -RemoteAS 65001 -RouterId 2.2.2.2
        $d = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $d -and (Get-BgpSession eb-b).State -ne 'Established') { Start-Sleep -Milliseconds 200 }
        (Get-BgpSession eb-b).Type | Should -Be 'eBGP'
        Send-BgpUpdate -Name eb-b -Nlri 10.8.0.0/24 -NextHop 192.0.2.2
        $d = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $d -and -not (Get-BgpRoute eb-a)) { Start-Sleep -Milliseconds 200 }
        (Get-BgpRoute eb-a).AsPath | Should -Be '65002'
        (Get-BgpRoute eb-a).LocalPref | Should -BeNullOrEmpty
    }
}
