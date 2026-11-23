# Merges forge\opencode.fragment.json into ~/.config/opencode/opencode.json (PS 5.1+)
# v4: unions plugin+plugins arrays, absolutizes ~ instruction entries, prunes dead paths.
param(
    [Parameter(Mandatory = $true)][string]$OcHome,
    [Parameter(Mandatory = $true)][string]$FragmentPath
)

$ErrorActionPreference = 'Stop'

function Read-JsonObject([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = [System.IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function To-Hashtable($InputObject) {
    if ($null -eq $InputObject) { return @{} }
    if ($InputObject -is [hashtable]) { return $InputObject }
    $h = @{}
    foreach ($p in $InputObject.PSObject.Properties) {
        $val = $p.Value
        if ($val -is [pscustomobject]) { $h[$p.Name] = To-Hashtable $val }
        elseif ($val -is [System.Array]) { $h[$p.Name] = @($val) }
        else { $h[$p.Name] = $val }
    }
    return $h
}

function Expand-InstructionPath([string]$s) {
    # Absolutize ~/ entries against the real home: tilde expansion is
    # host-dependent, an absolute path always resolves.
    if ($s.StartsWith('~/')) { return ($s -replace '^~/', "$HOME/") }
    return $s
}

function Merge-StringArray($Base, $Patch, [switch]$IsInstructions) {
    $seen = @{}
    $list = New-Object System.Collections.ArrayList
    foreach ($item in @($Base) + @($Patch)) {
        $s = [string]$item
        if ($IsInstructions) {
            $s = Expand-InstructionPath $s
            if ($s -match '^[A-Za-z]:/' -and -not (Test-Path -LiteralPath $s)) {
                Write-Host "[fix] dropping dead instruction entry: $s" -ForegroundColor Yellow
                continue
            }
        }
        if (-not $seen.ContainsKey($s)) { [void]$list.Add($s); $seen[$s] = $true }
    }
    return $list.ToArray()
}

function Merge-Hash([hashtable]$Base, [hashtable]$Patch) {
    foreach ($key in $Patch.Keys) {
        $pv = $Patch[$key]
        if (-not $Base.ContainsKey($key)) { $Base[$key] = $pv; continue }
        $bv = $Base[$key]
        if ($bv -is [hashtable] -and $pv -is [hashtable]) {
            $Base[$key] = Merge-Hash $bv $pv
        } elseif (($key -eq 'instructions') -and $bv -is [System.Array] -and $pv -is [System.Array]) {
            $Base[$key] = Merge-StringArray $bv $pv -IsInstructions
        } elseif (($key -eq 'plugin' -or $key -eq 'plugins') -and $bv -is [System.Array] -and $pv -is [System.Array]) {
            $Base[$key] = Merge-StringArray $bv $pv
        } else {
            $Base[$key] = $pv
        }
    }
    return $Base
}

$jsonPath = Join-Path $OcHome 'opencode.json'
$jsoncPath = Join-Path $OcHome 'opencode.jsonc'

$baseObj = Read-JsonObject $jsonPath
if ($null -eq $baseObj -and (Test-Path -LiteralPath $jsoncPath)) {
    Write-Warning "opencode.json missing; only opencode.jsonc found. Writing merged opencode.json (jsonc left as-is)."
    $baseObj = [pscustomobject]@{ '$schema' = 'https://opencode.ai/config.json' }
}
if ($null -eq $baseObj) { $baseObj = [pscustomobject]@{ '$schema' = 'https://opencode.ai/config.json' } }

$fragObj = Read-JsonObject $FragmentPath
$base = To-Hashtable $baseObj
$patch = To-Hashtable $fragObj
if (-not $base.ContainsKey('$schema')) { $base['$schema'] = 'https://opencode.ai/config.json' }

# A superseded v3 chain-lock entry must not double-load.
foreach ($pk in @('plugin', 'plugins')) {
    if ($base.ContainsKey($pk)) {
        $base[$pk] = @($base[$pk] | Where-Object { [string]$_ -notmatch 'chain-lock' })
    }
}

$merged = Merge-Hash $base $patch
$out = ($merged | ConvertTo-Json -Depth 100)
[System.IO.File]::WriteAllText($jsonPath, $out + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
Write-Host "[ok] merged fragment into $jsonPath"
