# Check if cc-switch.db has at least one configured provider
# Exit 0 if found, 1 otherwise
param([Parameter(Mandatory=$true)][string]$DbPath)

if (-not (Test-Path $DbPath)) { exit 1 }

# Try System.Data.SQLite first (precise SQL query, no false positives from deleted rows)
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

# Fallback: regex on binary content (may have false positives from deleted rows
# but very unlikely in practice — SQLite typically reuses pages)
try {
    $fs = [IO.FileStream]::new($DbPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $bytes = New-Object byte[] $fs.Length
    [void]$fs.Read($bytes, 0, $fs.Length)
    $fs.Close()

    $text = [Text.Encoding]::UTF8.GetString($bytes)

    $url = [regex]::Match($text, '"ANTHROPIC_BASE_URL"\s*:\s*"([^"]+)"')
    $key = [regex]::Match($text, '"ANTHROPIC_AUTH_TOKEN"\s*:\s*"([^"]+)"')
    if (-not $key.Success) {
        $key = [regex]::Match($text, '"ANTHROPIC_API_KEY"\s*:\s*"([^"]+)"')
    }

    if ($url.Success -and $key.Success -and $url.Groups[1].Value.Length -gt 5 -and $key.Groups[1].Value.Length -gt 5) {
        exit 0
    }
} catch {}

exit 1
