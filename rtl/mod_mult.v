// =============================================================================
// mod_mult.v - Pipelined modular multiplier with Barrett reduction
//
//   y = (a * b) mod Q ,  Q = 3329,  a, b < Q
//
//   Barrett:  z  = a*b                        (24 bit, z < 2^24)
//             qh = floor(z * M / 2^K)         M = floor(2^24/3329) = 5039, K = 24
//             r  = z - qh*Q                   r in [0, 2Q)   (proven exhaustively
//                                                             in model/ntt_golden.py)
//             y  = (r >= Q) ? r - Q : r
//   Because r < 2Q < 2^13, the subtraction is done on 13 bits only.
//
//   Pipeline (latency = 3 clock cycles, throughput = 1 / cycle):
//     Stage 1 : z  = a * b                    (12x12 multiplier)
//     Stage 2 : qh = (z * M) >> 24            (24x13 constant multiplier)
//     Stage 3 : r  = z - qh*Q, final correct  (13-bit constant mult + sub)
//
//   The datapath registers have no reset (smaller area); validity is tracked
//   by the controller. 'en' lets Design Compiler insert clock gating.
// =============================================================================
`timescale 1ns/1ps
module mod_mult (
    input  wire        clk,
    input  wire        en,
    input  wire [11:0] a,
    input  wire [11:0] b,
    output reg  [11:0] y
);
    localparam [11:0] Q = 12'd3329;
    localparam [12:0] M = 13'd5039;

    // ---------------- Stage 1 : integer multiplication -----------------------
    reg [23:0] z_s1;
    always @(posedge clk) begin
        if (en) z_s1 <= a * b;
    end

    // ---------------- Stage 2 : quotient estimation --------------------------
    wire [36:0] zm = z_s1 * M;
    reg  [12:0] qh_s2;          // <= 3326, fits in 12 bits; 13 kept for safety
    reg  [12:0] zl_s2;          // z mod 2^13
    always @(posedge clk) begin
        if (en) begin
            qh_s2 <= zm[36:24];
            zl_s2 <= z_s1[12:0];
        end
    end

    // ---------------- Stage 3 : reduction + final correction -----------------
    wire [24:0] qq = qh_s2 * Q;
    wire [12:0] r  = zl_s2 - qq[12:0];               // exact, r in [0, 2Q)
    wire [13:0] rq = {1'b0, r} - {2'b00, Q};         // r - Q (MSB = borrow)
    always @(posedge clk) begin
        if (en) y <= rq[13] ? r[11:0] : rq[11:0];
    end
endmodule
