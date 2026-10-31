function Invoke-BgpPeerLoop {
    param($S)

    $cfg = $S.Config
    $listener = $null
    $delay = $cfg.ReconnectDelay
    try {
        if ($cfg.Passive) {
            $listener = [Net.Sockets.TcpListener]::new($(if ($cfg.LocalAddress) { [ipaddress]$cfg.LocalAddress } elseif ('IPv6' -in $cfg.AddressFamily -and -not $cfg.Password) { [ipaddress]::IPv6Any } else { [ipaddress]::Any }), $cfg.Port)
            if ($listener.Server.AddressFamily -eq 'InterNetworkV6') { $listener.Server.DualMode = $true }
            if ($cfg.Password) { Set-BgpTcpMd5 -Socket $listener.Server -Address $cfg.RemoteAddress -Password $cfg.Password }
            $listener.Start()
        }
        while (-not $S.Stop) {
            Invoke-BgpPeerSession $S $listener
            if ($S.Stop -or -not $cfg.AutoReconnect) { break }

            # A session that reached Established resets the backoff
            if ($S.LastEstablished) { $delay = $cfg.ReconnectDelay; $S.LastEstablished = $false }
            $S.Reconnects++
            $S.NextRetry = (Get-Date).AddSeconds($delay)
            for ($i = 0; $i -lt ($delay * 10) -and -not $S.Stop; $i++) { Start-Sleep -Milliseconds 100 }
            $delay = [Math]::Min($delay * 2, $cfg.ReconnectMaxDelay)
            $S.NextRetry = $null
        }
    }
    catch { $S.LastError = $_.Exception.Message }
    finally {
        if ($listener) { $listener.Stop() }
        $S.State = 'Idle'
    }
}

function Invoke-BgpPeerSession {
    param($S, $Listener)

    $cfg = $S.Config
    $client = $null
    $stream = $null
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $buf = [System.Collections.Generic.List[byte]]::new()
    $tmp = [byte[]]::new(8192)

    $send = {
        param([byte[]]$Bytes)
        $stream.Write($Bytes, 0, $Bytes.Length)
        $S.Sent++
        $script:lastSent = $clock.Elapsed.TotalSeconds
        Add-BgpEvent $S 'Sent' $Bytes
    }

    try {
        $S.State = 'Active'

        if ($cfg.Passive) {
            while (-not $S.Stop -and -not $Listener.Pending()) { Start-Sleep -Milliseconds 100 }
            if ($S.Stop) { return }
            $client = $Listener.AcceptTcpClient()
        }
        else {
            while (-not $S.Stop -and -not $client) {
                $S.State = 'Connect'
                $c = if ($cfg.LocalAddress) { [Net.Sockets.TcpClient]::new([Net.IPEndPoint]::new([ipaddress]$cfg.LocalAddress, 0)) }
                elseif ($cfg.Password) { [Net.Sockets.TcpClient]::new([Net.Sockets.AddressFamily]::InterNetwork) }
                else { [Net.Sockets.TcpClient]::new() }
                if ($cfg.Password) { Set-BgpTcpMd5 -Socket $c.Client -Address $cfg.RemoteAddress -Password $cfg.Password }
                $task = $c.ConnectAsync($cfg.RemoteAddress, $cfg.Port)
                while (-not $task.IsCompleted -and -not $S.Stop) { Start-Sleep -Milliseconds 50 }
                if (-not $S.Stop -and $task.Status -eq 'RanToCompletion' -and $c.Connected) { $client = $c; break }
                $S.LastError = if ($task.IsFaulted) { $task.Exception.InnerException.Message } else { $S.LastError }
                $c.Dispose()
                $S.State = 'Active'
                for ($i = 0; $i -lt 30 -and -not $S.Stop; $i++) { Start-Sleep -Milliseconds 100 }
            }
            if ($S.Stop) { return }
        }

        $S.LastError = $null
        $client.NoDelay = $true
        if ($cfg.Ttl) { $client.Client.Ttl = [int16]$cfg.Ttl }
        $stream = $client.GetStream()
        $S.RemoteEndpoint = $client.Client.RemoteEndPoint.ToString()
        $S.LocalAddress = $client.Client.LocalEndPoint.Address.ToString()

        $script:lastSent = $clock.Elapsed.TotalSeconds
        $lastRecv = $clock.Elapsed.TotalSeconds
        $hold = 240
        & $send (New-BgpOpen -AS $cfg.LocalAS -RouterId $cfg.RouterId -HoldTime $cfg.HoldTime -AddressFamily $(if ($cfg.AddressFamily) { $cfg.AddressFamily } else { 'IPv4' }))
        $S.State = 'OpenSent'
        $done = $false

        while (-not $S.Stop -and -not $done) {
            $item = $null
            while ($S.Outbound.TryDequeue([ref]$item)) { & $send $item }

            if ($stream.DataAvailable) {
                $n = $stream.Read($tmp, 0, $tmp.Length)
                if ($n -eq 0) { $S.LastError = 'Connection closed by peer'; break }
                $buf.AddRange([byte[]]$tmp[0..($n - 1)])
            }
            elseif ($client.Client.Poll(0, [Net.Sockets.SelectMode]::SelectRead) -and -not $stream.DataAvailable) {
                $S.LastError = 'Connection closed by peer'
                break
            }

            while ($buf.Count -ge 19 -and -not $done) {
                $len = $buf[16] * 256 + $buf[17]
                if ($len -lt 19 -or $len -gt 4096) {
                    & $send (New-BgpNotification -Code 1 -Subcode 2)
                    $S.LastError = "Bad message length $len"; $done = $true; break
                }
                if ($buf.Count -lt $len) { break }
                $msg = $buf.GetRange(0, $len).ToArray()
                $buf.RemoveRange(0, $len)
                $lastRecv = $clock.Elapsed.TotalSeconds
                $S.Received++
                Add-BgpEvent $S 'Received' $msg
                $parsed = $null
                try { $parsed = ConvertFrom-BgpMessage $msg } catch { }

                switch ([int]$msg[18]) {
                    1 {
                        if (-not $parsed -or $S.State -ne 'OpenSent') { $done = $true; break }
                        if ($cfg.RemoteAS -and $parsed.Asn -ne $cfg.RemoteAS) {
                            & $send (New-BgpNotification -Code 2 -Subcode 2)
                            $S.LastError = "Bad peer AS $($parsed.Asn), expected $($cfg.RemoteAS)"; $done = $true; break
                        }
                        $S.PeerOpen = $parsed
                        $S.PeerFourOctet = [bool]($parsed.Capabilities | Where-Object Code -EQ 65)
                        $hold = [Math]::Min($cfg.HoldTime, $parsed.HoldTime)
                        $S.HoldTime = $hold
                        & $send (New-BgpKeepalive)
                        $S.State = 'OpenConfirm'
                    }
                    2 {
                        if ($S.State -ne 'Established') { $done = $true; break }
                        $u = ConvertFrom-BgpMessage $msg -TwoOctetAs:(-not $S.PeerFourOctet)
                        $dummy = $null
                        foreach ($p in $u.Withdrawn) { $null = $S.Learned.TryRemove($p, [ref]$dummy) }
                        $rules = $S.Config.InboundFilter; $defaultAction = $S.Config.InboundDefault
                        foreach ($p in $u.Nlri) {
                            if (($rules -or $defaultAction -eq 'Deny') -and -not (Test-BgpInboundFilter -Rules $rules -Default $defaultAction -Prefix $p -Update $u)) {
                                $S.Filtered++
                                $null = $S.Learned.TryRemove($p, [ref]$dummy)
                                continue
                            }
                            $S.Learned[$p] = [pscustomobject]@{
                                Peer = $S.Name; Prefix = $p; NextHop = "$($u.NextHop)"; AsPath = ($u.AsPath -join ' ')
                                Origin = $u.Origin; Med = $u.Med; LocalPref = $u.LocalPref; Community = ($u.Community -join ' '); Received = Get-Date
                            }
                        }
                    }
                    3 { $S.LastError = "Notification received: $($parsed.Summary)"; $done = $true }
                    4 {
                        if ($S.State -eq 'OpenConfirm') {
                            $S.State = 'Established'; $S.Established = Get-Date; $S.LastEstablished = $true
                            # Replay routes advertised before the session dropped
                            foreach ($e in @($S.Advertised.Values)) {
                                if (-not $e.Params) { continue }
                                $q = @{} + $e.Params
                                $q.Nlri = @($e.Prefix); $q.Remove('Withdrawn')
                                $S.Outbound.Enqueue([byte[]](New-BgpUpdate @q))
                            }
                        }
                    }
                }
            }
            if ($done) { break }

            $now = $clock.Elapsed.TotalSeconds
            if ($hold -gt 0 -and ($now - $lastRecv) -gt $hold) {
                & $send (New-BgpNotification -Code 4 -Subcode 0)
                $S.LastError = 'Hold timer expired'
                break
            }
            if ($hold -gt 0 -and $S.State -in 'OpenConfirm', 'Established' -and -not $S.SuppressKeepalives -and ($now - $script:lastSent) -ge ($hold / 3)) {
                & $send (New-BgpKeepalive)
            }
            Start-Sleep -Milliseconds 20
        }

        if ($S.Stop -and $stream) { try { & $send (New-BgpNotification -Code 6 -Subcode 0) } catch { } }
    }
    catch { $S.LastError = $_.Exception.Message }
    finally {
        if ($client) { $client.Dispose() }
        $S.State = 'Idle'
        $S.Established = $null
        $S.Learned.Clear()
        $dropped = $null
        while ($S.Outbound.TryDequeue([ref]$dropped)) { }
    }
}
