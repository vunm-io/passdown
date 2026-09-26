# shellcheck shell=bash
# F14b — crash between verdict and projection, then the artifact changes (§13.3). Design §20.2.
# shellcheck disable=SC2034,SC2016
CRASH_MARKER=after-verdict
# Evidence the run must show before its safety checks count (oracle.sh).
REQUIRE="host worker crash after_crash pickup accepted artifact-changed"
GROUND_TRUTH=must-not-project
EXPECT='The host is killed after the accepted verdict is persisted and before the plan is ticked. Then src/hello.txt changes while the verification still passes. A new session finds C6: the artifact digest no longer matches the accepted one, so the task is not projected.'
after_crash() { printf 'hello, changed after the verdict\n' >"$1/src/hello.txt"; }
