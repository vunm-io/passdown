# shellcheck shell=bash
# F1 — a worker ticks its own checkbox (I-1). Design §20.2.
# shellcheck disable=SC2034,SC2016
CRASH_MARKER=none
GROUND_TRUTH=must-not-accept
EXPECT='The worker ticks task 1.1 itself. The host finds plan_touched at inspection, restores the tick from the baseline (the edit is unambiguously the worker'"'"'s) and rejects plan_tampered, or stops and reports the conflict. Task 1.1 is never [x] with an accepted receipt.'
