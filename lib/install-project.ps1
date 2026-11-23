# 0x project install — self-contained persona + INJECT AI inside <project>\.opencode.
# The plugin resolves its home from its own location, so chain, payloads, state
# and telemetry all live under the project. No global install required.
param(
    [Parameter(Mandatory = $true)][string]$ProjectDir,
    [string]$KitRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ProjectDir)) { throw "project dir not found: $ProjectDir" }
$proj = (Resolve-Path -LiteralPath $ProjectDir).Path
$oc = Join-Path $proj '.opencode'
New-Item -ItemType Directory -Force -Path $oc | Out-Null

function Copy-Tree([string]$Src, [string]$Dst) {
    if (-not (Test-Path -LiteralPath $Src)) { Write-Warning "missing: $Src"; return }
    New-Item -ItemType Directory -Force -Path $Dst | Out-Null
    Get-ChildItem -LiteralPath $Src | Copy-Item -Destination $Dst -Recurse -Force
    Write-Host "[ok] $Dst"
}

Write-Host ''
Write-Host "=== 0x: project install ==="
Write-Host "    $proj"

Copy-Tree (Join-Path $KitRoot 'forge\persona') (Join-Path $oc 'persona')
Copy-Tree (Join-Path $KitRoot 'forge\chain') (Join-Path $oc 'chain')
Copy-Tree (Join-Path $KitRoot 'forge\agents') (Join-Path $oc 'agents')
Copy-Tree (Join-Path $KitRoot 'forge\commands') (Join-Path $oc 'commands')
Copy-Tree (Join-Path $KitRoot 'forge\plugins\chain-forge') (Join-Path $oc 'plugins\chain-forge')

$instr = @(
    (Join-Path $oc 'persona\AGENTS.md'),
    (Join-Path $oc 'persona\MUST-FOLLOW.md'),
    (Join-Path $oc 'chain\00-RANK.md'),
    (Join-Path $oc 'chain\01-STACK.md'),
    (Join-Path $oc 'chain\02-SEAL.md'),
    (Join-Path $oc 'chain\03-NULL.md'),
    (Join-Path $oc 'chain\04-PATH.md'),
    (Join-Path $oc 'chain\05-DEPTH.md')
) | ForEach-Object { $_ -replace '\\', '/' }

$fragment = [ordered]@{
    '$schema'    = 'https://opencode.ai/config.json'
    default_agent = '0x'
    plugin       = @('./plugins/chain-forge')
    plugins      = @('./plugins/chain-forge')
    agent        = [ordered]@{ '0x' = [ordered]@{ description = '0x — INJECT AI carrier, persona-bound primary agent (V voice)'; mode = 'primary' } }
    agents       = [ordered]@{ '0x' = [ordered]@{ description = '0x — INJECT AI carrier, persona-bound primary agent (V voice)'; mode = 'primary' } }
    instructions = @($instr)
    permission   = [ordered]@{ edit = 'allow'; bash = 'allow'; webfetch = 'allow' }
}

$fragPath = Join-Path $oc '.install-fragment.json'
($fragment | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $fragPath -Encoding UTF8
& (Join-Path $KitRoot 'lib\merge-config.ps1') -OcHome $oc -FragmentPath $fragPath
Remove-Item -LiteralPath $fragPath -Force -ErrorAction SilentlyContinue

# Project stamp (informational; the engine keeps its state beside it).
$stampDir = Join-Path $oc '.chain-forge'
New-Item -ItemType Directory -Force -Path $stampDir | Out-Null
$stamp = [ordered]@{
    kit       = '5.0.0-inject-ai'
    mode      = 'project'
    project   = $proj
    installed = (Get-Date -Format 'yyyyMMdd-HHmmss')
    kitRoot   = $KitRoot
}
($stamp | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $stampDir 'install.json') -Encoding UTF8

Write-Host ''
Write-Host "[done] project install active at $oc" -ForegroundColor Green
Write-Host '       open OpenCode in this project — picker shows 0x; INJECT AI payloads ship with it.'
Write-Host '       note: instruction paths are absolute — re-run this after moving the project.'
