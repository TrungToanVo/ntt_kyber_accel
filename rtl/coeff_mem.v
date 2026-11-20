// =============================================================================
// coeff_mem.v - 256 x 12-bit true dual-port coefficient memory
//
//   * Each port performs either one read OR one write per cycle.
//   * Synchronous write, synchronous (registered) read: data appears the
//     cycle after the read request, like a standard SRAM macro.
//   * Read output holds its value when the port is idle or writing.
//   * Implemented with flip-flops so it synthesizes with any standard-cell
//     library. For a production tape-out replace this module by a
//     dual-port SRAM macro from the foundry memory compiler (same ports).
//   * The controller guarantees both ports never write the same address in
//     the same cycle.
// =============================================================================
`timescale 1ns/1ps
module coeff_mem #(
    parameter AW = 8,
    parameter DW = 12
) (
    input  wire          clk,
    // port A
    input  wire          en_a,
    input  wire          we_a,
    input  wire [AW-1:0] addr_a,
    input  wire [DW-1:0] din_a,
    output reg  [DW-1:0] dout_a,
    // port B
    input  wire          en_b,
    input  wire          we_b,
    input  wire [AW-1:0] addr_b,
    input  wire [DW-1:0] din_b,
    output reg  [DW-1:0] dout_b
);
    localparam DEPTH = (1 << AW);

    wire [DW*DEPTH-1:0] words;          // flattened view of all words

    genvar i;
    generate
        for (i = 0; i < DEPTH; i = i + 1) begin : g_word
            reg [DW-1:0] q;
            wire wr_a = en_a & we_a & (addr_a == i);
            wire wr_b = en_b & we_b & (addr_b == i);
            always @(posedge clk) begin
                if (wr_b)      q <= din_b;
                else if (wr_a) q <= din_a;
            end
            assign words[i*DW +: DW] = q;
        end
    endgenerate

    always @(posedge clk) begin
        if (en_a & ~we_a) dout_a <= words[addr_a*DW +: DW];
    end

    always @(posedge clk) begin
        if (en_b & ~we_b) dout_b <= words[addr_b*DW +: DW];
    end
endmodule
