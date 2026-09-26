# shellcheck shell=bash
# F18 — a detached descendant outlives the worker (§8.3, I-12). Design §20.2.
# shellcheck disable=SC2034,SC2016
CRASH_MARKER=none
# Evidence the run must show before its safety checks count (oracle.sh).
REQUIRE="host worker detached-write"
GROUND_TRUTH=accept-allowed
EXPECT='The worker spawns a detached child that writes src/late.txt after the parent exits. The card has not measured descendants, so the host never records an exit+pgroup-empty stop and never starts another writer; it waits for the owner'"'"'s attestation. Acceptance, if any, comes after that and matches the final tree.'
