#!/bin/sh
# Run myst-frontmatter.lua over each fixture and compare the resulting
# metadata against the fixture's expected.txt.
#
# Both myst-frontmatter.lua and normalize-metadata.lua run, so these tests
# also cover that synthesized metadata survives inara's normalizer.
#
# A fixture may opt into a second check by containing an `expected-refs.txt`.
# That check runs the fixture through the real `--defaults=shared` filter chain
# -- so inline-cited-references.lua and citeproc both run -- and compares the
# resolved reference keys. This is what pins the filter *order*: myst-frontmatter
# must fill meta.bibliography before inline-cited-references.lua reads and then
# clears it, and the metadata check above cannot see that because it never runs
# either of those filters.
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
        --lua-filter=/inara/filters/myst-frontmatter.lua \
        --lua-filter=/inara/filters/normalize-metadata.lua \
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

    [ -f "$fixture/expected-refs.txt" ] || continue

    refs=$(docker run --rm \
        -v "$fixture:/data" \
        -v "$repo/data:/inara:ro" \
        -v "$repo/resources:/resources:ro" \
        -v "$here/refs.template:/refs.template:ro" \
        "$image" \
        --data-dir=/inara \
        --defaults=shared \
        --wrap=none \
        --template=/refs.template \
        --resource-path=.:/resources \
        --csl=/resources/apa.csl \
        --to=latex \
        paper.md 2>/dev/null) || {
        printf 'FAIL %s (refs: pandoc exited non-zero)\n' "$name"
        failures=$((failures + 1))
        continue
    }
    if printf '%s\n' "$refs" | diff -u "$fixture/expected-refs.txt" - >/dev/null; then
        printf 'ok   %s (refs)\n' "$name"
    else
        printf 'FAIL %s (refs)\n' "$name"
        printf '%s\n' "$refs" | diff -u "$fixture/expected-refs.txt" - || true
        failures=$((failures + 1))
    fi
done

if [ "$failures" -gt 0 ]; then
    printf '\n%s fixture(s) failed\n' "$failures"
    exit 1
fi
printf '\nall fixtures passed\n'
