library verilog;
use verilog.vl_types.all;
entity twiddle_rom is
    port(
        clk             : in     vl_logic;
        en              : in     vl_logic;
        addr            : in     vl_logic_vector(6 downto 0);
        zeta            : out    vl_logic_vector(11 downto 0)
    );
end twiddle_rom;
