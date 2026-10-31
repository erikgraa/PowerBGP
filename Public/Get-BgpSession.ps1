function Get-BgpSession {
    [CmdletBinding()]
    param([string]$Name = '*')
    $reg = Get-PowerBgpRegistry
    foreach ($S in @($reg.Bgp.Values)) {
        if ($S.Name -notlike $Name) { continue }
        $up = if ($S.Established) { (Get-Date) - $S.Established } else { $null }
        [pscustomobject]@{
            PSTypeName       = 'PowerBGP.Peer'
            Name             = $S.Name
            State            = $S.State
            Mode             = if ($S.Config.Passive) { 'Passive' } else { 'Active' }
            Remote           = if ($S.RemoteEndpoint) { $S.RemoteEndpoint } else { '{0}:{1}' -f $S.Config.RemoteAddress, $S.Config.Port }
            RemoteAddress    = if ($S.Config.RemoteAddress) { $S.Config.RemoteAddress } elseif ($S.RemoteEndpoint) { $S.RemoteEndpoint -replace '^\[(?:::ffff:)?(.+)\]:\d+$', '$1' } else { $null }
            LocalAS          = $S.Config.LocalAS
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
            Md5              = [bool]$S.Config.Password
            Reconnects       = $S.Reconnects
            NextRetry        = $S.NextRetry
            LastError        = $S.LastError
        }
    }
}
