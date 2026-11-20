library verilog;
use verilog.vl_types.all;
entity coeff_mem is
    generic(
        AW              : integer := 8;
        DW              : integer := 12
    );
    port(
        clk             : in     vl_logic;
        en_a            : in     vl_logic;
        we_a            : in     vl_logic;
        addr_a          : in     vl_logic_vector;
        din_a           : in     vl_logic_vector;
        dout_a          : out    vl_logic_vector;
        en_b            : in     vl_logic;
        we_b            : in     vl_logic;
        addr_b          : in     vl_logic_vector;
        din_b           : in     vl_logic_vector;
        dout_b          : out    vl_logic_vector
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of AW : constant is 1;
    attribute mti_svvh_generic_type of DW : constant is 1;
end coeff_mem;
