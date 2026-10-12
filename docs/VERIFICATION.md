# Verification

`make ci` runs on every push; `make full` adds the exhaustive runs and the N = 6 proofs. Logs and reports go to
`build/`, and `build/SUMMARY.md` collects them.

## Simulation (`make sim`, `make exhaustive`)

`tb/tb_booth_mult.sv` checks every product two ways:
* **Value:** against `$signed(M) * $signed(Q)`.
* **Timing:** busy for 2N cycles, `done` on edge 2N + 1, and product and `done` held afterwards.

Each architecture is judged against its predicted set of wrong products. The test fails on a wrong product outside
the set, and also on a predicted-wrong product that comes out right.

| Run | Wide | Narrow | Sign rule | Sign rule + zero detect |
|---|---|---|---|---|
| 169 corner pairs (0, ±1, ±2, max, −max, min, ±2^(N−2), alternating patterns) | pass | pass (12 predicted wrong) | pass (12) | pass |
| 3 000 random pairs (300 000 in Verilator), with extra min and 0 multiplicands | pass | pass | pass | pass |
| hold after `done`; start pulses and operand changes while busy; reset mid-operation | pass | pass | pass | pass |
| **exhaustive, N = 13: all 67 108 864 pairs** (Verilator) | pass | wrong on exactly the **8 191** predicted pairs | exactly **8 191** | pass |
| exhaustive, N = 6: all 4 096 pairs (Icarus and Verilator) | pass | pass (63) | pass (63) | pass |

The defines select the configuration: `ARCH`, `NOZERO`, `N`, and `EXHAUSTIVE`. Random operands come from the
fixed-seed xorshift generator in `tb/tb_common.svh`.

## Formal (`make formal`, `make formal-quick`)

`formal/booth_mult_formal.sv` captures the operands at every accepted start and asserts, for every start and reset
pattern:
* the exact latency;
* `product == M × Q` once `done` is high;
* idle after reset.

Two optional assumptions restrict the operands to where an architecture is claimed exact.

| Proof | N = 4 | N = 6 |
|---|---|---|
| wide, all operands | proved (3 s) | proved (242 s) |
| sign rule + zero detect, all operands | proved (2 s) | proved (235 s) |
| narrow, assuming M ≠ −2^(N−1) | proved (2 s) | proved (213 s) |
| narrow, all operands | **counterexample** (frame 10) | **counterexample** (frame 14) |
| sign rule without zero detect, assuming M ≠ 0 | proved (3 s) | proved (226 s) |
| sign rule without zero detect, all operands | **counterexample** (frame 10) | **counterexample** (frame 14) |

Each predicted exception is therefore both sufficient (with it, the proof holds) and necessary (without it, there is
a counterexample). The times were measured on a laptop. `formal/run_formal.sh` states every expected outcome and
exits non-zero if any differs.

## Tools and how they are run

| Tool (version) | Used for | Command |
|---|---|---|
| Icarus Verilog 12.0 | simulation | `iverilog -g2012 -I tb -DARCH=<a> [-DNOZERO] [-DN=<n>] -o build/<t>.vvp tb/tb_booth_mult.sv rtl/booth_mult.sv`, then `vvp -n` |
| Verilator 5.032 | lint, fast and exhaustive simulation | `verilator --lint-only -Wall -GARCH=<a> ...`; `verilator --binary --timing -O2 -Itb -D... --top-module tb_booth_mult ...` |
| Yosys 0.52 | synthesis, proof models, SAT | `synth -flatten; abc -g gates; stat; write_verilog`; `miter -equiv; sat -max 16 -set trigger 1` |
| ABC (yosys-abc) | unbounded proofs | `formal/pdr.sh`: `yosys-abc -c "read_aiger m.aig; fold; strash; pdr"` |

`scripts/run_sim.sh` wraps both simulators: one log per testbench in `build/<test>.<sim>.log`, and a non-zero exit
unless the log ends in `RESULT: PASS`.

The proof model is built with:

```
read_verilog -sv -formal -DFORMAL <rtl> <harness>; chparam -set N <n> -set ARCH <a> ... booth_mult_formal
prep -top booth_mult_formal; flatten; async2sync; chformal -lower; chformal -assume -early; chformal -cover -remove
opt_clean; setundef -anyseq; opt -keepdc -fast; techmap; opt -fast; dffunmap; abc -g AND -fast; opt_clean
write_aiger -I -B -zinit m.aig
```

`chformal -lower` is essential. Yosys 0.52 elaborates `assert` into `$check` cells, and without lowering the model has
no properties, so every proof would pass vacuously. `pdr.sh` refuses a model with zero properties.

## CI

| Workflow | Trigger | Runs |
|---|---|---|
| CI (`.github/workflows/ci.yml`) | every push to `main`, pull requests | `lint`, `sim`, `formal-quick`, `synth`, `equivalence` |
| Full verification (`full.yml`) | manual, or a `v*` tag | the CI steps, plus `exhaustive` and the full `formal`; a tag also publishes a release |

Both use the pinned `ubuntu:26.04` image and `scripts/install-tools.sh`, the same script as the `Dockerfile`, and
upload `build/` as an artifact.
