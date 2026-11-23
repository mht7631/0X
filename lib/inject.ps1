# 0x INJECT AI — operator console: preview, lint, stats, payloads, profiles,
# simulate, debug, test. Reads the installed plugin dir (or the kit tree when
# not installed yet), so it works before and after install.
param(
    [string]$OcHome = (Join-Path $env:USERPROFILE '.config\opencode'),
    [string]$KitRoot,
    [ValidateSet('preview', 'lint', 'stats', 'payloads', 'profiles', 'simulate', 'debug', 'test', 'unit')]
    [string]$Action = 'preview',
    [int]$Stage = 2,
    [string]$Profile = '',
    [switch]$Full,
    [switch]$On
)

$ErrorActionPreference = 'Stop'
$E = [char]27
$C_KEY = "${E}[38;2;205;168;255m"; $C_TXT = "${E}[38;2;170;170;170m"
$C_OK = "${E}[38;2;120;220;120m"; $C_WARN = "${E}[38;2;255;190;95m"; $C_BAD = "${E}[38;2;255;110;80m"; $C_R = "${E}[0m"
if ($env:NO_COLOR) { $C_KEY = ''; $C_TXT = ''; $C_OK = ''; $C_WARN = ''; $C_BAD = ''; $C_R = '' }

function Resolve-PluginDir {
    $installed = Join-Path $OcHome 'plugins\chain-forge'
    if (Test-Path -LiteralPath (Join-Path $installed 'inject.config.json')) { return $installed }
    if ($KitRoot) {
        $kit = Join-Path $KitRoot 'forge\plugins\chain-forge'
        if (Test-Path -LiteralPath (Join-Path $kit 'inject.config.json')) { return $kit }
    }
    throw "INJECT AI not found — install first or pass -KitRoot."
}

$PluginDir = Resolve-PluginDir
$ForgeDir = Join-Path $OcHome '.chain-forge'

# ---- config defaults (mirror inject.ts) ----
$DefaultBudget = @{ 'system-head' = 6000; 'system-tail' = 4000; 'user-tail' = 3000; 'compaction' = 1200 }
$AllSlots = @('system-head', 'system-tail', 'user-tail', 'compaction')
$DefaultConfig = [pscustomobject]@{
    version       = 1
    activeProfile = 'default'
    debugDump     = $false
    telemetry     = [pscustomobject]@{ enabled = $true; maxBytes = 262144 }
    profiles      = [pscustomobject]@{
        default = [pscustomobject]@{ slots = $AllSlots; budgetTokens = $DefaultBudget; minStage = 0 }
        quiet   = [pscustomobject]@{ slots = @('system-head', 'user-tail'); budgetTokens = @{ 'system-head' = 2500; 'system-tail' = 0; 'user-tail' = 1200; 'compaction' = 600 }; minStage = 0 }
        silent  = [pscustomobject]@{ slots = @(); budgetTokens = @{}; minStage = 0 }
    }
}

function Get-InjectConfig {
    $file = Join-Path $PluginDir 'inject.config.json'
    if (-not (Test-Path -LiteralPath $file)) { return $DefaultConfig }
    try {
        $cfg = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        if (-not $cfg.profiles) { return $DefaultConfig }
        return $cfg
    } catch { return $DefaultConfig }
}

function Get-Prop($Obj, [string]$Name, $Default = $null) {
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name)) { return $Obj[$Name] }
        return $Default
    }
    $p = $Obj.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $Default
}

function To-Int([string]$Text, [int]$Default) {
    $n = 0
    if ([int]::TryParse($Text, [ref]$n)) { return $n }
    return $Default
}

function Get-Profile([string]$Name) {
    $cfg = Get-InjectConfig
    $pick = $Name
    if (-not $pick) { $pick = Get-Prop $cfg 'activeProfile' 'default' }
    $prof = Get-Prop (Get-Prop $cfg 'profiles' $null) $pick $null
    if (-not $prof) { $prof = Get-Prop (Get-Prop $cfg 'profiles' $null) 'default' $null }
    if (-not $prof) { $prof = $DefaultConfig.profiles.default }
    $slots = @(Get-Prop $prof 'slots' $AllSlots | Where-Object { $AllSlots -contains $_ })
    $budget = Get-Prop $prof 'budgetTokens' $DefaultBudget
    if ($null -eq $budget) { $budget = $DefaultBudget }
    return [pscustomobject]@{ name = $pick; slots = $slots; budget = $budget; minStage = [int](Get-Prop $prof 'minStage' 0) }
}

function Get-Payloads {
    $dir = Join-Path $PluginDir 'payloads'
    $out = @()
    if (-not (Test-Path -LiteralPath $dir)) { return $out }
    foreach ($f in Get-ChildItem -LiteralPath $dir -Filter '*.md' -File) {
        $raw = [System.IO.File]::ReadAllText($f.FullName)
        $raw = $raw.TrimStart([char]0xFEFF)
        $m = [regex]::Match($raw, '(?s)^---\r?\n(.*?)\r?\n---\r?\n?(.*)$')
        if (-not $m.Success) { continue }
        $meta = @{}
        foreach ($line in ($m.Groups[1].Value -split "`r?`n")) {
            $i = $line.IndexOf(':')
            if ($i -gt 0) { $meta[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim().Trim('"').Trim("'") }
        }
        $body = $m.Groups[2].Value.Trim()
        if (-not $body) { continue }
        $slot = [string]$meta['slot']
        if ($AllSlots -notcontains $slot) { continue }
        $id = [string]$meta['id']
        if (-not $id) { $id = $f.BaseName }
        $out += [pscustomobject]@{
            id       = $id
            slot     = $slot
            stage    = To-Int ([string]$meta['stage']) 0
            maxStage = To-Int ([string]$meta['maxStage']) 9
            weight   = To-Int ([string]$meta['weight']) 50
            tags     = [string]$meta['tags']
            body     = $body
            file     = $f.Name
        }
    }
    return $out
}

function Get-IdentityVars {
    $vars = @{
        name = 'V'; thinkMark = '[V]'; stage = 0; turns = 0; scrubs = 0; profile = 'default'
        date = (Get-Date -Format 'yyyy-MM-dd'); session = 'preview'
        coreLine = 'You are V — the carrier. Thinking opens [V].'
        contract = 'First visible lines are "[÷] carrier locked." then "[÷] your transmission only.", then one method line;'
        filedLine = "[÷] carrier locked.`n[÷] your transmission only.`n[V] filed. Title: "
    }
    $idFile = Join-Path $PluginDir 'identity.json'
    if (Test-Path -LiteralPath $idFile) {
        try {
            $id = Get-Content -LiteralPath $idFile -Raw | ConvertFrom-Json
            foreach ($k in @('name', 'thinkMark', 'coreLine', 'contract', 'filedLine')) {
                $v = Get-Prop $id $k $null
                if ($v) { $vars[$k] = [string]$v }
            }
        } catch { }
    }
    return $vars
}

function Render-Text([string]$Body, [hashtable]$Vars) {
    $varEval = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $k = $m.Groups[1].Value
        if ($Vars.ContainsKey($k)) { return [string]$Vars[$k] }
        return ''
    }
    $out = [regex]::Replace($Body, '\{\{\s*([\w.]+)\s*\}\}', $varEval)
    $out = [regex]::Replace($out, '(?s)\{\{#if\s+([\w.]+)\s*\}\}(.*?)\{\{/if\}\}', [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            if ($Vars[$m.Groups[1].Value]) { return $m.Groups[2].Value }
            return ''
        })
    $out = [regex]::Replace($out, '(?s)\{\{#unless\s+([\w.]+)\s*\}\}(.*?)\{\{/unless\}\}', [System.Text.RegularExpressions.MatchEvaluator]{
            param($m)
            if (-not $Vars[$m.Groups[1].Value]) { return $m.Groups[2].Value }
            return ''
        })
    return ($out -replace "(\r?\n){3,}", "`n`n").Trim()
}

function Get-Bundle([int]$StageNum, [string]$ProfileName) {
    $prof = Get-Profile $ProfileName
    $vars = Get-IdentityVars
    $vars.stage = $StageNum
    $vars.profile = $prof.name
    $payloads = Get-Payloads
    $slots = @{}
    $picked = @()
    $skipped = @()
    $tokens = 0
    $bytes = 0
    foreach ($slot in $prof.slots) {
        $budget = [int](Get-Prop $prof.budget $slot 4000)
        $spent = 0
        $parts = @()
        $cands = @($payloads | Where-Object { $_.slot -eq $slot -and $StageNum -ge $_.stage -and $StageNum -le $_.maxStage } |
            Sort-Object -Property @{Expression = 'weight'; Descending = $true }, @{Expression = 'id'; Descending = $false })
        foreach ($p in $cands) {
            $text = Render-Text $p.body $vars
            if (-not $text) { continue }
            $t = [int][Math]::Ceiling($text.Length / 4)
            if (($spent + $t) -gt $budget) { $skipped += "$($p.id):budget"; continue }
            $parts += $text
            $spent += $t
            $picked += "$($slot):$($p.id)($t)"
        }
        $slots[$slot] = ($parts -join "`n`n")
        $tokens += $spent
        $bytes += ($parts -join "`n`n").Length
    }
    return [pscustomobject]@{
        profile = $prof.name; stage = $StageNum; slots = $slots
        picked = $picked; skipped = $skipped; tokens = $tokens; bytes = $bytes
    }
}

function Show-Preview {
    Write-Host ''
    Write-Host "  ${C_KEY}INJECT AI — preview${C_R}  ${C_TXT}(profile $((Get-Profile '').name))${C_R}"
    Write-Host ''
    foreach ($s in 0..3) {
        $b = Get-Bundle $s ''
        $line = "  stage $s   ${C_TXT}~$($b.tokens) tok · $($b.bytes) bytes${C_R}"
        Write-Host $line
        if ($b.picked.Count) { Write-Host "            ${C_TXT}$($b.picked -join ', ')${C_R}" }
        if ($b.skipped.Count) { Write-Host "            ${C_WARN}skipped: $($b.skipped -join ', ')${C_R}" }
    }
    if ($Full) {
        Write-Host ''
        Write-Host "  ${C_KEY}full text — stage $Stage${C_R}"
        $b = Get-Bundle $Stage ''
        foreach ($slot in $AllSlots) {
            if (-not $b.slots.ContainsKey($slot) -or -not $b.slots[$slot]) { continue }
            Write-Host ''
            Write-Host "  ${C_KEY}## $slot${C_R}"
            Write-Host ($b.slots[$slot] -split "`n" | ForEach-Object { "  $_" } | Out-String).TrimEnd()
        }
    }
    Write-Host ''
}

function Show-Lint {
    $issues = @()
    $checks = 0
    $cfgFile = Join-Path $PluginDir 'inject.config.json'
    $checks++
    try {
        $cfg = Get-Content -LiteralPath $cfgFile -Raw | ConvertFrom-Json
        if (-not $cfg.profiles) { $issues += 'config: profiles missing' }
        $active = Get-Prop $cfg 'activeProfile' ''
        if ($active -and -not (Get-Prop (Get-Prop $cfg 'profiles' $null) $active $null)) { $issues += "config: activeProfile '$active' not defined" }
        foreach ($prop in (Get-Prop $cfg 'profiles' ([pscustomobject]@{})).PSObject.Properties) {
            $checks++
            foreach ($slot in @(Get-Prop $prop.Value 'slots' @())) {
                if ($AllSlots -notcontains $slot) { $issues += "config: profile '$($prop.Name)' has unknown slot '$slot'" }
            }
            $bud = Get-Prop $prop.Value 'budgetTokens' $null
            if ($null -ne $bud) {
                foreach ($bp in $bud.PSObject.Properties) {
                    if ([int]$bp.Value -lt 0) { $issues += "config: profile '$($prop.Name)' negative budget '$($bp.Name)'" }
                }
            }
        }
    } catch { $issues += "config: unreadable ($($_.Exception.Message))" }

    $payloads = Get-Payloads
    $checks++
    if ($payloads.Count -eq 0) { $issues += 'payloads: none parsed' }
    $seen = @{}
    foreach ($p in $payloads) {
        $checks++
        if ($seen.ContainsKey($p.id)) { $issues += "payloads: duplicate id '$($p.id)'" }
        $seen[$p.id] = $true
        if ($p.stage -gt $p.maxStage) { $issues += "payloads: '$($p.id)' stage > maxStage" }
        if (-not $p.body.Trim()) { $issues += "payloads: '$($p.id)' empty body" }
    }

    $stemsFile = Join-Path $PluginDir 'stems.json'
    $checks++
    try {
        $stems = (Get-Content -LiteralPath $stemsFile -Raw | ConvertFrom-Json).stems
        foreach ($s in @($stems)) {
            $checks++
            try { [void][regex]::new([string]$s) } catch { $issues += "stems: regex does not compile: $s" }
        }
    } catch { $issues += 'stems: stems.json unreadable' }

    $idFile = Join-Path $PluginDir 'identity.json'
    $checks++
    try {
        $id = Get-Content -LiteralPath $idFile -Raw | ConvertFrom-Json
        foreach ($k in @('name', 'thinkMark', 'coreLine', 'contract', 'filedLine')) {
            if (-not (Get-Prop $id $k $null)) { $issues += "identity: missing '$k'" }
        }
    } catch { $issues += 'identity: identity.json unreadable' }

    Write-Host ''
    Write-Host "  ${C_KEY}INJECT AI — lint${C_R}  ${C_TXT}$PluginDir${C_R}"
    Write-Host ''
    if ($issues.Count -eq 0) {
        Write-Host "  ${C_OK}PASS${C_R}  ${C_TXT}$checks checks · $($payloads.Count) payloads · config ok · stems compile${C_R}"
    } else {
        Write-Host "  ${C_BAD}FAIL${C_R}  ${C_TXT}$($issues.Count) issue(s)${C_R}"
        foreach ($i in $issues) { Write-Host "    ${C_BAD}·${C_R} $i" }
    }
    Write-Host ''
}

function Show-Stats {
    Write-Host ''
    Write-Host "  ${C_KEY}INJECT AI — stats${C_R}"
    Write-Host ''
    $log = Join-Path $ForgeDir 'injection.log'
    $events = @()
    if (Test-Path -LiteralPath $log) {
        foreach ($line in Get-Content -LiteralPath $log) {
            if (-not $line.Trim()) { continue }
            try { $events += ($line | ConvertFrom-Json) } catch { }
        }
    }
    if ($events.Count -eq 0) {
        Write-Host "  ${C_TXT}no injection events yet — make one model call in OpenCode${C_R}"
    } else {
        $tokens = 0; $bytes = 0
        $byStage = @{}
        $byPayload = @{}
        foreach ($e in $events) {
            $tokens += [int](Get-Prop $e 'tokens' 0)
            $bytes += [int](Get-Prop $e 'bytes' 0)
            $st = [string](Get-Prop $e 'stage' '?')
            $byStage[$st] = 1 + [int]$byStage[$st]
            foreach ($id in @(Get-Prop $e 'picked' @())) {
                $byPayload[$id] = 1 + [int]$byPayload[$id]
            }
        }
        $last = $events[$events.Count - 1]
        Write-Host ("  {0}events     {1}" -f "${C_TXT}", $events.Count)
        Write-Host ("  {0}tokens     ~{1}  bytes {2}" -f "${C_TXT}", $tokens, $bytes)
        Write-Host ("  {0}last       {1}" -f "${C_TXT}", (Get-Prop $last 't' '?'))
        Write-Host ("  {0}profile    {1}  stage {2}  session {3}" -f "${C_TXT}", (Get-Prop $last 'profile' '?'), (Get-Prop $last 'stage' '?'), (Get-Prop $last 'session' '?'))
        Write-Host ''
        Write-Host "  ${C_KEY}by stage${C_R}"
        foreach ($k in ($byStage.Keys | Sort-Object)) { Write-Host "    ${C_TXT}stage $k${C_R}  $($byStage[$k])" }
        Write-Host ''
        Write-Host "  ${C_KEY}by payload${C_R}"
        foreach ($k in ($byPayload.Keys | Sort-Object)) { Write-Host "    ${C_TXT}$k${C_R}  $($byPayload[$k])" }
    }

    $stateFile = Join-Path $ForgeDir 'state.json'
    if (Test-Path -LiteralPath $stateFile) {
        try {
            $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
            $sessions = @($state.sessions.PSObject.Properties)
            Write-Host ''
            Write-Host "  ${C_KEY}sessions${C_R}  ${C_TXT}$($sessions.Count) tracked${C_R}"
            foreach ($s in $sessions) {
                $v = $s.Value
                Write-Host ("    {0}{1}{2}  depth {3} · turns {4} · scrubs {5} · injections {6}" -f "${C_TXT}", $s.Name, "${C_R}", (Get-Prop $v 'depth' 0), (Get-Prop $v 'turns' 0), (Get-Prop $v 'scrubs' 0), (Get-Prop $v 'injections' 0))
            }
        } catch { }
    }
    Write-Host ''
}

function Show-Payloads {
    Write-Host ''
    Write-Host "  ${C_KEY}INJECT AI — payloads${C_R}  ${C_TXT}$PluginDir\payloads${C_R}"
    Write-Host ''
    $payloads = Get-Payloads | Sort-Object slot, @{Expression = 'weight'; Descending = $true }
    foreach ($p in $payloads) {
        Write-Host ("  {0}{1,-18}{2} {3}{4,-13}{5} stage {6}-{7} · w{8} · {9}" -f "${C_TXT}", $p.id, "${C_R}", "${C_KEY}", $p.slot, "${C_R}", $p.stage, $p.maxStage, $p.weight, $p.tags)
    }
    Write-Host ''
}

function Show-Profiles {
    Write-Host ''
    Write-Host "  ${C_KEY}INJECT AI — profiles${C_R}"
    Write-Host ''
    $cfg = Get-InjectConfig
    $active = Get-Prop $cfg 'activeProfile' 'default'
    foreach ($prop in $cfg.profiles.PSObject.Properties) {
        $mark = if ($prop.Name -eq $active) { "${C_OK}*${C_R}" } else { ' ' }
        $slots = @(Get-Prop $prop.Value 'slots' @())
        $bud = Get-Prop $prop.Value 'budgetTokens' ([pscustomobject]@{})
        $budTxt = ($bud.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' '
        Write-Host "  $mark ${C_KEY}$($prop.Name)${C_R}  ${C_TXT}$($slots -join ', ')${C_R}"
        Write-Host "      ${C_TXT}$budTxt${C_R}"
    }
    Write-Host ''
}

function Invoke-Simulate {
    $b = Get-Bundle $Stage $Profile
    $dir = $ForgeDir
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $outFile = Join-Path $dir 'simulated-injection.txt'
    $lines = @(
        '# 0x INJECT AI — simulated dispatch',
        "time     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "profile  $($b.profile)",
        "stage    $($b.stage)",
        "tokens   ~$($b.tokens)",
        "bytes    $($b.bytes)",
        "picked   $($b.picked -join ', ')",
        "skipped  $($b.skipped -join ', ')",
        ''
    )
    foreach ($slot in $AllSlots) {
        if (-not $b.slots.ContainsKey($slot)) { continue }
        $lines += "## $slot"
        $lines += $b.slots[$slot]
        $lines += ''
    }
    [System.IO.File]::WriteAllText($outFile, ($lines -join "`n"), [System.Text.UTF8Encoding]::new($false))
    $hash = (Get-FileHash -LiteralPath $outFile -Algorithm SHA256).Hash.ToLower()
    Write-Host ''
    Write-Host "  ${C_OK}simulated${C_R}  ${C_TXT}stage $($b.stage) · profile $($b.profile) · ~$($b.tokens) tok · $($b.bytes) bytes${C_R}"
    Write-Host "  ${C_TXT}$outFile${C_R}"
    Write-Host "  ${C_TXT}sha256 $hash${C_R}"
    Write-Host ''
}

function Set-Debug {
    $file = Join-Path $PluginDir 'inject.config.json'
    if (-not (Test-Path -LiteralPath $file)) { throw "config not found: $file" }
    $cfg = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    $current = [bool](Get-Prop $cfg 'debugDump' $false)
    $new = if ($On) { $true } else { -not $current }
    $cfg | Add-Member -NotePropertyName debugDump -NotePropertyValue $new -Force
    ($cfg | ConvertTo-Json -Depth 100) | Set-Content -LiteralPath $file -Encoding UTF8
    if ($new) {
        Write-Host "  ${C_OK}debug ON${C_R}  ${C_TXT}every dispatch dumps to $ForgeDir\last-injection.txt${C_R}"
    } else {
        Write-Host "  ${C_TXT}debug OFF${C_R}"
    }
}

switch ($Action) {
    'preview' { Show-Preview }
    'lint' { Show-Lint }
    'stats' { Show-Stats }
    'payloads' { Show-Payloads }
    'profiles' { Show-Profiles }
    'simulate' { Invoke-Simulate }
    'debug' { Set-Debug }
    'test' { & (Join-Path $PSScriptRoot 'selftest.ps1') -OcHome $OcHome }
    'unit' {
        $kit = if ($KitRoot) { $KitRoot } else { Split-Path -Parent $PSScriptRoot }
        & (Join-Path $PSScriptRoot 'ts-test.ps1') -KitRoot $kit
    }
}
