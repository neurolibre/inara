--- Resolve MyST-style cross references for LaTeX output.
--
-- MyST writes cross references as ordinary markdown links to a target
-- identifier, letting the renderer fill in the visible text:
--
--     see [](#fig-circuit)              -> "see Figure 1"
--     see [Sec. %s](#clustering)        -> "see Sec. 3.2"
--     see [](#clustering)               -> "see Clustering"
--
-- Pandoc has no notion of this, so it emits `\hyperref[fig-circuit]{}` (an
-- invisible link) and prints `%s` verbatim. The `\label{}` anchors themselves
-- already make it into the LaTeX -- headings get one from pandoc, figures from
-- the myst-admonitions filter -- so all that is missing is to give each
-- reference a body built from `\ref{}`.
--
-- This filter must run *after* myst-admonitions.lua: it discovers figure and
-- table labels by inspecting the raw LaTeX that filter emits, which guarantees
-- that every `\ref{}` written here has a matching `\label{}` in the output.

if not FORMAT:match 'latex' then
  return {}
end

-- Label kind -> text placed in front of the number, following MyST's defaults.
local kind_prefix = {
  figure = 'Figure',
  table = 'Table',
  section = 'Section',
  equation = nil, -- `\eqref` already supplies the parentheses
}

-- LaTeX environments and counters that tell us what a `\label{}` refers to.
local kind_of_env = {
  figure = 'figure',
  ['figure*'] = 'figure',
  subfigure = 'figure',
  wrapfigure = 'figure',
  table = 'table',
  ['table*'] = 'table',
  longtable = 'table',
  tabular = 'table',
  equation = 'equation',
  ['equation*'] = 'equation',
  align = 'equation',
  ['align*'] = 'equation',
  gather = 'equation',
  multline = 'equation',
}

local kinds = {}         -- identifier -> 'figure' | 'table' | 'section' | 'equation'
local section_text = {}  -- identifier -> inlines of the heading, for bare section refs

--- Classify every `\label{}` in a chunk of raw LaTeX.
--
-- The kind is taken from the innermost `\begin{...}` or `\refstepcounter{...}`
-- preceding the label, which is how LaTeX itself decides what the label
-- captures.
local function collect_raw_labels (text)
  local pos = 1
  while true do
    local start, stop, label = text:find('\\label%s*{(.-)}', pos)
    if not start then
      break
    end
    local preceding = text:sub(1, start - 1)
    local kind
    -- Search backwards for whichever marker comes last.
    local best = 0
    for at, env in preceding:gmatch '()\\begin%s*{([%w%*]+)}' do
      if kind_of_env[env] and at > best then
        best, kind = at, kind_of_env[env]
      end
    end
    for at, counter in preceding:gmatch '()\\refstepcounter%s*{([%w]+)}' do
      if kind_of_env[counter] and at > best then
        best, kind = at, kind_of_env[counter]
      end
    end
    -- A figure nested inside an admonition cannot be a float, so it is set as
    -- `\captionof{figure}` instead. That steps the same counter, and its label
    -- must be classified the same way.
    for at, counter in preceding:gmatch '()\\captionof%s*{([%w%*]+)}' do
      if kind_of_env[counter] and at > best then
        best, kind = at, kind_of_env[counter]
      end
    end
    if kind and label ~= '' then
      kinds[label] = kind
    end
    pos = stop + 1
  end
end

--- Build the label registry from the whole document.
local function collect (blocks)
  pandoc.walk_block(pandoc.Div(blocks), {
    traverse = 'topdown',
    RawBlock = function (raw)
      if raw.format:match 'tex' then
        collect_raw_labels(raw.text)
      end
    end,
    RawInline = function (raw)
      if raw.format:match 'tex' then
        collect_raw_labels(raw.text)
      end
    end,
    Header = function (header)
      if header.identifier ~= '' then
        kinds[header.identifier] = 'section'
        section_text[header.identifier] = header.content
      end
    end,
    Table = function (tbl)
      if tbl.identifier ~= '' then
        kinds[tbl.identifier] = 'table'
      end
    end,
    Figure = function (fig)
      if fig.identifier ~= '' then
        kinds[fig.identifier] = 'figure'
      end
    end,
    Math = function (math)
      local label = math.text:match '\\label%s*{(.-)}'
      if label then
        kinds[label] = 'equation'
      end
    end,
  })
end

--- Labels defined on the project's other pages: label -> {kind, number}.
--
-- A MyST project is a set of pages listed in myst.yml, and a reference may
-- point at a figure or table on another page, such as a supplementary one.
-- Only this page becomes the PDF, so those labels have no `\label{}` here and
-- `\ref{}` would print "??". MyST numbers each page's figures and tables on
-- their own, applying the page's `numbering` front matter over the project's,
-- so the number the reader sees on the web can be worked out from the source.
local other_pages = nil

local MYST_FILE = 'myst.yml'

--- Directives that MyST numbers, and the counter each one steps.
local numbered_directive = {
  figure = 'figure',
  table = 'table',
  ['list-table'] = 'table',
  ['csv-table'] = 'table',
}

--- Parse a YAML string the way pandoc reads front matter, or nil.
local function read_yaml (text)
  local ok, doc = pcall(
    pandoc.read,
    '---\n' .. text .. '\n---\n',
    'commonmark+yaml_metadata_block'
  )
  return ok and doc and doc.meta or nil
end

local function read_file (path)
  local fh = io.open(path, 'r')
  if not fh then
    return nil
  end
  local content = fh:read 'a'
  fh:close()
  return content
end

--- The markdown pages of the project's table of contents, in order.
local function toc_pages (project)
  local pages = pandoc.List{}
  local function visit (entries)
    if pandoc.utils.type(entries) ~= 'List' then
      return
    end
    for _, entry in ipairs(entries) do
      if pandoc.utils.type(entry) == 'table' then
        if entry.file then
          local file = pandoc.utils.stringify(entry.file)
          if file:match '%.md$' then
            pages:insert(pandoc.path.normalize(file))
          end
        end
        visit(entry.children)
      end
    end
  end
  visit(project.toc)
  return pages
end

--- A front matter value as a Lua value: boolean, string, or the table itself.
local function plain (value)
  if value == nil then
    return nil
  end
  local t = pandoc.utils.type(value)
  if t == 'boolean' or t == 'table' then
    return value
  end
  return pandoc.utils.stringify(value)
end

--- How one kind is numbered, given page and project `numbering` settings.
--
-- Returns the enumerator template, the start value and whether numbering
-- continues from the previous page, or nil when the kind is not numbered.
local function numbering_for (kind, page_numbering, project_numbering)
  local function setting (numbering, key)
    if pandoc.utils.type(numbering) ~= 'table' then
      return nil
    end
    return plain(numbering[key])
  end
  local function pick (key)
    local value = setting(page_numbering, key)
    if value == nil then
      value = setting(project_numbering, key)
    end
    return value
  end
  local function pick_kind (key)
    for _, numbering in ipairs{page_numbering, project_numbering} do
      local kind_setting = setting(numbering, kind)
      if kind_setting == false then
        return false
      end
      local value = setting(kind_setting, key)
      if value ~= nil then
        return value
      end
    end
    return nil
  end

  if plain(page_numbering) == false
    or (page_numbering == nil and plain(project_numbering) == false)
    or pick_kind 'enabled' == false
  then
    return nil
  end
  local enumerator = pick_kind 'enumerator' or pick 'enumerator' or '%s'
  local start = tonumber(pick_kind 'start')
  local continues = pick_kind 'continue' == true or pick_kind 'continue' == 'true'
  return enumerator, start, continues
end

--- Figures and tables of one page, in order: a list of {kind, label}.
--
-- Read line by line rather than through pandoc, which does not understand
-- directives: an opening fence names the directive, and the `:label:` option,
-- if any, follows on the lines right after it. Ordinary code blocks are
-- skipped, so an example directive shown as code is not counted.
local function numbered_items (text)
  local items = pandoc.List{}
  local code_fence = nil
  local directive_fences = pandoc.List{} -- open ```{name} directives
  local current = nil
  for line in (text .. '\n'):gmatch '(.-)\r?\n' do
    local bare = line:match '^%s*([`~][`~][`~]+)%s*$'
    if code_fence then
      if bare and bare:sub(1, 1) == code_fence:sub(1, 1) and #bare >= #code_fence then
        code_fence = nil
      end
    else
      local colon_name = line:match '^%s*:::+%s*{([%w%-:]+)}'
      local tick, tick_name = line:match '^%s*([`~][`~][`~]+)%s*{([%w%-:]+)}'
      local name = colon_name or tick_name
      local last = directive_fences[#directive_fences]
      if name then
        if tick then
          directive_fences:insert(tick)
        end
        current = nil
        if numbered_directive[name] then
          current = {kind = numbered_directive[name]}
          items:insert(current)
        end
      elseif bare and last and bare:sub(1, 1) == last:sub(1, 1) and #bare >= #last then
        directive_fences:remove()
        current = nil
      elseif line:match '^%s*```' or line:match '^%s*~~~' then
        code_fence = line:match '^%s*([`~]+)'
        current = nil
      elseif current and line:match '^%s*:[%w%-_]+:' then
        current.label = current.label
          or line:match '^%s*:label:%s*(%S+)'
          or line:match '^%s*:name:%s*(%S+)'
      else
        current = nil
      end
    end
  end
  return items
end

--- Number the figures and tables on every page of the project.
local function load_other_pages ()
  local labels = {}
  local myst = read_file(MYST_FILE)
  local meta = myst and read_yaml(myst)
  local project = meta and meta.project
  if pandoc.utils.type(project) ~= 'table' then
    return labels
  end

  local counters = {}
  for _, path in ipairs(toc_pages(project)) do
    local text = read_file(path)
    if text then
      local front = text:match '^%-%-%-\r?\n(.-)\r?\n%-%-%-'
      local page_meta = front and read_yaml(front) or {}
      for _, item in ipairs(numbered_items(text)) do
        local enumerator, start, continues =
          numbering_for(item.kind, page_meta.numbering, project.numbering)
        if enumerator then
          local counter = counters[item.kind]
          if not counter or (counter.page ~= path and not continues) then
            counter = {page = path, value = (start or 1) - 1}
            counters[item.kind] = counter
          end
          counter.page = path
          counter.value = counter.value + 1
          if item.label and not labels[item.label] then
            labels[item.label] = {
              kind = item.kind,
              number = enumerator:gsub('%%s', tostring(counter.value)),
            }
          end
        end
      end
    end
  end
  return labels
end

--- The number of a figure or table on another page, or nil.
local function other_page_label (label)
  other_pages = other_pages or load_other_pages()
  return other_pages[label]
end

local function ref_command (label)
  local command = kinds[label] == 'equation' and '\\eqref' or '\\ref'
  return pandoc.RawInline('latex', command .. '{' .. label .. '}')
end

--- Body for a reference whose link text was left empty.
local function implicit_content (label, external)
  if external then
    -- Non-breaking space keeps "Table" and its number on the same line.
    return {pandoc.Str(kind_prefix[external.kind] .. '\u{00A0}' .. external.number)}
  end
  local kind = kinds[label]
  if kind == 'section' and section_text[label] then
    -- MyST shows the heading itself rather than a number.
    return {pandoc.Link(section_text[label], '#' .. label)}
  end
  local prefix = kind and kind_prefix[kind]
  if prefix then
    -- Non-breaking space keeps "Figure" and its number on the same line.
    return {pandoc.RawInline('latex', prefix .. '~'), ref_command(label)}
  end
  return {ref_command(label)}
end

--- Substitute `%s` (MyST's number placeholder) in explicit link text.
--
-- Every occurrence is replaced, including inside nested inlines such as
-- emphasis: a `%` that survives into the LaTeX would comment out the rest of
-- the line.
local function substitute_placeholder (inlines, label, external)
  local substituted = false
  local function expand (str)
    if not str.text:find('%s', 1, true) then
      return nil
    end
    substituted = true
    local result = pandoc.Inlines{}
    local rest = str.text
    while true do
      local before, after = rest:match '^(.-)%%s(.*)$'
      if not before then
        break
      end
      if before ~= '' then
        result:insert(pandoc.Str(before))
      end
      result:insert(external and pandoc.Str(external.number) or ref_command(label))
      rest = after
    end
    if rest ~= '' then
      result:insert(pandoc.Str(rest))
    end
    return result
  end
  local expanded = pandoc.walk_inline(pandoc.Span(inlines), {Str = expand})
  return substituted and expanded.content or nil
end

local function resolve_link (link)
  local label = link.target:match '^#(.+)$'
  if not label then
    return nil
  end
  local external = nil
  if not kinds[label] then
    external = other_page_label(label)
  end
  if not kinds[label] and not external then
    -- Keep going anyway: an unresolved `\ref` renders as "??", which is a far
    -- better signal to the author than silently dropping the reference.
    io.stderr:write(
      '[WARNING] myst-references: no LaTeX label found for reference "#'
      .. label .. '"\n'
    )
  end
  if #link.content == 0 then
    return implicit_content(label, external)
  end
  return substitute_placeholder(link.content, label, external)
end

return {
  {
    Pandoc = function (doc)
      collect(doc.blocks)
      return doc:walk{Link = resolve_link}
    end
  }
}
