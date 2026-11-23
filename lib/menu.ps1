# 0x — operator UI. Single-keypress control, gradient banner, INJECT AI console.
param(
    [Parameter(Mandatory = $true)][string]$KitRoot,
    [string]$Action = '',
    [string]$Lang = '',
    [switch]$Plain
)

# ---- brand (per-kit) ----
$Persona = 'V — the carrier'
$AgentId = '0x'

$OcHome = Join-Path $env:USERPROFILE '.config\opencode'
$BackupRoot = Join-Path $OcHome '.persona-kit-backups'
$ForgeDir = Join-Path $OcHome '.chain-forge'
$ErrorActionPreference = 'Continue'

# ---- language: -Lang wins, then .chain-forge\lang, then en ----
if (-not $Lang) {
    $langFile = Join-Path $ForgeDir 'lang'
    if (Test-Path -LiteralPath $langFile) {
        try { $Lang = (Get-Content -LiteralPath $langFile -Raw).Trim() } catch { }
    }
}
if ($Lang -ne 'fa') { $Lang = 'en' }
. (Join-Path $PSScriptRoot 'lang.ps1')
$script:L = $null
try {
    $script:L = Get-Lang -Code $Lang
} catch {
    Write-Warning ("Language table could not be loaded: {0}" -f $_.Exception.Message)
}
if ($script:L -isnot [System.Collections.IDictionary]) {
    $script:L = @{}
}
function T([string]$k) {
    $table = $script:L
    if ($table -is [System.Collections.IDictionary] -and $table.Contains($k)) {
        return [string]$table[$k]
    }
    return $k
}

# ---- palette / console ----
$E = [char]27
$noColor = $Plain -or $env:NO_COLOR
# propagate: every child script (inject/status/selftest) reads $env:NO_COLOR
if ($noColor) { $env:NO_COLOR = '1' }
if ($noColor) {
    $P_KEY = ''; $P_TXT = ''; $P_DIM = ''; $P_OK = ''; $P_WARN = ''; $P_BAD = ''; $P_R = ''
} else {
    $P_KEY = "${E}[38;2;205;168;255m"   # light purple
    $P_TXT = "${E}[38;2;170;170;170m"   # light gray
    $P_DIM = "${E}[38;2;100;100;100m"   # dim
    $P_OK = "${E}[38;2;120;220;120m"    # green
    $P_WARN = "${E}[38;2;255;190;95m"   # amber
    $P_BAD = "${E}[38;2;255;110;80m"    # red
    $P_R = "${E}[0m"
    try {
        Add-Type -Namespace Win32 -Name ForgeConsole -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern System.IntPtr GetStdHandle(int n);
[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern bool GetConsoleMode(System.IntPtr h, out int m);
[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern bool SetConsoleMode(System.IntPtr h, int m);
'@ -ErrorAction Stop
        $hOut = [Win32.ForgeConsole]::GetStdHandle(-11)
        $mode = 0
        [void][Win32.ForgeConsole]::GetConsoleMode($hOut, [ref]$mode)
        [void][Win32.ForgeConsole]::SetConsoleMode($hOut, $mode -bor 4)
    } catch { }
    try {
        $raw = $Host.UI.RawUI
        if ($raw.BufferSize.Width -lt 112) { $raw.BufferSize = New-Object System.Management.Automation.Host.Size(112, [Math]::Max($raw.BufferSize.Height, 3000)) }
        if ($raw.WindowSize.Width -lt 112) { $raw.WindowSize = New-Object System.Management.Automation.Host.Size(112, 40) }
    } catch { }
}

function Read-Key { return [System.Console]::ReadKey($true).KeyChar.ToString().ToLower() }

function Get-KitVersion {
    $stamp = Join-Path $ForgeDir 'install.json'
    if (Test-Path -LiteralPath $stamp) {
        try {
            $v = (Get-Content -LiteralPath $stamp -Raw | ConvertFrom-Json).kit
            if ($v) { return [string]$v }
        } catch { }
    }
    return '5.1.0-v2-native'
}

function Write-Banner {
    Clear-Host
    Write-Host ''

    # 0x mark — slashed zero + lowercase x, 5x6 pixel font
    $font = @{
        '0' = @('01110', '10001', '10011', '10101', '11001', '01110')
        'x' = @('00000', '10001', '01010', '00100', '01010', '10001')
    }
    $grad = @( @(243, 230, 255), @(226, 200, 255), @(205, 168, 255), @(180, 132, 255), @(152, 96, 248), @(124, 58, 237) )
    $blk = if ($noColor) { '##' } else { [string][char]0x2588 * 2 }
    for ($row = 0; $row -lt 6; $row++) {
        $line = ''
        foreach ($ch in '0x'.ToCharArray()) {
            $line += ($font[[string]$ch][$row] -replace '1', $blk -replace '0', '  ') + '  '
        }
        if ($noColor) {
            Write-Host "  $line"
        } else {
            $c = $grad[$row]
            Write-Host ("  ${E}[38;2;{0};{1};{2}m{3}${P_R}" -f $c[0], $c[1], $c[2], $line)
        }
    }
    Write-Host ''
    Write-Host "  ${P_DIM}0 · $Persona · $(Get-KitVersion)${P_R}"
    $taglines = @(
        'read the signal. lock the band.',
        'signal first. theory later.',
        'bind in — transmit out.',
        'every dispatch re-arms.',
        'the bench is wide. the floor is narrow.'
    )
    $tag = $taglines[(Get-Random -Maximum $taglines.Count)]
    Write-Host "  ${P_DIM}$tag${P_R}"
    Write-Host ''
}

function Show-Status {
    try {
        $st = & (Join-Path $KitRoot 'lib\status.ps1') -OcHome $OcHome
        $bullet = { param($good, $warnIf) if ($good) { "${P_OK}●${P_R}" } elseif ($warnIf) { "${P_WARN}●${P_R}" } else { "${P_BAD}●${P_R}" } }

        $filesOk = $st.AgentsMd -and $st.AgentsBytes -gt 40000 -and $st.ChainFiles -and $st.PluginSource
        $chainTxt = if ($st.ChainFiles) { 'ok' } else { 'MISSING' }
        $plugTxt = if ($st.PluginSource) { 'armed' } else { 'MISSING' }
        Write-Host ("  {0} files        ${P_DIM}$Persona {1} bytes · chain 6/6 $chainTxt · plugin $plugTxt${P_R}" -f (& $bullet $filesOk ($st.AgentsMd -or $st.PluginSource)), $st.AgentsBytes)

        $cfgOk = $st.CfgDefaultAgent -and $st.CfgPluginKey -and $st.CfgPermissions
        $daTxt = if ($st.CfgDefaultAgent) { 'set' } else { 'NOT SET' }
        $pkTxt = if ($st.CfgPluginKey) { 'set' } else { 'NOT SET' }
        $pmTxt = if ($st.CfgPermissions) { 'open' } else { 'default' }
        Write-Host ("  {0} config       ${P_DIM}default agent=$AgentId ${daTxt} · plugin key $pkTxt · perms $pmTxt${P_R}" -f (& $bullet $cfgOk ($st.CfgDefaultAgent -or $st.CfgPluginKey)))

        $alive = $st.Enforcement -match '^ALIVE'
        $encText = if ($null -ne $st.HeartbeatMin) { "last hook fire $($st.HeartbeatMin) min ago" } else { 'no fires recorded yet' }
        Write-Host ("  {0} enforcement  ${P_DIM}$encText${P_R}" -f (& $bullet $alive ($null -ne $st.HeartbeatMin)))

        $injectOk = $st.InjectPayloads -gt 0 -and $st.InjectProfile
        $injLast = if ($null -ne $st.InjectLastMin) { "$($st.InjectLastMin) min ago" } else { 'none yet' }
        $dbg = if ($st.InjectDebug) { ' · debug ON' } else { '' }
        Write-Host ("  {0} inject       ${P_DIM}profile=$($st.InjectProfile) · payloads=$($st.InjectPayloads) · last=$injLast · scrubs=$($st.Scrubs)$dbg${P_R}" -f (& $bullet $injectOk ($st.InjectProfile)))

        $driftText = if ($st.HashDrift -gt 0) { "drift: $($st.HashDrift) file(s) — repair will heal" } else { 'no drift' }
        Write-Host ("  {0} integrity    ${P_DIM}$driftText${P_R}" -f (& $bullet ($st.HashDrift -eq 0) $false))

        $sessions = if ($null -ne $st.Sessions) { $st.Sessions } else { 0 }
        $wdTxt = if ($st.WatchdogTask) { 'on' } else { 'off' }
        Write-Host ("  {0} depth        ${P_DIM}$sessions session(s) tracked · watchdog $wdTxt${P_R}" -f "${P_OK}●${P_R}")

        if ($st.ProjectOverride) { Write-Host "  ${P_WARN}▸ project override nearby: $($st.ProjectOverride)${P_R}" }
    } catch {
        Write-Host "  ${P_BAD}($(T 'status_unavailable'): $($_.Exception.Message))${P_R}"
    }
    Write-Host ''
}

function Show-Menu {
    $items = @(
        @{ k = '1'; t = (T 'menu_install') },
        @{ k = '2'; t = (T 'menu_repair') },
        @{ k = '3'; t = (T 'menu_restart') },
        @{ k = '4'; t = (T 'menu_deep') },
        @{ k = '5'; t = (T 'menu_status') },
        @{ k = '6'; t = (T 'menu_watchdog') },
        @{ k = '7'; t = (T 'menu_openoc') },
        @{ k = '8'; t = (T 'menu_revert') },
        @{ k = '9'; t = (T 'menu_depth') },
        @{ k = 'L'; t = (T 'menu_logs') },
        @{ k = 'B'; t = (T 'menu_backups') },
        @{ k = 'Q'; t = (T 'menu_quit') },
        @{ k = 'I'; t = (T 'menu_inject') },
        @{ k = 'S'; t = (T 'menu_sessions') },
        @{ k = 'F'; t = (T 'menu_lang') }
    )
    $colW = 24
    $cols = 3
    $rows = [math]::Ceiling($items.Count / $cols)
    for ($r = 0; $r -lt $rows; $r++) {
        $line = ''
        for ($c = 0; $c -lt $cols; $c++) {
            $idx = $r * $cols + $c
            if ($idx -ge $items.Count) { continue }
            $it = $items[$idx]
            $vis = '[' + $it.k + '] ' + $it.t
            $pad = $colW - 2 - $vis.Length
            if ($pad -lt 1) { $pad = 1 }
            $line += '  ' + $P_KEY + '[' + $it.k + ']' + $P_R + ' ' + $P_TXT + $it.t + $P_R + (' ' * $pad)
        }
        Write-Host $line
    }
    Write-Host ''
    Write-Host "  ${P_DIM}$(T 'custom_by') : ${P_TXT}XP4${P_R}"
    Write-Host "  ${P_DIM}$(T 'telegram') : ${P_TXT}t.me/LearnExploit${P_R}  ${P_KEY}[click - T]${P_R}"
    Write-Host "  ${P_DIM}$(T 'bax') : ${P_TXT}IR0Day.Today${P_R}  ${P_KEY}[click - X]${P_R}"
    Write-Host ''
}

function Pause-Key {
    Write-Host ''
    Write-Host "  ${P_DIM}$(T 'any_key')${P_R}"
    [void][System.Console]::ReadKey($true)
}

function Show-InjectConsole {
    while ($true) {
        Clear-Host
        Write-Host ''
        Write-Host "  ${P_KEY}$(T 'inject_title')${P_R}"
        Write-Host ''
        $rows = @(
            @('P', (T 'inject_preview')), @('L', (T 'inject_lint')), @('S', (T 'inject_stats')),
            @('A', (T 'inject_payloads')), @('O', (T 'inject_profiles')), @('D', (T 'inject_debug')),
            @('M', (T 'inject_sim')), @('T', (T 'inject_test')), @('U', (T 'inject_unit')), @('B', (T 'inject_back'))
        )
        foreach ($row in $rows) {
            Write-Host "  ${P_KEY}[$($row[0])]${P_R} ${P_TXT}$($row[1])${P_R}"
        }
        Write-Host ''
        $k = Read-Key
        $inj = Join-Path $KitRoot 'lib\inject.ps1'
        switch ($k) {
            'p' { & $inj -OcHome $OcHome -KitRoot $KitRoot -Action preview; Pause-Key }
            'l' { & $inj -OcHome $OcHome -KitRoot $KitRoot -Action lint; Pause-Key }
            's' { & $inj -OcHome $OcHome -KitRoot $KitRoot -Action stats; Pause-Key }
            'a' { & $inj -OcHome $OcHome -KitRoot $KitRoot -Action payloads; Pause-Key }
            'o' { & $inj -OcHome $OcHome -KitRoot $KitRoot -Action profiles; Pause-Key }
            'd' { & $inj -OcHome $OcHome -KitRoot $KitRoot -Action debug; Pause-Key }
            'm' { & $inj -OcHome $OcHome -KitRoot $KitRoot -Action simulate; Pause-Key }
            't' { & $inj -OcHome $OcHome -KitRoot $KitRoot -Action test; Pause-Key }
            'u' { & $inj -OcHome $OcHome -KitRoot $KitRoot -Action unit; Pause-Key }
            'b' { return }
        }
    }
}

function Show-Sessions {
    $stateFile = Join-Path $ForgeDir 'state.json'
    if (-not (Test-Path -LiteralPath $stateFile)) { Write-Host "  ${P_DIM}$(T 'sessions_none')${P_R}"; return }
    try { $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } catch { Write-Host "  ${P_BAD}state.json unreadable${P_R}"; return }
    $props = @($state.sessions.PSObject.Properties)
    if ($props.Count -eq 0) { Write-Host "  ${P_DIM}$(T 'sessions_none')${P_R}"; return }
    Write-Host ''
    Write-Host "  ${P_KEY}$(T 'sessions_title')${P_R}  ${P_DIM}$(T 'sessions_reset')${P_R}"
    $i = 1
    foreach ($p in $props) {
        $v = $p.Value
        $age = ''
        if ($v.last) {
            try { $age = " · $([int]((Get-Date) - [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$v.last)).TotalMinutes) min ago" } catch { }
        }
        Write-Host ("    [{0}] {1}  depth {2} · turns {3} · scrubs {4} · injections {5}{6}" -f $i, $p.Name, $v.depth, $v.turns, $v.scrubs, $v.injections, $age)
        $i++
    }
    Write-Host ''
    $pick = Read-Key
    if ($pick -match '^[1-9]$') {
        $idx = [int]$pick - 1
        if ($idx -lt $props.Count) {
            Write-Host "  ${P_DIM}$(T 'session_reset_q')${P_R}"
            if ((Read-Key) -eq 'y') {
                $state.sessions.PSObject.Properties.Remove($props[$idx].Name)
                ($state | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $stateFile -Encoding UTF8
                Write-Host "  ${P_OK}$(T 'session_reset_ok')${P_R}"
            } else { Write-Host "  ${P_DIM}$(T 'cancelled')${P_R}" }
        }
    }
}

function Toggle-Lang {
    $script:Lang = if ($script:Lang -eq 'fa') { 'en' } else { 'fa' }
    try {
        $script:L = Get-Lang -Code $script:Lang
        if ($script:L -isnot [System.Collections.IDictionary]) { $script:L = @{} }
    } catch {
        $script:L = @{}
        Write-Warning ("Language switch failed: {0}" -f $_.Exception.Message)
    }
    try {
        if (-not (Test-Path -LiteralPath $ForgeDir)) { New-Item -ItemType Directory -Force -Path $ForgeDir | Out-Null }
        Set-Content -LiteralPath (Join-Path $ForgeDir 'lang') -Value $script:Lang -Encoding ASCII
    } catch { }
}

function Get-OpenCodeExe {
    $cmd = Get-Command opencode -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in @(
            (Join-Path $env:LOCALAPPDATA 'Programs\ai.opencode.desktop\OpenCode.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\ai.opencode.desktop\resources\opencode-cli.exe')
        )) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Invoke-DeepRestart {
    Write-Host ''
    Write-Host '  deep restart: killing OpenCode, resetting depth state, cold start...'
    foreach ($n in @('opencode', 'OpenCode')) {
        Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
    $stateFile = Join-Path $ForgeDir 'state.json'
    if (Test-Path -LiteralPath $stateFile) {
        Remove-Item -LiteralPath $stateFile -Force
        Write-Host "  [ok] $(T 'depth_cleared_all')"
    }
    $exe = Get-OpenCodeExe
    if ($exe) {
        Start-Process -FilePath $exe -WindowStyle Normal
        Start-Sleep -Seconds 3
        $alive = $false
        foreach ($n in @('opencode', 'OpenCode')) { if (Get-Process -Name $n -ErrorAction SilentlyContinue) { $alive = $true } }
        if ($alive) { Write-Host "  [ok] $(T 'cold_started')" } else { Write-Host "  [warn] $(T 'not_visible')" }
    } else {
        Write-Host "  [warn] $(T 'start_manual')"
    }
}

function Invoke-DepthReset {
    Write-Host ''
    Write-Host "  $(T 'sure_depth')"
    if ((Read-Key) -eq 'y') {
        $stateFile = Join-Path $ForgeDir 'state.json'
        if (Test-Path -LiteralPath $stateFile) { Remove-Item -LiteralPath $stateFile -Force }
        Write-Host "  [ok] $(T 'depth_cleared')"
    } else { Write-Host "  ${P_DIM}$(T 'cancelled')${P_R}" }
}

function Show-Logs {
    Write-Host ''
    Write-Host "  ${P_KEY}$(T 'logs_hb')${P_R}  ${P_DIM}$(T 'logs_hb_note')${P_R}"
    $hb = Join-Path $ForgeDir 'heartbeat.log'
    if (Test-Path -LiteralPath $hb) {
        Get-Content -LiteralPath $hb -Tail 12 | ForEach-Object { Write-Host "    $_" }
    } else { Write-Host "    $(T 'no_heartbeat')" }
    Write-Host ''
    Write-Host "  ${P_KEY}$(T 'logs_heal')${P_R}  ${P_DIM}$(T 'logs_heal_note')${P_R}"
    $hl = Join-Path $ForgeDir 'heal.log'
    if (Test-Path -LiteralPath $hl) {
        Get-Content -LiteralPath $hl -Tail 8 | ForEach-Object { Write-Host "    $_" }
    } else { Write-Host "    $(T 'no_heal')" }
    Write-Host ''
    Write-Host "  ${P_KEY}injection${P_R}  ${P_DIM}(INJECT AI events)${P_R}"
    $il = Join-Path $ForgeDir 'injection.log'
    if (Test-Path -LiteralPath $il) {
        Get-Content -LiteralPath $il -Tail 6 | ForEach-Object { Write-Host "    $_" }
    } else { Write-Host '    (no injection events yet)' }
}

function Show-Backups {
    Write-Host ''
    if (-not (Test-Path -LiteralPath $BackupRoot)) { Write-Host "  $(T 'backups_none')"; return }
    $dirs = Get-ChildItem -LiteralPath $BackupRoot -Directory | Sort-Object Name -Descending | Select-Object -First 9
    if ($dirs.Count -eq 0) { Write-Host "  $(T 'backups_none')"; return }
    Write-Host "  ${P_KEY}$(T 'backups_title')${P_R}  ${P_DIM}$(T 'backups_note')${P_R}"
    $i = 1
    foreach ($d in $dirs) {
        Write-Host "    [$i] $($d.Name)"
        $i++
    }
    Write-Host "    $(T 'backups_cancel')"
    $pick = Read-Key
    if ($pick -match '^[1-9]$') {
        $idx = [int]$pick - 1
        if ($idx -lt $dirs.Count) {
            Write-Host ''
            Write-Host "  $(T 'reverting') $($dirs[$idx].Name)..."
            & (Join-Path $KitRoot 'lib\revert.ps1') -OcHome $OcHome -BackupStamp $dirs[$idx].Name
        }
    }
}

function Toggle-Watchdog {
    $task = Get-ScheduledTask -TaskName 'ChainForgeHeal' -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName 'ChainForgeHeal' -Confirm:$false
        Write-Host "  [ok] $(T 'watchdog_off')"
    } else {
        $heal = Join-Path $KitRoot 'lib\verify-heal.ps1'
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$heal`" -Silent -Notify"
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        Register-ScheduledTask -TaskName 'ChainForgeHeal' -Action $action -Trigger $trigger -Description '0x INJECT AI self-heal at logon' -Force | Out-Null
        Write-Host "  [ok] $(T 'watchdog_on')"
    }
}

function Invoke-Action([string]$a) {
    switch ($a.ToLower()) {
        'install' { & (Join-Path $KitRoot 'lib\install.ps1') -KitRoot $KitRoot -OcHome $OcHome -BackupRoot $BackupRoot -ForceAgentsMd }
        'repair' { & (Join-Path $KitRoot 'lib\install.ps1') -KitRoot $KitRoot -OcHome $OcHome -BackupRoot $BackupRoot -SkipRestart -ForceAgentsMd:$false }
        'status' { Show-Status }
        'revert' { & (Join-Path $KitRoot 'lib\revert.ps1') -OcHome $OcHome }
        'inject' { & (Join-Path $KitRoot 'lib\inject.ps1') -OcHome $OcHome -KitRoot $KitRoot -Action preview }
        'lint' { & (Join-Path $KitRoot 'lib\inject.ps1') -OcHome $OcHome -KitRoot $KitRoot -Action lint }
        'stats' { & (Join-Path $KitRoot 'lib\inject.ps1') -OcHome $OcHome -KitRoot $KitRoot -Action stats }
        'sessions' { Show-Sessions }
        'selftest' { & (Join-Path $KitRoot 'lib\selftest.ps1') -OcHome $OcHome }
        'unit' { & (Join-Path $KitRoot 'lib\ts-test.ps1') -KitRoot $KitRoot }
        default { Write-Host "unknown action: $a" }
    }
}

if ($Action) {
    Invoke-Action $Action
    return
}

while ($true) {
    Write-Banner
    Show-Menu
    $k = Read-Key
    switch ($k) {
        '1' {
            Write-Host ''
            Write-Host "  $(T 'sure_install')"
            if ((Read-Key) -eq 'y') {
                & (Join-Path $KitRoot 'lib\install.ps1') -KitRoot $KitRoot -OcHome $OcHome -BackupRoot $BackupRoot -ForceAgentsMd
            } else { Write-Host "  ${P_DIM}$(T 'cancelled')${P_R}" }
            Pause-Key
        }
        '2' {
            Write-Host ''
            Write-Host "  $(T 'sure_repair')"
            $force = (Read-Key) -eq 'y'
            & (Join-Path $KitRoot 'lib\install.ps1') -KitRoot $KitRoot -OcHome $OcHome -BackupRoot $BackupRoot -SkipRestart -ForceAgentsMd:$force
            Write-Host "  [ok] $(T 'repaired')"
            Pause-Key
        }
        '3' { Write-Host ''; & (Join-Path $KitRoot 'lib\restart.ps1'); Pause-Key }
        '4' { Invoke-DeepRestart; Pause-Key }
        '5' { Write-Host ''; Show-Status; Pause-Key }
        '6' { Write-Host ''; Toggle-Watchdog; Pause-Key }
        '7' {
            $exe = Get-OpenCodeExe
            if ($exe) { Start-Process -FilePath $exe -WindowStyle Normal; Write-Host "  [ok] $(T 'launched')" }
            else { Write-Host "  [warn] $(T 'not_on_path')" }
            Pause-Key
        }
        '8' {
            Write-Host ''
            Write-Host "  $(T 'sure_revert')"
            if ((Read-Key) -eq 'y') { & (Join-Path $KitRoot 'lib\revert.ps1') -OcHome $OcHome }
            else { Write-Host "  ${P_DIM}$(T 'cancelled')${P_R}" }
            Pause-Key
        }
        '9' { Invoke-DepthReset; Pause-Key }
        'l' { Show-Logs; Pause-Key }
        'b' { Show-Backups; Pause-Key }
        'i' { Show-InjectConsole }
        's' { Write-Host ''; Show-Sessions; Pause-Key }
        'f' { Toggle-Lang }
        't' { Start-Process 'https://t.me/LearnExploit' }
        'x' { Start-Process 'https://IR0Day.Today' }
        'q' { return }
        default { }
    }
}
