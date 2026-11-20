library verilog;
use verilog.vl_types.all;
entity ntt_axil_top is
    port(
        s_axi_aclk      : in     vl_logic;
        s_axi_aresetn   : in     vl_logic;
        s_axi_awaddr    : in     vl_logic_vector(11 downto 0);
        s_axi_awprot    : in     vl_logic_vector(2 downto 0);
        s_axi_awvalid   : in     vl_logic;
        s_axi_awready   : out    vl_logic;
        s_axi_wdata     : in     vl_logic_vector(31 downto 0);
        s_axi_wstrb     : in     vl_logic_vector(3 downto 0);
        s_axi_wvalid    : in     vl_logic;
        s_axi_wready    : out    vl_logic;
        s_axi_bresp     : out    vl_logic_vector(1 downto 0);
        s_axi_bvalid    : out    vl_logic;
        s_axi_bready    : in     vl_logic;
        s_axi_araddr    : in     vl_logic_vector(11 downto 0);
        s_axi_arprot    : in     vl_logic_vector(2 downto 0);
        s_axi_arvalid   : in     vl_logic;
        s_axi_arready   : out    vl_logic;
        s_axi_rdata     : out    vl_logic_vector(31 downto 0);
        s_axi_rresp     : out    vl_logic_vector(1 downto 0);
        s_axi_rvalid    : out    vl_logic;
        s_axi_rready    : in     vl_logic;
        irq             : out    vl_logic
    );
end ntt_axil_top;
