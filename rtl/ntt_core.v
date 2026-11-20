// =============================================================================
// ntt_core.v - Kyber NTT / INTT accelerator core (native interface)
//
//   +-------------+    +-----------+    +----------------+
//   | coeff_mem   |--->| butterfly |--->| write-back     |
//   | 256x12 DP   |<---| unit (BFU)|    | (in-place)     |
//   +-------------+    +-----------+    +----------------+
//          ^                 ^
//          |           twiddle_rom (128 x 12)
//      ntt_ctrl (FSM + address generator)
//
//   Host port (shares memory port A) may only be used while busy = 0.
//   Host read data is available on host_rdata one cycle after host_en.
// =============================================================================
`timescale 1ns/1ps
module ntt_core (
    input  wire        clk,
    input  wire        rst_n,
    // command / status
    input  wire        start,
    input  wire        mode_intt,
    output wire        busy,
    output wire        done,
    output reg  [15:0] cycle_cnt,     // clock cycles of last / current operation
    // host memory port (valid only when busy = 0)
    input  wire        host_en,
    input  wire        host_we,
    input  wire [7:0]  host_addr,
    input  wire [11:0] host_wdata,    // must be < q
    output wire [11:0] host_rdata
);
    localparam [11:0] N_INV = 12'd3303;     // 128^-1 mod 3329

    // ------------------------------------------------------------------------
    // Controller
    // ------------------------------------------------------------------------
    wire       eng_en_a, eng_we_a, eng_wsel_a;
    wire       eng_en_b, eng_we_b;
    wire [7:0] eng_addr_a, eng_addr_b;
    wire       rom_en;
    wire [6:0] rom_addr;
    wire       dp_en, sel_b_s1, use_ninv_s1;
    wire [1:0] mode_s1;

    ntt_ctrl u_ctrl (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (start),
        .mode_intt   (mode_intt),
        .busy        (busy),
        .done        (done),
        .eng_en_a    (eng_en_a),
        .eng_we_a    (eng_we_a),
        .eng_addr_a  (eng_addr_a),
        .eng_wsel_a  (eng_wsel_a),
        .eng_en_b    (eng_en_b),
        .eng_we_b    (eng_we_b),
        .eng_addr_b  (eng_addr_b),
        .rom_en      (rom_en),
        .rom_addr    (rom_addr),
        .dp_en       (dp_en),
        .mode_s1     (mode_s1),
        .sel_b_s1    (sel_b_s1),
        .use_ninv_s1 (use_ninv_s1)
    );

    // ------------------------------------------------------------------------
    // Coefficient memory (port A shared with host)
    // ------------------------------------------------------------------------
    wire [11:0] bfu_a_out, bfu_b_out;
    wire [11:0] mem_dout_a, mem_dout_b;

    wire        mem_en_a   = busy ? eng_en_a   : host_en;
    wire        mem_we_a   = busy ? eng_we_a   : host_we;
    wire [7:0]  mem_addr_a = busy ? eng_addr_a : host_addr;
    wire [11:0] mem_din_a  = busy ? (eng_wsel_a ? bfu_b_out : bfu_a_out) : host_wdata;

    coeff_mem #(.AW(8), .DW(12)) u_mem (
        .clk    (clk),
        .en_a   (mem_en_a),
        .we_a   (mem_we_a),
        .addr_a (mem_addr_a),
        .din_a  (mem_din_a),
        .dout_a (mem_dout_a),
        .en_b   (eng_en_b),
        .we_b   (eng_we_b),
        .addr_b (eng_addr_b),
        .din_b  (bfu_b_out),
        .dout_b (mem_dout_b)
    );

    assign host_rdata = mem_dout_a;

    // ------------------------------------------------------------------------
    // Twiddle factor ROM
    // ------------------------------------------------------------------------
    wire [11:0] rom_zeta;

    twiddle_rom u_rom (
        .clk  (clk),
        .en   (rom_en),
        .addr (rom_addr),
        .zeta (rom_zeta)
    );

    // ------------------------------------------------------------------------
    // Butterfly unit
    // ------------------------------------------------------------------------
    wire [11:0] bfu_a_in    = sel_b_s1    ? mem_dout_b : mem_dout_a;
    wire [11:0] bfu_zeta_in = use_ninv_s1 ? N_INV      : rom_zeta;

    butterfly_unit u_bfu (
        .clk     (clk),
        .en      (dp_en),
        .mode_s1 (mode_s1),
        .a_s1    (bfu_a_in),
        .b_s1    (mem_dout_b),
        .zeta_s1 (bfu_zeta_in),
        .a_out   (bfu_a_out),
        .b_out   (bfu_b_out)
    );

    // ------------------------------------------------------------------------
    // Performance counter
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)              cycle_cnt <= 16'd0;
        else if (start && !busy) cycle_cnt <= 16'd0;
        else if (busy)           cycle_cnt <= cycle_cnt + 16'd1;
    end
endmodule
