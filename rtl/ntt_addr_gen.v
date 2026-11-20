// =============================================================================
// ntt_addr_gen.v - Address / twiddle-index generator (combinational)
//
//   FIPS 203 NTT has 7 layers. In layer l (0..6):  len = 128 >> l
//   Butterfly k (0..127) of that layer:
//        group  g      = k >> (7 - l)              (0 .. 2^l - 1)
//        offset o      = k mod len
//        addr_a        = g*2*len + o   (= k with a '0' inserted at bit 7-l)
//        addr_b        = addr_a + len
//   Twiddle index (zetas[] in FIPS 203):
//        NTT  (i counts up   from 1  ) : idx = 2^l + g
//        INTT (i counts down from 127) : idx = 2^(l+1) - 1 - g
//   NTT  visits layers l = 0,1,...,6  (len 128 -> 2)
//   INTT visits layers l = 6,5,...,0  (len 2 -> 128)  - chosen by the controller
// =============================================================================
`timescale 1ns/1ps
module ntt_addr_gen (
    input  wire [2:0] layer,        // l = 0..6
    input  wire [6:0] k,            // butterfly index inside layer
    input  wire       intt,         // 1 = inverse NTT
    output wire [7:0] addr_a,
    output wire [7:0] addr_b,
    output wire [6:0] tw_idx
);
    wire [7:0] len   = 8'd128 >> layer;
    wire [7:0] mask  = len - 8'd1;
    wire [7:0] k8    = {1'b0, k};

    assign addr_a = ((k8 & ~mask) << 1) | (k8 & mask);
    assign addr_b = addr_a | len;

    wire [6:0] g     = k >> (3'd7 - layer);
    wire [6:0] lbit  = 7'd1 << layer;
    wire [6:0] lmask = lbit - 7'd1;

    assign tw_idx = intt ? (lbit | (~g & lmask)) : (lbit | g);
endmodule
