# Re-apply kit payloads + re-merge config without forcing AGENTS.md.
param(
    [Parameter(Mandatory = $true)][string]$KitRoot,
    [Parameter(Mandatory = $true)][string]$OcHome,
    [switch]$KeepAgentsMd
)

$ErrorActionPreference = 'Stop'
& (Join-Path $KitRoot 'lib\install.ps1') `
    -KitRoot $KitRoot `
    -OcHome $OcHome `
    -BackupRoot (Join-Path $OcHome '.persona-kit-backups') `
    -ForceAgentsMd:(-not $KeepAgentsMd) `
    -SkipRestart
Write-Host "[ok] repair finished — restart OpenCode (menu 3) to re-arm the plugin."
