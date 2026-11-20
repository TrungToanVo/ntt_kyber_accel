# =============================================================================
# constraints.sdc - Synopsys Design Constraints for ntt_axil_top / ntt_core
#   Target Technology : TSMC 65nm GP (or equivalent standard-cell library)
#   Default Clock     : 200 MHz (5.0 ns) - override via CLK_PERIOD_NS in DC/PT
# =============================================================================

if {![info exists CLK_PERIOD_NS]} {
    set CLK_PERIOD_NS 5.0
}

# Detect clock and reset ports automatically (works for both ntt_axil_top & ntt_core)
if {[sizeof_collection [get_ports -quiet s_axi_aclk]] > 0} {
    set CLK_PORT "s_axi_aclk"
    set RST_PORT "s_axi_aresetn"
} else {
    set CLK_PORT "clk"
    set RST_PORT "rst_n"
}

# 1. Master Clock Definition
create_clock -name clk_main -period $CLK_PERIOD_NS [get_ports $CLK_PORT]

# Clock uncertainty (PLL jitter + clock tree skew margin) & transition
set_clock_uncertainty -setup [expr {0.06 * $CLK_PERIOD_NS}] [get_clocks clk_main]
set_clock_uncertainty -hold  0.08                           [get_clocks clk_main]
set_clock_transition         [expr {0.04 * $CLK_PERIOD_NS}] [get_clocks clk_main]

# Do not buffer clock/reset trees during logic synthesis (handled in CTS)
set_ideal_network [get_ports $CLK_PORT]
set_ideal_network [get_ports $RST_PORT]
set_false_path -from [get_ports $RST_PORT]

# 2. I/O Timing Constraints (30% of clock period budgeted to external logic)
set IO_DELAY [expr {0.30 * $CLK_PERIOD_NS}]
set DATA_IN_PORTS [remove_from_collection [all_inputs] [get_ports [list $CLK_PORT $RST_PORT]]]

set_input_delay  -max $IO_DELAY -clock clk_main $DATA_IN_PORTS
set_input_delay  -min 0.20      -clock clk_main $DATA_IN_PORTS
set_output_delay -max $IO_DELAY -clock clk_main [all_outputs]
set_output_delay -min 0.10      -clock clk_main [all_outputs]

# 3. Electrical / DRC Constraints
set_max_transition  [expr {0.10 * $CLK_PERIOD_NS}] [current_design]
set_max_fanout      24                             [current_design]
set_input_transition 0.15                          $DATA_IN_PORTS
set_load            0.05                           [all_outputs]
