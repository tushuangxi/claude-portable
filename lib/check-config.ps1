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
# Read the file in 64KB chunks, decode each chunk as UTF-8, and search
# for the JSON keys. We keep a small overlap buffer between chunks to
# handle keys that straddle chunk boundaries.
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
        $overlap = 256  # large enough to span the longest expected JSON fragment
        $buffer = New-Object byte[] $chunkSize
        $tail = ""  # carries the last `overlap` decoded chars across iterations
        $foundUrl = $false
        $foundKey = $false
        $urlPat = [regex]'"ANTHROPIC_BASE_URL"\s*:\s*"([^"]{6,})"'
        $keyPat1 = [regex]'"ANTHROPIC_AUTH_TOKEN"\s*:\s*"([^"]{6,})"'
        $keyPat2 = [regex]'"ANTHROPIC_API_KEY"\s*:\s*"([^"]{6,})"'

        while ($true) {
            $n = $fs.Read($buffer, 0, $chunkSize)
            if ($n -le 0) { break }
            $chunkText = [Text.Encoding]::UTF8.GetString($buffer, 0, $n)
            $window = $tail + $chunkText
            if (-not $foundUrl -and $urlPat.IsMatch($window)) { $foundUrl = $true }
            if (-not $foundKey -and ($keyPat1.IsMatch($window) -or $keyPat2.IsMatch($window))) { $foundKey = $true }
            if ($foundUrl -and $foundKey) { exit 0 }
            # Carry the tail to handle keys that straddle the chunk boundary
            if ($window.Length -gt $overlap) {
                $tail = $window.Substring($window.Length - $overlap)
            } else {
                $tail = $window
            }
        }
    } finally {
        $fs.Close()
    }
} catch {}

exit 1
