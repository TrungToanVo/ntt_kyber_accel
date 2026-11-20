#!/usr/bin/env python3
# =============================================================================
# ntt_golden.py - Golden reference model for the Kyber (ML-KEM, FIPS 203) NTT
#
#   * NTT / INTT exactly as FIPS 203 Algorithm 9 / Algorithm 10
#   * Self-checks: round trip, polynomial multiplication via NTT vs schoolbook
#   * Exhaustive proof of the Barrett reduction used in rtl/mod_mult.v
#   * Generates rtl/twiddle_rom.v (zeta table)
#   * Generates test vectors for the Verilog testbenches (tb/vectors/*.hex)
#
# Usage:
#   python ntt_golden.py --selftest
#   python ntt_golden.py --gen-rom
#   python ntt_golden.py --gen-vectors --nvec 100 --seed 1
#   python ntt_golden.py --all          (everything above)
# =============================================================================
import argparse
import os
import random
import sys

import numpy as np

# ----------------------------------------------------------------------------
# Kyber parameters (FIPS 203)
# ----------------------------------------------------------------------------
N = 256          # polynomial degree
Q = 3329         # modulus (prime, 12 bit)
ZETA = 17        # primitive 256-th root of unity mod q
N_INV = 3303     # 128^-1 mod q (INTT final scaling, FIPS 203 Alg. 10)

# Barrett constants used in hardware (rtl/mod_mult.v)
BARRETT_K = 24
BARRETT_M = (1 << BARRETT_K) // Q      # 5039

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def bitrev7(x: int) -> int:
    """Reverse the 7 least-significant bits of x."""
    return int(f"{x:07b}"[::-1], 2)


# zetas[i] = 17^BitRev7(i) mod q, i = 0..127  (FIPS 203, Appendix A)
ZETAS = [pow(ZETA, bitrev7(i), Q) for i in range(128)]


# ----------------------------------------------------------------------------
# FIPS 203 Algorithm 9 : NTT
# ----------------------------------------------------------------------------
def ntt(f):
    f = list(f)
    i = 1
    length = 128
    while length >= 2:
        for start in range(0, N, 2 * length):
            zeta = ZETAS[i]
            i += 1
            for j in range(start, start + length):
                t = (zeta * f[j + length]) % Q
                f[j + length] = (f[j] - t) % Q
                f[j] = (f[j] + t) % Q
        length //= 2
    return f


# ----------------------------------------------------------------------------
# FIPS 203 Algorithm 10 : NTT^-1
# ----------------------------------------------------------------------------
def intt(f):
    f = list(f)
    i = 127
    length = 2
    while length <= 128:
        for start in range(0, N, 2 * length):
            zeta = ZETAS[i]
            i -= 1
            for j in range(start, start + length):
                t = f[j]
                f[j] = (t + f[j + length]) % Q
                f[j + length] = (zeta * (f[j + length] - t)) % Q
        length *= 2
    return [(x * N_INV) % Q for x in f]


# ----------------------------------------------------------------------------
# FIPS 203 Algorithms 11/12 : MultiplyNTTs / BaseCaseMultiply
# (only used to prove that the NTT above really implements Kyber's ring)
# ----------------------------------------------------------------------------
def multiply_ntts(f_hat, g_hat):
    h = [0] * N
    for i in range(128):
        gamma = pow(ZETA, 2 * bitrev7(i) + 1, Q)
        a0, a1 = f_hat[2 * i], f_hat[2 * i + 1]
        b0, b1 = g_hat[2 * i], g_hat[2 * i + 1]
        h[2 * i] = (a0 * b0 + a1 * b1 * gamma) % Q
        h[2 * i + 1] = (a0 * b1 + a1 * b0) % Q
    return h


def schoolbook_negacyclic(a, b):
    """a*b mod (X^256 + 1, q)."""
    c = [0] * N
    for i in range(N):
        for j in range(N):
            k = i + j
            if k < N:
                c[k] += a[i] * b[j]
            else:
                c[k - N] -= a[i] * b[j]
    return [x % Q for x in c]


# ----------------------------------------------------------------------------
# Bit-accurate model of the hardware Barrett reduction (rtl/mod_mult.v)
# ----------------------------------------------------------------------------
def hw_mod_mult(a, b):
    z = a * b                                  # stage 1 : 24-bit product
    qh = (z * BARRETT_M) >> BARRETT_K          # stage 2 : quotient estimate
    r = ((z & 0x1FFF) - ((qh * Q) & 0x1FFF)) & 0x1FFF   # stage 3 : 13-bit sub
    return r - Q if r >= Q else r


def check_barrett_exhaustive():
    """Prove r = z - floor(z*m/2^k)*q lies in [0, 2q) for every z = a*b,
    a, b in [0, q-1], and that the 13-bit truncated datapath is exact."""
    a = np.arange(Q, dtype=np.int64)
    worst = 0
    for b in range(Q):
        z = a * b
        qh = (z * BARRETT_M) >> BARRETT_K
        r_full = z - qh * Q
        if r_full.min() < 0 or r_full.max() >= 2 * Q:
            return False, f"r out of [0,2q) for b={b}"
        worst = max(worst, int(r_full.max()))
        r13 = ((z & 0x1FFF) - ((qh * Q) & 0x1FFF)) & 0x1FFF
        if not np.array_equal(r13, r_full):
            return False, f"13-bit truncation mismatch for b={b}"
        y = np.where(r13 >= Q, r13 - Q, r13)
        if not np.array_equal(y, z % Q):
            return False, f"result mismatch for b={b}"
    return True, f"all {Q*Q} products OK, max pre-correction r = {worst} (< 2q = {2*Q})"


# ----------------------------------------------------------------------------
# Self test
# ----------------------------------------------------------------------------
def selftest():
    ok = True
    print(f"[INFO] q={Q}, n={N}, zeta={ZETA}, 128^-1 mod q = {N_INV}")
    print(f"[INFO] zetas[0:8] = {ZETAS[:8]}")
    assert pow(ZETA, 128, Q) == Q - 1, "17 must have order 256"
    assert (128 * N_INV) % Q == 1

    rng = random.Random(2026)
    for t in range(200):
        f = [rng.randrange(Q) for _ in range(N)]
        if intt(ntt(f)) != f:
            print("[FAIL] round trip INTT(NTT(f)) != f")
            ok = False
            break
    else:
        print("[PASS] round trip INTT(NTT(f)) == f   (200 random polys)")

    for t in range(5):
        a = [rng.randrange(Q) for _ in range(N)]
        b = [rng.randrange(Q) for _ in range(N)]
        c_ntt = intt(multiply_ntts(ntt(a), ntt(b)))
        if c_ntt != schoolbook_negacyclic(a, b):
            print("[FAIL] NTT-based multiplication != schoolbook")
            ok = False
            break
    else:
        print("[PASS] INTT(NTT(a) o NTT(b)) == a*b mod (X^256+1)   (5 random pairs)")

    good, msg = check_barrett_exhaustive()
    print(("[PASS] " if good else "[FAIL] ") + "Barrett reduction (m=5039, k=24): " + msg)
    ok &= good
    return ok


# ----------------------------------------------------------------------------
# ROM generator
# ----------------------------------------------------------------------------
def gen_rom(path):
    lines = []
    lines.append("// =============================================================================")
    lines.append("// twiddle_rom.v - Kyber twiddle factor ROM  (AUTO-GENERATED by model/ntt_golden.py)")
    lines.append("//   zeta[i] = 17^BitRev7(i) mod 3329, i = 0..127   (FIPS 203, Appendix A)")
    lines.append("//   Synchronous read (1-cycle latency) to align with coeff_mem.")
    lines.append("//   Synthesizes to combinational logic + 12 output flops (no ROM macro needed).")
    lines.append("// =============================================================================")
    lines.append("`timescale 1ns/1ps")
    lines.append("module twiddle_rom (")
    lines.append("    input  wire        clk,")
    lines.append("    input  wire        en,")
    lines.append("    input  wire [6:0]  addr,")
    lines.append("    output reg  [11:0] zeta")
    lines.append(");")
    lines.append("    reg [11:0] rom_val;")
    lines.append("")
    lines.append("    always @(*) begin")
    lines.append("        case (addr)")
    for i, z in enumerate(ZETAS):
        lines.append(f"            7'd{i:<3}: rom_val = 12'd{z};")
    lines.append("            default: rom_val = 12'd0;")
    lines.append("        endcase")
    lines.append("    end")
    lines.append("")
    lines.append("    always @(posedge clk) begin")
    lines.append("        if (en) zeta <= rom_val;")
    lines.append("    end")
    lines.append("endmodule")
    with open(path, "w", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"[INFO] wrote {path}")


# ----------------------------------------------------------------------------
# Test vector generator
# ----------------------------------------------------------------------------
def gen_vectors(outdir, nvec, seed):
    os.makedirs(outdir, exist_ok=True)
    rng = random.Random(seed)
    vecs = []
    # directed corner cases first
    vecs.append([0] * N)                              # all zero
    vecs.append([Q - 1] * N)                          # all q-1 (max value)
    vecs.append([1] + [0] * (N - 1))                  # impulse at 0
    vecs.append([0] * (N - 1) + [Q - 1])              # impulse at 255
    vecs.append([i % Q for i in range(N)])            # ramp
    vecs.append([(Q - 1) if i % 2 else 0 for i in range(N)])  # alternating
    while len(vecs) < nvec:
        vecs.append([rng.randrange(Q) for _ in range(N)])
    vecs = vecs[:nvec]

    def dump(name, polys):
        p = os.path.join(outdir, name)
        with open(p, "w", newline="\n") as fh:
            for poly in polys:
                for c in poly:
                    fh.write(f"{c:03x}\n")
        return p

    dump("ntt_in.hex", vecs)
    dump("ntt_exp.hex", [ntt(v) for v in vecs])
    dump("intt_exp.hex", [intt(v) for v in vecs])
    with open(os.path.join(outdir, "nvec.txt"), "w") as fh:
        fh.write(f"{nvec}\n")
    print(f"[INFO] wrote {nvec} vectors (+expected NTT / INTT) to {outdir}")


def main():
    ap = argparse.ArgumentParser(description="Kyber NTT golden model")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--gen-rom", action="store_true")
    ap.add_argument("--gen-vectors", action="store_true")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--nvec", type=int, default=100)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    if not (args.selftest or args.gen_rom or args.gen_vectors or args.all):
        args.all = True

    ok = True
    if args.selftest or args.all:
        ok = selftest()
    if args.gen_rom or args.all:
        gen_rom(os.path.join(ROOT, "rtl", "twiddle_rom.v"))
    if args.gen_vectors or args.all:
        gen_vectors(os.path.join(ROOT, "tb", "vectors"), args.nvec, args.seed)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
