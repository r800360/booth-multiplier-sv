# Sequential Booth multiplier: lint, simulation, formal verification, synthesis, equivalence-checking demo.
# Toolchain: Icarus Verilog, Verilator, Yosys + yosys-abc (exact versions in scripts/install-tools.sh).

RTL := rtl/booth_mult.sv
TB  := tb/tb_booth_mult.sv
RUN := bash scripts/run_sim.sh

.PHONY: all ci full summary lint sim sim-icarus sim-verilator exhaustive formal formal-quick synth equivalence clean

all: lint sim

# CI entry points (.github/workflows): `make ci` runs on every push, `make full` adds the long runs
ci: lint sim formal-quick synth equivalence summary
full: lint sim synth equivalence exhaustive formal summary

summary:
	@bash scripts/summary.sh > /dev/null && echo "wrote build/SUMMARY.md"

lint:
	verilator --lint-only -Wall --top-module booth_mult $(RTL)
	verilator --lint-only -Wall --top-module booth_mult -GARCH=1 $(RTL)
	verilator --lint-only -Wall --top-module booth_mult -GARCH=2 $(RTL)
	verilator --lint-only -Wall --top-module booth_mult -GARCH=2 -GZERO_DETECT="1'b0" $(RTL)

define TESTS
	$(RUN) $(1) wide           $(TB) "ARCH=0"          $(RTL)
	$(RUN) $(1) narrow         $(TB) "ARCH=1"          $(RTL)
	$(RUN) $(1) signrule_zd    $(TB) "ARCH=2"          $(RTL)
	$(RUN) $(1) signrule       $(TB) "ARCH=2 NOZERO"   $(RTL)
	$(RUN) $(1) wide_n6_exh    $(TB) "ARCH=0 N=6 EXHAUSTIVE"        $(RTL)
	$(RUN) $(1) narrow_n6_exh  $(TB) "ARCH=1 N=6 EXHAUSTIVE"        $(RTL)
	$(RUN) $(1) signzd_n6_exh  $(TB) "ARCH=2 N=6 EXHAUSTIVE"        $(RTL)
	$(RUN) $(1) sign_n6_exh    $(TB) "ARCH=2 NOZERO N=6 EXHAUSTIVE" $(RTL)
endef

sim: sim-icarus sim-verilator

sim-icarus:
	$(call TESTS,icarus)

sim-verilator:
	$(call TESTS,verilator)

# all 2^26 operand pairs at N = 13 for every architecture (Verilator; several minutes each)
exhaustive:
	$(RUN) verilator wide_exh     $(TB) "ARCH=0 EXHAUSTIVE"          $(RTL)
	$(RUN) verilator narrow_exh   $(TB) "ARCH=1 EXHAUSTIVE"          $(RTL)
	$(RUN) verilator signzd_exh   $(TB) "ARCH=2 EXHAUSTIVE"          $(RTL)
	$(RUN) verilator sign_exh     $(TB) "ARCH=2 NOZERO EXHAUSTIVE"   $(RTL)

formal:
	bash formal/run_formal.sh

# N = 4 only (about 20 seconds)
formal-quick:
	BOOTH_N=4 bash formal/run_formal.sh

synth:
	bash scripts/synth.sh

equivalence:
	bash equivalence/check.sh

clean:
	rm -rf build obj_dir
