#!/usr/bin/env bash
# The two decisions verify.sh makes about a finished lane, kept in a file with
# no side effects so a test can source it and call them with fixture values.
#
# Nothing here starts a container, reads a global, or writes one. That is the
# point: every other check on verify.sh reads the script as TEXT, so a regex
# can still match after a change that inverts what the code does. These two
# are the ones where that gap costs the most — they decide whether the whole
# gate reports green.
#
# Sourced by scripts/dip/verify.sh. Bash, not sh: rspec_lane_totals uses [[ ]]
# and BASH_REMATCH.

# parallel_tests prints one aggregate "N examples, M failures[, K pending]"
# line after every worker in a lane has finished
# (ParallelTests::CLI#report_results -> Test::Runner.summarize_results) — the
# LAST such line in a lane's log is that combined total, not any one worker's
# own. grep -Eo keeps only the matched prefix so a trailing ", K pending"
# cannot confuse the two capture groups below. Echoes "0 0" (did-not-complete,
# never green) when no such line exists at all, e.g. every worker
# crashed before finishing.
rspec_lane_totals() {
    local log="$1" line
    line="$(grep -Eo '^[0-9]+ examples?, [0-9]+ failures?' "$log" 2>/dev/null | tail -1 || true)"
    if [[ "$line" =~ ^([0-9]+)\ examples?,\ ([0-9]+)\ failures? ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    else
        echo "0 0"
    fi
}

# @lat: [[verification-gates#Docker lanes]]
rake_gates_totals() {
    local log="$1" line
    line="$(grep -Eo '^rake-gates: [0-9]+ of [0-9]+ gates failed' "$log" 2>/dev/null | tail -1 || true)"
    if [[ "$line" =~ ^rake-gates:\ ([0-9]+)\ of\ ([0-9]+)\ gates ]]; then
        echo "${BASH_REMATCH[2]} ${BASH_REMATCH[1]}"
    else
        echo "0 0"
    fi
}

# Echoes one of green / red / did-not-complete. The order of the tests
# below is the contract, not a detail: each one can only decide the cases the
# ones above it have not already taken.
#
#   docker_exit  the container's own exit code, "" for a host lane
#   oom          "true" when the kernel killed it for memory
#   lane_exit    what the lane's own process returned
#   examples     an rspec lane's summed example count, "" for every other lane
#   failures     an rspec lane's summed failure count, "" for every other lane
#   ok_codes     exit codes this lane documents as a real result, default "0 1"
lane_state() {
    local docker_exit="$1" oom="$2" lane_exit="$3" examples="$4" failures="$5"
    local ok_codes="${6:-0 1}"

    # Killed, rather than finished with an answer. 137 is the signal-9 exit.
    if [ "$docker_exit" = "137" ] || [ "$oom" = "true" ]; then
        echo "did-not-complete"
        return 0
    fi

    # An exit code the tool does not document means it never reached a result:
    # a crash before it ran, or a death by signal. Padded so a lane exiting 3
    # cannot match the "3" inside another lane's list by substring alone.
    case " $ok_codes " in
        *" $lane_exit "*) ;;
        *)
            echo "did-not-complete"
            return 0
            ;;
    esac

    # A lane that ran nothing is a broken split, not a pass — reporting it
    # green is exactly the failure this gate exists to remove.
    if [ -n "$examples" ] && [ "$examples" = "0" ]; then
        echo "did-not-complete"
        return 0
    fi

    # The lane's own count outranks its exit code, and is asked FIRST: after
    # the exit-code test below, this could never fire for the only case it is
    # for — a lane that counted failures and still exited 0, which is what a
    # wrapper swallowing a status looks like from out here.
    if [ -n "$failures" ] && [ "$failures" != "0" ]; then
        echo "red"
        return 0
    fi

    if [ "$lane_exit" = "0" ]; then
        echo "green"
    else
        echo "red"
    fi
}
