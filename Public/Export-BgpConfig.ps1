function Export-BgpConfig {
    <#
    .SYNOPSIS
        Saves the current peers and BFD sessions to a JSON file. Note: TCP-MD5 passwords are stored in clear text.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $reg = Get-PowerBgpRegistry
    $peers = foreach ($S in @($reg.Bgp.Values)) {
        $c = $S.Config
        [ordered]@{
            Name = $S.Name; RemoteAddress = $c.RemoteAddress; RemoteAS = $c.RemoteAS; LocalAddress = $c.LocalAddress; AddressFamily = @($c.AddressFamily); LocalAS = $c.LocalAS
            RouterId = "$($c.RouterId)"; HoldTime = $c.HoldTime; Port = $c.Port; Passive = $c.Passive; Ttl = $c.Ttl
            GracefulRestart = [bool]$c.GracefulRestart; RestartTime = $c.RestartTime
            AutoReconnect = $c.AutoReconnect; ReconnectDelay = $c.ReconnectDelay; ReconnectMaxDelay = $c.ReconnectMaxDelay
            Password = $c.Password; InboundDefault = $c.InboundDefault; InboundFilter = @($c.InboundFilter)
        }
    }
    [ordered]@{ Version = 1; Peers = @($peers) } | ConvertTo-Json -Depth 5 | Set-Content -Path $Path
}

function Import-BgpConfig {
    <#
    .SYNOPSIS
        Starts the peers saved by Export-BgpConfig.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $cfg = Get-Content -Path $Path -Raw | ConvertFrom-Json
    foreach ($p in $cfg.Peers) {
        $a = @{ Name = $p.Name; LocalAS = [uint32]$p.LocalAS; RouterId = [ipaddress]$p.RouterId; HoldTime = [uint16]$p.HoldTime; Port = [int]$p.Port }
        if ($p.RemoteAddress) { $a.RemoteAddress = $p.RemoteAddress }
        if ($p.RemoteAS) { $a.RemoteAS = [uint32]$p.RemoteAS }
        if ($p.LocalAddress) { $a.LocalAddress = [ipaddress]$p.LocalAddress }
        if ($p.AddressFamily) { $a.AddressFamily = @($p.AddressFamily) }
        if ($p.Passive) { $a.Passive = $true }
        if ($p.Ttl) { $a.Ttl = [int]$p.Ttl }
        $a.AutoReconnect = [bool]$p.AutoReconnect
        if ($p.GracefulRestart) { $a.GracefulRestart = $true }
        if ($null -ne $p.RestartTime) { $a.RestartTime = [int]$p.RestartTime }
        if ($p.ReconnectDelay) { $a.ReconnectDelay = [int]$p.ReconnectDelay }
        if ($p.ReconnectMaxDelay) { $a.ReconnectMaxDelay = [int]$p.ReconnectMaxDelay }
        if ($p.Password) { $a.Password = $p.Password }
        if ($p.InboundFilter) { $a.InboundFilter = @(ConvertTo-BgpFilterRule $p.InboundFilter) }
        if ($p.InboundDefault) { $a.InboundDefault = $p.InboundDefault }
        Start-BgpSession @a
    }
}
