// =============================================================================
// ntt_ctrl.v - Control FSM + address sequencing for the NTT accelerator
//
//   Schedule (dual-port memory: each port does 1 read OR 1 write per cycle):
//     * A free-running 'phase' bit splits time into even/odd cycles.
//     * Butterfly mode : a token (read a & b) is issued on every EVEN cycle,
//       its results are written back exactly L = 5 cycles later (ODD cycle),
//       so reads and writes never collide on a port -> 1 butterfly / 2 cycles.
//     * Between layers the pipeline is drained (RAW hazard on in-place memory).
//     * Scale mode (INTT only, x * 128^-1): one coefficient per cycle, read on
//       port A (even) / port B (odd); each result is written back L = 5 cycles
//       later through the same port, which is then free (L is odd).
//
//   Schedule is fixed and data independent -> constant-time execution
//   (no timing side channel).
//
//   Latency: NTT  ~ 7 * 262          = ~1835 cycles
//            INTT ~ 7 * 262 + 256 + 6 = ~2097 cycles
// =============================================================================
`timescale 1ns/1ps
module ntt_ctrl (
    input  wire       clk,
    input  wire       rst_n,
    // command
    input  wire       start,          // 1-cycle pulse, accepted in IDLE only
    input  wire       mode_intt,      // 0 = NTT, 1 = INTT
    output wire       busy,
    output reg        done,           // 1-cycle pulse when operation finished
    // memory port A (engine side)
    output reg        eng_en_a,
    output reg        eng_we_a,
    output reg  [7:0] eng_addr_a,
    output reg        eng_wsel_a,     // 1: write data = butterfly b_out (scale)
    // memory port B (engine side)
    output reg        eng_en_b,
    output reg        eng_we_b,
    output reg  [7:0] eng_addr_b,
    // twiddle ROM
    output wire       rom_en,
    output wire [6:0] rom_addr,
    // butterfly datapath (signals aligned to pipeline stage S1)
    output wire       dp_en,
    output wire [1:0] mode_s1,
    output wire       sel_b_s1,       // scale: operand comes from port B
    output wire       use_ninv_s1     // scale: zeta = 128^-1 mod q
);
    localparam [1:0] MODE_CT = 2'd0,
                     MODE_GS = 2'd1,
                     MODE_SC = 2'd2;

    localparam [2:0] S_IDLE   = 3'd0,
                     S_BF     = 3'd1,   // issue butterflies of one layer
                     S_DRAIN  = 3'd2,   // wait for pipeline to empty
                     S_SCALE  = 3'd3,   // INTT scaling pass
                     S_SDRAIN = 3'd4,   // drain after scaling
                     S_FINISH = 3'd5;

    reg [2:0] state;
    reg       intt_r;
    reg [2:0] lc;           // layer counter 0..6
    reg [6:0] k;            // butterfly counter 0..127
    reg [7:0] sc;           // scale counter 0..255
    reg       phase;        // 0 = even (read) cycle, 1 = odd (write) cycle

    // ------------------------------------------------------------------------
    // Address generation
    // ------------------------------------------------------------------------
    wire [2:0] layer = intt_r ? (3'd6 - lc) : lc;
    wire [7:0] ag_a, ag_b;
    wire [6:0] ag_tw;

    ntt_addr_gen u_addr_gen (
        .layer  (layer),
        .k      (k),
        .intt   (intt_r),
        .addr_a (ag_a),
        .addr_b (ag_b),
        .tw_idx (ag_tw)
    );

    // ------------------------------------------------------------------------
    // Token issue
    // ------------------------------------------------------------------------
    wire       issue_bf   = (state == S_BF) & ~phase;
    wire       issue_sc   = (state == S_SCALE);
    wire       issue      = issue_bf | issue_sc;
    wire [1:0] iss_mode   = issue_sc ? MODE_SC : (intt_r ? MODE_GS : MODE_CT);
    wire       iss_port   = issue_sc & phase;          // scale: 0 = port A, 1 = port B
    wire [7:0] iss_addr_a = issue_sc ? sc : ag_a;
    wire [7:0] iss_addr_b = issue_sc ? sc : ag_b;

    // ------------------------------------------------------------------------
    // Token pipeline (S1..S5) : valid, mode, port, write-back addresses
    // ------------------------------------------------------------------------
    reg [5:1]  v;
    reg [1:0]  md1, md2, md3, md4, md5;
    reg        pt1, pt2, pt3, pt4, pt5;
    reg [7:0]  aa1, aa2, aa3, aa4, aa5;
    reg [7:0]  ab1, ab2, ab3, ab4, ab5;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v   <= 5'd0;
            md1 <= 2'd0; md2 <= 2'd0; md3 <= 2'd0; md4 <= 2'd0; md5 <= 2'd0;
            pt1 <= 1'b0; pt2 <= 1'b0; pt3 <= 1'b0; pt4 <= 1'b0; pt5 <= 1'b0;
            aa1 <= 8'd0; aa2 <= 8'd0; aa3 <= 8'd0; aa4 <= 8'd0; aa5 <= 8'd0;
            ab1 <= 8'd0; ab2 <= 8'd0; ab3 <= 8'd0; ab4 <= 8'd0; ab5 <= 8'd0;
        end else begin
            v   <= {v[4:1], issue};
            md1 <= iss_mode;   md2 <= md1; md3 <= md2; md4 <= md3; md5 <= md4;
            pt1 <= iss_port;   pt2 <= pt1; pt3 <= pt2; pt4 <= pt3; pt5 <= pt4;
            aa1 <= iss_addr_a; aa2 <= aa1; aa3 <= aa2; aa4 <= aa3; aa5 <= aa4;
            ab1 <= iss_addr_b; ab2 <= ab1; ab3 <= ab2; ab4 <= ab3; ab5 <= ab4;
        end
    end

    wire pipe_empty = ~|v;

    // ------------------------------------------------------------------------
    // Memory port arbitration (write-back of S5 token has priority; by
    // construction a read is never requested on the same port in that cycle)
    // ------------------------------------------------------------------------
    wire wr_a = v[5]  & ((md5 != MODE_SC)      | ~pt5);
    wire wr_b = v[5]  & ((md5 != MODE_SC)      |  pt5);
    wire rd_a = issue & ((iss_mode != MODE_SC) | ~iss_port);
    wire rd_b = issue & ((iss_mode != MODE_SC) |  iss_port);

    always @(*) begin
        eng_en_a   = wr_a | rd_a;
        eng_we_a   = wr_a;
        eng_addr_a = wr_a ? aa5 : iss_addr_a;
        eng_wsel_a = (md5 == MODE_SC);
        eng_en_b   = wr_b | rd_b;
        eng_we_b   = wr_b;
        eng_addr_b = wr_b ? ab5 : iss_addr_b;
    end

    assign rom_en      = issue_bf;
    assign rom_addr    = ag_tw;
    assign dp_en       = busy;
    assign mode_s1     = md1;
    assign sel_b_s1    = (md1 == MODE_SC) & pt1;
    assign use_ninv_s1 = (md1 == MODE_SC);
    assign busy        = (state != S_IDLE);

    // ------------------------------------------------------------------------
    // Main FSM
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= S_IDLE;
            intt_r <= 1'b0;
            lc     <= 3'd0;
            k      <= 7'd0;
            sc     <= 8'd0;
            phase  <= 1'b0;
            done   <= 1'b0;
        end else begin
            done  <= 1'b0;
            phase <= ~phase;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        intt_r <= mode_intt;
                        lc     <= 3'd0;
                        k      <= 7'd0;
                        sc     <= 8'd0;
                        state  <= S_BF;
                    end
                end
                S_BF: begin
                    if (!phase) begin
                        k <= k + 7'd1;                     // wraps to 0 after 127
                        if (k == 7'd127) state <= S_DRAIN;
                    end
                end
                S_DRAIN: begin
                    if (pipe_empty) begin
                        if (lc == 3'd6) begin
                            state <= intt_r ? S_SCALE : S_FINISH;
                            sc    <= 8'd0;
                        end else begin
                            lc    <= lc + 3'd1;
                            state <= S_BF;
                        end
                    end
                end
                S_SCALE: begin
                    sc <= sc + 8'd1;
                    if (sc == 8'd255) state <= S_SDRAIN;
                end
                S_SDRAIN: begin
                    if (pipe_empty) state <= S_FINISH;
                end
                S_FINISH: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Simulation-only protocol check
    // ------------------------------------------------------------------------
    // synopsys translate_off
    always @(posedge clk) begin
        if (rst_n && ((wr_a && rd_a) || (wr_b && rd_b)))
            $display("[%0t] ERROR ntt_ctrl: read/write collision on memory port", $time);
    end
    // synopsys translate_on
endmodule
