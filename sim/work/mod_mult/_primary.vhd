library verilog;
use verilog.vl_types.all;
entity mod_mult is
    port(
        clk             : in     vl_logic;
        en              : in     vl_logic;
        a               : in     vl_logic_vector(11 downto 0);
        b               : in     vl_logic_vector(11 downto 0);
        y               : out    vl_logic_vector(11 downto 0)
    );
end mod_mult;
