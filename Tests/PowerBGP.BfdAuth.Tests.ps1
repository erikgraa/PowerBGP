BeforeAll { Import-Module "$PSScriptRoot\..\PowerBGP.psd1" -Force }
AfterAll { Get-BfdSession | Remove-BfdSession -Confirm:$false }

Describe 'BFD authentication packets' {
    It 'unauthenticated packets are unchanged (24 bytes, A bit clear)' {
        $p = New-BfdControl -State Up
        $p.Length | Should -Be 24
        ($p[1] -band 0x04) | Should -Be 0
        (ConvertFrom-BfdControl $p).Auth | Should -BeNullOrEmpty
    }
    It 'builds and verifies Simple Password' {
        $p = New-BfdControl -State Up -AuthType SimplePassword -AuthKeyId 3 -AuthKey 'hunter2'
        $p.Length | Should -Be 34
        $p[3] | Should -Be 34
        $a = (ConvertFrom-BfdControl $p -AuthKey 'hunter2').Auth
        $a.Type | Should -Be 'SimplePassword'; $a.KeyId | Should -Be 3; $a.Valid | Should -BeTrue
        (ConvertFrom-BfdControl $p -AuthKey 'wrong').Auth.Valid | Should -BeFalse
    }
    It 'builds and verifies Keyed SHA1' {
        $p = New-BfdControl -State Up -AuthType KeyedSHA1 -AuthKeyId 1 -AuthKey 's3cret' -AuthSequence 42
        $p.Length | Should -Be 52
        $a = (ConvertFrom-BfdControl $p -AuthKey 's3cret').Auth
        $a.Type | Should -Be 'KeyedSHA1'; $a.Sequence | Should -Be 42; $a.Valid | Should -BeTrue
        (ConvertFrom-BfdControl $p -AuthKey 'nope').Auth.Valid | Should -BeFalse
        $p[10] = $p[10] -bxor 1
        (ConvertFrom-BfdControl $p -AuthKey 's3cret').Auth.Valid | Should -BeFalse
    }
    It 'rejects a missing or oversized key' {
        { New-BfdControl -AuthType KeyedSHA1 } | Should -Throw '*AuthKey*'
        { New-BfdControl -AuthType SimplePassword -AuthKey ('x' * 17) } | Should -Throw '*at most 16*'
    }
}

Describe 'BFD authentication sessions' {
    It 'comes Up with matching SHA1 keys and stays Down on a mismatch' {
        $null = Start-BfdSession -Name au-a -RemoteAddress 127.0.0.1 -LocalAddress 127.0.0.1 -ListenPort 13784 -Port 13785 -DesiredMinTxMs 100 -RequiredMinRxMs 100 -AuthType KeyedSHA1 -AuthKey 'k1'
        $null = Start-BfdSession -Name au-b -RemoteAddress 127.0.0.1 -LocalAddress 127.0.0.1 -ListenPort 13785 -Port 13784 -DesiredMinTxMs 100 -RequiredMinRxMs 100 -AuthType KeyedSHA1 -AuthKey 'k1'
        $d = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $d -and (Get-BfdSession au-a).State -ne 'Up') { Start-Sleep -Milliseconds 200 }
        (Get-BfdSession au-a).State | Should -Be 'Up'
        (Get-BfdSession au-a).AuthType | Should -Be 'KeyedSHA1'

        $null = Update-BfdSession -Name au-b -AuthKey 'other'
        $d = (Get-Date).AddSeconds(15)
        while ((Get-Date) -lt $d -and (Get-BfdSession au-a).State -eq 'Up') { Start-Sleep -Milliseconds 200 }
        (Get-BfdSession au-a).State | Should -Not -Be 'Up'
        $d = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $d -and (Get-BfdSession au-a).AuthFailures -eq 0) { Start-Sleep -Milliseconds 200 }
        (Get-BfdSession au-a).AuthFailures | Should -BeGreaterThan 0
    }
}
