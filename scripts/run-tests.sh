#!/bin/bash
# Usage: scripts/run-tests.sh
# Builds and runs every test line from CONTRIBUTING.md, keeps going after a failure and lists every problem at the end.
# On CI a test that prints that it skipped something fails too, unless scripts/ci-skips.txt lists that skip with a reason.
# TEST_TIME_LIMIT is how many seconds a test may take to build and to run (600); the limit needs timeout or gtimeout from coreutils.
set -uo pipefail
cd "$(dirname "$0")/.."

SKIPS=scripts/ci-skips.txt
SECS="${TEST_TIME_LIMIT:-600}"
problems=()
problem() {
    problems+=("$2")
    echo "::error title=$1::$2"
}

tests=$(grep '^swiftc .*scripts/test-' CONTRIBUTING.md)
[ -n "$tests" ] || problem CONTRIBUTING.md "CONTRIBUTING.md has no test lines"
for file in scripts/test-*.swift; do
    [[ "$tests" == *"$file"* ]] || problem "$file" "$file has no line in CONTRIBUTING.md, so it never runs"
done

ENTRY='^test-[a-z0-9-]+ [|] [^|]+ [|] .*[a-z]'
while IFS= read -r entry; do
    [[ -z "$entry" || "$entry" == \#* || "$entry" =~ $ENTRY ]] || problem "$SKIPS" "$SKIPS: write each line as “test-name | text the test prints | why CI can’t run it”, not “$entry”"
done < "$SKIPS"

TIMEOUT=$(command -v gtimeout || command -v timeout || true)
LIMIT=()
if [ -n "$TIMEOUT" ]; then
    LIMIT=("$TIMEOUT" -k 30 "$SECS")
elif [ -n "${CI:-}" ]; then
    problem timeout "No timeout or gtimeout here (brew install coreutils), so a stuck test would stop the ones after it"
fi
stopped() { [ -n "$TIMEOUT" ] && [ $((SECONDS - $1)) -ge "$SECS" ]; }

mkdir -p build/test-logs
count=0
while IFS= read -r test; do
    [ -n "$test" ] || continue
    count=$((count + 1))
    run="${test##* && }"
    name="${run#build/}"
    name="${name%% *}"
    log="build/test-logs/$name.log"
    echo "::group::$name"
    start=$SECONDS
    if [[ "$test" != *" && "* ]]; then
        problem "$name" "This CONTRIBUTING.md line doesn’t build a test and then run it: $test"
    elif ! ${LIMIT[@]+"${LIMIT[@]}"} bash -c "${test% && *}" < /dev/null; then
        stopped $start && problem "$name" "$name took longer than $SECS s to build and was stopped" || problem "$name" "$name did not build"
    else
        start=$SECONDS
        ${LIMIT[@]+"${LIMIT[@]}"} bash -c "$run" < /dev/null > "$log" 2>&1
        status=$?
        cat "$log"
        if [ "$status" -ne 0 ]; then
            stopped $start && problem "$name" "$name ran longer than $SECS s and was stopped" || problem "$name" "$name failed (exit $status)"
        elif [ -n "${CI:-}" ]; then
            while IFS= read -r line; do
                problem "$name" "$name skipped a check, and $SKIPS has no line for it: $line"
            done < <(awk -v name="$name" -v list="$SKIPS" '
                BEGIN { while ((getline entry < list) > 0) { split(entry, f, " [|] "); if (f[1] == name) allowed[f[2]] } }
                tolower($0) ~ /skip/ && $0 !~ /: ok$/ { for (text in allowed) if (index($0, text)) next; print }' "$log")
        fi
    fi
    echo "::endgroup::"
done <<< "$tests"

{
    if [ ${#problems[@]} -eq 0 ]; then
        echo "All $count tests passed"
    else
        echo "${#problems[@]} problem(s) in $count tests:"
        printf -- '- %s\n' "${problems[@]}"
    fi
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
[ ${#problems[@]} -eq 0 ]
