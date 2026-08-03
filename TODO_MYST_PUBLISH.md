# TODO: let a submission publish from `myst.yml` alone

inara can now build a paper whose `paper.md` has no YAML front matter, taking the title,
authors, affiliations, tags and bibliography from the project's `myst.yml` instead
(`data/filters/myst-frontmatter.lua`). The publishing pipeline cannot yet reach that
capability, because the step that runs *before* inara still requires the front matter.

This document records the gap so whoever closes it does not have to re-derive it.

## What already works

Driving inara directly against a real submission with no front matter produces every artifact
the acceptance flow needs:

```sh
docker run --rm -v "$PWD:/data" neurolibre/inara:latest \
  -m /usr/local/share/openjournals/default-article-info.yaml \
  -l -o neurolibre,crossref,jats ./paper.md
```

Verified against `polyquantique/Neurolibre-Photon-Number-Classification` with its front matter
deleted:

- `paper.pdf` — page 1 identical to the front-matter build: title, all six authors,
  affiliation superscripts, accented names, ORCID icons when `myst.yml` declares them.
- `paper.crossref` — **byte-identical** to the front-matter build apart from `doi_batch_id`
  and `timestamp`. Since the front-matter output already passes
  `validate-xml-files-action` in `strict` mode, so does this one.
- `paper.jats` — differs only in affiliation punctuation (see "Smaller follow-ups") and a
  missing `<pub-date>`.

The filter is registered in `data/defaults/shared.yaml`, not in a per-format defaults file, so
`neurolibre`, `crossref`, `jats` and `cff` all inherit it from one registration.

`cff` output has not been exercised with the fallback.

## The gap

```
@editorialbot generate pdf | recommend-accept
  └─ neurolibre/preprints  .github/workflows/{draft-paper,recommend-acceptance}.yml
      └─ neurolibre/paper-action@main
          ├─ get_paper.rb          <-- BLOCKED HERE, before inara runs
          └─ neurolibre/summary-pdf-action@main
              └─ docker://neurolibre/inara:latest
```

`get_paper.rb` builds the `-m paper-metadata.yaml` file that inara consumes, using the
`neurolibre` gem (`Theoj` namespace, https://github.com/neurolibre/neurolibre-gem, pinned at
1.5.4 in `paper-action`'s `Gemfile.lock`).

`Theoj::Paper#load_metadata` reads the paper with `YAML.load_file(paper_path)`, relying on YAML
parsing stopping at the front matter's closing `---`. With no front matter that returns a
`String` rather than a `Hash`, and `Theoj::Paper#parse_authors` then raises:

```
t1/fm/paper.md     -> Hash    title="Accurate Unsupervised Photon C"  authors=Array
t1/nofm/paper.md   -> String  value="We compare methods for signal classifica"
                      parse_authors: NoMethodError: undefined method `each' for nil
```

So the "Compile Paper" step fails before inara is invoked, for both the draft and the
acceptance workflows.

Swapping the YAML source is not sufficient on its own. `Theoj::Paper#parse_authors` also does

```ruby
affiliation_index = author['affiliation']
failure "Author (#{author['name']}) is missing affiliation" if affiliation_index.nil?
parsed_author = Author.new(author['name'], author['orcid'], affiliation_index, affiliations_metadata)
```

which wants JOSS-style *index* affiliations (`affiliation: "1,2"`). `myst.yml` names
affiliations by id (`affiliations: polytechnique`) and splits addresses into parts. A Ruby-side
translation is therefore required, equivalent to the one in
`data/filters/myst-frontmatter.lua` and in `full-stack-server`'s `api/myst_frontmatter.py`.

The canonical mapping both existing implementations follow:

| target | source under `project:` |
|---|---|
| `title` | `title` |
| `date` | `date` |
| `tags` | `keywords` |
| `bibliography` | `bibliography` |
| `authors[].name` / `.email` / `.orcid` / `.corresponding` | same keys |
| `authors[].equal-contrib` | `equal_contributor` |
| `authors[].affiliation` | `affiliations`, resolved to a comma-joined index string |
| `affiliations[].index` | position in `project.affiliations`, 1-based |
| `affiliations[].name` | `department`, `institution` (alias `name`), `address`, `city`, `region` (alias `state`), `postal_code`, `country`, joined with `", "`, empties skipped |

Rules worth carrying over, each of which caused a real bug during implementation:

- An author's `affiliations` may be a list, a single id, or several ids in one `;`-separated
  string. Declared order is preserved.
- A token matching no declared id is an ad-hoc affiliation: append it under its own index with
  that literal name rather than dropping the author's affiliation.
- A non-mapping entry in `authors` or `affiliations` is legal MyST (a bare string) and becomes
  an entry named by that string, still consuming its index position.
- A front-matter key that is present but empty (`authors:` with no value) must count as absent,
  or the fallback never fires and the paper publishes with a blank byline.
- `authors` and `affiliations` fill as a **pair**. An index only means something relative to the
  list that defines it, so taking authors from one source and affiliations from the other
  silently credits the wrong institutions.

## Options for closing it

1. **`get_paper.rb` in `paper-action`.** Clone the repository, and when `paper.md` has no front
   matter, synthesize one from `myst.yml` before passing the local path to
   `Theoj::Paper.new(url, branch, path)` — that constructor skips its own clone when given a
   path. No gem release needed. Unverified caveat: `Submission#article_metadata` may reach
   `Paper#languages` → `detect_languages`, which expects the gem's own clone to exist; check
   that before committing to this route.
2. **The `neurolibre` gem.** Put the fallback in `Theoj::Paper` itself, which is the natural
   home. Costs a gem release plus a `Gemfile.lock` bump in `paper-action`.
3. **Invert the order.** Have inara emit its resolved metadata as an output format and let the
   Ruby side consume that instead of re-parsing `paper.md`. Larger change, but the only option
   that does not create a *third* copy of the mapping.

Option 1 unblocks fastest; option 3 is the better end state. The duplication is already the
weakest part of this design — a review found the Lua and Python copies silently disagreeing on
two legal MyST inputs (bare-string authors, and string entries in `affiliations`), and nothing
in CI compares them.

## Smaller follow-ups

- **`summary-pdf-action` pins `docker://neurolibre/inara:latest`** and a composite action cannot
  take the image from an input, so a PR's `staging-pr-<n>` image is never exercised by the bot
  workflows. Testing a change end to end means driving inara directly, or temporarily pointing
  that action elsewhere.
- **JATS is still generated**, even though `recommend-acceptance.yml` has its upload and
  validation commented out. `scripts/entrypoint.sh` runs each format with `|| exit 1`, so a JATS
  failure still fails the whole compile. It succeeds today with the fallback.
- **`date` has no `myst.yml` equivalent in most submissions.** The filter maps `project.date`
  when present; without it JATS loses `<pub-date>`. Crossref and the PDF are unaffected because
  their dates come from the `-m` article-info file.
- **Affiliation strings will not match a hand-written front matter exactly.** `myst.yml` holds
  structured parts, so `Montréal, QC` becomes `Montreal, Quebec` if that is what the parts say.
  Submissions should expect to correct their `myst.yml` values, not inara.
- **An ORCID that fails checksum validation is dropped silently** by
  `data/filters/normalize/authors.lua` — no icon, no `<ORCID>` element, no warning. A
  `myst.yml`-only workflow gives authors one less place to notice. Worth a warning.
- **`data/filters/myst-references.lua` logs a false positive** on citeproc-generated citation
  links (`#ref-<key>`) because it warns before checking whether it will substitute anything.
  Log noise only; no output effect.
- **Neither test suite runs in CI** — inara's `test/myst-frontmatter/run.sh` nor
  full-stack-server's pytest suite.
