// =============================================================================
// ntt_axil_top.v - AXI4-Lite slave wrapper of the Kyber NTT accelerator
//                  (top level for ASIC synthesis / SoC integration)
//
//   Register map (32-bit, byte addresses):
//     0x000 CTRL    [0] START (W, self-clearing)   [1] MODE (0 NTT, 1 INTT)
//                   [2] IRQ_EN
//     0x004 STATUS  [0] BUSY (RO)                  [1] DONE (sticky, W1C)
//     0x008 CYCLES  [15:0] cycles of last operation (RO)
//     0x00C ID      0x4E545401  ("NTT", version 1) (RO)
//     0x010 PARAM   [31:16] n = 256, [15:0] q = 3329 (RO)
//     0x400..0x7FC  COEFF[0..255], bits [11:0]
//                   Write values >= q are reduced (x - q) automatically.
//                   Access while BUSY returns SLVERR.
//
//   AXI4-Lite notes: AW and W are accepted together in the same cycle; one
//   outstanding transaction per channel; read data has 1 cycle latency.
// =============================================================================
`timescale 1ns/1ps
module ntt_axil_top (
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,
    // write address channel
    input  wire [11:0] s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    // write data channel
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    // write response channel
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    // read address channel
    input  wire [11:0] s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    // read data channel
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,
    // interrupt
    output wire        irq
);
    localparam [1:0]  RESP_OKAY   = 2'b00,
                      RESP_SLVERR = 2'b10;
    localparam [11:0] Q           = 12'd3329;
    localparam [31:0] ID_VALUE    = 32'h4E54_5401;
    localparam [31:0] PARAM_VALUE = {16'd256, 16'd3329};

    localparam [9:0]  REG_CTRL   = 10'h000 >> 2,
                      REG_STATUS = 10'h004 >> 2,
                      REG_CYCLES = 10'h008 >> 2,
                      REG_ID     = 10'h00C >> 2,
                      REG_PARAM  = 10'h010 >> 2;

    wire clk   = s_axi_aclk;
    wire rst_n = s_axi_aresetn;

    // ------------------------------------------------------------------------
    // Core
    // ------------------------------------------------------------------------
    wire        busy, done;
    wire [15:0] cycle_cnt;
    wire [11:0] host_rdata;
    reg         start_p;
    reg         mode_r, irq_en_r, done_r;
    reg         host_en, host_we;
    reg  [7:0]  host_addr;
    reg  [11:0] host_wdata;

    ntt_core u_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start_p),
        .mode_intt  (mode_r),
        .busy       (busy),
        .done       (done),
        .cycle_cnt  (cycle_cnt),
        .host_en    (host_en),
        .host_we    (host_we),
        .host_addr  (host_addr),
        .host_wdata (host_wdata),
        .host_rdata (host_rdata)
    );

    // ------------------------------------------------------------------------
    // Write channel
    // ------------------------------------------------------------------------
    wire        wr_fire   = s_axi_awvalid & s_axi_wvalid & ~s_axi_bvalid;
    wire        wr_coeff  = (s_axi_awaddr[11:10] == 2'b01);
    wire [9:0]  wr_word   = s_axi_awaddr[11:2];
    wire [11:0] wr_val    = s_axi_wdata[11:0];
    wire [11:0] wr_val_red= (wr_val >= Q) ? (wr_val - Q) : wr_val;  // < q

    assign s_axi_awready = wr_fire;
    assign s_axi_wready  = wr_fire;

    // ------------------------------------------------------------------------
    // Read channel
    // ------------------------------------------------------------------------
    reg         rd_pend;            // read accepted, data next cycle
    reg         rd_is_coeff;
    reg  [9:0]  rd_word_r;
    reg         rd_err_r;
    wire        rd_fire  = s_axi_arvalid & ~s_axi_rvalid & ~rd_pend & ~wr_fire;
    wire        rd_coeff = (s_axi_araddr[11:10] == 2'b01);

    assign s_axi_arready = rd_fire;

    // host memory port: write has priority, read only when no write fires
    always @(*) begin
        host_en    = 1'b0;
        host_we    = 1'b0;
        host_addr  = 8'd0;
        host_wdata = wr_val_red;
        if (wr_fire && wr_coeff && !busy) begin
            host_en   = 1'b1;
            host_we   = 1'b1;
            host_addr = s_axi_awaddr[9:2];
        end else if (rd_fire && rd_coeff && !busy) begin
            host_en   = 1'b1;
            host_addr = s_axi_araddr[9:2];
        end
    end

    // ------------------------------------------------------------------------
    // Registers, write response
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= RESP_OKAY;
            start_p      <= 1'b0;
            mode_r       <= 1'b0;
            irq_en_r     <= 1'b0;
            done_r       <= 1'b0;
        end else begin
            start_p <= 1'b0;
            if (done) done_r <= 1'b1;

            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;

            if (wr_fire) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= RESP_OKAY;
                if (wr_coeff) begin
                    if (busy) s_axi_bresp <= RESP_SLVERR;
                end else begin
                    case (wr_word)
                        REG_CTRL: begin
                            if (s_axi_wstrb[0]) begin
                                irq_en_r <= s_axi_wdata[2];
                                if (!busy) begin
                                    mode_r <= s_axi_wdata[1];
                                    if (s_axi_wdata[0]) begin
                                        start_p <= 1'b1;
                                        done_r  <= 1'b0;
                                    end
                                end else if (s_axi_wdata[0]) begin
                                    s_axi_bresp <= RESP_SLVERR;  // start while busy
                                end
                            end
                        end
                        REG_STATUS: begin
                            if (s_axi_wstrb[0] && s_axi_wdata[1]) done_r <= 1'b0;
                        end
                        default: ;  // read-only / unmapped: ignored
                    endcase
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // Read data
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_pend      <= 1'b0;
            rd_is_coeff  <= 1'b0;
            rd_word_r    <= 10'd0;
            rd_err_r     <= 1'b0;
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= 32'd0;
            s_axi_rresp  <= RESP_OKAY;
        end else begin
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;

            if (rd_fire) begin
                rd_pend     <= 1'b1;
                rd_is_coeff <= rd_coeff;
                rd_word_r   <= s_axi_araddr[11:2];
                rd_err_r    <= rd_coeff & busy;
            end

            if (rd_pend) begin
                rd_pend      <= 1'b0;
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= rd_err_r ? RESP_SLVERR : RESP_OKAY;
                if (rd_is_coeff) begin
                    s_axi_rdata <= rd_err_r ? 32'd0 : {20'd0, host_rdata};
                end else begin
                    case (rd_word_r)
                        REG_CTRL:   s_axi_rdata <= {29'd0, irq_en_r, mode_r, 1'b0};
                        REG_STATUS: s_axi_rdata <= {30'd0, done_r, busy};
                        REG_CYCLES: s_axi_rdata <= {16'd0, cycle_cnt};
                        REG_ID:     s_axi_rdata <= ID_VALUE;
                        REG_PARAM:  s_axi_rdata <= PARAM_VALUE;
                        default:    s_axi_rdata <= 32'd0;
                    endcase
                end
            end
        end
    end

    assign irq = done_r & irq_en_r;
endmodule
