#!/usr/bin/env bash
# @lat: [[verification-gates#Docker lanes]]

set -u

if [ "$#" -eq 0 ]; then
    echo "rake-gates.sh: name at least one rake task." >&2
    exit 64
fi

status=0
failed=0
summary=""

for task in "$@"; do
    echo "--- $task"
    if bundle exec rake "$task"; then
        code=0
    else
        code=$?
        status=1
        failed=$((failed + 1))
    fi
    summary="$summary$(printf '%-40s exit %s' "$task" "$code")
"
done

echo ""
echo "rake-gates: $failed of $# gates failed"
printf '%s' "$summary"

exit "$status"
