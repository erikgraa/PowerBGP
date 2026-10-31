function Get-PowerBgpRegistry {
    # AppDomain data is visible to every runspace, so Pode request runspaces and peer runspaces share one registry.
    $r = [AppDomain]::CurrentDomain.GetData('PowerBGP.Registry')
    if (-not $r) {
        $r = [hashtable]::Synchronized(@{
                Bgp = [hashtable]::Synchronized(@{})
                Bfd = [hashtable]::Synchronized(@{})
            })
        [AppDomain]::CurrentDomain.SetData('PowerBGP.Registry', $r)
    }
    $r
}

function Start-PowerBgpRunspace {
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][string]$Entry)

    $manifest = Join-Path (Get-Module PowerBGP).ModuleBase 'PowerBGP.psd1'
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $null = $ps.AddScript({
            param($manifest, $state, $entry)
            $mod = Import-Module $manifest -PassThru
            & $mod { param($e, $s) & $e $s } $entry $state
        }).AddArgument($manifest).AddArgument($State).AddArgument($Entry)
    $State.PowerShell = $ps
    $State.Handle = $ps.BeginInvoke()
}

function Stop-PowerBgpRunspace {
    param($State, [int]$TimeoutSeconds = 5)
    $State.Stop = $true
    if ($State.Handle) { $null = $State.Handle.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000) }
    if ($State.PowerShell) {
        try { $State.PowerShell.Runspace.Dispose(); $State.PowerShell.Dispose() } catch { }
    }
}

function Add-BgpEvent {
    param($State, [string]$Direction, [byte[]]$Bytes, [string]$Note)
    $parsed = $null
    try { $parsed = ConvertFrom-BgpMessage $Bytes } catch { }
    $State.Events.Enqueue([pscustomobject]@{
            Time      = Get-Date
            Peer      = $State.Name
            Direction = $Direction
            Type      = if ($parsed) { $parsed.Type } else { 'RAW' }
            Summary   = if ($parsed) { $parsed.Summary } else { $Note }
            Message   = $parsed
            Bytes     = $Bytes
        })
    $dummy = $null
    while ($State.Events.Count -gt 500) { $null = $State.Events.TryDequeue([ref]$dummy) }
}
