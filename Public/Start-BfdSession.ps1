function Start-BfdSession {
    <#
    .SYNOPSIS
        Starts a BFD session (UDP, TTL 255, source port 49152-65535). Single-hop (RFC 5881, port 3784) by default.
    .PARAMETER MultiHop
        Multihop BFD (RFC 5883): defaults -Port and -ListenPort to 4784 instead of 3784. Use it when the peer is
        not on the same L2 segment (single-hop peers drop packets whose TTL is below 255) and supports multihop BFD.
    .PARAMETER LocalAddress
        Bind to this local IPv4 address, so packets leave from the address the peer expects.
    .PARAMETER ListenPort
        Local UDP port to receive on (3784 normally, 4784 with -MultiHop).
    .PARAMETER Port
        Remote UDP port to send to (3784 normally, 4784 with -MultiHop).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RemoteAddress,
        [string]$Name,
        [int]$Port,
        [int]$ListenPort,
        [switch]$MultiHop,
        [ipaddress]$LocalAddress,
        [uint32]$DesiredMinTxMs = 500,
        [uint32]$RequiredMinRxMs = 500,
        [ValidateRange(1, 255)][int]$DetectMult = 3
    )
    $default = if ($MultiHop) { 4784 } else { 3784 }
    if (-not $PSBoundParameters.ContainsKey('Port')) { $Port = $default }
    if (-not $PSBoundParameters.ContainsKey('ListenPort')) { $ListenPort = $default }
    if (-not $Name) { $Name = $RemoteAddress }
    $reg = Get-PowerBgpRegistry
    $existing = $reg.Bfd[$Name]
    if ($existing -and $existing.State -ne 'Stopped') { throw "BFD session '$Name' already exists." }

    $S = [hashtable]::Synchronized(@{
            Name               = $Name
            Config             = [pscustomobject]@{
                RemoteAddress = $RemoteAddress; RemotePort = $Port; ListenPort = $ListenPort
                LocalAddress = if ($LocalAddress) { $LocalAddress.ToString() } else { $null }
                DesiredMinTx = $DesiredMinTxMs * 1000; RequiredMinRx = $RequiredMinRxMs * 1000; DetectMult = $DetectMult
            }
            State              = 'Down'
            RemoteState        = $null
            Stop               = $false
            Suppress           = $false
            Sent               = 0
            Received           = 0
            LocalDiscriminator = 0
            LastError          = $null
            History            = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
            PowerShell         = $null
            Handle             = $null
        })
    $reg.Bfd[$Name] = $S
    Start-PowerBgpRunspace -State $S -Entry 'Invoke-BfdSessionLoop'
    Get-BfdSession -Name $Name
}

function Get-BfdSession {
    [CmdletBinding()]
    param([string]$Name = '*')
    foreach ($S in @((Get-PowerBgpRegistry).Bfd.Values)) {
        if ($S.Name -notlike $Name) { continue }
        [pscustomobject]@{
            PSTypeName    = 'PowerBGP.BfdSession'
            Name          = $S.Name
            State         = $S.State
            RemoteState   = $S.RemoteState
            Remote        = '{0}:{1}' -f $S.Config.RemoteAddress, $S.Config.RemotePort
            LocalAddress  = $S.Config.LocalAddress
            TxMs          = $S.Config.DesiredMinTx / 1000
            RxMs          = $S.Config.RequiredMinRx / 1000
            DetectMult    = $S.Config.DetectMult
            Sent          = $S.Sent
            Received      = $S.Received
            Suppressed    = [bool]$S.Suppress
            LastError     = $S.LastError
            History       = $S.History.ToArray()
        }
    }
}

function Stop-BfdSession {
    <#
    .SYNOPSIS
        Stops a BFD session. It stays configured (State 'Stopped') so Resume-BfdSession can restart it;
        use Remove-BfdSession to delete it.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$Name)
    process {
        $S = (Get-PowerBgpRegistry).Bfd[$Name]
        if (-not $S) { Write-Error "No such BFD session '$Name'."; return }
        Stop-PowerBgpRunspace $S
        $S.State = 'Stopped'
    }
}

function Resume-BfdSession {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$Name)
    process {
        $old = (Get-PowerBgpRegistry).Bfd[$Name]
        if (-not $old) { Write-Error "No such BFD session '$Name'."; return }
        $c = $old.Config
        $la = if ($c.LocalAddress) { @{ LocalAddress = [ipaddress]$c.LocalAddress } } else { @{} }
        $null = Start-BfdSession -Name $Name -RemoteAddress $c.RemoteAddress -Port $c.RemotePort -ListenPort $c.ListenPort @la `
            -DesiredMinTxMs ($c.DesiredMinTx / 1000) -RequiredMinRxMs ($c.RequiredMinRx / 1000) -DetectMult $c.DetectMult
        Get-BfdSession -Name $Name
    }
}

function Update-BfdSession {
    <#
    .SYNOPSIS
        Changes a BFD session's stored settings. A running session is restarted (it goes Down and renegotiates).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [int]$Port,
        [int]$ListenPort,
        [ipaddress]$LocalAddress,
        [uint32]$DesiredMinTxMs,
        [uint32]$RequiredMinRxMs,
        [ValidateRange(1, 255)][int]$DetectMult
    )
    $S = (Get-PowerBgpRegistry).Bfd[$Name]
    if (-not $S) { throw "No such BFD session '$Name'." }
    $wasRunning = $S.State -ne 'Stopped'
    if ($wasRunning) { Stop-BfdSession -Name $Name }
    $c = $S.Config
    if ($PSBoundParameters.ContainsKey('Port')) { $c.RemotePort = $Port }
    if ($PSBoundParameters.ContainsKey('ListenPort')) { $c.ListenPort = $ListenPort }
    if ($PSBoundParameters.ContainsKey('LocalAddress')) { $c.LocalAddress = $LocalAddress.ToString() }
    if ($PSBoundParameters.ContainsKey('DesiredMinTxMs')) { $c.DesiredMinTx = $DesiredMinTxMs * 1000 }
    if ($PSBoundParameters.ContainsKey('RequiredMinRxMs')) { $c.RequiredMinRx = $RequiredMinRxMs * 1000 }
    if ($PSBoundParameters.ContainsKey('DetectMult')) { $c.DetectMult = $DetectMult }
    if ($wasRunning) { Resume-BfdSession -Name $Name } else { Get-BfdSession -Name $Name }
}

function Remove-BfdSession {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, ValueFromPipelineByPropertyName)][string]$Name)
    process {
        $reg = Get-PowerBgpRegistry
        $S = $reg.Bfd[$Name]
        if (-not $S) { Write-Error "No such BFD session '$Name'."; return }
        if ($PSCmdlet.ShouldProcess($Name, 'Remove BFD session')) {
            Stop-PowerBgpRunspace $S
            $reg.Bfd.Remove($Name)
        }
    }
}

function Set-BfdSession {
    <#
    .SYNOPSIS
        Fault injection: -Suppress $true stops sending BFD control packets while the session object stays alive.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][bool]$Suppress)
    $S = (Get-PowerBgpRegistry).Bfd[$Name]
    if (-not $S) { throw "No such BFD session '$Name'." }
    $S.Suppress = $Suppress
}
