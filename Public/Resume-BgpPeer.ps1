function Resume-BgpPeer {
    <#
    .SYNOPSIS
        Restarts a stopped peer with its original configuration. Routes advertised earlier are re-sent once Established.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$Name)
    process {
        $old = (Get-PowerBgpRegistry).Bgp[$Name]
        if (-not $old) { Write-Error "No such peer '$Name'."; return }
        $c = $old.Config
        $p = @{
            Name = $Name; LocalAS = $c.LocalAS; RouterId = $c.RouterId; HoldTime = $c.HoldTime; Port = $c.Port
            ReconnectDelay = $c.ReconnectDelay; ReconnectMaxDelay = $c.ReconnectMaxDelay
            Passive = $c.Passive; AutoReconnect = $c.AutoReconnect
        }
        if ($c.RemoteAddress) { $p.RemoteAddress = $c.RemoteAddress }
        if ($c.RemoteAS) { $p.RemoteAS = $c.RemoteAS }
        if ($c.Ttl) { $p.Ttl = $c.Ttl }
        if ($c.Password) { $p.Password = $c.Password }
        $kept = @($old.Advertised.Values)

        $null = Start-BgpPeer @p
        $new = (Get-PowerBgpRegistry).Bgp[$Name]
        foreach ($e in $kept) { $new.Advertised[$e.Prefix] = $e }
        Get-BgpPeer -Name $Name
    }
}
