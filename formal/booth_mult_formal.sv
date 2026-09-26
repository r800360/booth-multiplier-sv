// booth_mult_formal.sv - properties of booth_mult for every operand pair and every start / reset pattern.
//
// After an accepted start (start while idle) the harness counts rising edges t (the start edge is t = 1) and keeps
// the operands. Then:
//   P1  1 <= t <= 2N : busy and not done;   t >= 2N + 1 : done and not busy     (exact latency 2N + 1)
//   P2  done -> product == multiplicand x multiplier                            (2N-bit two's complement)
//   P3  after reset and before the next start: neither busy nor done
// Optional assumptions restrict the operands to the domain where an architecture is claimed to be exact:
//   NOT_MIN   multiplicand != -2^(N-1)       (ARCH 1, narrow adder)
//   NONZERO   multiplicand != 0              (ARCH 2 without zero detection)
// The first cycle is a reset cycle (the design has no initial values).
module booth_mult_formal #(
  parameter int N           = 4,
  parameter int ARCH        = 0,
  parameter bit ZERO_DETECT = 1'b1,
  parameter bit NOT_MIN     = 1'b0,
  parameter bit NONZERO     = 1'b0
) (
  input logic         clk,
  input logic         rst,
  input logic         start,
  input logic [N-1:0] multiplicand,
  input logic [N-1:0] multiplier
);
  logic [2*N-1:0] product;
  logic busy, done;
  booth_mult #(.N(N), .ARCH(ARCH), .ZERO_DETECT(ZERO_DETECT)) dut (
    .clk, .rst, .start, .multiplicand, .multiplier, .product, .busy, .done);

  localparam int TW = $clog2(2 * N + 2) + 1;
  localparam logic [TW-1:0] TDONE = TW'(2 * N + 1);
  logic          first = 1'b1, running = 1'b0;
  logic [TW-1:0] t;
  logic [N-1:0]  ma, mb;
  logic          accept;
  assign accept = start && !busy;

  always_ff @(posedge clk) begin
    first <= 1'b0;
    if (rst) running <= 1'b0;
    else if (accept) begin
      running <= 1'b1; t <= TW'(1); ma <= multiplicand; mb <= multiplier;
    end else if (running && t != TDONE) t <= t + 1'b1;
  end

  always_comb begin
    if (first) assume (rst);
    if (NOT_MIN && accept) assume (multiplicand != {1'b1, {(N-1){1'b0}}});
    if (NONZERO && accept) assume (multiplicand != '0);
  end

  logic signed [2*N-1:0] expv;
  assign expv = $signed(ma) * $signed(mb);
  always_comb begin
    if (!first) begin
      if (!running) assert (!busy && !done);
      else if (t != TDONE) assert (busy && !done);
      else begin
        assert (!busy && done);
        assert (product == expv);
      end
    end
  end
endmodule
