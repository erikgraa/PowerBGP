function ConvertFrom-BgpPassword {
    # Accepts a string or SecureString and returns the plain text the TCP-MD5 socket option needs.
    param($Password)
    if ($Password -is [securestring]) { return [pscredential]::new('bgp', $Password).GetNetworkCredential().Password }
    if ($null -eq $Password) { return '' }
    [string]$Password
}
