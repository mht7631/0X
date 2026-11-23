# 0x INJECT AI watchdog body. Runs from the ChainForgeHeal logon task (or menu).
# Restores drifted/deleted kit files from the kit root recorded at install,
# re-merges config if keys went missing. Never kills a running OpenCode —
# repaired files arm on its next start.
param(
    [string]$OcHome = (Join-Path $env:USERPROFILE '.config\opencode'),
    [switch]$Silent,
    [switch]$Notify
)

$ErrorActionPreference = 'Continue'
$forge = Join-Path $OcHome '.chain-forge'
$logFile = Join-Path $forge 'heal.log'

function Show-HealToast([int]$count) {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $ni = New-Object System.Windows.Forms.NotifyIcon
        $ni.Icon = [System.Drawing.SystemIcons]::Information
        $ni.Visible = $true
        $ni.ShowBalloonTip(5000, '0x INJECT AI', "chain healed — $count repair(s) applied", [System.Windows.Forms.ToolTipIcon]::Info)
        Start-Sleep -Seconds 2
        $ni.Dispose()
    } catch { }
}

function Log([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    try { Add-Content -LiteralPath $logFile -Value $line } catch { }
    if (-not $Silent) { Write-Host $line }
}

$stampFile = Join-Path $forge 'install.json'
if (-not (Test-Path -LiteralPath $stampFile)) { Log 'no install stamp — nothing to heal against'; exit 0 }
$stamp = Get-Content -LiteralPath $stampFile -Raw | ConvertFrom-Json
$KitRoot = $stamp.kitRoot
if (-not (Test-Path -LiteralPath $KitRoot)) { Log "kit root gone ($KitRoot) — cannot heal"; exit 1 }

$repairs = 0

# 0. Supersede holds: the other persona kit's agent files stay gone.
foreach ($stale in @(
    (Join-Path $OcHome 'agents\galaxy.md'),
    (Join-Path $OcHome 'agents\galaxy-repair.md'),
    (Join-Path $OcHome 'agent\galaxy.md'),
    (Join-Path $OcHome 'agent\galaxy-repair.md')
)) {
    if (Test-Path -LiteralPath $stale) {
        Remove-Item -LiteralPath $stale -Force
        Log "[heal] re-removed superseded agent file: $stale"
        $repairs++
    }
}

# 1. AGENTS.md: restore only if MISSING (operator edits are respected).
if (-not (Test-Path -LiteralPath (Join-Path $OcHome 'AGENTS.md'))) {
    Copy-Item (Join-Path $KitRoot 'forge\persona\AGENTS.md') (Join-Path $OcHome 'AGENTS.md') -Force
    Log '[heal] AGENTS.md was missing — restored'
    $repairs++
}

# 2. Hash drift on chain / agents / commands / plugins / persona short file.
$hashFile = Join-Path $forge 'hashes.json'
if (Test-Path -LiteralPath $hashFile) {
    $hashes = Get-Content -LiteralPath $hashFile -Raw | ConvertFrom-Json
    foreach ($p in $hashes.PSObject.Properties) {
        $target = Join-Path $OcHome $p.Name
        $bad = $false
        if (-not (Test-Path -LiteralPath $target)) { $bad = $true }
        elseif ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLower() -ne $p.Value) { $bad = $true }
        if ($bad) {
            # Map the oc-relative path back onto the forge tree.
            $rel = $p.Name -replace '^agent(s)?[\\/]', 'agents\' -replace '^command(s)?[\\/]', 'commands\'
            $src = Join-Path $KitRoot "forge\$rel"
            if (Test-Path -LiteralPath $src) {
                $parent = Split-Path $target -Parent
                if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
                Copy-Item -LiteralPath $src -Destination $target -Force
                Log "[heal] restored drifted file: $($p.Name)"
                $repairs++
            }
        }
    }
}

# 3. Config keys.
$jsonPath = Join-Path $OcHome 'opencode.json'
$needMerge = $false
if (Test-Path -LiteralPath $jsonPath) {
    try {
        $cfg = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
        if ($cfg.default_agent -ne '0x') { $needMerge = $true }
        $plugged = (@($cfg.plugin) + @($cfg.plugins) | Where-Object { [string]$_ -match 'chain-forge' }).Count -gt 0
        if (-not $plugged) { $needMerge = $true }
        if (@($cfg.instructions).Count -lt 3) { $needMerge = $true }
    } catch { $needMerge = $true }
} else { $needMerge = $true }

if ($needMerge) {
    & (Join-Path $KitRoot 'lib\merge-config.ps1') -OcHome $OcHome -FragmentPath (Join-Path $KitRoot 'forge\opencode.fragment.json')
    Log '[heal] re-merged opencode.json fragment'
    $repairs++
}

# 4. Refresh hashes after any repair so healed state is the new baseline.
if ($repairs -gt 0) {
    $newHashes = @{}
    foreach ($rel in @('chain', 'agents', 'agent', 'commands', 'command', 'plugins\chain-forge', 'persona\MUST-FOLLOW.md')) {
        $p = Join-Path $OcHome $rel
        if (-not (Test-Path -LiteralPath $p)) { continue }
        Get-ChildItem -LiteralPath $p -Recurse -File | ForEach-Object {
            $r = $_.FullName.Substring($OcHome.Length).TrimStart('\')
            $newHashes[$r] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower()
        }
    }
    $newHashes | ConvertTo-Json | Set-Content -LiteralPath $hashFile -Encoding UTF8
    Log "[heal] $repairs repair(s); baseline refreshed. OpenCode picks files up on next start."
    if (-not $Silent) { Write-Host "[heal] $repairs repair(s) applied" -ForegroundColor Yellow }
    if ($Notify) { Show-HealToast $repairs }
} else {
    Log '[heal] chain intact — no repairs'
}
exit 0
