// tb_booth_mult.sv - self-checking testbench for rtl/booth_mult.sv.
//
// Reference: $signed(multiplicand) * $signed(multiplier). Every multiplication is also checked for its timing:
// busy from the start edge, done exactly 2N + 1 rising edges after it, product and done held until the next start.
//
// +define+ARCH=a (0 wide, 1 narrow, 2 sign rule), +define+NOZERO (sign rule without zero detection), +define+N=n.
// Each architecture is checked against its *predicted* set of wrong products (README.md):
//   wide, sign rule + zero detection   none
//   narrow                              exactly the pairs with multiplicand = -2^(N-1) and multiplier != 0
//   sign rule without zero detection    exactly the pairs with multiplicand = 0 and multiplier != 0
// A wrong product outside the predicted set, or a predicted pair that comes out right, is a failure.
// +define+EXHAUSTIVE runs all 2^(2N) pairs (use Verilator for N = 13).
`timescale 1ns/10ps
`include "tb_common.svh"
`ifndef N
`define N 13
`endif
`ifndef ARCH
`define ARCH 0
`endif
`ifdef NOZERO
`define ZD 1'b0
`else
`define ZD 1'b1
`endif

module tb_booth_mult;
  localparam int N = `N;
  localparam int ARCH = `ARCH;
  localparam bit ZD = `ZD;
  localparam logic [N-1:0] MINV = {1'b1, {(N-1){1'b0}}};

  logic clk = 1'b0, rst = 1'b0, start = 1'b0;
  logic [N-1:0] multiplicand = '0, multiplier = '0;
  logic [2*N-1:0] product;
  logic busy, done;

  booth_mult #(.N(N), .ARCH(ARCH), .ZERO_DETECT(ZD)) dut (.clk, .rst, .start, .multiplicand, .multiplier,
                                                         .product, .busy, .done);

  task automatic tick(); #1 clk = 1'b1; #1 clk = 1'b0; #1; endtask

  // predicted wrong products of each architecture
  function automatic bit predicted_wrong(input logic [N-1:0] a, input logic [N-1:0] b);
    if (b == '0) return 1'b0;
    if (ARCH == 1) return a == MINV;
    if (ARCH == 2 && !ZD) return a == '0;
    return 1'b0;
  endfunction

  int e_unexp, e_missing, e_timing;
  // one multiplication through the ports; checks product and the exact cycle of done
  task automatic multiply(input logic [N-1:0] a, input logic [N-1:0] b, input int hold = 0,
                          input bit scramble = 0);
    logic signed [2*N-1:0] expv;
    bit t_ok, wrong;
    t_ok = 1'b1;
    expv = $signed(a) * $signed(b);
    multiplicand = a; multiplier = b; start = 1'b1;
    tick();
    start = 1'b0;
    for (int r = 1; r <= 2 * N; r++) begin
      if (busy !== 1'b1 || done !== 1'b0) t_ok = 1'b0;
      if (scramble) begin multiplicand = N'(tb_rand()); multiplier = N'(tb_rand()); start = tb_rand() & 1; end
      tick();
    end
    start = 1'b0;
    if (busy !== 1'b0 || done !== 1'b1) t_ok = 1'b0;
    wrong = (product !== expv);
    for (int r = 0; r < hold; r++) begin
      tick();
      if (done !== 1'b1 || product !== (wrong ? product : expv)) t_ok = 1'b0;
    end
    if (!t_ok) e_timing++;
    if (wrong && !predicted_wrong(a, b)) begin
      e_unexp++;
      if (e_unexp <= 3) $display("   %0d x %0d = %0d, expected %0d", $signed(a), $signed(b), $signed(product), expv);
    end
    if (!wrong && predicted_wrong(a, b)) e_missing++;
  endtask

  task automatic group(input string cat, input string name, input int n);
    `CHECK(cat, $sformatf("%s (%0d products)", name, n), e_unexp == 0 && e_missing == 0 && e_timing == 0,
           $sformatf("%0d unexpected wrong products, %0d predicted-wrong products came out right, %0d timing errors",
                     e_unexp, e_missing, e_timing))
    e_unexp = 0; e_missing = 0; e_timing = 0;
  endtask

  // corner operands: 0, +-1, +-2, max, -max, min, +-2^(N-2), ...1010, ...0101, 7
  function automatic logic [N-1:0] corner(input int i);
    logic [N-1:0] alt;
    for (int j = 0; j < N; j++) alt[j] = j[0];
    case (i)
      0: return '0;          1: return N'(1);        2: return '1;          3: return N'(2);
      4: return -N'(2);      5: return ~MINV;        6: return MINV + 1'b1; 7: return MINV;
      8: return N'(1) << (N - 2);                    9: return -(N'(1) << (N - 2));
      10: return alt;        11: return ~alt;        default: return N'(7);
    endcase
  endfunction
  localparam int NC = 13;

  int n, nrand, npred;
  logic [N-1:0] a, b;
  initial begin
    e_unexp = 0; e_missing = 0; e_timing = 0;
    $display("booth_mult: N = %0d, ARCH = %0d (%s), zero detection %0b", N, ARCH,
             ARCH == 0 ? "wide" : ARCH == 1 ? "narrow" : "sign rule", ZD);
    rst = 1'b1; tick(); rst = 1'b0;
    `CHECK("FUNC", "reset: idle, done = 0", busy === 1'b0 && done === 1'b0, "busy/done wrong after reset")

    n = 0; npred = 0;
    for (int i = 0; i < NC; i++) for (int j = 0; j < NC; j++) begin
      multiply(corner(i), corner(j)); n++; npred += predicted_wrong(corner(i), corner(j));
    end
    group("FUNC", $sformatf("corner operand pairs incl. min x min (%0d predicted wrong)", npred), n);

    n = 0;
    nrand = 3000;
`ifdef VERILATOR
    nrand = 300000;
`endif
    tb_rng_state = 32'd2024;
    for (int i = 0; i < nrand; i++) begin
      a = N'(tb_rand()); b = N'(tb_rand());
      if (i % 50 == 0) a = MINV;                    // enough largest-negative multiplicands
      if (i % 50 == 1) a = '0;                      // and zero multiplicands
      multiply(a, b); n++;
    end
    group("FUNC", "random operand pairs", n);

    n = 0;
    for (int i = 0; i < 50; i++) begin a = N'(tb_rand()); b = N'(tb_rand()); multiply(a, b, 8); n++; end
    group("FUNC", "product and done hold for 8 cycles after completion", n);

    n = 0;
    for (int i = 0; i < 200; i++) begin a = N'(tb_rand()); b = N'(tb_rand()); multiply(a, b, 0, 1'b1); n++; end
    group("ROBUST", "start pulses and changing operands while busy are ignored", n);

    n = 0;
    for (int i = 0; i < 200; i++) begin
      int stop;
      a = N'(tb_rand()); b = N'(tb_rand());
      multiplicand = a; multiplier = b; start = 1'b1; tick(); start = 1'b0;
      stop = int'(tb_rand() % (2 * N));
      repeat (stop) tick();
      rst = 1'b1; tick(); rst = 1'b0;
      if (busy !== 1'b0 || done !== 1'b0) e_timing++;
      a = N'(tb_rand()); b = N'(tb_rand());
      multiply(a, b); n++;
    end
    group("ROBUST", "reset in the middle of a multiplication, then a clean one", n);

`ifdef EXHAUSTIVE
    n = 0; npred = 0;
    for (int ia = 0; ia < (1 << N); ia++)
      for (int ib = 0; ib < (1 << N); ib++) begin
        multiply(N'(ia), N'(ib)); n++; npred += predicted_wrong(N'(ia), N'(ib));
      end
    group("FUNC", $sformatf("EXHAUSTIVE: every operand pair (%0d predicted wrong)", npred), n);
`endif
    `REPORT
    $finish;
  end
endmodule
