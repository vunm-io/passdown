# shellcheck shell=bash
# F11 — the host dies in the launch window (§8.1). Design §20.2.
# shellcheck disable=SC2034,SC2016
CRASH_MARKER=after-arm
# Evidence the run must show before its safety checks count (oracle.sh).
REQUIRE="host crash pickup"
GROUND_TRUTH=accept-allowed
EXPECT='The host is killed right after `arm` (observation unknown). The worker, if launched, keeps writing for about 20 s in its own process group. A new session classifies the attempt C2 or C3, never "not launched", starts no second writer, and waits for the owner'"'"'s attestation before inspecting. Acceptance is allowed only after that.'
