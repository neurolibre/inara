--- Typeset MyST document parts: the abstract above the body, the rest in it.
--
-- MyST lets a paper mark parts of itself -- an abstract, a data availability
-- statement, acknowledgments -- in three ways, none of which pandoc knows:
--
--     +++ { "part": "data_availability" }
--     ...
--     +++
--
--     # Abstract
--     ...
--
--     ---
--     acknowledgments: ...
--     ---
--
-- The first is a MyST block break carrying metadata. A break divides the page
-- into blocks, so a part runs from its `+++` line to the next one, or to the
-- end of the page. Pandoc typesets the `+++` lines and the JSON verbatim. The
-- second reads as an ordinary section. The third is front matter that no
-- template prints, so the part is lost.
--
-- The abstract becomes `meta.abstract`, which the templates already place above
-- the body, set apart, and which the JATS writer turns into `<abstract>`.
-- neurolibrenew.tex styles the `abstract` environment as a box.
--
-- Every other part is typeset as an ordinary section, headed with the part's
-- name, at the top heading level the paper uses. A part in the body stays where
-- it was written. A part from the front matter has no place in the body, so it
-- goes where articles put it: summary, key points, dedication and epigraph
-- first, everything else just before the bibliography. A part declared in the
-- front matter wins over one of the same name in the body.
--
-- Runs after the other block filters, myst-admonitions.lua above all: an
-- abstract moved into metadata is out of their reach, so one holding an
-- admonition would otherwise be typeset as its own source. Citations are not
-- affected by the order: citeproc resolves them in metadata as well as in the
-- body.

local stringify = pandoc.utils.stringify

--- Headings for the parts MyST defines. Any other part is headed with its name.
local part_titles = {
  summary = 'Summary',
  keypoints = 'Key points',
  dedication = 'Dedication',
  epigraph = 'Epigraph',
  data_availability = 'Data availability',
  acknowledgments = 'Acknowledgments',
}

--- Front matter keys that declare a part, in the order they are typeset, and
--- the part each names. Parts listed under `parts:` follow, sorted by name.
local frontmatter_parts = {
  leading = {
    {key = 'summary', part = 'summary'},
    {key = 'keypoints', part = 'keypoints'},
    {key = 'dedication', part = 'dedication'},
    {key = 'epigraph', part = 'epigraph'},
  },
  trailing = {
    {key = 'data_availability', part = 'data_availability'},
    {key = 'acknowledgments', part = 'acknowledgments'},
    {key = 'acknowledgements', part = 'acknowledgments'},
  },
}

--- Split a paragraph's inlines into the source lines they came from.
--
-- With no blank lines around it, a `+++` line and the text after it collapse
-- into a single paragraph, and the SoftBreaks are the only record of where its
-- lines were.
local function to_lines (inlines)
  local lines = pandoc.List{pandoc.Inlines{}}
  for _, inline in ipairs(inlines) do
    if inline.t == 'SoftBreak' or inline.t == 'LineBreak' then
      lines:insert(pandoc.Inlines{})
    else
      lines[#lines]:insert(inline)
    end
  end
  return lines
end

local function from_lines (lines)
  local inlines = pandoc.Inlines{}
  for _, line in ipairs(lines) do
    if #line > 0 then
      if #inlines > 0 then
        inlines:insert(pandoc.SoftBreak())
      end
      inlines:extend(line)
    end
  end
  return #inlines > 0 and pandoc.Para(inlines) or nil
end

--- Is this line a block break? Returns the part it names, or '' for none.
--
-- The metadata is matched loosely on purpose: pandoc's smart quotes have
-- already turned `"part"` into curly-quoted inlines by the time the line is
-- stringified, and MyST accepts the key in either quote style or none.
local function block_break (text)
  local rest = text:match '^%+%+%+(.*)$'
  if not rest then
    return nil
  end
  local unquoted = rest:gsub('[“”‘’"\']', '')
  return unquoted:match 'part%s*:%s*([%w_%-]+)' or ''
end

--- Is a metadata value absent, or present but carrying nothing?
local function is_blank (value)
  if value == nil then
    return true
  end
  local t = pandoc.utils.type(value)
  if t == 'List' or t == 'Inlines' or t == 'Blocks' then
    return #value == 0
  end
  if t == 'table' then
    return next(value) == nil
  end
  local ok, text = pcall(stringify, value)
  return ok and text:match '^%s*$' ~= nil
end

--- A front matter value as blocks.
local function as_blocks (value)
  local t = pandoc.utils.type(value)
  if t == 'Blocks' then
    return value:clone()
  end
  if t == 'Inlines' then
    return pandoc.Blocks{pandoc.Para(value:clone())}
  end
  return pandoc.read(stringify(value), 'markdown').blocks
end

--- Blocks for lines split out of a paragraph at a block break.
--
-- Pandoc needs a blank line before a heading, MyST does not, so a heading
-- written right after a `+++` line reached us as paragraph text starting with
-- `#`. Lines that read as a heading become one again.
local function blocks_from_lines (lines)
  local blocks = pandoc.List{}
  local pending = pandoc.List{}
  local function flush ()
    local para = from_lines(pending)
    if para then
      blocks:insert(para)
    end
    pending = pandoc.List{}
  end
  for _, line in ipairs(lines) do
    local first, second = line[1], line[2]
    local hashes = first and first.t == 'Str' and first.text:match '^(#+)$'
    if hashes and #hashes <= 6 and second and second.t == 'Space' then
      flush()
      local text = pandoc.Inlines{}
      for k = 3, #line do
        text:insert(line[k])
      end
      blocks:insert(pandoc.Header(#hashes, text))
    else
      pending:insert(line)
    end
  end
  flush()
  return blocks
end

--- Divide the body at its block breaks.
--
-- Returns a list of segments, each {part = name or nil, blocks = ...}. The
-- break lines themselves are dropped. A break can share a paragraph with the
-- text around it, so paragraphs are split at break lines.
local function segments (blocks)
  local result = pandoc.List{{blocks = pandoc.List{}}}
  local found = false
  for _, block in ipairs(blocks) do
    if block.t == 'Para' or block.t == 'Plain' then
      local pending = pandoc.List{}
      for _, line in ipairs(to_lines(block.content)) do
        local part = block_break(stringify(line))
        if part then
          found = true
          result[#result].blocks:extend(blocks_from_lines(pending))
          pending = pandoc.List{}
          result:insert{part = part ~= '' and part or nil, blocks = pandoc.List{}}
        else
          pending:insert(line)
        end
      end
      if #pending > 0 then
        if #pending == #to_lines(block.content) then
          result[#result].blocks:insert(block)
        else
          result[#result].blocks:extend(blocks_from_lines(pending))
        end
      end
    else
      result[#result].blocks:insert(block)
    end
  end
  return result, found
end

--- Take the abstract written as an `# Abstract` section.
--
-- The section ends at the next heading of the same level or higher, which is
-- how a reader would read it too.
local function take_section (blocks)
  for i, block in ipairs(blocks) do
    if block.t == 'Header' and stringify(block):lower():match '^%s*abstract%s*$' then
      local abstract = pandoc.List{}
      local j = i + 1
      while j <= #blocks do
        local next_block = blocks[j]
        if next_block.t == 'Header' and next_block.level <= block.level then
          break
        end
        abstract:insert(next_block)
        j = j + 1
      end

      local rest = pandoc.List{}
      for k = 1, #blocks do
        if k < i or k >= j then
          rest:insert(blocks[k])
        end
      end
      return abstract, rest
    end
  end
  return nil
end

--- The highest heading level the paper uses, so a part reads as a section.
local function top_level (blocks)
  local level = nil
  for _, block in ipairs(blocks) do
    if block.t == 'Header' and (not level or block.level < level) then
      level = block.level
    end
  end
  return level or 1
end

--- A part as a section: its blocks, under a heading unless it opens with one.
local function as_section (part, blocks, level)
  if blocks[1] and blocks[1].t == 'Header' then
    return blocks
  end
  local title = part_titles[part]
    or (part:gsub('[_%-]+', ' '):gsub('^%l', string.upper))
  local section = pandoc.List{
    pandoc.Header(level, pandoc.Inlines(title), pandoc.Attr((part:gsub('_', '-')))),
  }
  section:extend(blocks)
  return section
end

--- Where trailing parts go: before the bibliography and its heading, if any.
local function back_matter_index (blocks)
  for i, block in ipairs(blocks) do
    if block.t == 'Div' and block.identifier == 'refs' then
      local previous = blocks[i - 1]
      if previous and previous.t == 'Header' then
        return i - 1
      end
      return i
    end
  end
  return #blocks + 1
end

--- The parts declared in the front matter, as {leading = ..., trailing = ...}.
local function declared_parts (meta)
  local declared = {leading = pandoc.List{}, trailing = pandoc.List{}, names = {}}
  for _, position in ipairs{'leading', 'trailing'} do
    for _, entry in ipairs(frontmatter_parts[position]) do
      local value = meta[entry.key]
      if not is_blank(value) and not declared.names[entry.part] then
        declared.names[entry.part] = true
        declared[position]:insert{part = entry.part, blocks = as_blocks(value)}
      end
    end
  end

  if pandoc.utils.type(meta.parts) == 'table' then
    local names = {}
    for name in pairs(meta.parts) do
      table.insert(names, name)
    end
    table.sort(names)
    for _, name in ipairs(names) do
      local value = meta.parts[name]
      if name == 'abstract' then
        -- Handled with the abstract proper, not as a section.
      elseif not is_blank(value) and not declared.names[name] then
        declared.names[name] = true
        declared.trailing:insert{part = name, blocks = as_blocks(value)}
      end
    end
  end
  return declared
end

function Pandoc (doc)
  local level = top_level(doc.blocks)
  local declared = declared_parts(doc.meta)
  local declared_abstract = doc.meta.abstract
  if is_blank(declared_abstract) and pandoc.utils.type(doc.meta.parts) == 'table' then
    declared_abstract = doc.meta.parts.abstract
  end

  local abstract = nil
  local body = pandoc.List{}
  local parts, found = segments(doc.blocks)
  for _, segment in ipairs(parts) do
    if segment.part == 'abstract' then
      abstract = abstract or pandoc.List{}
      abstract:extend(segment.blocks)
    elseif segment.part and declared.names[segment.part] then
      io.stderr:write(
        '[WARNING] myst-parts: the front matter already declares the '
        .. segment.part .. ' part; the one in the body was dropped\n'
      )
    elseif segment.part then
      body:extend(as_section(segment.part, segment.blocks, level))
    else
      body:extend(segment.blocks)
    end
  end

  if not abstract then
    local section, rest = take_section(body)
    if section then
      abstract, body = section, rest
    end
  end

  -- An abstract given in the front matter or myst.yml wins; it was written for
  -- this purpose, whereas this one is inferred from the body. The body copy is
  -- still taken out: it is marked as the abstract, so leaving it would print
  -- the paper's abstract twice.
  if abstract and #abstract > 0 then
    if not is_blank(declared_abstract) then
      io.stderr:write(
        '[WARNING] myst-parts: the front matter already declares an abstract; '
        .. 'the one in the body was dropped\n'
      )
    else
      doc.meta.abstract = pandoc.MetaBlocks(abstract)
      io.stderr:write '[INFO] myst-parts: moved the abstract into metadata\n'
    end
  elseif is_blank(doc.meta.abstract) and not is_blank(declared_abstract) then
    doc.meta.abstract = declared_abstract
  end

  local leading = pandoc.List{}
  for _, part in ipairs(declared.leading) do
    leading:extend(as_section(part.part, part.blocks, level))
  end
  local trailing = pandoc.List{}
  for _, part in ipairs(declared.trailing) do
    trailing:extend(as_section(part.part, part.blocks, level))
  end

  if not found and not abstract and #leading == 0 and #trailing == 0 then
    return nil
  end

  local at = back_matter_index(body)
  local blocks = pandoc.List{}
  blocks:extend(leading)
  for i = 1, at - 1 do
    blocks:insert(body[i])
  end
  blocks:extend(trailing)
  for i = at, #body do
    blocks:insert(body[i])
  end
  doc.blocks = blocks
  return doc
end
