# 0x INJECT AI — full install. Backup -> copy -> render SEAL -> hashes ->
# merge -> validate -> stamp -> post-check (auto-rollback on failure) -> prune.
param(
    [Parameter(Mandatory = $true)][string]$KitRoot,
    [Parameter(Mandatory = $true)][string]$OcHome,
    [Parameter(Mandatory = $true)][string]$BackupRoot,
    [switch]$ForceAgentsMd,
    [switch]$SkipRestart,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $BackupRoot $stamp
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

$manifest = [ordered]@{ timestamp = $stamp; backupDir = $backupDir; kitRoot = $KitRoot; files = @() }

# --- preflight (warn, never block a working kit) ---
if ($PSVersionTable.PSVersion.Major -lt 5) { throw 'PowerShell 5.1+ required' }
if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) {
    Write-Host '[warn] opencode not on PATH — install continues; verify after starting it' -ForegroundColor Yellow
}
$fragPath = Join-Path $KitRoot 'forge\opencode.fragment.json'
try { [void](Get-Content -LiteralPath $fragPath -Raw | ConvertFrom-Json) } catch { throw "fragment unreadable: $($_.Exception.Message)" }
foreach ($req in @('forge\persona\AGENTS.md', 'forge\plugins\chain-forge\inject.config.json', 'forge\plugins\chain-forge\payloads')) {
    if (-not (Test-Path -LiteralPath (Join-Path $KitRoot $req))) { throw "kit incomplete: missing $req" }
}

function Backup-IfExists([string]$Rel) {
    $src = Join-Path $OcHome $Rel
    if (-not (Test-Path -LiteralPath $src)) { return }
    $dest = Join-Path $backupDir $Rel
    $parent = Split-Path $dest -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dest -Force -Recurse
    $manifest.files += $Rel
}

function Copy-Contents([string]$RelFromForge, [string]$RelToOc) {
    $src = Join-Path $KitRoot $RelFromForge
    $dest = Join-Path $OcHome $RelToOc
    if (-not (Test-Path -LiteralPath $src)) { Write-Warning "missing forge path: $src"; return }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Get-ChildItem -LiteralPath $src | Copy-Item -Destination $dest -Recurse -Force
    Write-Host "[ok] $RelToOc"
}

Write-Host ""
Write-Host "=== 0x INJECT AI: install ===" -ForegroundColor Cyan

# --- backup everything the install can touch ---
Backup-IfExists 'AGENTS.md'
Backup-IfExists 'opencode.json'
Backup-IfExists 'opencode.jsonc'
Backup-IfExists 'chain'
Backup-IfExists 'commands'
Backup-IfExists 'command'
Backup-IfExists 'agents'
Backup-IfExists 'agent'
Backup-IfExists 'plugins\chain-forge'
Backup-IfExists 'plugins\chain-lock'
Backup-IfExists 'persona\MUST-FOLLOW.md'

# --- persona ---
New-Item -ItemType Directory -Force -Path (Join-Path $OcHome 'persona') | Out-Null
Copy-Item (Join-Path $KitRoot 'forge\persona\MUST-FOLLOW.md') (Join-Path $OcHome 'persona\MUST-FOLLOW.md') -Force

$agentsSrc = Join-Path $KitRoot 'forge\persona\AGENTS.md'
$agentsDst = Join-Path $OcHome 'AGENTS.md'
if ($ForceAgentsMd -or -not (Test-Path -LiteralPath $agentsDst)) {
    Copy-Item $agentsSrc $agentsDst -Force
    Write-Host "[ok] V AGENTS.md installed"
} else {
    Write-Host "[skip] AGENTS.md exists — repair (menu 2, answer y) to overwrite"
}

# --- agents: dual-directory cover (agent/ and agents/ spellings across hosts) ---
Copy-Contents 'forge\agents' 'agents'
Copy-Contents 'forge\agents' 'agent'

# --- commands: dual-directory cover ---
Copy-Contents 'forge\commands' 'commands'
Copy-Contents 'forge\commands' 'command'

# --- chain static layer ---
Copy-Contents 'forge\chain' 'chain'

# --- plugin ---
Copy-Contents 'forge\plugins\chain-forge' 'plugins\chain-forge'

# --- supersede: one persona owns the bench. Remove the other kit's agents
#     and the retired v3 plugin so the picker and the spine carry V only. ---
foreach ($stale in @(
    (Join-Path $OcHome 'agents\galaxy.md'),
    (Join-Path $OcHome 'agents\galaxy-repair.md'),
    (Join-Path $OcHome 'agent\galaxy.md'),
    (Join-Path $OcHome 'agent\galaxy-repair.md'),
    (Join-Path $OcHome 'agents\v.md'),
    (Join-Path $OcHome 'agents\v-repair.md'),
    (Join-Path $OcHome 'agent\v.md'),
    (Join-Path $OcHome 'agent\v-repair.md')
)) {
    if (Test-Path -LiteralPath $stale) {
        Remove-Item -LiteralPath $stale -Force
        Write-Host "[supersede] removed $stale" -ForegroundColor Yellow
    }
}
$oldPlugin = Join-Path $OcHome 'plugins\chain-lock'
if (Test-Path -LiteralPath $oldPlugin) {
    Remove-Item -LiteralPath $oldPlugin -Recurse -Force
    Write-Host "[supersede] removed retired chain-lock v3 plugin" -ForegroundColor Yellow
}

# --- render 02-SEAL.md stems section from stems.json (single source) ---
$stemsPath = Join-Path $OcHome 'plugins\chain-forge\stems.json'
$sealPath  = Join-Path $OcHome 'chain\02-SEAL.md'
try {
    $stems = (Get-Content -LiteralPath $stemsPath -Raw | ConvertFrom-Json).stems
    $seal  = [System.IO.File]::ReadAllText($sealPath)
    $bullets = ($stems | ForEach-Object { "- /$_/i" }) -join "`n"
    $pattern = '(?s)<!-- stems:begin[^>]*-->.*?<!-- stems:end -->'
    $replacement = "<!-- stems:begin — regenerated from plugins/chain-forge/stems.json; edit the json, not this section -->`n$bullets`n<!-- stems:end -->"
    $seal = [regex]::Replace($seal, $pattern, $replacement)
    [System.IO.File]::WriteAllText($sealPath, $seal, [System.Text.UTF8Encoding]::new($false))
    Write-Host "[ok] 02-SEAL.md rendered from stems.json ($($stems.Count) stems)"
} catch {
    Write-Warning "SEAL render skipped: $($_.Exception.Message)"
}

# --- hashes manifest for watchdog drift detection (AGENTS.md excluded: operator-editable) ---
$hashFile = Join-Path $OcHome '.chain-forge\hashes.json'
New-Item -ItemType Directory -Force -Path (Join-Path $OcHome '.chain-forge') | Out-Null
$hashes = @{}
foreach ($rel in @('chain', 'agents', 'agent', 'commands', 'command', 'plugins\chain-forge', 'persona\MUST-FOLLOW.md')) {
    $p = Join-Path $OcHome $rel
    if (-not (Test-Path -LiteralPath $p)) { continue }
    Get-ChildItem -LiteralPath $p -Recurse -File | ForEach-Object {
        $r = $_.FullName.Substring($OcHome.Length).TrimStart('\')
        $hashes[$r] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower()
    }
}
$hashes | ConvertTo-Json | Set-Content -LiteralPath $hashFile -Encoding UTF8
Write-Host "[ok] hashes.json ($($hashes.Count) files tracked)"

# --- config merge + validation ---
& (Join-Path $KitRoot 'lib\merge-config.ps1') -OcHome $OcHome -FragmentPath (Join-Path $KitRoot 'forge\opencode.fragment.json')
$jsonPath = Join-Path $OcHome 'opencode.json'
try { [void](Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json) } catch { throw "opencode.json invalid after merge: $($_.Exception.Message)" }

# --- supersede in config: drop the other kit's keys and the retired "v" id ---
try {
    $cfg = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
    $dirty = $false
    foreach ($pk in @('agent', 'agents')) {
        if ($cfg.PSObject.Properties.Name -contains $pk -and $cfg.$pk) {
            foreach ($gid in @('galaxy', 'galaxy-repair', 'v', 'v-repair')) {
                if ($cfg.$pk.PSObject.Properties.Name -contains $gid) {
                    $cfg.$pk.PSObject.Properties.Remove($gid)
                    $dirty = $true
                    Write-Host "[supersede] removed config key $pk.$gid" -ForegroundColor Yellow
                }
            }
        }
    }
    if ($dirty) {
        ($cfg | ConvertTo-Json -Depth 100) | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    }
} catch {
    Write-Warning "config supersede skipped: $($_.Exception.Message)"
}

# --- stamp (watchdog reads kitRoot from here) ---
$installStamp = [ordered]@{ kit = '5.1.0-v2-native'; installed = $stamp; kitRoot = $KitRoot }
$installStamp | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OcHome '.chain-forge\install.json') -Encoding UTF8
$manifestPath = Join-Path $backupDir 'manifest.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Copy-Item $manifestPath (Join-Path $OcHome '.chain-forge\last-manifest.json') -Force
Write-Host "[ok] backup: $backupDir"

# --- post-check: a failed install rolls itself back, never leaves a half-kit ---
try {
    $st = & (Join-Path $KitRoot 'lib\status.ps1') -OcHome $OcHome
    $st | Format-List
    if (-not $st.ChainFiles) { throw 'chain install failed' }
    if (-not $st.PluginSource) { throw 'plugin copy failed' }
    if ($st.AgentsBytes -lt 1000) { throw 'AGENTS.md too small — V bundle missing?' }
    if (-not $st.InjectProfile) { throw 'INJECT AI config missing from plugin dir' }
    if ($st.InjectPayloads -lt 1) { throw 'INJECT AI payload library missing' }
} catch {
    Write-Host "[fail] $($_.Exception.Message) — rolling back from $backupDir" -ForegroundColor Red
    try {
        & (Join-Path $KitRoot 'lib\revert.ps1') -OcHome $OcHome -BackupStamp $stamp
    } catch {
        Write-Warning "rollback failed: $($_.Exception.Message) — revert manually from $backupDir"
    }
    throw
}

# --- prune old backups: keep the newest 8 ---
try {
    $all = Get-ChildItem -LiteralPath $BackupRoot -Directory | Sort-Object Name -Descending
    $all | Select-Object -Skip 8 | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
        Write-Host "[prune] removed old backup $($_.Name)"
    }
} catch { Write-Warning "backup prune skipped: $($_.Exception.Message)" }

if ($SelfTest) {
    Write-Host ""
    & (Join-Path $KitRoot 'lib\selftest.ps1') -OcHome $OcHome
}

if (-not $SkipRestart) {
    Write-Host ""
    & (Join-Path $KitRoot 'lib\restart.ps1')
}

Write-Host ""
Write-Host "[done] 0x INJECT AI active at $OcHome" -ForegroundColor Green
Write-Host "       open a NEW session — the picker shows 0x; make one model call, then status."
