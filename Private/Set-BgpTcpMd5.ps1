function Set-BgpTcpMd5 {
    # Linux-only: installs an RFC 2385 TCP-MD5 key via setsockopt(TCP_MD5SIG / TCP_MD5SIG_EXT) on an IPv4 socket.
    param(
        [Parameter(Mandatory)][Net.Sockets.Socket]$Socket,
        [string]$Address,
        [Parameter(Mandatory)][string]$Password
    )
    $key = [Text.Encoding]::UTF8.GetBytes($Password)
    if ($key.Length -gt 80) { throw 'TCP-MD5 password must be at most 80 bytes.' }

    # struct tcp_md5sig: sockaddr_storage[128], flags, prefixlen, keylen(u16), ifindex(i32), key[80]
    $b = [byte[]]::new(216)
    [BitConverter]::GetBytes([uint16]2).CopyTo($b, 0)   # AF_INET
    if ($Address) {
        $ip = $null
        if (-not [ipaddress]::TryParse($Address, [ref]$ip)) {
            $ip = [Net.Dns]::GetHostAddresses($Address) | Where-Object AddressFamily -eq 'InterNetwork' | Select-Object -First 1
        }
        if (-not $ip -or $ip.AddressFamily -ne 'InterNetwork') { throw "TCP-MD5 needs an IPv4 address (got '$Address')." }
        $ip.GetAddressBytes().CopyTo($b, 4)
        $opt = 14                                       # TCP_MD5SIG
    }
    else {
        $b[128] = 1                                     # TCP_MD5SIG_FLAG_PREFIX, prefixlen 0 = any peer
        $opt = 32                                       # TCP_MD5SIG_EXT
    }
    [BitConverter]::GetBytes([uint16]$key.Length).CopyTo($b, 130)
    $key.CopyTo($b, 136)
    $Socket.SetRawSocketOption(6, $opt, $b)             # SOL_TCP
}
