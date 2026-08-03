# Syncing with `openjournals/inara`

An assessment of which upstream changes this fork can adopt, what they cost, and what breaks
elsewhere in the NeuroLibre pipeline if adopted carelessly.

Measured 2026-08-03 against:

| | commit |
|---|---|
| upstream head | `88ee5d6` — *Update changelog for Inara v1.3.1* (released 2026-06-10) |
| our `main` | `ba53543` — *Merge pull request #1 from neurolibre/myst-cross-references* |
| merge base | `6df0601` — *Ensure that a usage note is printed if unknown options are used* |

162 commits ahead, 113 behind. Upstream has gone `v1.0.0 → v1.3.1`; we forked around `v1.0.0`.

Reproduce the analysis without touching your remotes:

```sh
git fetch https://github.com/openjournals/inara.git main
U=$(git rev-parse FETCH_HEAD); B=$(git merge-base origin/main $U)
git diff --numstat $B $U          # what upstream changed
git diff --name-only $B origin/main   # what we changed
```

## How entangled are we, really?

Less than the commit counts suggest. Upstream touched ~50 files since the fork point; we touched
23; **only 11 overlap**.

A dry-run merge (`git merge --no-commit --no-ff $U` in a throwaway worktree) gives the real
number: **8 conflicted files, 11 conflict hunks, 56 files merged cleanly.**

| Conflicted file | Hunks | Resolution |
|---|---|---|
| `.gitignore` | 1 | Keep both. Pure additions on each side. |
| `data/defaults/crossref.yaml` | 1 | Keep both. We inserted `conditional-archives.lua` where they inserted `prepare-affiliations.lua`. |
| `data/custom/cff.lua` | 1 | Keep ours (`type: preprint`, neurolibre URL). Optionally adopt their `journal.url` parameterisation and `volume`. |
| `data/filters/draft.lua` | 1 | Keep our DOI placeholders; take their single change, `os.date('*t', epoch)`. Needed for `SOURCE_DATE_EPOCH`. |
| `.github/workflows/build.yaml` | 2 | Keep ours (staging-PR image tags), cherry-pick their improvements. |
| `.github/workflows/example-doc.yml` | 2 | Take theirs wholesale — JOSS example documentation. |
| `example/paper.md` | 1 | Take either; it is only the sample paper. |
| `Dockerfile` | 2 | **The only real decision.** Pandoc `3.2.0 → 3.6.4` and a trimmed `tlmgr` list. See Tier 3. |

Seven of eight are mechanical. The difficulty is not the merge — it is validating the pandoc jump
afterwards.

Note `data/defaults/shared.yaml` merged *cleanly* only because `myst-frontmatter.lua` is
registered on the `myst-yml-metadata-fallback` branch, not on `main`. Merge upstream into `main`
first, then rebase that branch, and expect one trivial conflict there.

Nothing genuinely NeuroLibre-specific conflicts at all. Upstream never touches
`data/templates/neurolibre*`, `data/filters/myst-*.lua`, `neurolibre-handle-crowd.lua`,
`self-citation.lua`, `conditional-archives.lua`, `data/defaults/neurolibre.yaml`, or
`resources/neurolibre/`.

## Upstream's changelog, mapped to our interests

| Version | Change | Relevance |
|---|---|---|
| v1.1.0 | ROR identifier support (`prepare-affiliations.lua`) | Tier 2 — our CrossRef carries no affiliations at all |
| v1.1.1 | Ignore failures around affiliations | comes with the above |
| v1.1.2 | Golden tests switched from PDF to `.tex`; test folders refactored | **Tier 1 — the biggest win** |
| v1.1.3 | CrossRef: affiliations element moved *before* ORCID | required if we adopt Tier 2 |
| v1.1.4 | HTML-escape institution names in CrossRef; copyright year from publication year | required if we adopt Tier 2 |
| v1.2.0 | `tlmgr` pinned to 2024 packages (contributed by Agah); raw LaTeX in sidebar via metadata; pandoc 3.2.1 | we already have the `tlmgr` pin |
| v1.3.0 | pandoc 3.6.4; LaTeX templates refactored onto pandoc partials | Tier 3 |
| v1.3.1 | RSECon26 configuration | skip |

## Tier 1 — adopt first: high value, low risk

### 1. The golden-file test suite

`test/` plus the `test`, `test-golden-draft`, `test-golden-pub` and `test-{draft,pub}-%` targets in
the `Makefile`. Upstream generates crossref / jats / tex and `diff`s each against a committed
expected file.

This closes the gap this fork's own review flagged: **nothing in CI runs any test.** It is also the
class of test that would have caught the citeproc/bibliography filter-ordering bug found by human
review during the `myst.yml` work, and it is the safety net that makes Tier 3 tractable.

Adaptation needed:

- Our formats are `neurolibre`, `crossref`, `jats` — not upstream's `pdf`/`preprint`.
- Upstream tests `.tex`, not `.pdf`, deliberately: PDFs are not byte-reproducible. That is what
  their new `data/defaults/tex.yaml` appears to exist for. Our `neurolibre.yaml` emits a PDF via
  `latexmk`, so testing our template the same way means adding a defaults variant that writes
  `.tex` with `data/templates/neurolibrenew.tex`.
- Add a fixture with no `paper.md` front matter, so the `myst.yml` fallback is covered here too
  and not only by `test/myst-frontmatter/run.sh`.

### 2. `scripts/entrypoint.sh` — take wholesale

We have never diverged on this file, so it merges cleanly. Gains:

- A real robustness fix: today `-vv` runs `cat "${article_info_file}"` unguarded and errors when
  no `-m` was passed. Upstream guards it with `[ -n … ] && [ -f … ]`.
- A `-r` retraction-notice flag. Harmless to us.

### 3. `data/filters/time.lua`

Adds `SOURCE_DATE_EPOCH` support — **the prerequisite for item 1**, since golden files cannot
match while timestamps float. Also sets `meta.copyright.year` from `published_parts.year`.

Related, but currently inert for us: `resources/neurolibre/defaults.yaml` hardcodes
`copyright.year: 2022`. Neither `neurolibre.crossref` nor `neurolibrenew.tex` reads
`copyright.year` today, so this is latent rather than a live bug — worth fixing while in the area.

Taking this filter also requires the one-line `draft.lua` conflict resolution above, since
`draft.lua` calls `os.date('*t')` and upstream's version threads `epoch` through.

### 4. `data/filters/fix-bibentry-spacing.lua` and `data/custom/jats.lua`

Both new files, purely additive, and we have known JATS pain. But see the ripple warning below
before touching anything JATS-related.

## Tier 2 — worth real porting effort

### 5. Affiliations in the CrossRef deposit, with ROR

**Our CrossRef deposits currently carry no affiliation metadata whatsoever.** Verified: a generated
`paper.crossref` contains no `<institution_name>` elements.

Upstream's `prepare-affiliations.lua` builds an `afxml` value, and `default.crossref` emits it
immediately before `<ORCID>`:

```
$if(it.afxml)$
            $it.afxml$
$endif$
$if(it.orcid)$
            <ORCID>https://orcid.org/${it.orcid}</ORCID>
$endif$
```

The placement is the v1.1.3 fix — the CrossRef schema mandates affiliations before ORCID. Adopting
this means porting both the filter and the template lines into `data/templates/neurolibre.crossref`,
which has neither element.

Take v1.1.4's HTML-escaping of institution names at the same time: an `&` in an institution name
would otherwise produce invalid deposit XML, and `recommend-acceptance.yml` validates CrossRef with
`validation_mode: strict`.

Synergy worth noting: MyST `myst.yml` affiliations support `ror:` natively, and
`data/filters/myst-frontmatter.lua` currently ignores it. Adopting this upstream work plus one
mapping addition would give NeuroLibre DOIs institutional identifiers straight from `myst.yml`.

## Tier 3 — sequence last

### 6. Pandoc 3.2.0 → 3.6.4, trimmed `tlmgr` list, LaTeX partials

This is where the risk concentrates. `myst-admonitions.lua` depends on
`pandoc.utils.stringify` behaviour and on block-shape quirks of the reader; all three `myst-*.lua`
filters use `pandoc.utils.type`, `Figure`, and `walk`. Four minor pandoc releases is ample room for
AST changes.

Upstream also trimmed the package list (`booktabs`, `caption`, `etoolbox`, `fancyvrb`, `float`,
`fontspec`, `listings`, `logreq`, `mathspec`, `pgf` removed; `hyperxmp` added) on the assumption
that the newer base image supplies them. Our `neurolibrenew.tex` is not upstream's template and may
still need some of them.

**Do Tier 1 item 1 first.** Bumping pandoc without golden tests means discovering regressions in
production PDFs; with them, one `make test` answers the question. That sequencing is the main
recommendation of this document.

The LaTeX-partials refactor applies to `default.latex` and `preprint.latex`, which we do not use.
Not applicable directly, though it would make future upstream template fixes easier to track if we
ever rebase `neurolibrenew.tex` onto their partials.

## Skip

`data/templates/{default.latex,preprint.latex,default.crossref}` (we use our own),
`resources/{resciencec,jose,joss}/*`, RSECon26 and ReScience configuration, `CHANGELOG.md`,
`docs/names.md` (optional), `example/paper.md`.

## Ripple effects on the rest of the pipeline

### One upstream change definitely breaks the pipeline — do not take it blind

Upstream moved the JATS output:

```diff
-to: jats_publishing+element_citations
-output-file: paper.jats
-extract-media: media
+to: jats.lua
+output-file: jats/paper.jats
```

`neurolibre/paper-action`'s `check_result.rb` hardcodes the old location:

```ruby
paper_jats_path = File.dirname(paper_md_path)+"/paper.jats"
if File.exist?(paper_jats_path)
  …
else
  raise "   !! ERROR: Failed to generate JATS file" if formats.include?("jats")
end
```

`get_paper.rb` always includes `jats` in `inara_args`, and `check_result.rb` is invoked with
`neurolibre,crossref,jats`. So adopting upstream's `data/defaults/jats.yaml` puts the file at
`jats/paper.jats`, the existence check fails, and the **"Compile Paper" step raises** — breaking
both `@editorialbot generate pdf` and `recommend-accept`.

Either keep our `output-file: paper.jats`, or change `check_result.rb` in `paper-action` in the same
change. This is the one hard coupling found.

### Everything else needs no change

| System | Impact |
|---|---|
| `roboneuro-neo` | None. `config/settings-production.yml` dispatches workflows by name; no inara coupling. |
| `full-stack-server` | None. It runs `neurolibre/inara:latest -o neurolibre ./paper.md` and reads `paper.pdf`; `neurolibre.yaml` is ours and upstream does not touch it. |
| `neurolibre/preprints` workflows | None, unless the JATS upload is re-enabled — it is currently commented out in `recommend-acceptance.yml`. |
| `neurolibre/summary-pdf-action` | None. It pins `docker://neurolibre/inara:latest` and passes args through. |
| neurolibre.org app | **Needs a check before Tier 2.** The only deposit *content* change would be added CrossRef affiliation elements. That is schema-valid — upstream validates strictly too — but nobody has confirmed how the site's ingest parses CrossRef. Verify before enabling. |

### A related finding worth acting on independently

`check_result.rb` scrapes `paper.crossref.log` and `paper.jats.log` for pandoc `WARNING` entries and
**auto-posts them to the review issue**. Our filters write warnings with `io.stderr:write`, which
does not land in pandoc's JSON log, so an author with a typo'd cross-reference, an unresolvable
label, or an ORCID that fails checksum validation never sees the warning. Emitting these through
pandoc's logging API instead would surface them in the review thread automatically — more valuable
now that `myst.yml` is a supported metadata source.

## Suggested order of work

1. Merge upstream into `main`, resolving the 8 conflicts as tabled above, but **keep our
   `data/defaults/jats.yaml`**.
2. Adopt Tier 1: `entrypoint.sh`, `time.lua` (+ the `draft.lua` line), then port the golden-file
   tests to our formats and add a no-front-matter fixture. Wire them into CI.
3. Rebase `myst-yml-metadata-fallback` and confirm both suites still pass.
4. Tier 2, with the neurolibre.org ingest check first.
5. Tier 3 last, gated on the golden tests existing.

## Open questions

- Upstream removed `substitute-in-format.lua` from `data/defaults/shared.yaml`. Confirm nothing of
  ours relies on it before taking their version.
- Does `Submission#article_metadata` in the `neurolibre` gem reach `Paper#languages` →
  `detect_languages`? That determines whether the cheap fix in `TODO_MYST_PUBLISH.md` option 1 is
  viable. Unverified.
- Our `cff` output has never been exercised with the `myst.yml` fallback, and `cff` is only
  generated on acceptance (`-o …,cff -p`).
