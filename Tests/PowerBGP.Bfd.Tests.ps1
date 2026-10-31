BeforeAll { Import-Module "$PSScriptRoot\..\PowerBGP.psd1" -Force }
AfterAll { Get-BfdSession | Remove-BfdSession -Confirm:$false }

Describe 'BFD multihop and local address' {
    It 'defaults to port 4784 with -MultiHop and 3784 otherwise' {
        $m = Start-BfdSession -Name mh -RemoteAddress 127.0.0.9 -MultiHop -ListenPort 15910
        $m.Remote | Should -Be '127.0.0.9:4784'
        $s = Start-BfdSession -Name sh -RemoteAddress 127.0.0.10 -ListenPort 15911
        $s.Remote | Should -Be '127.0.0.10:3784'
        Get-BfdSession | Remove-BfdSession -Confirm:$false
    }
    It 'comes Up between two sessions bound to different local addresses' {
        $null = Start-BfdSession -Name la-a -RemoteAddress 127.0.0.6 -LocalAddress 127.0.0.5 -ListenPort 15900 -Port 15901 -DesiredMinTxMs 100 -RequiredMinRxMs 100
        $null = Start-BfdSession -Name la-b -RemoteAddress 127.0.0.5 -LocalAddress 127.0.0.6 -ListenPort 15901 -Port 15900 -DesiredMinTxMs 100 -RequiredMinRxMs 100
        $deadline = (Get-Date).AddSeconds(12)
        while ((Get-Date) -lt $deadline -and ((Get-BfdSession la-a).State -ne 'Up' -or (Get-BfdSession la-b).State -ne 'Up')) { Start-Sleep -Milliseconds 200 }
        (Get-BfdSession la-a).State | Should -Be 'Up'
        (Get-BfdSession la-a).LocalAddress | Should -Be '127.0.0.5'
        (Get-BfdSession la-b).State | Should -Be 'Up'
    }
}

Describe 'BFD Poll sequence' {
    It 'answers a Poll with the Final bit' {
        $null = Start-BfdSession -Name pf -RemoteAddress 127.0.0.8 -LocalAddress 127.0.0.7 -ListenPort 15902 -Port 15903
        $peer = [Net.Sockets.UdpClient]::new([Net.IPEndPoint]::new([ipaddress]'127.0.0.8', 15903))
        try {
            $peer.Client.ReceiveTimeout = 500
            $poll = New-BfdControl -State Down -Poll -MyDiscriminator 77 -YourDiscriminator 0
            $final = $false
            $deadline = (Get-Date).AddSeconds(6)
            while (-not $final -and (Get-Date) -lt $deadline) {
                $null = $peer.Send($poll, $poll.Length, [Net.IPEndPoint]::new([ipaddress]'127.0.0.7', 15902))
                try {
                    $ep = [Net.IPEndPoint]::new([ipaddress]::Any, 0)
                    $final = (ConvertFrom-BfdControl ($peer.Receive([ref]$ep))).Final
                }
                catch [Net.Sockets.SocketException] { }
            }
            $final | Should -BeTrue
        }
        finally { $peer.Dispose() }
    }
}
