function New-BgpFilterRule {
    <#
    .SYNOPSIS
        Builds an inbound route filter rule for Start-BgpSession / Update-BgpSession -InboundFilter.
    .DESCRIPTION
        Rules are evaluated in order and the first match wins; routes that match no rule get the session's -InboundDefault action.
        All conditions given on a rule must match. A rule without conditions matches every route.
        -Prefix alone matches that exact prefix. With -Ge and/or -Le it matches any prefix inside -Prefix whose length is
        between -Ge (default: the length of -Prefix) and -Le (default: 32), like a prefix-list.
    .EXAMPLE
        $f = (New-BgpFilterRule -Action Deny -Prefix 10.0.0.0/8 -Le 32), (New-BgpFilterRule -Action Permit -AsPathContains 65100)
        Start-BgpSession -Name lab -RemoteAddress 192.168.1.1 -RemoteAS 65000 -LocalAS 65001 -RouterId 192.168.1.50 -InboundFilter $f -InboundDefault Deny
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Permit', 'Deny')][string]$Action,
        [string]$Prefix,
        [ValidateRange(0, 32)][int]$Ge,
        [ValidateRange(0, 32)][int]$Le,
        [uint32]$AsPathContains,
        [string]$Community
    )
    $ip = $null; $len = $null
    if ($Prefix) {
        $ipText, $lenText = $Prefix -split '/'
        if (-not [ipaddress]::TryParse($ipText, [ref]$ip) -or $ip.AddressFamily -ne 'InterNetwork' -or $lenText -notmatch '^\d+$' -or [int]$lenText -gt 32) {
            throw "Invalid IPv4 prefix '$Prefix'."
        }
        $len = [int]$lenText
    }
    elseif ($PSBoundParameters.ContainsKey('Ge') -or $PSBoundParameters.ContainsKey('Le')) {
        throw '-Ge and -Le need -Prefix.'
    }
    $geVal = if ($PSBoundParameters.ContainsKey('Ge')) { $Ge } else { $null }
    $leVal = if ($PSBoundParameters.ContainsKey('Le')) { $Le } else { $null }
    if ($null -ne $geVal -and $null -ne $leVal -and $geVal -gt $leVal) { throw '-Ge cannot be greater than -Le.' }
    if ($null -ne $len -and (($null -ne $geVal -and $geVal -lt $len) -or ($null -ne $leVal -and $leVal -lt $len))) {
        throw "-Ge and -Le cannot be shorter than the prefix length (/$len)."
    }

    [pscustomobject]@{
        PSTypeName     = 'PowerBGP.FilterRule'
        Action         = $Action
        Prefix         = if ($Prefix) { '{0}/{1}' -f $ip, $len } else { $null }
        Ge             = $geVal
        Le             = $leVal
        AsPathContains = if ($PSBoundParameters.ContainsKey('AsPathContains')) { $AsPathContains } else { $null }
        Community      = if ($Community) { $Community } else { $null }
    }
}
