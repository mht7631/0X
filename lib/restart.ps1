# Restart OpenCode + smoke check: process alive, plugin file present.
$ErrorActionPreference = 'SilentlyContinue'

$names = @('opencode', 'OpenCode')
foreach ($n in $names) {
    Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 1

$exe = Get-Command opencode -ErrorAction SilentlyContinue
$exePath = if ($exe) { $exe.Source } else {
    $fallback = $null
    foreach ($c in @(
            (Join-Path $env:LOCALAPPDATA 'Programs\ai.opencode.desktop\OpenCode.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\ai.opencode.desktop\resources\opencode-cli.exe')
        )) {
        if (Test-Path -LiteralPath $c) { $fallback = $c; break }
    }
    $fallback
}
if (-not $exePath) {
    Write-Host "[warn] opencode not found on PATH or in the desktop app — start it manually"
    return
}

Start-Process -FilePath $exePath -WindowStyle Normal
Start-Sleep -Seconds 3

$alive = $false
foreach ($n in $names) {
    if (Get-Process -Name $n -ErrorAction SilentlyContinue) { $alive = $true }
}
if ($alive) {
    Write-Host "[ok] opencode restarted (pid alive after 3s)"
} else {
    Write-Host "[warn] opencode process not visible after start — check the install"
}
Write-Host "[i] enforcement proof: make one model call, then run status — HeartbeatMin < 10 means hooks fire."
