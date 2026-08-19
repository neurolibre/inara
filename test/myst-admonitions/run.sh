#!/bin/sh
# Run myst-admonitions.lua over each fixture and compare the resulting LaTeX
# against the fixture's expected.tex.
#
# myst-references.lua runs too, so these tests also cover that a label defined
# by an admonition can be referenced from elsewhere in the document -- the two
# filters are ordered against each other precisely for that.
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
        "$image" \
        --data-dir=/inara \
        --wrap=none \
        --lua-filter=/inara/filters/myst-admonitions.lua \
        --lua-filter=/inara/filters/myst-references.lua \
        --to=latex \
        paper.md 2>/dev/null) || {
        printf 'FAIL %s (pandoc exited non-zero)\n' "$name"
        failures=$((failures + 1))
        continue
    }
    if printf '%s\n' "$actual" | diff -u "$fixture/expected.tex" - >/dev/null; then
        printf 'ok   %s\n' "$name"
    else
        printf 'FAIL %s\n' "$name"
        printf '%s\n' "$actual" | diff -u "$fixture/expected.tex" - || true
        failures=$((failures + 1))
    fi
done

if [ "$failures" -gt 0 ]; then
    printf '\n%s fixture(s) failed\n' "$failures"
    exit 1
fi
printf '\nall fixtures passed\n'
