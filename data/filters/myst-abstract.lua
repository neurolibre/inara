--- Lift a paper's abstract out of the body and into `meta.abstract`.
--
-- MyST offers two ways to mark one, and neither reaches pandoc:
--
--     +++ { "part": "abstract" }
--     ...
--     +++
--
--     # Abstract
--     ...
--
-- The first is a MyST block break carrying metadata; pandoc knows nothing of
-- it and typesets the `+++` lines and the JSON verbatim, in the middle of the
-- running text. The second reads as an ordinary section, so the abstract is set
-- exactly like the rest of the paper.
--
-- Both become `meta.abstract`, which the templates already know where to put --
-- above the body, set apart -- and which the JATS writer turns into
-- `<abstract>`. neurolibrenew.tex styles the `abstract` environment as a box.
--
-- Runs after citeproc so that a citation in the abstract is already resolved:
-- citeproc processes the body, not metadata, and would leave one behind.

local stringify = pandoc.utils.stringify

--- Split a paragraph's inlines into the source lines they came from.
--
-- With no blank lines around it, a whole `+++` block collapses into a single
-- paragraph, and the SoftBreaks are the only record of where its lines were.
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

--- Does this line open a `+++` block declaring itself the abstract?
--
-- Matched loosely on purpose: pandoc's smart quotes have already turned
-- `"part"` into curly-quoted inlines by the time the line is stringified, and
-- MyST accepts the key in either quote style or none.
local function opens_abstract (text)
  if not text:match '^%+%+%+%s*{' then
    return false
  end
  return text:lower():match 'part' ~= nil and text:lower():match 'abstract' ~= nil
end

local function is_plus_fence (text)
  return text:match '^%+%+%+%s*$' ~= nil
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

--- Take the abstract written as a `+++` part block.
--
-- Returns the abstract's blocks and the remaining document blocks, or nil.
local function take_plus_block (blocks)
  for i, block in ipairs(blocks) do
    if block.t == 'Para' or block.t == 'Plain' then
      local lines = to_lines(block.content)
      if opens_abstract(stringify(lines[1])) then
        local abstract = pandoc.List{}
        local inner = pandoc.List{}
        local closed = false

        for j = 2, #lines do
          if is_plus_fence(stringify(lines[j])) then
            closed = true
            break
          end
          inner:insert(lines[j])
        end
        local para = from_lines(inner)
        if para then
          abstract:insert(para)
        end

        local last = i
        if not closed then
          -- Blank lines separate the parts, so the block runs on.
          local j = i + 1
          while j <= #blocks do
            if is_plus_fence(stringify(blocks[j])) then
              closed = true
              break
            end
            abstract:insert(blocks[j])
            j = j + 1
          end
          last = closed and j or i
        end

        if not closed then
          io.stderr:write '[WARNING] myst-abstract: unclosed +++ abstract block\n'
          return nil
        end

        local rest = pandoc.List{}
        for j = 1, #blocks do
          if j < i or j > last then
            rest:insert(blocks[j])
          end
        end
        return abstract, rest
      end
    end
  end
  return nil
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

function Pandoc (doc)
  local abstract, rest = take_plus_block(doc.blocks)
  if not abstract then
    abstract, rest = take_section(doc.blocks)
  end
  if not abstract or #abstract == 0 then
    return nil
  end

  -- An abstract given in the front matter or myst.yml wins; it was written for
  -- this purpose, whereas this one is inferred from the body. The body copy is
  -- still taken out: it is marked as the abstract, so leaving it would print
  -- the paper's abstract twice, the second time with its `+++` markers intact.
  if not is_blank(doc.meta.abstract) then
    io.stderr:write(
      '[WARNING] myst-abstract: the front matter already declares an abstract; '
      .. 'the one in the body was dropped\n'
    )
    doc.blocks = rest
    return doc
  end

  doc.meta.abstract = pandoc.MetaBlocks(abstract)
  doc.blocks = rest
  io.stderr:write '[INFO] myst-abstract: moved the abstract into metadata\n'
  return doc
end
