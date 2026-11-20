// =============================================================================
// mod_sub.v - Modular subtractor  y = (a - b) mod Q   (combinational)
//   Precondition : a < Q, b < Q
// =============================================================================
`timescale 1ns/1ps
module mod_sub #(
    parameter          W = 12,
    parameter [W-1:0]  Q = 12'd3329
) (
    input  wire [W-1:0] a,
    input  wire [W-1:0] b,
    output wire [W-1:0] y
);
    wire [W:0] d  = {1'b0, a} - {1'b0, b};            // MSB = borrow (a < b)
    wire [W:0] dq = d + {1'b0, Q};                    // a - b + Q

    assign y = d[W] ? dq[W-1:0] : d[W-1:0];
endmodule
