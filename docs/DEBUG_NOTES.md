# Debug Notes

During regression, seed 10 exposed a RAW dependency corner case involving multiple consecutive writes to the same source register followed by an immediate consuming instruction.

## Failing Pattern Observed Before v7

```text
instruction[6]  writes x7
instruction[7]  writes x7
instruction[8]  reads  x7
```

The consumer needed the newest x7 value. Earlier versions did not handle this dependency correctly in the relevant bypass path, causing a scoreboard mismatch.

## Final Fix

The final v7 design includes a decode-bypass / youngest-writer forwarding fix so the consumer observes the newest architectural value.

## Result After Fix

Seed 10 was rerun on v7 and passed with:

```text
Scoreboard PASS: checked 40 committed instructions
UVM_ERROR : 0
UVM_FATAL : 0
```

The full v7 20-seed regression was then rerun successfully.
