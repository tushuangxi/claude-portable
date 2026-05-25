# Check if cc-switch.db has at least one configured provider
# Exit 0 if found, 1 otherwise
param([Parameter(Mandatory=$true)][string]$DbPath)

if (-not (Test-Path $DbPath)) { exit 1 }

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

    # Both must exist AND have non-empty values
    if ($url.Success -and $key.Success -and $url.Groups[1].Value.Length -gt 5 -and $key.Groups[1].Value.Length -gt 5) {
        exit 0
    }
} catch {}

exit 1
