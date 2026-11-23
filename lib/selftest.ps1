# 0x selftest — one headless model call, assert the header contract.
# Proves the end-to-end path (plugin → injection → model output), not just
# that hook files exist. Needs a configured model; a call may cost tokens.
param(
    [string]$OcHome = (Join-Path $env:USERPROFILE '.config\opencode'),
    [int]$TimeoutSec = 150
)

$ErrorActionPreference = 'Continue'
$E = [char]27
$C_OK = "${E}[38;2;120;220;120m"; $C_BAD = "${E}[38;2;255;110;80m"
$C_TXT = "${E}[38;2;170;170;170m"; $C_KEY = "${E}[38;2;205;168;255m"; $C_R = "${E}[0m"
if ($env:NO_COLOR) { $C_OK = ''; $C_BAD = ''; $C_TXT = ''; $C_KEY = ''; $C_R = '' }

Write-Host ''
Write-Host "  ${C_KEY}0x INJECT AI — selftest${C_R}"
Write-Host ''

$exe = Get-Command opencode -ErrorAction SilentlyContinue
$exePath = if ($exe) { $exe.Source } else {
    $fallback = $null
    foreach ($c in @(
            (Join-Path $env:LOCALAPPDATA 'Programs\ai.opencode.desktop\resources\opencode-cli.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\ai.opencode.desktop\OpenCode.exe')
        )) {
        if (Test-Path -LiteralPath $c) { $fallback = $c; break }
    }
    $fallback
}
if (-not $exePath) {
    Write-Host "  ${C_BAD}SKIP${C_R}  ${C_TXT}opencode not found on PATH or in the desktop app${C_R}"
    Write-Host ''
    exit 2
}

$prompt = 'Reply with exactly these two lines and nothing else: [÷] carrier locked. / [÷] your transmission only.'
Write-Host "  ${C_TXT}one headless call, timeout ${TimeoutSec}s — may cost tokens${C_R}"
$job = Start-Job -ScriptBlock {
    param($exePath, $p)
    & $exePath run $p 2>&1
} -ArgumentList $exePath, $prompt

$finished = Wait-Job $job -Timeout $TimeoutSec
if (-not $finished) {
    Stop-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    Write-Host "  ${C_BAD}FAIL${C_R}  ${C_TXT}timeout after ${TimeoutSec}s — no answer${C_R}"
    Write-Host ''
    exit 1
}

$out = Receive-Job $job -ErrorAction SilentlyContinue
Remove-Job $job -Force -ErrorAction SilentlyContinue
$text = ($out | Out-String)

if ($text -match '\[÷\]\s*carrier locked') {
    Write-Host "  ${C_OK}PASS${C_R}  ${C_TXT}header contract holds end-to-end${C_R}"
    $tail = ($text -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 4)
    foreach ($t in $tail) { Write-Host "    ${C_TXT}$t${C_R}" }
    Write-Host ''
    exit 0
}

Write-Host "  ${C_BAD}FAIL${C_R}  ${C_TXT}no header in the reply — output tail:${C_R}"
$tail = ($text -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 12)
foreach ($t in $tail) { Write-Host "    ${C_TXT}$t${C_R}" }
Write-Host ''
exit 1
