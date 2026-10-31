BeforeAll { Import-Module "$PSScriptRoot\..\PowerBGP.psd1" -Force }
AfterAll { Get-BgpSession | Remove-BgpSession -Confirm:$false }

Describe 'AutoReconnect default' {
    It 'is on unless disabled explicitly' {
        $null = Start-BgpSession -Name ar-on -Passive -Port 12801 -LocalAS 65001 -RouterId 1.1.1.1
        $null = Start-BgpSession -Name ar-off -Passive -Port 12802 -LocalAS 65001 -RouterId 1.1.1.2 -AutoReconnect:$false
        (Get-BgpSession ar-on).AutoReconnect | Should -BeTrue
        (Get-BgpSession ar-off).AutoReconnect | Should -BeFalse
    }
    It 'survives an export and import round trip' {
        $f = Join-Path ([IO.Path]::GetTempPath()) 'pb-ar.json'
        Export-BgpConfig -Path $f
        Get-BgpSession | Remove-BgpSession -Confirm:$false
        Import-BgpConfig -Path $f
        (Get-BgpSession ar-on).AutoReconnect | Should -BeTrue
        (Get-BgpSession ar-off).AutoReconnect | Should -BeFalse
        Remove-Item $f -ErrorAction SilentlyContinue
    }
}
