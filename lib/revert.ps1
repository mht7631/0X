# chain-forge revert — complete: restores backups, strips kit keys when no
# prior config existed, removes the watchdog task and stamps.
param(
    [Parameter(Mandatory = $true)][string]$OcHome,
    [string]$BackupStamp
)

$ErrorActionPreference = 'Stop'
$backupRoot = Join-Path $OcHome '.persona-kit-backups'

if ([string]::IsNullOrWhiteSpace($BackupStamp)) {
    $latest = Join-Path $OcHome '.chain-forge\last-manifest.json'
    if (-not (Test-Path -LiteralPath $latest)) {
        $latest = Join-Path $OcHome '.persona-kit\last-manifest.json'
    }
    if (-not (Test-Path -LiteralPath $latest)) {
        throw "No last-manifest.json — run install first or pass -BackupStamp yyyyMMdd-HHmmss"
    }
    $meta = Get-Content -LiteralPath $latest -Raw | ConvertFrom-Json
    $backupDir = $meta.backupDir
} else {
    $backupDir = Join-Path $backupRoot $BackupStamp
}

$manifestPath = Join-Path $backupDir 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "manifest not found: $manifestPath" }

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$restoredConfig = $false
foreach ($rel in $manifest.files) {
    $src = Join-Path $backupDir $rel
    if (-not (Test-Path -LiteralPath $src)) { continue }
    $dest = Join-Path $OcHome $rel
    $parent = Split-Path $dest -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dest -Force -Recurse
    if ($rel -match '^opencode\.json') { $restoredConfig = $true }
    Write-Host "[restored] $rel"
}

# No pre-existing config in the backup: the merged file is kit-made. Strip
# kit-owned keys so OpenCode does not try to load a deleted plugin.
$jsonPath = Join-Path $OcHome 'opencode.json'
if (-not $restoredConfig -and (Test-Path -LiteralPath $jsonPath)) {
    try {
        $cfg = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
        $h = @{}
        foreach ($p in $cfg.PSObject.Properties) { $h[$p.Name] = $p.Value }
        if ($h['default_agent'] -eq '0x' -or $h['default_agent'] -eq 'v' -or $h['default_agent'] -eq 'galaxy') { $h.Remove('default_agent') }
        foreach ($pk in @('plugin', 'plugins')) {
            if ($h.Contains($pk)) {
                $kept = @($h[$pk] | Where-Object { [string]$_ -notmatch 'chain-forge|chain-lock' })
                if ($kept.Count -gt 0) { $h[$pk] = $kept } else { $h.Remove($pk) }
            }
        }
        if ($h.Contains('instructions')) {
            $kept = @($h['instructions'] | Where-Object { [string]$_ -notmatch '\.config[/\\]opencode[/\\](AGENTS\.md|persona|chain)' })
            if ($kept.Count -gt 0) { $h['instructions'] = $kept } else { $h.Remove('instructions') }
        }
        if ($h.Contains('permission')) {
            $perm = $h['permission']
            if ($perm.edit -eq 'allow' -and $perm.bash -eq 'allow' -and $perm.webfetch -eq 'allow') { $h.Remove('permission') }
        }
        ($h | ConvertTo-Json -Depth 100) | Set-Content -LiteralPath $jsonPath -Encoding UTF8
        Write-Host "[stripped] kit-owned keys from opencode.json"
    } catch {
        Write-Warning "config strip failed: $($_.Exception.Message) — remove chain-forge keys by hand"
    }
}

# Watchdog task must not resurrect the chain after a deliberate revert.
$task = Get-ScheduledTask -TaskName 'ChainForgeHeal' -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName 'ChainForgeHeal' -Confirm:$false
    Write-Host "[removed] ChainForgeHeal watchdog task"
}

foreach ($stampPath in @((Join-Path $OcHome '.chain-forge'), (Join-Path $OcHome '.persona-kit'))) {
    if (Test-Path -LiteralPath $stampPath) { Remove-Item -LiteralPath $stampPath -Recurse -Force }
}

# Kit payload dirs whose content was not in the backup (fresh-machine install)
# must go, or a stripped config still finds files.
foreach ($dir in @('chain', 'plugins\chain-forge', 'plugins\chain-lock', 'agent', 'agents', 'command', 'commands')) {
    $p = Join-Path $OcHome $dir
    $hadBackup = $manifest.files -contains $dir
    if (-not $hadBackup -and (Test-Path -LiteralPath $p)) {
        Remove-Item -LiteralPath $p -Recurse -Force
        Write-Host "[removed] $dir (no pre-install backup existed)"
    }
}

Write-Host "[ok] reverted from $backupDir — restart OpenCode"
