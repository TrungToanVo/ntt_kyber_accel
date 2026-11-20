library verilog;
use verilog.vl_types.all;
entity mod_add is
    generic(
        W               : integer := 12;
        Q               : vl_logic_vector
    );
    port(
        a               : in     vl_logic_vector;
        b               : in     vl_logic_vector;
        y               : out    vl_logic_vector
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of W : constant is 1;
    attribute mti_svvh_generic_type of Q : constant is 4;
end mod_add;
