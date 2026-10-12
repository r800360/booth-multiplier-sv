# Design

## Booth's algorithm and the datapath (`rtl/booth_mult.sv`)

Booth recoding turns each multiplier bit pair `(q_i, q_(i−1))`, with `q_(−1) = 0`, into a digit in {−1, 0, +1}:
* `10` subtracts the multiplicand;
* `01` adds it;
* `00` and `11` do nothing.

After each step, `{A, Q}` shifts right arithmetically.

| Register | Width | Role |
|---|---|---|
| A | N | accumulator |
| Q | N | multiplier; becomes the low half of the product |
| M | N | multiplicand |
| F1 | 1 | previous multiplier bit `q_(i−1)` |
| F2 | 1 | **true sign of the last stored partial sum**; shifted into A |

The sequence is: load, then N × (EX: optional add or subtract; SHIFT), then `done`.
* `done` rises exactly 2N + 1 edges after the start edge (27 for N = 13).
* `start` is ignored while busy.
* The product and `done` hold until the next start.

## The sign problem

**The bound.** Read the low k multiplier bits as a k-bit signed number x_k. After k steps, the stored partial sum is
`M · x_k / 2^(k−1)`. Since `|x_k| ≤ 2^(k−1)`, every stored partial sum has magnitude ≤ |M|.

**Its sign.** The partial sum is non-zero whenever an operation happens. Its top Booth digit outweighs all the digits
below it combined, so its sign is the sign of M times the sign of the digit (+ for an add, − for a subtract), unless
M = 0.

That gives three ways to produce F2 (`ARCH`):

| ARCH | F2 = | When it is wrong |
|---|---|---|
| 0 wide | bit N of an (N+1)-bit add | never |
| 1 narrow | bit N−1 of an N-bit add | only M = −2^(N−1) makes \|partial sum\| = 2^(N−1), which does not fit: the first subtraction, 0 − M, already overflows. So it fails exactly when M = −2^(N−1) and the multiplier ≠ 0 |
| 2 sign rule | `M[N−1] XOR SUB` | the rule assumes a non-zero partial sum. With M = 0 it injects 1s, so it fails exactly when M = 0 and the multiplier ≠ 0 |
| 2 + `ZERO_DETECT` | the rule, forced to 0 for M = 0 | never |

For the wide architecture, a stored A that overflowed by one bit is never added to again before a shift. The shift
brings in the correct sign from F2, so sign-extending A by its own top bit in the adder is always safe.

## Synthesis (`make synth`)

Yosys `synth -flatten; abc -g gates`, as cells including the flip-flops (48, or 49 with zero detection):

| N | wide | narrow | sign rule | sign rule + zero detect |
|--:|--:|--:|--:|--:|
| 8 | 163 | 153 | 155 | 164 |
| 13 | 251 | 243 | 245 | 258 |
| 16 | 302 | 292 | 294 | 311 |

## Equivalence-checking demo (`equivalence/`)

`check.sh` builds a miter (`y_left XOR y_right`) for each pair of functions in `functions.sv`. Yosys's SAT solver
either proves the miter unsatisfiable, or enumerates every input on which the two functions differ (`sat -max 16 -set
trigger 1`).

| Pair | Result |
|---|---|
| `Y0 = (A+B)(C'+D)(A+C')`, `Y1 = AC' + AD + C'D + A'BD'` | differ exactly on ABCD = 0001 and 0110 |
| `Z0 = B'(A+C)(A'+C')`, `Z1 = AB'C' + A'B'C` | equivalent: both are `B'(A XOR C)` |
| `F0 = (A XOR B) XNOR C`, `F1 = (A'B + AB')C + (AB + A'B')C'` | equivalent |
