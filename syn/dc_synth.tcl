# =============================================================================
# dc_synth.tcl - Synopsys Design Compiler Synthesis Script for Kyber NTT
#
#   Usage:
#     cd syn
#     dc_shell -f dc_synth.tcl | tee dc_synth.log
#
#   Environment variable overrides (optional):
#     NTT_TARGET_LIB   : path to target .db library (default: TSMC 65nm placeholder)
#     NTT_TOP_MODULE   : ntt_axil_top (default) or ntt_core
#     NTT_CLK_NS       : clock period in ns (default: 5.0 -> 200 MHz)
# =============================================================================

set PROJ_ROOT   [file normalize [file dirname [info script]]/..]
set TOP_MODULE  [expr {[info exists ::env(NTT_TOP_MODULE)] ? $::env(NTT_TOP_MODULE) : "ntt_axil_top"}]
set CLK_PERIOD_NS [expr {[info exists ::env(NTT_CLK_NS)]   ? $::env(NTT_CLK_NS)     : 5.0}]
set TARGET_LIB  [expr {[info exists ::env(NTT_TARGET_LIB)] ? $::env(NTT_TARGET_LIB) : "tcbn65gpluswc.db"}]

file mkdir "$PROJ_ROOT/syn/reports"
file mkdir "$PROJ_ROOT/syn/out"
file mkdir "$PROJ_ROOT/syn/work"

# -----------------------------------------------------------------------------
# 1. Library Setup
# -----------------------------------------------------------------------------
set_app_var search_path [list "." "$PROJ_ROOT/rtl" "$PROJ_ROOT/syn"]
set_app_var target_library [list $TARGET_LIB]
set_app_var link_library   [list "*" $TARGET_LIB "dw_foundation.sldb"]
set_app_var synthetic_library [list "dw_foundation.sldb"]

define_design_lib WORK -path "$PROJ_ROOT/syn/work"
set_svf "$PROJ_ROOT/syn/out/${TOP_MODULE}.svf"

# -----------------------------------------------------------------------------
# 2. Read & Elaborate RTL
# -----------------------------------------------------------------------------
set RTL_FILES [list \
    "$PROJ_ROOT/rtl/mod_add.v"        \
    "$PROJ_ROOT/rtl/mod_sub.v"        \
    "$PROJ_ROOT/rtl/mod_mult.v"       \
    "$PROJ_ROOT/rtl/butterfly_unit.v" \
    "$PROJ_ROOT/rtl/twiddle_rom.v"    \
    "$PROJ_ROOT/rtl/coeff_mem.v"      \
    "$PROJ_ROOT/rtl/ntt_addr_gen.v"   \
    "$PROJ_ROOT/rtl/ntt_ctrl.v"       \
    "$PROJ_ROOT/rtl/ntt_core.v"       \
    "$PROJ_ROOT/rtl/ntt_axil_top.v"   \
]

analyze -format verilog -library WORK $RTL_FILES
elaborate $TOP_MODULE -library WORK
current_design $TOP_MODULE
link
uniquify

check_design > "$PROJ_ROOT/syn/reports/check_design.rpt"

# -----------------------------------------------------------------------------
# 3. Timing & Optimization Constraints
# -----------------------------------------------------------------------------
source "$PROJ_ROOT/syn/constraints.sdc"

# Clock-gating style (utilizes explicit 'en' enables on datapath & memory)
set_clock_gating_style \
    -sequential_cell latch \
    -positive_edge_logic {integrated} \
    -minimum_bitwidth 4 \
    -max_fanout 32

# Prevent assign statements / tri-state nets in output gate-level netlist
set_fix_multiple_port_nets -all -buffer_constants

# -----------------------------------------------------------------------------
# 4. Compile (High-effort synthesis with architectural & clock-gating opt)
# -----------------------------------------------------------------------------
compile_ultra -gate_clock -no_autoungroup

# Resolve naming rules for Verilog netlist export
change_names -rules verilog -hierarchy

# -----------------------------------------------------------------------------
# 5. Export Netlist, SDF, Constraints, DDC
# -----------------------------------------------------------------------------
write -format verilog -hierarchy -output "$PROJ_ROOT/syn/out/${TOP_MODULE}_netlist.v"
write -format ddc     -hierarchy -output "$PROJ_ROOT/syn/out/${TOP_MODULE}.ddc"
write_sdf "$PROJ_ROOT/syn/out/${TOP_MODULE}.sdf"
write_sdc "$PROJ_ROOT/syn/out/${TOP_MODULE}.sdc"

# -----------------------------------------------------------------------------
# 6. Generate PPA & QoR Reports
# -----------------------------------------------------------------------------
report_qor                                   > "$PROJ_ROOT/syn/reports/qor.rpt"
report_area -hierarchy                       > "$PROJ_ROOT/syn/reports/area_hier.rpt"
report_area                                  > "$PROJ_ROOT/syn/reports/area.rpt"
report_timing -delay_type max -max_paths 20  > "$PROJ_ROOT/syn/reports/timing_setup.rpt"
report_timing -delay_type min -max_paths 20  > "$PROJ_ROOT/syn/reports/timing_hold.rpt"
report_power  -hierarchy                     > "$PROJ_ROOT/syn/reports/power_hier.rpt"
report_power                                 > "$PROJ_ROOT/syn/reports/power.rpt"
report_clock_gating                          > "$PROJ_ROOT/syn/reports/clock_gating.rpt"
report_constraint -all_violators             > "$PROJ_ROOT/syn/reports/violators.rpt"

set_svf -off
puts "\[INFO\] Synthesis completed for $TOP_MODULE @ ${CLK_PERIOD_NS} ns."
exit
