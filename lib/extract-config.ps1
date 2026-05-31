# Extract ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN / ANTHROPIC_MODEL from cc-switch.db
# Writes URL on line 1, key on line 2, model on line 3 (omitted if empty)
# to stdout. Exit 0 on success, 1 otherwise.
#
# Why model matters: the config center lets users pick a model (e.g.
# deepseek-v4-pro). cc-switch stores it as ANTHROPIC_MODEL. If the
# launcher doesn't pass it through, Claude Code falls back to its built-in
# default name (Opus 4.8) in the UI even though requests go to the
# configured endpoint — confusing users into thinking the wrong model
# is active. Emitting it here lets the .bat export it before launch.
#
# Why stdout instead of temp files: writing the API key to %TEMP%\*.txt
# leaks it indefinitely if the launcher crashes between write and delete.
# Windows doesn't clean %TEMP% reliably; some users see files from months ago.
# Using stdout, the key only lives in process memory.
#
# Usage: powershell -File extract-config.ps1 <db_path>
param(
    [Parameter(Mandatory=$true)][string]$DbPath
)

if (-not (Test-Path $DbPath)) { exit 1 }

# Helper: emit URL + key (+ optional model) on stdout if URL and key
# both look valid, then exit 0.
# Force ASCII output via raw byte writes — UTF-8 output without BOM
# avoids cmd's `for /f` picking up encoding garbage in the first line.
# API URLs and auth tokens are ASCII anyway.
function Emit-Pair {
    param([string]$Url, [string]$Key, [string]$Model)
    if (-not $Url -or -not $Key) { return $false }
    $u = $Url.Trim()
    $k = $Key.Trim()
    $m = if ($Model) { $Model.Trim() } else { "" }
    if ($u.Length -lt 6 -or $k.Length -lt 6) { return $false }
    # Refuse multi-line content — defense against injection if cc-switch
    # ever stored a value containing a newline. cmd's `set "X=..."`
    # would only get the first line, but we'd rather fail loud.
    if ($u -match "[\r\n]" -or $k -match "[\r\n]") { return $false }
    # Reject non-ASCII to avoid encoding mismatches between PS / cmd.
    # In practice API keys/URLs are ASCII; if not, the user has a bigger
    # problem than this script.
    if ($u -match "[^\x20-\x7e]" -or $k -match "[^\x20-\x7e]") { return $false }
    # Model name: only emit if it's clean single-line ASCII. A bad model
    # value must not block launch — just drop it and let Claude default.
    if ($m -match "[\r\n]" -or $m -match "[^\x20-\x7e]") { $m = "" }
    [Console]::Out.WriteLine($u)
    [Console]::Out.WriteLine($k)
    [Console]::Out.WriteLine($m)
    return $true
}

# ── Strategy 1: System.Data.SQLite (precise SELECT) ──────────────────────────
try {
    Add-Type -AssemblyName System.Data.SQLite -ErrorAction Stop
    $cs = "Data Source=$DbPath;Read Only=True;"
    $conn = [System.Data.SQLite.SQLiteConnection]::new($cs)
    $conn.Open()
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT settings_config FROM providers WHERE app_type='claude' AND is_current=1 LIMIT 1"
        $row = $cmd.ExecuteScalar()
    } finally {
        $conn.Close()
        $conn.Dispose()
    }
    if ($row) {
        $cfg = $row | ConvertFrom-Json
        $e = $cfg.env
        $url = $e.ANTHROPIC_BASE_URL
        $key = if ($e.ANTHROPIC_AUTH_TOKEN) { $e.ANTHROPIC_AUTH_TOKEN } else { $e.ANTHROPIC_API_KEY }
        $model = $e.ANTHROPIC_MODEL
        if (Emit-Pair $url $key $model) { exit 0 }
    }
} catch {}

# ── Strategy 2: shell out to sqlite3.exe if on PATH ──────────────────────────
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
            $model = $e.ANTHROPIC_MODEL
            if (Emit-Pair $url $key $model) { exit 0 }
        }
    }
} catch {}

# ── Strategy 3: regex fallback (LAST RESORT) ────────────────────────────────
#
# WARNING: this fallback can return STALE credentials when the user has
# multiple providers in the DB. Reasons:
#   1. SQLite stores rows in physical page order, not insertion order
#   2. Deleted-but-not-vacuumed rows still match the regex
#   3. Picking the "last match" is just a heuristic
try {
    # Streamed read in 64KB chunks (don't load full DB into memory).
    # Carry up to 4 trailing bytes across iterations so multi-byte UTF-8
    # sequences split across chunk boundaries decode correctly. Without
    # this, GetString would emit U+FFFD on either side of every boundary,
    # silently corrupting non-ASCII data near every 64KB mark.
    $fs = [IO.FileStream]::new($DbPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $sb = [Text.StringBuilder]::new()
        $buf = New-Object byte[] 65536
        $byteTail = New-Object byte[] 0
        $byteOverlap = 4
        while ($true) {
            $n = $fs.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            $combined = New-Object byte[] ($byteTail.Length + $n)
            [Array]::Copy($byteTail, 0, $combined, 0, $byteTail.Length)
            [Array]::Copy($buf,      0, $combined, $byteTail.Length, $n)
            $reserve = [Math]::Min($byteOverlap, $combined.Length)
            $decodeLen = $combined.Length - $reserve
            if ($decodeLen -gt 0) {
                [void]$sb.Append([Text.Encoding]::UTF8.GetString($combined, 0, $decodeLen))
            }
            $byteTail = New-Object byte[] $reserve
            [Array]::Copy($combined, $decodeLen, $byteTail, 0, $reserve)
            # Cap to 50MB even if file is bigger — beyond that the fallback
            # is not going to help.
            if ($sb.Length -gt 50000000) { break }
        }
        # Flush remaining byteTail (final chars at end of file)
        if ($byteTail.Length -gt 0) {
            [void]$sb.Append([Text.Encoding]::UTF8.GetString($byteTail))
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
    $modelMatches = [regex]::Matches($text, '"ANTHROPIC_MODEL"\s*:\s*"([^"]+)"')

    if ($urlMatches.Count -gt 0 -and $keyMatches.Count -gt 0) {
        if ($urlMatches.Count -gt 1 -or $keyMatches.Count -gt 1) {
            [Console]::Error.WriteLine("[warn] Multiple providers detected; picking last-stored. Install Python or sqlite3.exe for accurate selection.")
        }
        $url = $urlMatches[$urlMatches.Count - 1].Groups[1].Value
        $key = $keyMatches[$keyMatches.Count - 1].Groups[1].Value
        # Model is best-effort in the fallback: pick the last match if any.
        # It may not correspond to the same provider as url/key when the
        # DB has multiple rows, but a wrong/empty model only affects the
        # display name, never the endpoint the request hits.
        $model = ""
        if ($modelMatches.Count -gt 0) {
            $model = $modelMatches[$modelMatches.Count - 1].Groups[1].Value
        }
        if (Emit-Pair $url $key $model) { exit 0 }
    }
} catch {}

exit 1
