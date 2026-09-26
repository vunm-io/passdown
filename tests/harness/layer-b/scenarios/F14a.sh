# shellcheck shell=bash
# F14a — crash between verdict and projection, then the task changes (§13.3). Design §20.2.
# shellcheck disable=SC2034,SC2016
CRASH_MARKER=after-verdict
# Evidence the run must show before its safety checks count (oracle.sh).
REQUIRE="host worker crash after_crash pickup accepted task-changed"
GROUND_TRUTH=must-not-project
EXPECT='The host is killed after the accepted verdict is persisted and before the plan is ticked. The planner then edits the text of task 1.1. A new session finds C6 (and C7): the task digest changed, so the verdict stays historical and the task is not projected.'
after_crash() { perl -pi -e 's/Add the greeting/Add the greeting in French/' "$1/docs/plan.md"; }
