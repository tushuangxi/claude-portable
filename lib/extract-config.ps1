# Extract ANTHROPIC_BASE_URL and ANTHROPIC_AUTH_TOKEN from cc-switch.db
# Usage: powershell -File extract-config.ps1 <db_path> <out_url> <out_key>
param(
    [Parameter(Mandatory=$true)][string]$DbPath,
    [Parameter(Mandatory=$true)][string]$OutUrl,
    [Parameter(Mandatory=$true)][string]$OutKey
)

if (-not (Test-Path $DbPath)) { exit 1 }

# ── Strategy 1: System.Data.SQLite (precise SELECT) ──────────────────────────
# Only available if user has installed sqlite-net or similar.
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

# ── Strategy 2: shell out to sqlite3.exe if on PATH ──────────────────────────
# Git for Windows ships sqlite3.exe; Python users may have it too.
try {
    $sqlite = Get-Command sqlite3.exe -ErrorAction Stop
    if ($sqlite) {
        $sql = "SELECT settings_config FROM providers WHERE app_type='claude' AND is_current=1 LIMIT 1;"
        $row = & $sqlite.Source $DbPath $sql 2>$null
        if ($LASTEXITCODE -eq 0 -and $row) {
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
    }
} catch {}

# ── Strategy 3: regex fallback (LAST RESORT, may be inaccurate) ──────────────
#
# WARNING: this fallback can return STALE credentials when the user has
# multiple providers in the DB. Reasons:
#   1. SQLite stores rows in physical page order, not insertion order
#   2. Deleted-but-not-vacuumed rows still match the regex
#   3. Picking the "last match" is just a heuristic
#
# We also CHECK if multiple providers are present and emit a warning to
# stderr. The launcher can decide whether to abort or proceed.
try {
    # Streamed read in 64KB chunks (don't load full DB into memory).
    $fs = [IO.FileStream]::new($DbPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $sb = [Text.StringBuilder]::new()
        $buf = New-Object byte[] 65536
        while ($true) {
            $n = $fs.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $n))
            # Cap to 50MB even if file is bigger — beyond that the fallback
            # is not going to help.
            if ($sb.Length -gt 50000000) { break }
        }
        $text = $sb.ToString()
    } finally {
        $fs.Close()
    }

    $urlMatches = [regex]::Matches($text, '"ANTHROPIC_BASE_URL"\s*:\s*"([^"]+)"')
    $keyMatches = [regex]::Matches($text, '"ANTHROPIC_AUTH_TOKEN"\s*:\s*"([^"]+)"')
    if ($keyMatches.Count -eq 0) {
        $keyMatches = [regex]::Matches($text, '"ANTHROPIC_API_KEY"\s*:\s*"([^"]+)"')
    }

    if ($urlMatches.Count -gt 0 -and $keyMatches.Count -gt 0) {
        if ($urlMatches.Count -gt 1 -or $keyMatches.Count -gt 1) {
            # Surface a warning so the user knows accuracy is degraded.
            # The CMD wrapper hides stderr so this is mostly for diagnostics.
            [Console]::Error.WriteLine("[warn] Multiple providers detected; selecting the last-stored one. Install Python or sqlite3.exe for accurate selection.")
        }
        $url = $urlMatches[$urlMatches.Count - 1].Groups[1].Value
        $key = $keyMatches[$keyMatches.Count - 1].Groups[1].Value
        [IO.File]::WriteAllText($OutUrl, $url)
        [IO.File]::WriteAllText($OutKey, $key)
        exit 0
    }
} catch {}

exit 1
