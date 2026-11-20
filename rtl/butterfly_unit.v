// =============================================================================
// butterfly_unit.v - Unified Cooley-Tukey / Gentleman-Sande butterfly
//
//   mode = CT (forward NTT, FIPS 203 Alg. 9):
//        t  = zeta * b
//        a' = a + t ,  b' = a - t                      (mod q)
//   mode = GS (inverse NTT, FIPS 203 Alg. 10):
//        a' = a + b ,  b' = zeta * (b - a)             (mod q)
//   mode = SC (INTT final scaling pass):
//        b' = zeta * a      (zeta = 3303 = 128^-1 mod q, a' unused)
//
//   One modular multiplier is shared by all modes (only operand muxes differ).
//
//   Pipeline (5 stages, inputs arrive in S1, results combinational in S5):
//     S1 : pre-add/sub (GS: a+b, b-a), operand select      -> reg
//     S2 : mod_mult stage 1  (a*b)
//     S3 : mod_mult stage 2  (Barrett quotient)
//     S4 : mod_mult stage 3  (reduction)                   -> p_s5
//     S5 : post-add/sub (CT: a +/- t), output mux          -> a_out / b_out
//   Latency S1 -> S5 = 4 clock cycles.
// =============================================================================
`timescale 1ns/1ps
module butterfly_unit (
    input  wire        clk,
    input  wire        en,
    input  wire [1:0]  mode_s1,     // 0 = CT, 1 = GS, 2 = SC
    input  wire [11:0] a_s1,        // coefficient a (memory port A, or scale operand)
    input  wire [11:0] b_s1,        // coefficient b (memory port B)
    input  wire [11:0] zeta_s1,     // twiddle factor
    output wire [11:0] a_out,       // valid in S5
    output wire [11:0] b_out        // valid in S5
);
    localparam [1:0] MODE_CT = 2'd0,
                     MODE_GS = 2'd1,
                     MODE_SC = 2'd2;

    // ------------------------------- S1 --------------------------------------
    wire [11:0] sum_ab, diff_ba;
    mod_add u_pre_add (.a(a_s1), .b(b_s1), .y(sum_ab));    // a + b
    mod_sub u_pre_sub (.a(b_s1), .b(a_s1), .y(diff_ba));   // b - a

    reg [11:0] op_s2, zeta_s2, a_s2;
    reg [1:0]  mode_s2;
    always @(posedge clk) begin
        if (en) begin
            case (mode_s1)
                MODE_CT: begin op_s2 <= b_s1;    a_s2 <= a_s1;   end
                MODE_GS: begin op_s2 <= diff_ba; a_s2 <= sum_ab; end
                default: begin op_s2 <= a_s1;    a_s2 <= a_s1;   end  // SC
            endcase
            zeta_s2 <= zeta_s1;
            mode_s2 <= mode_s1;
        end
    end

    // --------------------------- S2 .. S4 ------------------------------------
    wire [11:0] p_s5;                                     // zeta * op mod q
    mod_mult u_mult (.clk(clk), .en(en), .a(op_s2), .b(zeta_s2), .y(p_s5));

    // delay line for 'a' operand and mode (matches 3-cycle multiplier latency)
    reg [11:0] a_s3, a_s4, a_s5;
    reg [1:0]  mode_s3, mode_s4, mode_s5;
    always @(posedge clk) begin
        if (en) begin
            a_s3 <= a_s2;    mode_s3 <= mode_s2;
            a_s4 <= a_s3;    mode_s4 <= mode_s3;
            a_s5 <= a_s4;    mode_s5 <= mode_s4;
        end
    end

    // ------------------------------- S5 --------------------------------------
    wire [11:0] ct_a, ct_b;
    mod_add u_post_add (.a(a_s5), .b(p_s5), .y(ct_a));    // a + t
    mod_sub u_post_sub (.a(a_s5), .b(p_s5), .y(ct_b));    // a - t

    assign a_out = (mode_s5 == MODE_CT) ? ct_a : a_s5;    // GS: a+b
    assign b_out = (mode_s5 == MODE_CT) ? ct_b : p_s5;    // GS: zeta*(b-a), SC: zeta*a
endmodule
