library verilog;
use verilog.vl_types.all;
entity butterfly_unit is
    port(
        clk             : in     vl_logic;
        en              : in     vl_logic;
        mode_s1         : in     vl_logic_vector(1 downto 0);
        a_s1            : in     vl_logic_vector(11 downto 0);
        b_s1            : in     vl_logic_vector(11 downto 0);
        zeta_s1         : in     vl_logic_vector(11 downto 0);
        a_out           : out    vl_logic_vector(11 downto 0);
        b_out           : out    vl_logic_vector(11 downto 0)
    );
end butterfly_unit;
