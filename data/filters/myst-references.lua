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

local function ref_command (label)
  local command = kinds[label] == 'equation' and '\\eqref' or '\\ref'
  return pandoc.RawInline('latex', command .. '{' .. label .. '}')
end

--- Body for a reference whose link text was left empty.
local function implicit_content (label)
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
local function substitute_placeholder (inlines, label)
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
      result:insert(ref_command(label))
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
  if not kinds[label] then
    -- Keep going anyway: an unresolved `\ref` renders as "??", which is a far
    -- better signal to the author than silently dropping the reference.
    io.stderr:write(
      '[WARNING] myst-references: no LaTeX label found for reference "#'
      .. label .. '"\n'
    )
  end
  if #link.content == 0 then
    return implicit_content(label)
  end
  return substitute_placeholder(link.content, label)
end

return {
  {
    Pandoc = function (doc)
      collect(doc.blocks)
      return doc:walk{Link = resolve_link}
    end
  }
}
