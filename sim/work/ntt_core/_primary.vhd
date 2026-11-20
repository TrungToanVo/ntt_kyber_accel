library verilog;
use verilog.vl_types.all;
entity ntt_core is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        start           : in     vl_logic;
        mode_intt       : in     vl_logic;
        busy            : out    vl_logic;
        done            : out    vl_logic;
        cycle_cnt       : out    vl_logic_vector(15 downto 0);
        host_en         : in     vl_logic;
        host_we         : in     vl_logic;
        host_addr       : in     vl_logic_vector(7 downto 0);
        host_wdata      : in     vl_logic_vector(11 downto 0);
        host_rdata      : out    vl_logic_vector(11 downto 0)
    );
end ntt_core;
