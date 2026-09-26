// booth_mult.sv - sequential radix-2 Booth multiplier, N x N -> 2N bits, two's complement.
//
// start (while idle) loads the operands; the multiplier then runs N steps of
//   EX     if the Booth pair (Q[0], F1) is 10: A -= M, if 01: A += M, otherwise nothing
//   SHIFT  {A, Q} >>= 1 arithmetically, with F2 (the sign of the last stored partial sum) shifted into A;
//          F1 <= Q[0]
// and raises done 2N + 1 rising edges after the start edge (load, then N x (EX, SHIFT)). product = {A, Q}.
//
// The accumulator A is N bits; F2 holds the true sign that A alone cannot represent. ARCH selects how F2 is made:
//   0  WIDE       an (N+1)-bit adder; F2 = its bit N.                      Exact for every operand pair.
//   1  NARROW     an N-bit adder; F2 = its bit N-1.                        Exact unless multiplicand = -2^(N-1).
//   2  SIGN_RULE  an N-bit adder; F2 = M[N-1] xor SUB, the sign rule.      Exact unless multiplicand = 0;
//                 with ZERO_DETECT = 1, F2 is forced to 0 for a zero multiplicand, which makes it exact.
// Why: every stored partial sum is M * x_k / 2^(k-1), where x_k is the multiplier's low k bits read as a signed
// number, so |partial sum| <= |M| (it fits in N bits unless M = -2^(N-1)), and its sign is the sign of M times the
// sign of the Booth digit (+ for an add, - for a subtract) unless M = 0. See README.md.
module booth_mult #(
  parameter int N           = 13,
  parameter int ARCH        = 0,
  parameter bit ZERO_DETECT = 1'b1
) (
  input  logic           clk,
  input  logic           rst,           // synchronous: idle, done = 0
  input  logic           start,         // ignored while busy
  input  logic [N-1:0]   multiplicand,
  input  logic [N-1:0]   multiplier,
  output logic [2*N-1:0] product,       // valid while done = 1
  output logic           busy,
  output logic           done
);
  localparam int KW = $clog2(N);

  logic [N-1:0]  a, q, m;
  logic          f1, f2, phase, m_nonzero;   // phase: 0 = EX, 1 = SHIFT
  logic [KW-1:0] k;

  // ---------------------------------------------------------------- add / subtract and the stored sign
  logic          sub, op;
  logic [N:0]    sum_wide;
  logic [N-1:0]  sum;
  logic          sign;
  assign op  = q[0] ^ f1;                     // Booth pair 01 or 10
  assign sub = q[0];                          // 10: subtract, 01: add
  assign sum_wide = sub ? {a[N-1], a} - {m[N-1], m} : {a[N-1], a} + {m[N-1], m};
  assign sum = sum_wide[N-1:0];               // the low N bits are the same for every architecture
  always_comb begin
    case (ARCH)
      0:       sign = sum_wide[N];
      1:       sign = sum_wide[N-1];
      default: sign = (m[N-1] ^ sub) & (m_nonzero | !ZERO_DETECT);
    endcase
  end

  // ---------------------------------------------------------------- sequencer and datapath
  always_ff @(posedge clk) begin
    if (rst) begin
      busy <= 1'b0; done <= 1'b0;
      a <= '0; q <= '0; m <= '0; f1 <= 1'b0; f2 <= 1'b0; phase <= 1'b0; k <= '0; m_nonzero <= 1'b0;
    end else if (start && !busy) begin
      busy <= 1'b1; done <= 1'b0;
      a <= '0; q <= multiplier; m <= multiplicand; f1 <= 1'b0; f2 <= 1'b0; phase <= 1'b0; k <= '0;
      m_nonzero <= (multiplicand != '0);
    end else if (busy) begin
      if (!phase) begin
        if (op) begin a <= sum; f2 <= sign; end
      end else begin
        {a, q} <= {f2, a, q[N-1:1]};
        f1 <= q[0];
        k  <= k + 1'b1;
        if (k == KW'(N - 1)) begin busy <= 1'b0; done <= 1'b1; end
      end
      phase <= !phase;
    end
  end

  assign product = {a, q};
endmodule
