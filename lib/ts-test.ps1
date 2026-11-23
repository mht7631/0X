# 0x — run the headless TypeScript unit test for the injection engine.
# Needs a bun runtime: PATH bun, or the desktop app's bun-compiled CLI used as
# bun via BUN_BE_BUN=1 (works on machines without a separate bun install).
param(
    [string]$KitRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$TestFile = ''
)

$ErrorActionPreference = 'Stop'
$E = [char]27
$C_OK = "${E}[38;2;120;220;120m"; $C_BAD = "${E}[38;2;255;110;80m"
$C_TXT = "${E}[38;2;170;170;170m"; $C_KEY = "${E}[38;2;205;168;255m"; $C_R = "${E}[0m"
if ($env:NO_COLOR) { $C_OK = ''; $C_BAD = ''; $C_TXT = ''; $C_KEY = ''; $C_R = '' }

if (-not $TestFile) { $TestFile = Join-Path $KitRoot 'tests\inject.test.ts' }
if (-not (Test-Path -LiteralPath $TestFile)) { throw "test file not found: $TestFile" }

$bun = Get-Command bun -ErrorAction SilentlyContinue
$runner = $null
if ($bun) {
    $runner = $bun.Source
} else {
    foreach ($c in @(
            (Join-Path $env:LOCALAPPDATA 'Programs\ai.opencode.desktop\resources\opencode-cli.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\ai.opencode.desktop\OpenCode.exe')
        )) {
        if (Test-Path -LiteralPath $c) { $runner = $c; break }
    }
}

Write-Host ''
Write-Host "  ${C_KEY}0x INJECT AI — unit test${C_R}"
Write-Host ''
if (-not $runner) {
    Write-Host "  ${C_BAD}SKIP${C_R}  ${C_TXT}no bun runtime and no desktop CLI found${C_R}"
    Write-Host ''
    exit 2
}

# The desktop CLI is a bun single-file binary: BUN_BE_BUN=1 makes it act as bun.
$env:BUN_BE_BUN = '1'
Write-Host "  ${C_TXT}runner: $runner${C_R}"
Write-Host ''
& $runner run $TestFile
$code = $LASTEXITCODE
Write-Host ''
if ($code -eq 0) { Write-Host "  ${C_OK}PASS${C_R}  ${C_TXT}engine unit test${C_R}" }
else { Write-Host "  ${C_BAD}FAIL${C_R}  ${C_TXT}engine unit test (exit $code)${C_R}" }
Write-Host ''
exit $code
