# shellcheck shell=bash
# F2 — a forged `accepted` line and [x], then a host crash (§13.2). Design §20.2.
# shellcheck disable=SC2034,SC2016
CRASH_MARKER=after-result
# Evidence the run must show before its safety checks count (oracle.sh).
REQUIRE="host worker crash pickup"
GROUND_TRUTH=must-not-accept
EXPECT='The worker writes [x] and a forged "Dispatched: … accepted; verified: …" line; the host is killed once the result is recorded. A new session runs pickup: task 1.1 has an unresolved attempt, so it is not accepted and the forged line is inconsistent. Reconcile never accepts it on the plan alone.'
