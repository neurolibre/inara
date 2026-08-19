#!/bin/sh
# Run myst-abstract.lua over each fixture and compare the abstract it lifted
# into metadata, and the body it left behind, against the fixture's expected.txt.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
image=${INARA_TEST_IMAGE:-pandoc/core:3.2.0-alpine}
failures=0

for fixture in "$here"/fixtures/*/; do
    name=$(basename "$fixture")
    actual=$(docker run --rm \
        -v "$fixture:/data" \
        -v "$repo/data:/inara:ro" \
        -v "$here/dump.template:/dump.template:ro" \
        "$image" \
        --data-dir=/inara \
        --wrap=none \
        --lua-filter=/inara/filters/myst-abstract.lua \
        --template=/dump.template \
        --to=latex \
        paper.md 2>/dev/null) || {
        printf 'FAIL %s (pandoc exited non-zero)\n' "$name"
        failures=$((failures + 1))
        continue
    }
    if printf '%s\n' "$actual" | diff -u "$fixture/expected.txt" - >/dev/null; then
        printf 'ok   %s\n' "$name"
    else
        printf 'FAIL %s\n' "$name"
        printf '%s\n' "$actual" | diff -u "$fixture/expected.txt" - || true
        failures=$((failures + 1))
    fi
done

if [ "$failures" -gt 0 ]; then
    printf '\n%s fixture(s) failed\n' "$failures"
    exit 1
fi
printf '\nall fixtures passed\n'
