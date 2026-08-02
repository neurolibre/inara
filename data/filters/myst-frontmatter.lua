--- Fill gaps in the paper.md front matter from the project's myst.yml.
--
-- A NeuroLibre submission declares its title, authors, and affiliations in
-- myst.yml for the living preprint, and the publishing pipeline needs the same
-- information from the paper.md front matter. This filter lets the front matter
-- omit anything myst.yml already says.
--
-- It must run before normalize-metadata.lua: normalize/authors.lua iterates
-- meta.authors unconditionally, so a paper.md without an authors key errors the
-- build rather than merely losing its byline.
--
-- The fallback is best-effort by design. A missing, unreadable, or malformed
-- myst.yml leaves the metadata exactly as it was; it must never be the reason a
-- build fails.

function Meta (meta)
  return meta
end
