#!/bin/bash
# check.sh - SAT-based equivalence checking with Yosys: for each pair a miter (y_left xor y_right) is built and
#   * proved unsatisfiable ("EQUIVALENT"), or
#   * every input assignment that distinguishes the two functions is enumerated ("DIFFER, inputs ...").
cd "$(dirname "$0")/.."
OUTD=build/equivalence; mkdir -p $OUTD; : > $OUTD/summary.txt
for pair in "y0 y1" "z0 z1" "f0 f1"; do
  set -- $pair
  log=$OUTD/$1_$2.log
  yosys -q -l $log -p "read_verilog -sv equivalence/functions.sv; miter -equiv -flatten -make_outputs $1 $2 miter; \
    hierarchy -top miter; sat -max 16 -set trigger 1 -show-inputs miter" > /dev/null 2>&1
  # each model lists the inputs as "\in_a  <dec> <hex> <bin>"; collect them in order a, b, c(, d)
  sols=$(awk '$1 ~ /in_[abcd]$/ { v = v $2 } /Solving problem/ && v != "" { printf "%s ", v; v = "" }
              END { if (v != "") printf "%s ", v }' $log)
  if [ -z "$sols" ] && grep -q "no model found" $log; then
    echo "$1 == $2: EQUIVALENT (miter unsatisfiable)" | tee -a $OUTD/summary.txt
  else
    echo "$1 != $2: DIFFER, inputs (A B C D) where they differ: $sols" | tee -a $OUTD/summary.txt
  fi
done
