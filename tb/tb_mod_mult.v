// =============================================================================
// tb_mod_mult.v - Unit test for mod_mult (Barrett, latency 3)
//   Corner cases + random operands, checked against (a*b) % 3329
// =============================================================================
`timescale 1ns/1ps
module tb_mod_mult;
    localparam Q      = 3329;
    localparam NRAND  = 200000;
    localparam LAT    = 3;

    reg         clk = 1'b0;
    reg  [11:0] a, b;
    wire [11:0] y;

    always #5 clk = ~clk;

    mod_mult dut (.clk(clk), .en(1'b1), .a(a), .b(b), .y(y));

    // expected-value delay line
    integer exp_q [0:LAT];
    reg     vld_q [0:LAT];
    integer i, n, errors, checked;
    integer corner [0:7];

    task drive(input integer x, input integer z);
        begin
            @(negedge clk);
            a = x; b = z;
            exp_q[0] = (x * z) % Q;
            vld_q[0] = 1'b1;
        end
    endtask

    // shift expected values on each posedge, check output at negedge
    always @(posedge clk) begin
        for (i = LAT; i > 0; i = i - 1) begin
            exp_q[i] <= exp_q[i-1];
            vld_q[i] <= vld_q[i-1];
        end
    end

    always @(negedge clk) begin
        if (vld_q[LAT] === 1'b1) begin
            checked = checked + 1;
            if (y !== exp_q[LAT][11:0]) begin
                errors = errors + 1;
                if (errors < 10)
                    $display("[FAIL] y=%0d expected=%0d", y, exp_q[LAT]);
            end
        end
    end

    initial begin
        errors = 0; checked = 0;
        for (i = 0; i <= LAT; i = i + 1) begin vld_q[i] = 1'b0; exp_q[i] = 0; end
        corner[0] = 0;    corner[1] = 1;    corner[2] = 2;    corner[3] = 17;
        corner[4] = 1664; corner[5] = 1665; corner[6] = 3327; corner[7] = 3328;

        // all corner pairs
        for (n = 0; n < 64; n = n + 1) drive(corner[n/8], corner[n%8]);
        // full sweep of a with b = q-1 (largest products)
        for (n = 0; n < Q; n = n + 1) drive(n, Q-1);
        // random
        for (n = 0; n < NRAND; n = n + 1) drive({$random} % Q, {$random} % Q);

        @(negedge clk); vld_q[0] = 1'b0;
        repeat (LAT + 2) @(negedge clk);

        if (errors == 0) $display("[PASS] tb_mod_mult : %0d products checked, 0 errors", checked);
        else             $display("[FAIL] tb_mod_mult : %0d errors / %0d", errors, checked);
        $finish;
    end
endmodule
