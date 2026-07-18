[CmdletBinding()]
param(
    [ValidateSet("BoardCheck", "PPA", "ProjectCreate", "Synthesis", "Stage1", "ProjectSynth", "Implementation")]
    [string]$Stage = "BoardCheck",
    [string]$VivadoPath = "vivado",
    [string]$BoardRepo = $env:ULTRA96_BOARD_REPO
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$reportRoot = Join-Path $projectRoot "hardware\reports\ultra96_v2"

if ([System.IO.Path]::IsPathRooted($VivadoPath) -and !(Test-Path -LiteralPath $VivadoPath)) {
    throw "Vivado was not found at $VivadoPath"
}
if ($BoardRepo) {
    if (!(Test-Path -LiteralPath $BoardRepo)) {
        throw "Ultra96 board repository was not found at $BoardRepo"
    }
    $env:ULTRA96_BOARD_REPO = (Resolve-Path -LiteralPath $BoardRepo).Path
}

New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null

function Invoke-VivadoScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptName,
        [Parameter(Mandatory = $true)][string]$LogName
    )

    $scriptPath = Join-Path $projectRoot "vivado\scripts\$ScriptName"
    $logPath = Join-Path $reportRoot $LogName
    $journalPath = [System.IO.Path]::ChangeExtension($logPath, ".jou")

    & $VivadoPath -mode batch -source $scriptPath -log $logPath -journal $journalPath
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado failed for $ScriptName. See $logPath"
    }
}

switch ($Stage) {
    "BoardCheck" {
        Invoke-VivadoScript "check_ultra96_v2_board.tcl" "board_check.log"
    }
    "PPA" {
        Invoke-VivadoScript "run_ultra96_v2_parallelism_sweep.tcl" "parallelism_sweep.log"
    }
    "ProjectCreate" {
        Invoke-VivadoScript "create_ultra96_v2_production_v2_project.tcl" "production_v2_create.log"
    }
    "Synthesis" {
        Invoke-VivadoScript "run_ultra96_v2_production_v2_synth.tcl" "production_v2_synth.log"
    }
    "Stage1" {
        Invoke-VivadoScript "check_ultra96_v2_board.tcl" "board_check.log"
        Invoke-VivadoScript "run_ultra96_v2_parallelism_sweep.tcl" "parallelism_sweep.log"
        Invoke-VivadoScript "create_ultra96_v2_production_v2_project.tcl" "production_v2_create.log"
        Invoke-VivadoScript "run_ultra96_v2_production_v2_synth.tcl" "production_v2_synth.log"
    }
    "ProjectSynth" {
        Invoke-VivadoScript "create_ultra96_v2_production_v2_project.tcl" "production_v2_create.log"
        Invoke-VivadoScript "run_ultra96_v2_production_v2_synth.tcl" "production_v2_synth.log"
    }
    "Implementation" {
        Invoke-VivadoScript "run_ultra96_v2_production_v2_implementation.tcl" "production_v2_implementation.log"
    }
}

Write-Host "Ultra96-V2 $Stage complete. Reports: $reportRoot"
