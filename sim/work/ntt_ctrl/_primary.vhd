library verilog;
use verilog.vl_types.all;
entity ntt_ctrl is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        start           : in     vl_logic;
        mode_intt       : in     vl_logic;
        busy            : out    vl_logic;
        done            : out    vl_logic;
        eng_en_a        : out    vl_logic;
        eng_we_a        : out    vl_logic;
        eng_addr_a      : out    vl_logic_vector(7 downto 0);
        eng_wsel_a      : out    vl_logic;
        eng_en_b        : out    vl_logic;
        eng_we_b        : out    vl_logic;
        eng_addr_b      : out    vl_logic_vector(7 downto 0);
        rom_en          : out    vl_logic;
        rom_addr        : out    vl_logic_vector(6 downto 0);
        dp_en           : out    vl_logic;
        mode_s1         : out    vl_logic_vector(1 downto 0);
        sel_b_s1        : out    vl_logic;
        use_ninv_s1     : out    vl_logic
    );
end ntt_ctrl;
