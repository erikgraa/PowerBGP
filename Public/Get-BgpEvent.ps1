function Get-BgpEvent {
    <#
    .SYNOPSIS
        Returns recent sent/received messages (ring buffer of 500 per peer), oldest first.
    #>
    [CmdletBinding()]
    param([string]$Name = '*', [int]$Last = 50)
    $events = foreach ($S in @((Get-PowerBgpRegistry).Bgp.Values)) {
        if ($S.Name -like $Name) { $S.Events.ToArray() }
    }
    $events | Sort-Object Time | Select-Object -Last $Last
}
