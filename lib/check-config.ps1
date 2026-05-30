# Check if cc-switch.db has at least one configured provider
# Exit 0 if found, 1 otherwise
param([Parameter(Mandatory=$true)][string]$DbPath)

if (-not (Test-Path $DbPath)) { exit 1 }

# Try System.Data.SQLite first (precise SQL query, no false positives from deleted rows).
# This assembly is available when sqlite-net or similar is installed,
# but is NOT shipped with Windows PowerShell 5.1 by default.
try {
    Add-Type -AssemblyName System.Data.SQLite -ErrorAction Stop
    $cs = "Data Source=$DbPath;Read Only=True;"
    $conn = [System.Data.SQLite.SQLiteConnection]::new($cs)
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT settings_config FROM providers WHERE app_type='claude' AND is_current=1 LIMIT 1"
    $row = $cmd.ExecuteScalar()
    $conn.Close()
    if ($row) {
        $cfg = $row | ConvertFrom-Json
        $env = $cfg.env
        $url = $env.ANTHROPIC_BASE_URL
        $key = if ($env.ANTHROPIC_AUTH_TOKEN) { $env.ANTHROPIC_AUTH_TOKEN } else { $env.ANTHROPIC_API_KEY }
        if ($url -and $key -and $url.Length -gt 5 -and $key.Length -gt 5) { exit 0 }
    }
    exit 1
} catch {}

# Fallback: streamed regex scan (don't load entire DB into memory).
# Read the file in 64KB chunks and search for the JSON keys.
#
# UTF-8 boundary handling: a multi-byte char split between chunks would
# decode as U+FFFD (replacement char). We carry over the last few BYTES
# of each chunk into the next decode operation so multi-byte sequences
# stay intact. ASCII keys (ANTHROPIC_*) and ASCII URLs/tokens make this
# mostly cosmetic in practice, but it's the correct behavior.
#
# Caveats acknowledged (vs SQLite query):
#   - matches deleted-but-not-vacuumed rows (very unlikely to false-positive
#     in practice because cc-switch always replaces is_current entries)
#   - cross-row matches possible (also very rare)
# But in exchange we don't load the whole DB to memory.
try {
    $fs = [IO.FileStream]::new($DbPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $chunkSize = 65536
        $textOverlap = 256       # decoded chars carried so regex matches across boundary
        $byteOverlap = 4         # max UTF-8 sequence length
        $buffer = New-Object byte[] $chunkSize
        # carry: previously-decoded tail (string) + leftover undecoded bytes
        $textTail = ""
        $byteTail = New-Object byte[] 0
        $foundUrl = $false
        $foundKey = $false
        $urlPat = [regex]'"ANTHROPIC_BASE_URL"\s*:\s*"([^"]{6,})"'
        $keyPat1 = [regex]'"ANTHROPIC_AUTH_TOKEN"\s*:\s*"([^"]{6,})"'
        $keyPat2 = [regex]'"ANTHROPIC_API_KEY"\s*:\s*"([^"]{6,})"'

        while ($true) {
            $n = $fs.Read($buffer, 0, $chunkSize)
            if ($n -le 0) { break }
            # Concat byteTail + new chunk so split UTF-8 sequences merge cleanly.
            $combined = New-Object byte[] ($byteTail.Length + $n)
            [Array]::Copy($byteTail, 0, $combined, 0, $byteTail.Length)
            [Array]::Copy($buffer,    0, $combined, $byteTail.Length, $n)

            # Save up to byteOverlap trailing bytes for next iteration.
            # If combined.Length <= byteOverlap, we're at end / starting case.
            $reserveBytes = [Math]::Min($byteOverlap, $combined.Length)
            $decodeLen = $combined.Length - $reserveBytes
            $chunkText = if ($decodeLen -gt 0) { [Text.Encoding]::UTF8.GetString($combined, 0, $decodeLen) } else { "" }
            $byteTail = New-Object byte[] $reserveBytes
            [Array]::Copy($combined, $decodeLen, $byteTail, 0, $reserveBytes)

            $window = $textTail + $chunkText
            if (-not $foundUrl -and $urlPat.IsMatch($window)) { $foundUrl = $true }
            if (-not $foundKey -and ($keyPat1.IsMatch($window) -or $keyPat2.IsMatch($window))) { $foundKey = $true }
            if ($foundUrl -and $foundKey) { exit 0 }
            if ($window.Length -gt $textOverlap) {
                $textTail = $window.Substring($window.Length - $textOverlap)
            } else {
                $textTail = $window
            }
        }
        # Decode any final byteTail (last chars)
        if ($byteTail.Length -gt 0) {
            $window = $textTail + [Text.Encoding]::UTF8.GetString($byteTail)
            if (-not $foundUrl -and $urlPat.IsMatch($window)) { $foundUrl = $true }
            if (-not $foundKey -and ($keyPat1.IsMatch($window) -or $keyPat2.IsMatch($window))) { $foundKey = $true }
            if ($foundUrl -and $foundKey) { exit 0 }
        }
    } finally {
        $fs.Close()
    }
} catch {}

exit 1
