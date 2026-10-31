function Test-BfdAuth {
    # Verifies the RFC 5880 6.7 authentication section of a received control packet
    param([byte[]]$Packet, [string]$Type, [int]$KeyId, [string]$Key)
    $len = [int]$Packet[3]
    if (($Packet[1] -band 0x04) -eq 0 -or $Packet.Length -lt $len -or $len -lt 27) { return $false }
    $keyBytes = [Text.Encoding]::UTF8.GetBytes($Key)
    switch ($Type) {
        'SimplePassword' {
            if ($Packet[24] -ne 1 -or $Packet[26] -ne $KeyId -or $Packet[25] -ne ($len - 24)) { return $false }
            $pw = [byte[]]$Packet[27..($len - 1)]
            return [Security.Cryptography.CryptographicOperations]::FixedTimeEquals($pw, $keyBytes)
        }
        'KeyedSHA1' {
            if ($Packet[24] -ne 4 -or $Packet[25] -ne 28 -or $len -ne 52 -or $Packet[26] -ne $KeyId -or $keyBytes.Length -gt 20) { return $false }
            $padded = [byte[]]::new(20); [Array]::Copy($keyBytes, $padded, $keyBytes.Length)
            $tmp = [byte[]]$Packet[0..31] + $padded
            $calc = [Security.Cryptography.SHA1]::HashData($tmp)
            return [Security.Cryptography.CryptographicOperations]::FixedTimeEquals($calc, [byte[]]$Packet[32..51])
        }
    }
    $false
}
