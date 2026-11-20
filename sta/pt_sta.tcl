# =============================================================================
# pt_sta.tcl - Synopsys PrimeTime Static Timing & Power Analysis Script
#
#   Usage:
#     cd sta
#     pt_shell -f pt_sta.tcl | tee pt_sta.log
#
#   Environment variable overrides (optional):
#     NTT_TARGET_LIB   : path to target .db library (default: tcbn65gpluswc.db)
#     NTT_TOP_MODULE   : ntt_axil_top (default) or ntt_core
#     NTT_SPEF_FILE    : optional post-layout SPEF parasitic file from ICC
#     NTT_VCD_FILE     : optional switching activity VCD/SAIF for PT-PX power
# =============================================================================

set PROJ_ROOT   [file normalize [file dirname [info script]]/..]
set TOP_MODULE  [expr {[info exists ::env(NTT_TOP_MODULE)] ? $::env(NTT_TOP_MODULE) : "ntt_axil_top"}]
set TARGET_LIB  [expr {[info exists ::env(NTT_TARGET_LIB)] ? $::env(NTT_TARGET_LIB) : "tcbn65gpluswc.db"}]
set NETLIST     "$PROJ_ROOT/syn/out/${TOP_MODULE}_netlist.v"
set SDC_FILE    "$PROJ_ROOT/syn/out/${TOP_MODULE}.sdc"

file mkdir "$PROJ_ROOT/sta/reports"

# -----------------------------------------------------------------------------
# 1. Library & Netlist Setup
# -----------------------------------------------------------------------------
set_app_var search_path [list "." "$PROJ_ROOT/syn/out" "$PROJ_ROOT/sta"]
set_app_var link_path   [list "*" $TARGET_LIB]

read_verilog $NETLIST
current_design $TOP_MODULE
link_design

# -----------------------------------------------------------------------------
# 2. Read Constraints & Parasitics (Pre-layout or Post-layout SPEF)
# -----------------------------------------------------------------------------
read_sdc $SDC_FILE

if {[info exists ::env(NTT_SPEF_FILE)] && [file exists $::env(NTT_SPEF_FILE)]} {
    puts "\[INFO\] Reading post-layout SPEF parasitics: $::env(NTT_SPEF_FILE)"
    read_parasitics -format SPEF $::env(NTT_SPEF_FILE)
    set_propagated_clock [all_clocks]
}

# On-Chip Variation (OCV) derating (+/- 5% for 65nm signoff)
set_timing_derate -early 0.95
set_timing_derate -late  1.05
set_app_var timing_remove_clock_reconvergence_pessimism true

# -----------------------------------------------------------------------------
# 3. Timing Verification & Reports
# -----------------------------------------------------------------------------
update_timing -full

check_timing -verbose > "$PROJ_ROOT/sta/reports/check_timing.rpt"
report_global_timing  > "$PROJ_ROOT/sta/reports/global_timing.rpt"

# Setup (Max delay) & Hold (Min delay) critical paths
report_timing -delay_type max -max_paths 30 -input_pins -nets -transition_time -capacitance \
    > "$PROJ_ROOT/sta/reports/timing_setup_max.rpt"
report_timing -delay_type min -max_paths 30 -input_pins -nets -transition_time -capacitance \
    > "$PROJ_ROOT/sta/reports/timing_hold_min.rpt"

# Bottleneck & Clock Skew / Latency analysis
report_bottleneck -max_cells 20           > "$PROJ_ROOT/sta/reports/bottleneck.rpt"
report_clock_timing -type summary         > "$PROJ_ROOT/sta/reports/clock_summary.rpt"
report_clock_timing -type skew            > "$PROJ_ROOT/sta/reports/clock_skew.rpt"
report_clock_timing -type latency         > "$PROJ_ROOT/sta/reports/clock_latency.rpt"
report_constraint -all_violators -verbose > "$PROJ_ROOT/sta/reports/violators.rpt"

# Export SDF for gate-level post-STA timing simulation
write_sdf "$PROJ_ROOT/sta/reports/${TOP_MODULE}_pt.sdf"

# -----------------------------------------------------------------------------
# 4. PrimeTime PX Power Analysis (optional if VCD is provided)
# -----------------------------------------------------------------------------
if {[info exists ::env(NTT_VCD_FILE)] && [file exists $::env(NTT_VCD_FILE)]} {
    set_app_var power_enable_analysis true
    set_app_var power_analysis_mode time_based
    read_vcd -strip_path "tb_ntt_top/dut" $::env(NTT_VCD_FILE)
    update_power
    report_power -hierarchy > "$PROJ_ROOT/sta/reports/ptpx_power_hier.rpt"
    report_power -verbose   > "$PROJ_ROOT/sta/reports/ptpx_power.rpt"
}

puts "\[INFO\] PrimeTime STA completed. Reports saved in sta/reports/."
exit
