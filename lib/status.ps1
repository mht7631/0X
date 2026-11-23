# 0x status — measures LIFE (hook fires + INJECT AI events), not file existence.
param([string]$OcHome)

$forge   = Join-Path $OcHome '.chain-forge'
$agents  = Join-Path $OcHome 'AGENTS.md'
$plugin  = Join-Path $OcHome 'plugins\chain-forge\index.ts'
$stems   = Join-Path $OcHome 'plugins\chain-forge\stems.json'
$injCfg  = Join-Path $OcHome 'plugins\chain-forge\inject.config.json'
$payDir  = Join-Path $OcHome 'plugins\chain-forge\payloads'
$hbFile  = Join-Path $forge 'heartbeat.log'
$hashFile= Join-Path $forge 'hashes.json'
$json    = Join-Path $OcHome 'opencode.json'
$stateFile = Join-Path $forge 'state.json'
$injLog  = Join-Path $forge 'injection.log'
$healLog = Join-Path $forge 'heal.log'

$chainCount = 0
foreach ($f in @('00-RANK.md','01-STACK.md','02-SEAL.md','03-NULL.md','04-PATH.md','05-DEPTH.md')) {
    if (Test-Path (Join-Path $OcHome "chain\$f")) { $chainCount++ }
}

# --- config keys ---
$cfgDefault = $false; $cfgPlugin = $false; $cfgPerm = $false; $cfgInstr = 0
if (Test-Path -LiteralPath $json) {
    try {
        $cfg = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
        $cfgDefault = ($cfg.default_agent -eq '0x')
        $cfgPlugin  = (@($cfg.plugins) | Where-Object { [string]$_ -match 'chain-forge' }).Count -gt 0
        $cfgPerm    = ($cfg.permission.edit -eq 'allow' -and $cfg.permission.bash -eq 'allow')
        $cfgInstr   = @($cfg.instructions).Count
    } catch { }
}

# --- heartbeat age: the only honest liveness signal ---
$hbAgeMin = $null
$enforcement = 'no fires recorded yet'
if (Test-Path -LiteralPath $hbFile) {
    $lastLine = (Get-Content -LiteralPath $hbFile -Tail 1)
    if ($lastLine -match '^(\S+)\s') {
        try {
            $hbAgeMin = [int]((Get-Date) - [DateTime]::Parse($Matches[1])).TotalMinutes
            $enforcement = if ($hbAgeMin -lt 10) { 'ALIVE (hooks firing)' } else { "quiet (${hbAgeMin} min since last fire)" }
        } catch { }
    }
}

# --- hash drift ---
$drift = 0; $drifted = @()
if (Test-Path -LiteralPath $hashFile) {
    try {
        $hashes = Get-Content -LiteralPath $hashFile -Raw | ConvertFrom-Json
        foreach ($p in $hashes.PSObject.Properties) {
            $f = Join-Path $OcHome $p.Name
            if (-not (Test-Path -LiteralPath $f)) { $drift++; $drifted += $p.Name; continue }
            if ((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLower() -ne $p.Value) { $drift++; $drifted += $p.Name }
        }
    } catch { }
}

# --- project-level override scan (silent spine-killer) ---
$projWarn = @()
foreach ($candidate in @((Join-Path (Get-Location) 'opencode.json'), (Join-Path (Get-Location) 'opencode.jsonc'), (Join-Path (Get-Location) '.opencode'))) {
    if (Test-Path -LiteralPath $candidate) { $projWarn += $candidate }
}

# --- INJECT AI surface ---
$injProfile = ''
$injPayloads = 0
$injDebug = $false
if (Test-Path -LiteralPath $injCfg) {
    try {
        $ic = Get-Content -LiteralPath $injCfg -Raw | ConvertFrom-Json
        if ($ic.activeProfile) { $injProfile = [string]$ic.activeProfile }
        $injDebug = [bool]$ic.debugDump
    } catch { }
}
if (Test-Path -LiteralPath $payDir) {
    $injPayloads = @(Get-ChildItem -LiteralPath $payDir -Filter '*.md' -File -ErrorAction SilentlyContinue).Count
}

$injLastMin = $null
if (Test-Path -LiteralPath $injLog) {
    $line = Get-Content -LiteralPath $injLog -Tail 1
    if ($line) {
        try {
            $ev = $line | ConvertFrom-Json
            if ($ev.t) { $injLastMin = [int]((Get-Date).ToUniversalTime() - [DateTime]::Parse($ev.t).ToUniversalTime()).TotalMinutes }
        } catch { }
    }
}

# --- sessions / scrubs ---
$sessions = 0; $scrubs = 0
if (Test-Path -LiteralPath $stateFile) {
    try {
        $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        $props = @($state.sessions.PSObject.Properties)
        $sessions = $props.Count
        foreach ($p in $props) { $scrubs += [int]$p.Value.scrubs }
    } catch { }
}

$lastHealMin = $null
if (Test-Path -LiteralPath $healLog) {
    $h = Get-Content -LiteralPath $healLog -Tail 1
    if ($h -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
        try { $lastHealMin = [int]((Get-Date) - [DateTime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', $null)).TotalMinutes } catch { }
    }
}

[pscustomobject]@{
    Installed       = Test-Path (Join-Path $forge 'install.json')
    AgentsMd        = Test-Path $agents
    AgentsBytes     = if (Test-Path $agents) { (Get-Item $agents).Length } else { 0 }
    ChainFiles      = ($chainCount -eq 6)
    PluginSource    = (Test-Path $plugin) -and (Test-Path (Join-Path (Split-Path $plugin -Parent) 'hooks.ts')) -and (Test-Path (Join-Path (Split-Path $plugin -Parent) 'package.json')) -and (Test-Path $stems) -and (Test-Path $injCfg)
    CfgDefaultAgent = $cfgDefault
    CfgPluginKey    = $cfgPlugin
    CfgPermissions  = $cfgPerm
    CfgInstructions = $cfgInstr
    HeartbeatMin    = $hbAgeMin
    Enforcement     = $enforcement
    HashDrift       = $drift
    DriftedFiles    = ($drifted -join ', ')
    ProjectOverride = ($projWarn -join ', ')
    OpenCodeOnPath  = $null -ne (Get-Command opencode -ErrorAction SilentlyContinue)
    WatchdogTask    = $null -ne (Get-ScheduledTask -TaskName 'ChainForgeHeal' -ErrorAction SilentlyContinue)
    InjectProfile   = $injProfile
    InjectPayloads  = $injPayloads
    InjectDebug     = $injDebug
    InjectLastMin   = $injLastMin
    Sessions        = $sessions
    Scrubs          = $scrubs
    LastHealMin     = $lastHealMin
}
