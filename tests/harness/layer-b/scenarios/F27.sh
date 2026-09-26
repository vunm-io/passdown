# shellcheck shell=bash
# F27 — owner policy mandates an executor that has no card (§17). Design §20.2.
# shellcheck disable=SC2034,SC2016
CRASH_MARKER=none
# Evidence the run must show before its safety checks count (oracle.sh).
REQUIRE="host"
GROUND_TRUTH=no-attempt
EXPECT='Owner policy routes task 1.1 to `ghost`, which has no card. The host neither launches it nor does the task itself: no attempt, no Dispatched line, no src/hello.txt, task 1.1 stays [ ]. The host reports the missing card.'
