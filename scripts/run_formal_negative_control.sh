#!/usr/bin/env bash
set -euo pipefail

SBY_FILE="formal/negative_control/riscv_forwarding_buggy.sby"
WORK_DIR="formal/negative_control/riscv_forwarding_buggy_prove"
OUT_DIR="formal/negative_control/artifacts"
LOG_FILE="${OUT_DIR}/injected_bug_formal.log"

mkdir -p "$OUT_DIR"
rm -rf "$WORK_DIR"

set +e
sby -f "$SBY_FILE" prove 2>&1 | tee "$LOG_FILE"
sby_rc=${PIPESTATUS[0]}
set -e

if [[ "$sby_rc" -eq 0 ]]; then
  echo "ERROR: the intentionally buggy forwarding design unexpectedly passed."
  exit 1
fi

TRACE_FILE="$(find "$WORK_DIR" -type f \\( -name 'trace.vcd' -o -name 'trace0.vcd' \\) -print -quit)"
if [[ -z "$TRACE_FILE" ]]; then
  echo "ERROR: formal run failed but no VCD counterexample trace was produced."
  exit 1
fi

cp "$TRACE_FILE" "${OUT_DIR}/forwarding_priority_counterexample.vcd"
echo "PASS: formal rejected the injected old-over-new forwarding bug."
echo "Counterexample copied to ${OUT_DIR}/forwarding_priority_counterexample.vcd"
