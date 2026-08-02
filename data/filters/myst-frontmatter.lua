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

  if #filled > 0 then
    io.stderr:write(
      '[INFO] myst-frontmatter: filled from myst.yml: '
      .. table.concat(filled, ', ') .. '\n'
    )
  end
  return meta
end
