function Get-BgpSession {
    [CmdletBinding()]
    param([string]$Name = '*')
    $reg = Get-PowerBgpRegistry
    foreach ($S in @($reg.Bgp.Values)) {
        if ($S.Name -notlike $Name) { continue }
        Remove-BgpStaleRoute $S
        $peerGr = Get-BgpPeerGracefulRestart $S.PeerOpen
        $est = $S.Established
        $up = if ($est -is [datetime]) { (Get-Date) - $est } else { $null }
        [pscustomobject]@{
            PSTypeName       = 'PowerBGP.Peer'
            Name             = $S.Name
            State            = $S.State
            Mode             = if ($S.Config.Passive) { 'Passive' } else { 'Active' }
            Remote           = if ($S.RemoteEndpoint) { $S.RemoteEndpoint } else { '{0}:{1}' -f $S.Config.RemoteAddress, $S.Config.Port }
            RemoteAddress    = if ($S.Config.RemoteAddress) { $S.Config.RemoteAddress } elseif ($S.RemoteEndpoint) { $S.RemoteEndpoint -replace '^\[(?:::ffff:)?(.+)\]:\d+$', '$1' -replace '^(\d+\.\d+\.\d+\.\d+):\d+$', '$1' } else { $null }
            LocalAS          = $S.Config.LocalAS
            Type             = $(
                $pa = if ($S.PeerOpen) { $S.PeerOpen.Asn } else { $S.Config.RemoteAS }
                if ($pa) { if ([uint32]$pa -eq [uint32]$S.Config.LocalAS) { 'iBGP' } else { 'eBGP' } }
            )
            AddressFamily    = ($S.Config.AddressFamily -join ',')
            LocalAddress     = if ($S.LocalAddress) { $S.LocalAddress } else { $S.Config.LocalAddress }
            PeerAS           = if ($S.PeerOpen) { $S.PeerOpen.Asn } else { $S.Config.RemoteAS }
            RouterId         = $S.Config.RouterId.ToString()
            PeerRouterId     = if ($S.PeerOpen) { $S.PeerOpen.RouterId.ToString() } else { $null }
            HoldTime         = $S.HoldTime
            Uptime           = if ($up) { '{0:d\.hh\:mm\:ss}' -f $up } else { '' }
            Sent             = $S.Sent
            Received         = $S.Received
            Learned          = $S.Learned.Count
            Filtered         = $S.Filtered
            Advertised       = $S.Advertised.Count
            KeepalivesPaused = [bool]$S.SuppressKeepalives
            AutoReconnect    = $S.Config.AutoReconnect
            GracefulRestart  = [bool]$S.Config.GracefulRestart
            RestartTime      = $S.Config.RestartTime
            PeerGracefulRestart = [bool]$peerGr
            PeerRestartTime  = $peerGr.RestartTime
            StaleRoutes      = @($S.Learned.Values | Where-Object Stale).Count
            Md5              = [bool]$S.Config.Password
            Reconnects       = $S.Reconnects
            NextRetry        = $S.NextRetry
            LastError        = $S.LastError
        }
    }
}
