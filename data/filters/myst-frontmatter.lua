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

local stringify = pandoc.utils.stringify
local ptype = pandoc.utils.type

local MYST_FILE = 'myst.yml'

--- Coerce a myst.yml value to Inlines.
--
-- Values parsed out of myst.yml are already Inlines. They must stay that way:
-- normalize/authors.lua calls `metainlines:walk{...}` on author.name, so a
-- plain Lua string passes its type check and then crashes.
local function to_inlines (value)
  if value == nil then
    return nil
  elseif ptype(value) == 'Inlines' then
    return value
  else
    return pandoc.Inlines{pandoc.Str(tostring(value))}
  end
end

--- Read the `project` table out of ./myst.yml, or nil.
--
-- NeuroLibre guarantees myst.yml at the repository root beside paper.md, and
-- inara's entrypoint has already cd-ed there, so this looks in the working
-- directory and nowhere else.
local function read_project ()
  local fh = io.open(MYST_FILE, 'r')
  if not fh then
    return nil
  end
  local content = fh:read 'a'
  fh:close()
  if not content then
    return nil
  end
  -- Reuse the trick from normalize-metadata.lua: wrap the YAML in a metadata
  -- block and let pandoc's reader parse it. No new dependency.
  local ok, doc = pcall(
    pandoc.read,
    '---\n' .. content .. '\n---\n',
    'commonmark+yaml_metadata_block'
  )
  if not ok or not doc or not doc.meta then
    return nil
  end
  local project = doc.meta.project
  return ptype(project) == 'table' and project or nil
end

-- Parts of a myst.yml affiliation, joined into the single name string that
-- inara's templates and the Zenodo task expect. Department precedes
-- institution to match the convention in existing NeuroLibre front matter.
local NAME_PARTS = {
  'department',
  'institution',
  'address',
  'city',
  'region',
  'postal_code',
  'country',
}

--- Read one affiliation part, honouring MyST's aliases.
--
-- Written as statements rather than an `or` chain: `a[k] or (k == 'institution'
-- and a.name)` yields `false`, not nil, for every other key.
local function part (aff, key)
  local value = aff[key]
  if value == nil and key == 'institution' then
    value = aff.name
  end
  if value == nil and key == 'region' then
    value = aff.state
  end
  return value
end

--- Join an affiliation's parts into one Inlines value.
local function affiliation_name (aff)
  local name = pandoc.Inlines{}
  for _, key in ipairs(NAME_PARTS) do
    local value = part(aff, key)
    if value ~= nil and stringify(value) ~= '' then
      if #name > 0 then
        name:insert(pandoc.Str(','))
        name:insert(pandoc.Space())
      end
      name:extend(to_inlines(value))
    end
  end
  return name
end

--- Build the indexed affiliation list and an id -> index map.
local function build_affiliations (project)
  local affiliations = pandoc.List{}
  local index_of = {}
  for i, aff in ipairs(project.affiliations or {}) do
    local index = tostring(i)
    affiliations:insert{index = index, name = affiliation_name(aff)}
    if aff.id ~= nil then
      index_of[stringify(aff.id)] = index
    end
  end
  return affiliations, index_of
end

--- Normalise an author's `affiliations` value to a list of trimmed tokens.
--
-- MyST accepts a list, a single id, or several ids in one `;`-separated string.
local function affiliation_tokens (value)
  local tokens = pandoc.List{}
  if value == nil then
    return tokens
  end
  if ptype(value) == 'List' then
    for _, entry in ipairs(value) do
      tokens:insert(stringify(entry))
    end
  else
    for token in stringify(value):gmatch '[^;]+' do
      tokens:insert((token:gsub('^%s*(.-)%s*$', '%1')))
    end
  end
  return tokens
end

--- Build the author list, resolving affiliation ids to indices.
--
-- Appends to `affiliations` and `index_of` for any token that matches no
-- declared id: MyST permits ad-hoc affiliations, and dropping the author's
-- affiliation would be worse than inventing an entry for it.
local function build_authors (project, affiliations, index_of)
  local authors = pandoc.List{}
  for _, source in ipairs(project.authors or {}) do
    local author = {name = to_inlines(source.name)}
    author.email = source.email
    author.orcid = source.orcid
    author.corresponding = source.corresponding
    author['equal-contrib'] = source.equal_contributor

    local indices = pandoc.List{}
    local tokens = affiliation_tokens(source.affiliations or source.affiliation)
    for _, token in ipairs(tokens) do
      local index = index_of[token]
      if not index then
        index = tostring(#affiliations + 1)
        affiliations:insert{
          index = index,
          name = to_inlines(token),
        }
        index_of[token] = index
      end
      indices:insert(index)
    end
    if #indices > 0 then
      author.affiliation = pandoc.Inlines{
        pandoc.Str(table.concat(indices, ','))
      }
    end

    authors:insert(author)
  end
  return authors
end

function Meta (meta)
  local project = read_project()
  if not project then
    return nil
  end

  local filled = pandoc.List{}
  local function fill (key, value)
    if meta[key] == nil and value ~= nil then
      meta[key] = value
      filled:insert(key)
    end
  end

  fill('title', project.title)
  fill('date', project.date)
  fill('tags', project.keywords)
  fill('bibliography', project.bibliography)

  -- Authors and affiliations are filled as a pair. An affiliation index only
  -- means something relative to the list that defines it, so mixing front
  -- matter authors with myst.yml affiliations would silently attach authors to
  -- the wrong institutions.
  if meta.authors == nil or meta.affiliations == nil then
    local affiliations, index_of = build_affiliations(project)
    local authors = build_authors(project, affiliations, index_of)
    if #authors > 0 then
      meta.authors = authors
      meta.affiliations = affiliations
      filled:insert('authors')
      filled:insert('affiliations')
    end
  end

  if #filled > 0 then
    io.stderr:write(
      '[INFO] myst-frontmatter: filled from myst.yml: '
      .. table.concat(filled, ', ') .. '\n'
    )
  end
  return meta
end
