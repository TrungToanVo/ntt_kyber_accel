# CRYSTALS-Kyber (ML-KEM / FIPS 203) NTT/INTT Hardware Accelerator — ASIC RTL Package

Thiết kế RTL hoàn chỉnh ở mức **synthesizable ASIC (Verilog-2001)** cho bộ tăng tốc phần cứng **Number Theoretic Transform (NTT / INTT)** tuân thủ chính xác đặc tả **NIST FIPS 203 (ML-KEM / CRYSTALS-Kyber)**:
- Vành đa thức: $\mathbb{Z}_q[X]/(X^n + 1)$ với $n = 256, q = 3329, \zeta = 17, 128^{-1} \bmod q = 3303$
- Hỗ trợ **Forward NTT** (Algorithm 9 — Cooley-Tukey), **Inverse NTT + Scaling** (Algorithm 10 — Gentleman-Sande + nhân $128^{-1} \bmod q$) trên cùng 1 Butterfly Unit hợp nhất
- Thực thi **Constant-Time** (thời gian cố định, độc lập dữ liệu — chống tấn công kênh kề thời gian):
  - **Forward NTT:** đúng **1,835 chu kỳ clock**
  - **Inverse NTT (gồm cả bước nhân hệ số $128^{-1} \bmod q$):** đúng **2,097 chu kỳ clock**

---

## 1. Cấu trúc thư mục

```text
ntt_kyber_accel/
├── model/
│   └── ntt_golden.py       # Golden model Python (FIPS 203 Alg. 9/10/11), chứng minh vét cạn Barrett,
│                           # sinh rtl/twiddle_rom.v và test vectors tb/vectors/*.hex
├── rtl/
│   ├── mod_add.v           # Bộ cộng modular (a + b) mod 3329 (combinational)
│   ├── mod_sub.v           # Bộ trừ modular (a - b) mod 3329 (combinational)
│   ├── mod_mult.v          # Bộ nhân modular Barrett 3-stage pipeline (latency = 3, throughput = 1/cycle)
│   ├── butterfly_unit.v    # Khối Butterfly hợp nhất CT / GS / Scale (5-stage pipeline)
│   ├── twiddle_rom.v       # Bảng hằng số zetas[0..127] = 17^BitRev7(i) mod 3329 (synchronous read)
│   ├── coeff_mem.v         # Bộ nhớ hệ số True Dual-Port 256 x 12-bit (in-place)
│   ├── ntt_addr_gen.v      # Bộ sinh địa chỉ cặp hệ số (a, b) và chỉ số twiddle qua 7 layer
│   ├── ntt_ctrl.v          # FSM điều khiển chính + pipeline token tracking tránh xung đột R/W
│   ├── ntt_core.v          # Tích hợp core NTT/INTT (native interface)
│   └── ntt_axil_top.v      # Top-level bọc giao tiếp chuẩn AMBA AXI4-Lite Slave + Interrupt
├── tb/
│   ├── tb_mod_mult.v       # Unit test bộ nhân Barrett (203,393 phép nhân: corner cases + random)
│   ├── tb_butterfly.v      # Unit test Butterfly Unit (100,000 phép toán: CT, GS, SC ở full throughput)
│   ├── tb_ntt_top.v        # System testbench qua bus AXI4-Lite (NTT, Round-trip, INTT, SLVERR, IRQ)
│   └── vectors/            # Các file .hex sinh tự động từ ntt_golden.py
├── sim/
│   ├── rtl_files.f         # Danh sách file RTL chuẩn dùng chung cho simulation & synthesis
│   └── run_sim.ps1         # Script tự động chạy Golden Model + RTL Simulation (Vivado xsim / ModelSim)
├── syn/
│   ├── constraints.sdc     # Ràng buộc timing chuẩn SDC (mặc định 200 MHz / 5.0 ns)
│   └── dc_synth.tcl        # Script tổng hợp logic cho Synopsys Design Compiler (compile_ultra -gate_clock)
├── sta/
│   └── pt_sta.tcl          # Script phân tích STA & Power (OCV derating, SPEF, VCD) cho Synopsys PrimeTime
└── pnr/
    └── icc_pnr.tcl         # Script Physical Design (Floorplan -> Placement -> CTS -> Route) cho Synopsys ICC
```

---

## 2. Bản đồ thanh ghi AXI4-Lite (`ntt_axil_top`)

| Địa chỉ (Byte) | Tên thanh ghi | Quyền | Mô tả các trường bit |
|---|---|---|---|
| `0x000` | `CTRL` | R/W | `[0] START` (tự xóa, ghi `1` khi rảnh để chạy)<br>`[1] MODE` (`0` = Forward NTT, `1` = Inverse NTT)<br>`[2] IRQ_EN` (cho phép ngắt trên chân `irq` khi `DONE=1`) |
| `0x004` | `STATUS` | R/W1C | `[0] BUSY` (Read-only, `1` khi core đang tính toán)<br>`[1] DONE` (Sticky flag, ghi `1` vào bit 1 để xóa — W1C) |
| `0x008` | `CYCLES` | RO | `[15:0]` Số chu kỳ clock thực tế của lần chạy NTT/INTT gần nhất |
| `0x00C` | `ID` | RO | `0x4E545401` (`"NTT"`, phiên bản 1) |
| `0x010` | `PARAM` | RO | `[31:16] = 256` ($n$), `[15:0] = 3329` ($q$) |
| `0x400 .. 0x7FC` | `COEFF[0..255]` | R/W | Hệ số đa thức thứ `i` tại địa chỉ `0x400 + 4*i` (`[11:0]`).<br>Tự động rút gọn $x - q$ nếu ghi giá trị $\ge q$.<br>Truy cập đọc/ghi khi `BUSY = 1` sẽ trả về lỗi `AXI SLVERR (2'b10)`. |

---

## 3. Hướng dẫn chạy kiểm thử (Verification)

Yêu cầu: Python 3 (có `numpy`) và **Xilinx Vivado Simulator (`xsim`)** hoặc **ModelSim**.

```powershell
cd C:\Users\Toan\.gemini\antigravity\scratch\ntt_kyber_accel\sim

# Chạy toàn bộ self-test Python + 3 testbench RTL (100 bộ vector):
powershell -ExecutionPolicy Bypass -File .\run_sim.ps1 -Test all -NVec 100

# Stress test với 1,000 đa thức ngẫu nhiên (3,000 phép biến đổi NTT/INTT):
powershell -ExecutionPolicy Bypass -File .\run_sim.ps1 -Test top -NVec 1000
```

---

## 4. Hướng dẫn chạy luồng ASIC (Synopsys DC / ICC / PrimeTime)

```bash
# 1. Logic Synthesis với Synopsys Design Compiler (mặc định 200 MHz / 5.0 ns)
cd syn
export NTT_TARGET_LIB="/path/to/tsmc65/tcbn65gpluswc.db"
export NTT_CLK_NS="5.0"
dc_shell -f dc_synth.tcl | tee dc_synth.log

# 2. Static Timing Analysis (Pre-layout hoặc Post-layout) với Synopsys PrimeTime
cd ../sta
pt_shell -f pt_sta.tcl | tee pt_sta.log

# 3. Physical Design (Place & Route) với Synopsys IC Compiler
cd ../pnr
icc_shell -f icc_pnr.tcl | tee icc_pnr.log
```
