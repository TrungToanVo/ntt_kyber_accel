// =============================================================================
// tb_butterfly.v - Unit test for butterfly_unit (CT / GS / SC modes)
//   New random operands every cycle (full throughput), latency S1->S5 = 4
// =============================================================================
`timescale 1ns/1ps
module tb_butterfly;
    localparam Q     = 3329;
    localparam NTEST = 100000;
    localparam LAT   = 4;

    reg         clk = 1'b0;
    reg  [1:0]  mode;
    reg  [11:0] a, b, z;
    wire [11:0] ao, bo;

    always #5 clk = ~clk;

    butterfly_unit dut (
        .clk(clk), .en(1'b1), .mode_s1(mode),
        .a_s1(a), .b_s1(b), .zeta_s1(z),
        .a_out(ao), .b_out(bo)
    );

    integer ea [0:LAT];
    integer eb [0:LAT];
    integer em [0:LAT];
    reg     ev [0:LAT];
    integer i, n, errors, checked, ia, ib, iz, t;
    integer cnt_mode [0:2];

    always @(posedge clk) begin
        for (i = LAT; i > 0; i = i - 1) begin
            ea[i] <= ea[i-1]; eb[i] <= eb[i-1]; em[i] <= em[i-1]; ev[i] <= ev[i-1];
        end
    end

    always @(negedge clk) begin
        if (ev[LAT] === 1'b1) begin
            checked = checked + 1;
            // in SC mode only b_out is meaningful
            if ((em[LAT] != 2 && ao !== ea[LAT][11:0]) || bo !== eb[LAT][11:0]) begin
                errors = errors + 1;
                if (errors < 10)
                    $display("[FAIL] mode=%0d a'=%0d/%0d b'=%0d/%0d", em[LAT],
                             ao, ea[LAT], bo, eb[LAT]);
            end
        end
    end

    initial begin
        errors = 0; checked = 0;
        cnt_mode[0] = 0; cnt_mode[1] = 0; cnt_mode[2] = 0;
        for (i = 0; i <= LAT; i = i + 1) begin ev[i] = 1'b0; ea[i] = 0; eb[i] = 0; em[i] = 0; end

        for (n = 0; n < NTEST; n = n + 1) begin
            @(negedge clk);
            if (n < 27) begin                // directed: all combos of {0,1,q-1}
                ia = (n % 3 == 2) ? Q-1 : n % 3;
                ib = ((n/3) % 3 == 2) ? Q-1 : (n/3) % 3;
                iz = ((n/9) % 3 == 2) ? Q-1 : (n/9) % 3;
            end else begin
                ia = {$random} % Q; ib = {$random} % Q; iz = {$random} % Q;
            end
            mode = n % 3;
            a = ia; b = ib; z = iz;
            case (n % 3)
                0: begin                     // CT
                    t = (ib * iz) % Q;
                    ea[0] = (ia + t) % Q;
                    eb[0] = (ia - t + Q) % Q;
                end
                1: begin                     // GS
                    ea[0] = (ia + ib) % Q;
                    eb[0] = (((ib - ia + Q) % Q) * iz) % Q;
                end
                default: begin               // SC
                    ea[0] = 0;
                    eb[0] = (ia * iz) % Q;
                end
            endcase
            em[0] = n % 3;
            ev[0] = 1'b1;
            cnt_mode[n % 3] = cnt_mode[n % 3] + 1;
        end
        @(negedge clk); ev[0] = 1'b0;
        repeat (LAT + 2) @(negedge clk);

        if (errors == 0)
            $display("[PASS] tb_butterfly : %0d ops (CT=%0d GS=%0d SC=%0d), 0 errors",
                     checked, cnt_mode[0], cnt_mode[1], cnt_mode[2]);
        else
            $display("[FAIL] tb_butterfly : %0d errors / %0d", errors, checked);
        $finish;
    end
endmodule
