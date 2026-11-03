#!/bin/sh
# Run myst-admonitions.lua over each fixture and compare the resulting LaTeX
# against the fixture's expected.tex.
#
# myst-references.lua runs too, so these tests also cover that a label defined
# by an admonition can be referenced from elsewhere in the document -- the two
# filters are ordered against each other precisely for that.
#
# citeproc runs between the two, as it does in the real PDF run, because
# myst-references.lua sees the links citeproc makes to bibliography entries.
#
# The default image extension matches data/defaults/shared.yaml, since it
# changes what an embed like `![](#cell)` looks like by the time a filter sees it.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
image=${INARA_TEST_IMAGE:-pandoc/core:3.2.0-alpine}
failures=0

for fixture in "$here"/fixtures/*/; do
    name=$(basename "$fixture")
    stderr_file=$(mktemp)
    actual=$(docker run --rm \
        -v "$fixture:/data" \
        -v "$repo/data:/inara:ro" \
        "$image" \
        --data-dir=/inara \
        --wrap=none \
        --default-image-extension=.png \
        --lua-filter=/inara/filters/myst-admonitions.lua \
        --citeproc \
        --lua-filter=/inara/filters/myst-references.lua \
        --to=latex \
        paper.md 2>"$stderr_file") || {
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

    # A fixture with an expected.stderr also checks the filters' warnings.
    # Docker's own notice about emulating another platform is not ours.
    if [ -f "$fixture/expected.stderr" ]; then
        warnings=$(grep -v '^WARNING: The requested image' "$stderr_file" || true)
        if printf '%s\n' "$warnings" | diff -u "$fixture/expected.stderr" - >/dev/null; then
            printf 'ok   %s [warnings]\n' "$name"
        else
            printf 'FAIL %s [warnings]\n' "$name"
            printf '%s\n' "$warnings" | diff -u "$fixture/expected.stderr" - || true
            failures=$((failures + 1))
        fi
    fi
    rm -f "$stderr_file"

    # The JATS run uses this filter too (data/defaults/jats.yaml), where it
    # must build plain pandoc elements rather than raw LaTeX. A fixture with an
    # expected.jats is checked against that output as well. myst-references.lua
    # is LaTeX-only and is not part of the JATS run.
    [ -f "$fixture/expected.jats" ] || continue
    actual=$(docker run --rm \
        -v "$fixture:/data" \
        -v "$repo/data:/inara:ro" \
        "$image" \
        --data-dir=/inara \
        --wrap=none \
        --default-image-extension=.png \
        --lua-filter=/inara/filters/myst-admonitions.lua \
        --to=jats_publishing \
        paper.md 2>/dev/null) || {
        printf 'FAIL %s [jats] (pandoc exited non-zero)\n' "$name"
        failures=$((failures + 1))
        continue
    }
    if printf '%s\n' "$actual" | diff -u "$fixture/expected.jats" - >/dev/null; then
        printf 'ok   %s [jats]\n' "$name"
    else
        printf 'FAIL %s [jats]\n' "$name"
        printf '%s\n' "$actual" | diff -u "$fixture/expected.jats" - || true
        failures=$((failures + 1))
    fi
done

if [ "$failures" -gt 0 ]; then
    printf '\n%s fixture(s) failed\n' "$failures"
    exit 1
fi
printf '\nall fixtures passed\n'
