# Extract ANTHROPIC_BASE_URL and ANTHROPIC_AUTH_TOKEN from cc-switch.db
# Usage: powershell -File extract-config.ps1 <db_path> <out_url> <out_key>
param(
    [Parameter(Mandatory=$true)][string]$DbPath,
    [Parameter(Mandatory=$true)][string]$OutUrl,
    [Parameter(Mandatory=$true)][string]$OutKey
)

if (-not (Test-Path $DbPath)) { exit 1 }

# Try System.Data.SQLite (precise — only reads active provider, no stale data)
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
        $e = $cfg.env
        $url = $e.ANTHROPIC_BASE_URL
        $key = if ($e.ANTHROPIC_AUTH_TOKEN) { $e.ANTHROPIC_AUTH_TOKEN } else { $e.ANTHROPIC_API_KEY }
        if ($url -and $key) {
            [IO.File]::WriteAllText($OutUrl, $url)
            [IO.File]::WriteAllText($OutKey, $key)
            exit 0
        }
    }
    exit 1
} catch {}

# Fallback: regex on file content (handles cases where System.Data.SQLite is missing)
try {
    $fs = [IO.FileStream]::new($DbPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $bytes = New-Object byte[] $fs.Length
    [void]$fs.Read($bytes, 0, $fs.Length)
    $fs.Close()

    $text = [Text.Encoding]::UTF8.GetString($bytes)

    # Find ALL matches and use the LAST one (most recently written tends to be latest)
    $urlMatches = [regex]::Matches($text, '"ANTHROPIC_BASE_URL"\s*:\s*"([^"]+)"')
    $keyMatches = [regex]::Matches($text, '"ANTHROPIC_AUTH_TOKEN"\s*:\s*"([^"]+)"')
    if ($keyMatches.Count -eq 0) {
        $keyMatches = [regex]::Matches($text, '"ANTHROPIC_API_KEY"\s*:\s*"([^"]+)"')
    }

    if ($urlMatches.Count -gt 0 -and $keyMatches.Count -gt 0) {
        $url = $urlMatches[$urlMatches.Count - 1].Groups[1].Value
        $key = $keyMatches[$keyMatches.Count - 1].Groups[1].Value
        [IO.File]::WriteAllText($OutUrl, $url)
        [IO.File]::WriteAllText($OutKey, $key)
        exit 0
    }
} catch {}

exit 1
