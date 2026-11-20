#!/usr/bin/env pwsh
# =============================================================================
# run_sim.ps1 - Run all RTL simulations (Vivado Simulator xsim or ModelSim vsim)
#   Usage :  cd sim ; ./run_sim.ps1            (all tests, 100 vectors)
#            ./run_sim.ps1 -NVec 1000          (stress test, regenerate vectors)
#            ./run_sim.ps1 -Test top           (only the system test)
#            ./run_sim.ps1 -Sim modelsim       (force ModelSim)
# =============================================================================
param(
    [int]$NVec = 100,
    [ValidateSet("all", "mod_mult", "butterfly", "top")]
    [string]$Test = "all",
    [ValidateSet("auto", "xsim", "modelsim")]
    [string]$Sim = "auto"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $PSScriptRoot

# 1. Golden model : ROM + vectors
python "$root/model/ntt_golden.py" --all --nvec $NVec
if ($LASTEXITCODE -ne 0) { throw "golden model self-test failed" }

# 2. Vectors are read relative to the simulation directory
if (Test-Path vectors) { Remove-Item -Recurse -Force vectors }
Copy-Item -Recurse "$root/tb/vectors" vectors

$rtl = Get-Content "$root/sim/rtl_files.f" | Where-Object { $_ -and -not $_.StartsWith("#") } |
       ForEach-Object { Join-Path $root $_ }
$tbs = @("$root/tb/tb_mod_mult.v", "$root/tb/tb_butterfly.v", "$root/tb/tb_ntt_top.v")

# Detect simulator
$vivadoBin = "C:\Xilinx\Vivado\2021.2\bin"
if ($Sim -eq "auto") {
    if (Test-Path "$vivadoBin\xvlog.bat") {
        $Sim = "xsim"
    } else {
        $Sim = "modelsim"
    }
}

if ($Sim -eq "xsim") {
    $env:PATH = "$vivadoBin;$env:PATH"
    Write-Host "[INFO] Using Xilinx Vivado Simulator (xvlog / xelab / xsim)"
    & "$vivadoBin\xvlog.bat" --nolog @rtl @tbs
    if ($LASTEXITCODE -ne 0) { throw "xvlog compilation failed" }

    function Run-Xsim($top) {
        Write-Host "---------------- $top ----------------"
        & "$vivadoBin\xelab.bat" --nolog -debug off $top -s "${top}_snap" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "xelab failed for $top" }
        & "$vivadoBin\xsim.bat" --nolog "${top}_snap" -R |
            Select-String -Pattern "PASS|FAIL|INFO|ERROR|RESULT|=====|Vectors|Sub-tests|latency|Error"
    }

    if ($Test -in "all", "mod_mult")  { Run-Xsim "tb_mod_mult" }
    if ($Test -in "all", "butterfly") { Run-Xsim "tb_butterfly" }
    if ($Test -in "all", "top")       { Run-Xsim "tb_ntt_top" }
} else {
    Write-Host "[INFO] Using ModelSim (vlib / vlog / vsim)"
    if (Test-Path work) { Remove-Item -Recurse -Force work }
    vlib work | Out-Null
    vlog -quiet -work work +incdir+$root/rtl @rtl @tbs
    if ($LASTEXITCODE -ne 0) { throw "vlog compilation failed" }

    function Run-Vsim($top, $extra = "") {
        Write-Host "---------------- $top ----------------"
        vsim -c -quiet work.$top $extra -do "run -all; quit -f" |
            Select-String -Pattern "PASS|FAIL|INFO|ERROR|RESULT|=====|Vectors|Sub-tests|latency|Error"
    }

    if ($Test -in "all", "mod_mult")  { Run-Vsim "tb_mod_mult" }
    if ($Test -in "all", "butterfly") { Run-Vsim "tb_butterfly" }
    if ($Test -in "all", "top")       { Run-Vsim "tb_ntt_top" "+NVEC=$NVec" }
}
