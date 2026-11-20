// =============================================================================
// mod_add.v - Modular adder  y = (a + b) mod Q      (combinational)
//   Precondition : a < Q, b < Q
//   Kyber        : Q = 3329, W = 12
// =============================================================================
`timescale 1ns/1ps
module mod_add #(
    parameter          W = 12,
    parameter [W-1:0]  Q = 12'd3329
) (
    input  wire [W-1:0] a,
    input  wire [W-1:0] b,
    output wire [W-1:0] y
);
    wire [W:0]   s  = {1'b0, a} + {1'b0, b};          // 0 .. 2Q-2
    wire [W+1:0] sq = {1'b0, s} - {2'b00, Q};         // s - Q (MSB = borrow)

    assign y = sq[W+1] ? s[W-1:0] : sq[W-1:0];
endmodule
