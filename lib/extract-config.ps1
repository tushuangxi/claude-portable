# Extract ANTHROPIC_BASE_URL and ANTHROPIC_AUTH_TOKEN from cc-switch.db
# Usage: powershell -File extract-config.ps1 <db_path> <out_url> <out_key>
param(
    [Parameter(Mandatory=$true)][string]$DbPath,
    [Parameter(Mandatory=$true)][string]$OutUrl,
    [Parameter(Mandatory=$true)][string]$OutKey
)

if (-not (Test-Path $DbPath)) { exit 1 }

try {
    # Open with FileShare.ReadWrite so we don't conflict with cc-switch holding the file
    $fs = [IO.FileStream]::new($DbPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $bytes = New-Object byte[] $fs.Length
    [void]$fs.Read($bytes, 0, $fs.Length)
    $fs.Close()

    $text = [Text.Encoding]::UTF8.GetString($bytes)

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
