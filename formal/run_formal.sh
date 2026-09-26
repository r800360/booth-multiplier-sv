#!/bin/bash
# run_formal.sh - formal campaign (Yosys + ABC PDR) for rtl/booth_mult.sv. Every line states the expected outcome;
# the script exits 1 if any outcome differs. Summary: build/formal/summary.txt. BOOTH_N = operand widths to prove.
#   1. the exact architectures are proved for every operand pair
#   2. the other two are proved exact on the domain the analysis predicts, and shown to fail without that restriction
cd "$(dirname "$0")/.."
OUTD=build/formal; mkdir -p $OUTD
OUT=$OUTD/summary.txt; : > $OUT
F="rtl/booth_mult.sv formal/booth_mult_formal.sv"
T=booth_mult_formal
bad=0
check() {  # expected tag params
  local exp=$1 tag=$2 params=$3
  local r; r=$(bash formal/pdr.sh "$tag" $T "$F" "$params")
  local got=${r#*: }; got=${got%% *}
  if [ "$got" = "$exp" ]; then echo "  ok        $r" | tee -a $OUT
  else echo "  UNEXPECTED (expected $exp) $r" | tee -a $OUT; bad=1; fi
}
for n in ${BOOTH_N:-4 6}; do
  echo "== N = $n" | tee -a $OUT
  check PROVED wide_n$n            "-set N $n -set ARCH 0"
  check PROVED signrule_zd_n$n     "-set N $n -set ARCH 2 -set ZERO_DETECT 1"
  check PROVED narrow_notmin_n$n   "-set N $n -set ARCH 1 -set NOT_MIN 1"
  check FAILED narrow_n$n          "-set N $n -set ARCH 1"
  check PROVED signrule_nz_n$n     "-set N $n -set ARCH 2 -set ZERO_DETECT 0 -set NONZERO 1"
  check FAILED signrule_n$n        "-set N $n -set ARCH 2 -set ZERO_DETECT 0"
done
[ $bad -eq 0 ] && echo "ALL OUTCOMES AS EXPECTED" | tee -a $OUT || echo "SOME OUTCOMES UNEXPECTED" | tee -a $OUT
exit $bad
