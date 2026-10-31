function Invoke-BfdSessionLoop {
    param($S)
    $c = $S.Config
    $rx = $null; $tx = $null
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $rand = [Random]::new()

    try {
        $bindIp = if ($c.LocalAddress) { [ipaddress]$c.LocalAddress } else { [ipaddress]::Any }
        $rx = [Net.Sockets.UdpClient]::new([Net.IPEndPoint]::new($bindIp, $c.ListenPort))
        for ($i = 0; $i -lt 20 -and -not $tx; $i++) {
            try { $tx = [Net.Sockets.UdpClient]::new([Net.IPEndPoint]::new($bindIp, $rand.Next(49152, 65535))) } catch { }
        }
        if (-not $tx) { throw 'Could not bind a source port in 49152-65535.' }
        $tx.Client.Ttl = 255
        $remote = [Net.IPEndPoint]::new([ipaddress]$c.RemoteAddress, $c.RemotePort)

        $myDisc = [uint32]$rand.Next(1, [int]::MaxValue)
        $yourDisc = [uint32]0
        $fsm = @{ State = 'Down'; Diag = 0 }
        $remoteMult = 0; $remoteDesiredTx = 1000000; $remoteRequiredRx = 1000000
        $lastRx = 0.0
        $replyFinal = $false
        $nextTx = 0.0
        $S.State = 'Down'
        $S.LocalDiscriminator = $myDisc

        $setState = {
            param($new, $newDiag)
            if ($new -ne $fsm.State) {
                $S.History.Enqueue(('{0:HH:mm:ss.fff} {1} -> {2}' -f (Get-Date), $fsm.State, $new))
                $dummy = $null
                while ($S.History.Count -gt 100) { $null = $S.History.TryDequeue([ref]$dummy) }
            }
            $fsm.State = $new; $fsm.Diag = $newDiag
            $S.State = $new
        }

        while (-not $S.Stop) {
            $now = $clock.Elapsed.TotalMilliseconds

            while ($rx.Available -gt 0) {
                $ep = [Net.IPEndPoint]::new([ipaddress]::Any, 0)
                $data = $rx.Receive([ref]$ep)
                if (-not $ep.Address.Equals($remote.Address) -or $data.Length -lt 24) { continue }
                $p = ConvertFrom-BfdControl $data
                if ($p.Version -ne 1 -or $p.DetectMult -eq 0 -or $p.MyDiscriminator -eq 0) { continue }
                if ($p.YourDiscriminator -ne 0 -and $p.YourDiscriminator -ne $myDisc) { continue }

                $S.Received++
                $lastRx = $now
                $yourDisc = $p.MyDiscriminator
                $remoteMult = $p.DetectMult
                $remoteDesiredTx = $p.DesiredMinTx
                $remoteRequiredRx = $p.RequiredMinRx
                $S.RemoteState = $p.State

                switch ($fsm.State) {
                    'Down' {
                        if ($p.State -eq 'Down') { & $setState 'Init' 0 }
                        elseif ($p.State -eq 'Init') { & $setState 'Up' 0 }
                    }
                    'Init' {
                        if ($p.State -in 'Init', 'Up') { & $setState 'Up' 0 }
                    }
                    'Up' {
                        if ($p.State -in 'Down', 'AdminDown') { & $setState 'Down' 3 }
                    }
                }
                if ($p.Poll) { $nextTx = 0; $replyFinal = $true }
            }

            if ($fsm.State -in 'Init', 'Up' -and $remoteMult -gt 0) {
                $detectMs = $remoteMult * [Math]::Max($c.RequiredMinRx, $remoteDesiredTx) / 1000.0
                if (($now - $lastRx) -gt $detectMs) { & $setState 'Down' 1; $yourDisc = 0 }
            }

            if (-not $S.Suppress -and $now -ge $nextTx) {
                $advTx = if ($fsm.State -eq 'Up') { $c.DesiredMinTx } else { [Math]::Max($c.DesiredMinTx, 1000000) }
                $pkt = New-BfdControl -State $fsm.State -Diagnostic $fsm.Diag -DetectMult $c.DetectMult -MyDiscriminator $myDisc `
                    -YourDiscriminator $yourDisc -DesiredMinTx $advTx -RequiredMinRx $c.RequiredMinRx -Final:$replyFinal
                $replyFinal = $false
                $null = $tx.Send($pkt, $pkt.Length, $remote)
                $S.Sent++
                $intervalUs = if ($fsm.State -eq 'Up') { [Math]::Max($c.DesiredMinTx, $remoteRequiredRx) } else { [Math]::Max($c.DesiredMinTx, 1000000) }
                $nextTx = $now + ($intervalUs / 1000.0) * (1 - 0.25 * $rand.NextDouble())
            }
            Start-Sleep -Milliseconds 5
        }

        $pkt = New-BfdControl -State AdminDown -Diagnostic 7 -DetectMult $c.DetectMult -MyDiscriminator $myDisc -YourDiscriminator $yourDisc
        $null = $tx.Send($pkt, $pkt.Length, $remote)
    }
    catch { $S.LastError = $_.Exception.Message }
    finally {
        if ($rx) { $rx.Dispose() }
        if ($tx) { $tx.Dispose() }
        $S.State = 'AdminDown'
    }
}
