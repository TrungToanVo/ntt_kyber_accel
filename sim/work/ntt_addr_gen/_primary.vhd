library verilog;
use verilog.vl_types.all;
entity ntt_addr_gen is
    port(
        layer           : in     vl_logic_vector(2 downto 0);
        k               : in     vl_logic_vector(6 downto 0);
        intt            : in     vl_logic;
        addr_a          : out    vl_logic_vector(7 downto 0);
        addr_b          : out    vl_logic_vector(7 downto 0);
        tw_idx          : out    vl_logic_vector(6 downto 0)
    );
end ntt_addr_gen;
