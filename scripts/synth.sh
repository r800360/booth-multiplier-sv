#!/bin/bash
# synth.sh - Yosys synthesis of each architecture to a generic gate library (synth -flatten; abc -g gates):
# flip-flops, two-input gates and inverters. Full statistics in build/synth/<name>.txt.
cd "$(dirname "$0")/.."
B=build/synth; mkdir -p $B
printf '%-30s %6s %6s %6s %6s\n' configuration FFs gates inv total | tee $B/summary.txt
one() {  # name chparam
  yosys -q -p "read_verilog -sv rtl/booth_mult.sv; chparam $2 booth_mult; synth -top booth_mult -flatten; \
    abc -g gates; opt_clean; tee -q -o $B/$1.txt stat; write_verilog -noattr $B/$1.v" > $B/$1.log 2>&1 || { echo "$1: yosys failed"; return; }
  awk -v n="$1" '/^ +\$_/ { c=$1; v=$2; if (c ~ /DFF/) ff+=v; else if (c=="$_NOT_") inv+=v; else g+=v }
    END { printf "%-30s %6d %6d %6d %6d\n", n, ff, g, inv, ff+g+inv }' $B/$1.txt | tee -a $B/summary.txt
}
for n in 8 13 16; do
  one wide_n$n          "-set N $n -set ARCH 0"
  one narrow_n$n        "-set N $n -set ARCH 1"
  one signrule_zd_n$n   "-set N $n -set ARCH 2 -set ZERO_DETECT 1"
  one signrule_n$n      "-set N $n -set ARCH 2 -set ZERO_DETECT 0"
done
