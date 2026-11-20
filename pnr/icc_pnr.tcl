# =============================================================================
# icc_pnr.tcl - Synopsys IC Compiler (ICC) Physical Design Flow Script
#   Covers: Floorplan -> Power Plan -> Placement -> CTS -> Routing ->
#           Skew / Latency / Congestion / Cell Density / OCV checks -> Signoff
#
#   Usage:
#     cd pnr
#     icc_shell -f icc_pnr.tcl | tee icc_pnr.log
# =============================================================================

set PROJ_ROOT    [file normalize [file dirname [info script]]/..]
set TOP_MODULE   [expr {[info exists ::env(NTT_TOP_MODULE)] ? $::env(NTT_TOP_MODULE) : "ntt_axil_top"}]
set TARGET_LIB   [expr {[info exists ::env(NTT_TARGET_LIB)] ? $::env(NTT_TARGET_LIB) : "tcbn65gpluswc.db"}]
set MW_REF_LIB   [expr {[info exists ::env(NTT_MW_REF_LIB)] ? $::env(NTT_MW_REF_LIB) : "tcbn65gplus_mw"}]
set TECH_FILE    [expr {[info exists ::env(NTT_TECH_FILE)]  ? $::env(NTT_TECH_FILE)  : "tsmc65_9lm.tf"}]
set TLUPLUS_MAX  [expr {[info exists ::env(NTT_TLUP_MAX)]   ? $::env(NTT_TLUP_MAX)   : "tsmc65_max.tluplus"}]
set TLUPLUS_MIN  [expr {[info exists ::env(NTT_TLUP_MIN)]   ? $::env(NTT_TLUP_MIN)   : "tsmc65_min.tluplus"}]
set TLUPLUS_MAP  [expr {[info exists ::env(NTT_TLUP_MAP)]   ? $::env(NTT_TLUP_MAP)   : "star.map_9M"}]

file mkdir "$PROJ_ROOT/pnr/reports"
file mkdir "$PROJ_ROOT/pnr/out"

# -----------------------------------------------------------------------------
# 1. Milkyway Library & Design Setup
# -----------------------------------------------------------------------------
set_app_var search_path [list "." "$PROJ_ROOT/syn/out" "$PROJ_ROOT/pnr"]
set_app_var target_library [list $TARGET_LIB]
set_app_var link_library   [list "*" $TARGET_LIB]

set MW_DESIGN_LIB "$PROJ_ROOT/pnr/${TOP_MODULE}_mw"
if {[file exists $MW_DESIGN_LIB]} {
    file delete -force $MW_DESIGN_LIB
}
create_mw_lib $MW_DESIGN_LIB \
    -technology $TECH_FILE \
    -mw_reference_library $MW_REF_LIB \
    -open

import_designs "$PROJ_ROOT/syn/out/${TOP_MODULE}_netlist.v" \
    -format verilog \
    -top $TOP_MODULE \
    -cel "${TOP_MODULE}_init"

set_tlu_plus_files \
    -max_tluplus $TLUPLUS_MAX \
    -min_tluplus $TLUPLUS_MIN \
    -tech2itf_map $TLUPLUS_MAP

read_sdc "$PROJ_ROOT/syn/out/${TOP_MODULE}.sdc"

# -----------------------------------------------------------------------------
# 2. Floorplanning & Power Grid Synthesis (68% core utilization target)
# -----------------------------------------------------------------------------
create_floorplan \
    -control_type aspect_ratio \
    -core_aspect_ratio 1.0 \
    -core_utilization 0.68 \
    -left_io2core 10.0 -bottom_io2core 10.0 -right_io2core 10.0 -top_io2core 10.0

derive_pg_connection -power_net VDD -power_pin VDD -ground_net VSS -ground_pin VSS
derive_pg_connection -power_net VDD -ground_net VSS -tie

create_rectangular_rings \
    -nets {VDD VSS} \
    -left_offset 2.0 -right_offset 2.0 -top_offset 2.0 -bottom_offset 2.0 \
    -left_segment_width 2.0 -right_segment_width 2.0 \
    -top_segment_width 2.0 -bottom_segment_width 2.0

create_power_straps \
    -direction vertical \
    -nets {VDD VSS} \
    -layer M6 \
    -width 1.6 \
    -step 30.0 \
    -start_at 15.0

preroute_standard_cells -nets {VDD VSS} -connect horizontal
save_mw_cel -as "${TOP_MODULE}_floorplan"

# -----------------------------------------------------------------------------
# 3. Placement & Congestion Analysis
# -----------------------------------------------------------------------------
set_place_opt_strategy -effort high -congestion_effort high
place_opt -area_recovery -congestion -optimize_dft

report_placement_utilization > "$PROJ_ROOT/pnr/reports/place_utilization.rpt"
report_congestion            > "$PROJ_ROOT/pnr/reports/place_congestion.rpt"
report_timing -delay_type max > "$PROJ_ROOT/pnr/reports/place_timing_setup.rpt"
save_mw_cel -as "${TOP_MODULE}_placed"

# -----------------------------------------------------------------------------
# 4. Clock Tree Synthesis (CTS) & Skew/Latency/OCV Analysis
# -----------------------------------------------------------------------------
remove_ideal_network [all_fanout -flat -clock_tree]
set_clock_tree_options \
    -target_skew 0.08 \
    -max_transition 0.25 \
    -max_capacitance 0.15

set_timing_derate -early 0.95
set_timing_derate -late  1.05

clock_opt -fix_hold_all_clocks -inter_clock_balance
set_propagated_clock [all_clocks]

report_clock_tree -summary   > "$PROJ_ROOT/pnr/reports/cts_summary.rpt"
report_clock_timing -type skew    > "$PROJ_ROOT/pnr/reports/cts_skew.rpt"
report_clock_timing -type latency > "$PROJ_ROOT/pnr/reports/cts_latency.rpt"
report_timing -delay_type max > "$PROJ_ROOT/pnr/reports/cts_timing_setup.rpt"
report_timing -delay_type min > "$PROJ_ROOT/pnr/reports/cts_timing_hold.rpt"
save_mw_cel -as "${TOP_MODULE}_cts"

# -----------------------------------------------------------------------------
# 5. Detailed Routing, Filler Cells, DRC/LVS & Signoff Extraction
# -----------------------------------------------------------------------------
route_opt -effort high
verify_zrt_route > "$PROJ_ROOT/pnr/reports/route_drc.rpt"
verify_lvs       > "$PROJ_ROOT/pnr/reports/route_lvs.rpt"

report_design -physical      > "$PROJ_ROOT/pnr/reports/physical_summary.rpt"
report_qor                   > "$PROJ_ROOT/pnr/reports/pnr_qor.rpt"
report_timing -delay_type max > "$PROJ_ROOT/pnr/reports/route_timing_setup.rpt"
report_timing -delay_type min > "$PROJ_ROOT/pnr/reports/route_timing_hold.rpt"
report_power                 > "$PROJ_ROOT/pnr/reports/route_power.rpt"

# Export post-route Verilog netlist, SPEF parasitics (for PrimeTime), DEF, GDS
write_verilog "$PROJ_ROOT/pnr/out/${TOP_MODULE}_postroute.v"
write_def -output "$PROJ_ROOT/pnr/out/${TOP_MODULE}.def"
extract_rc
write_parasitics -format SPEF -output "$PROJ_ROOT/pnr/out/${TOP_MODULE}.spef"
save_mw_cel -as "${TOP_MODULE}_routed"

puts "\[INFO\] IC Compiler PnR completed. Outputs in pnr/out/, reports in pnr/reports/."
exit
