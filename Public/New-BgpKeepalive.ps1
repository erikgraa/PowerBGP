function New-BgpKeepalive {
    [CmdletBinding()]
    param()
    New-BgpMessage -Type 4
}
