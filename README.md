# Sequential Booth multiplier: three ways to handle the sign, each characterized exactly

A parameterized radix-2 Booth multiplier (N × N → 2N bits, two's complement) with a fully synchronous controller.
It comes in three architectures that differ only in how the sign of the partial sum is kept. For each one, a short
argument predicts **exactly** which operand pairs come out wrong, and three independent checks confirm the
prediction:
* exhaustive simulation of all 2²⁶ pairs at N = 13;
* unbounded formal proofs at N = 4 and 6;
* formal counterexamples when an assumption is removed.

The repository also includes a small SAT-based logic equivalence checking demo.

## Booth's algorithm and the datapath

Booth recoding turns the multiplier's bit pairs `(q_i, q_(i−1))` (with `q_(−1) = 0`) into digits in {−1, 0, +1}:
pair `10` subtracts the multiplicand, `01` adds it, and `00` / `11` do nothing. After each step `{A, Q}` shifts right
arithmetically. The registers are:
* A, the N-bit accumulator;
* Q, the multiplier;
* M, the multiplicand;
* F1, the previous multiplier bit;
* F2, the **true sign of the last stored partial sum**, which is shifted into A.

```
start ──► load ──► N × ( EX: if (Q[0], F1) = 10: A −= M, 01: A += M     SHIFT: {A, Q} >>= 1, F2 → A[N−1], F1 ← Q[0] )
                                                                                                  ──► done, product = {A, Q}
```

`done` rises exactly 2N + 1 edges after the start edge (27 for N = 13). `start` is ignored while busy. The product
and `done` hold until the next start.

## The sign problem

An N-bit accumulator cannot always hold the partial sum's sign. Suppose that after k steps the low k multiplier
bits, read as a k-bit signed number, have the value `x_k`. The stored partial sum is then `M · x_k / 2^(k−1)`. Since
`|x_k| ≤ 2^(k−1)`:

> **every stored partial sum has magnitude ≤ |M|**, and it is non-zero with the sign of M times the sign of the
> Booth digit, unless M = 0.

That gives three architectures (`ARCH`):

| ARCH | F2 = | Cost (N = 13, Yosys cells incl. 48–49 flip-flops) | Predicted wrong products |
|---|---|---|---|
| 0 **wide** | bit N of an (N+1)-bit adder | 251 cells | **none** |
| 1 **narrow** | bit N−1 of an N-bit adder | 243 cells | exactly the pairs with **M = −2^(N−1) and multiplier ≠ 0**. Only that M makes \|partial sum\| = 2^(N−1) (the first subtraction, 0 − M) |
| 2 **sign rule** | `M[N−1] ⊕ SUB` (one XOR) | 245 cells | exactly the pairs with **M = 0 and multiplier ≠ 0**: the rule injects 1s although the sum is 0 |
| 2 + `ZERO_DETECT` | the sign rule, forced to 0 for M = 0 | 258 cells | **none** |

The narrow adder saves 8 gates (3 %). Making the sign rule exact again costs more than the wider adder. The
(N+1)-bit adder is the simplest exact design, and the others are useful mainly as a lesson in *why* they fail.

## Verification

### Simulation: `tb/tb_booth_mult.sv`

The reference is `$signed(M) * $signed(Q)`. Every product is also checked for exact timing: busy for 2N cycles,
`done` on the (2N + 1)-th edge, product and `done` held afterwards. Each architecture is compared with its
*predicted* set of wrong products. A wrong product outside the set fails the test, and so does a predicted-wrong
product that comes out right.

| Run | Wide | Narrow | Sign rule | Sign rule + zero detect |
|---|---|---|---|---|
| 169 corner pairs (0, ±1, ±2, max, −max, min, ±2^(N−2), alternating patterns) | pass | pass (12 predicted wrong) | pass (12) | pass |
| 3 000 random pairs, with extra min and 0 multiplicands (300 000 with Verilator) | pass | pass | pass | pass |
| Hold after `done`; start pulses and operand changes while busy; reset mid-operation | pass | pass | pass | pass |
| **Exhaustive, N = 13: all 67 108 864 pairs** (`make exhaustive`, Verilator) | pass | pass: exactly the **8 191** predicted pairs wrong | pass: exactly **8 191** | pass |
| Exhaustive, N = 6: all 4 096 pairs (Icarus and Verilator) | pass | pass (63) | pass (63) | pass |

### Formal: `make formal` (Yosys + ABC PDR)

`formal/booth_mult_formal.sv` captures the operands at every accepted start and asserts, for every start and reset
pattern:
* the exact latency;
* `product == M × Q` once `done`;
* idle after reset.

Optional assumptions restrict the operands to where an architecture is claimed exact.

| Proof | N = 4 | N = 6 |
|---|---|---|
| wide, all operands | proved (3 s) | proved (242 s) |
| sign rule + zero detect, all operands | proved (2 s) | proved (235 s) |
| narrow, assuming M ≠ −2^(N−1) | proved (2 s) | proved (213 s) |
| narrow, all operands | **counterexample** (frame 10) | **counterexample** (frame 14) |
| sign rule without zero detect, assuming M ≠ 0 | proved (3 s) | proved (226 s) |
| sign rule without zero detect, all operands | **counterexample** (frame 10) | **counterexample** (frame 14) |

So each predicted exception is both sufficient (the proof holds without it) and necessary (removing the assumption
gives a counterexample).

## Equivalence checking demo: `make equivalence`

`equivalence/check.sh` builds a miter (`y_left xor y_right`) for each pair of functions in
`equivalence/functions.sv`. It then either proves the miter unsatisfiable with Yosys's SAT solver, or enumerates
every input on which the two functions differ:

```
y0 != y1: DIFFER, inputs (A B C D) where they differ: 0110 0001
z0 == z1: EQUIVALENT (miter unsatisfiable)
f0 == f1: EQUIVALENT (miter unsatisfiable)
```

The three pairs are:
* `Y0 = (A+B)(C'+D)(A+C')` and `Y1 = AC' + AD + C'D + A'BD'`, which differ exactly on ABCD = 0001 and 0110;
* `Z0 = B'(A+C)(A'+C')` and `Z1 = AB'C' + A'B'C`, which are both `B'(A ⊕ C)`;
* `F0 = (A ⊕ B) ⊙ C` and `F1 = (A'B + AB')C + (AB + A'B')C'`.

## Repository layout

```
rtl/booth_mult.sv              the multiplier (parameters N, ARCH, ZERO_DETECT)
tb/tb_booth_mult.sv            self-checking testbench (+ tb_common.svh)
formal/booth_mult_formal.sv    properties; pdr.sh, run_formal.sh (proofs and counterexamples with expected outcomes)
equivalence/                   functions.sv, check.sh
scripts/                       run_sim.sh, synth.sh
```

## Running

```bash
make                 # lint, Icarus and Verilator simulation of all architectures
make exhaustive      # all 2^26 pairs per architecture (Verilator, several minutes each)
make formal          # PDR proofs, N = 4 and 6 (BOOTH_N="4" for the fast subset)
make synth           # gate counts for N = 8, 13, 16
make equivalence     # SAT equivalence checking demo
```

Requirements: Verilator 5, Icarus Verilog 12, Yosys ≥ 0.30 with yosys-abc. Tested with Verilator 5.032, Icarus 12.0
and Yosys 0.52.

## Background

This design started as a university digital-design lab assignment, built as schematics around a provided,
clock-gated controller. This repository is a from-scratch, fully synchronous re-implementation in SystemVerilog. It
adds the exact characterization of each architecture, proven formally and confirmed exhaustively.
