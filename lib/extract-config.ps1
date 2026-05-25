# Extract ANTHROPIC_BASE_URL and ANTHROPIC_AUTH_TOKEN from cc-switch.db
# Usage: powershell -File extract-config.ps1 <db_path> <out_url> <out_key>
# Exits 0 on success, 1 on failure.

param(
    [Parameter(Mandatory=$true)][string]$DbPath,
    [Parameter(Mandatory=$true)][string]$OutUrl,
    [Parameter(Mandatory=$true)][string]$OutKey
)

if (-not (Test-Path $DbPath)) { exit 1 }

try {
    $bytes = [IO.File]::ReadAllBytes($DbPath)
    $text = [Text.Encoding]::UTF8.GetString($bytes)

    # Find all settings_config JSON blobs and extract the active claude one
    # SQLite stores them as raw text in the file
    $urlMatch = [regex]::Match($text, '"ANTHROPIC_BASE_URL"\s*:\s*"([^"]+)"')
    $keyMatch = [regex]::Match($text, '"ANTHROPIC_AUTH_TOKEN"\s*:\s*"([^"]+)"')
    if (-not $keyMatch.Success) {
        $keyMatch = [regex]::Match($text, '"ANTHROPIC_API_KEY"\s*:\s*"([^"]+)"')
    }

    if ($urlMatch.Success -and $keyMatch.Success) {
        [IO.File]::WriteAllText($OutUrl, $urlMatch.Groups[1].Value)
        [IO.File]::WriteAllText($OutKey, $keyMatch.Groups[1].Value)
        exit 0
    }
} catch {}

exit 1
