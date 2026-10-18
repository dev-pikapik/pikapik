#!/bin/bash
# Usage: scripts/run-tests.sh [--changed] [--list]
# Builds and runs every test line from CONTRIBUTING.md, keeps going after a failure and lists every problem at the end.
# --changed runs only the lines that build, name or read a file changed since origin/main, committed or not, and all of them when this script changed;
# --list prints the names of the tests instead of running them.
# On CI a test that prints that it skipped something fails too, unless scripts/ci-skips.txt lists that skip with a reason.
# TEST_TIME_LIMIT is how many seconds a test may take to build and to run (600); the limit needs timeout or gtimeout from coreutils.
set -uo pipefail
cd "$(dirname "$0")/.."

changed=false
list=false
for arg in "$@"; do
    case $arg in
        --changed) changed=true ;;
        --list) list=true ;;
        *) echo "Usage: scripts/run-tests.sh [--changed] [--list]" >&2; exit 2 ;;
    esac
done

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

if $changed; then
    base=$(git merge-base origin/main HEAD 2>/dev/null) || { echo "There is no origin/main to compare with: run git fetch origin first" >&2; exit 2; }
    files=$({ git -c core.quotePath=false diff --name-only --no-renames "$base"; git -c core.quotePath=false ls-files --others --exclude-standard; } | sort -u)
    new_lines=$(git diff "$base" -- CONTRIBUTING.md | sed -n 's/^+\(swiftc \)/\1/p')
    targets=""
    data=""
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -e "$path" ]; then
            targets+="$path"$'\n'
        else
            dir=$path
            while [[ "$dir" == */* ]]; do
                dir="${dir%/*}"
                [ -d "$dir" ] && break
            done
            [ -d "$dir" ] && targets+="$dir/"$'\n'
        fi
        part=$path
        while :; do
            data+="\"$part\""$'\n'"\"$part/\""$'\n'"/$part\""$'\n'"/$part/\""$'\n'
            [[ "$part" == */* ]] || break
            part="${part%/*}"
        done
    done <<< "$files"
fi

inputs() {
    local build="${1% && *}" cmds="" part
    build="${build//.\/scripts\/test-core.sh/words}"
    while :; do
        part="${build%% && *}"
        cmds+="words ${part#* }"$'\n'
        [ "$part" = "$build" ] && break
        build="${build#* && }"
    done
    ( set +u; words() { printf '%s\n' "$@"; }; eval "$cmds" ) < /dev/null 2> /dev/null
}

selected() {
    $changed || return 0
    [[ $'\n'"$files"$'\n' == *$'\n'scripts/run-tests.sh$'\n'* || $'\n'"$new_lines"$'\n' == *$'\n'"$1"$'\n'* ]] && return 0
    local path words sources
    while IFS= read -r path; do
        [[ -n "$path" && "$1" == *"$path"* ]] && return 0
    done <<< "$files"
    words=$(inputs "$1")
    TARGETS="$targets" awk 'BEGIN { n = split(ENVIRON["TARGETS"], t, "\n") }
        { for (i = 1; i <= n; i++) if (t[i] != "" && ($0 == t[i] || (t[i] ~ /\/$/ && index($0, t[i]) == 1))) { found = 1; exit } }
        END { exit !found }' <<< "$words" && return 0
    sources=$(grep '^scripts/.*\.swift$' <<< "$words")
    [ -n "$sources" ] && [ -n "$data" ] && grep -qF -- "${data%$'\n'}" $sources 2> /dev/null
}

mkdir -p build/test-logs
total=0
count=0
while IFS= read -r test; do
    [ -n "$test" ] || continue
    total=$((total + 1))
    run="${test##* && }"
    name="${run#build/}"
    name="${name%% *}"
    selected "$test" || continue
    if $list; then
        echo "$name"
        continue
    fi
    count=$((count + 1))
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

if $list; then
    [ ${#problems[@]} -eq 0 ]
    exit
fi

{
    $changed && echo "$count of $total tests use the files changed since origin/main"
    if [ ${#problems[@]} -gt 0 ]; then
        echo "${#problems[@]} problem(s) in $count tests:"
        printf -- '- %s\n' "${problems[@]}"
    elif [ "$count" -gt 0 ]; then
        echo "All $count tests passed"
    fi
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
[ ${#problems[@]} -eq 0 ]
