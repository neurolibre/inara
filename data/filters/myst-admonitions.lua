--- Render MyST admonition and figure directives as LaTeX boxes.
--
-- MyST writes these as colon fences:
--
--     :::: {important} Interactive dashboard
--     :::{iframe} https://example.org
--     :::
--     ::::
--
-- Pandoc does not parse them. A fence whose opening line carries a title after
-- the `{type}` is not a valid `fenced_divs` opener, so the whole construct
-- arrives here as ordinary paragraphs of literal text, fences included. This
-- filter recognises those paragraphs and replaces them with LaTeX.
--
-- Two rules matter and both were once broken:
--
--   * The colons and `{type}` may be separated by a space. `:::: {important}`
--     and `::: {figure}` are as common in real submissions as `:::{figure}`,
--     and a pattern anchored on `:+{` silently passes them through as text.
--   * A fence closes on a run of colons of *its own length*. MyST nests by
--     widening the outer fence, so an outer `::::` must not be closed by the
--     `:::` belonging to something nested inside it.
--
-- Content is collected as blocks and rendered with pandoc, not concatenated as
-- strings, so emphasis, citations and math inside a box survive. Nested
-- directives are processed recursively before their parent is rendered.

local stringify = pandoc.utils.stringify

--- Per-type styling. `title` is what the box is labelled in the PDF.
local admonition_styles = {
  figure = {
    color = 'red!5!white',
    frame = 'red!75!black',
    title = 'Interactive content placeholder',
  },
  iframe = {
    color = 'red!5!white',
    frame = 'red!75!black',
    title = 'Interactive content',
  },
  table = {
    color = 'red!5!white',
    frame = 'red!75!black',
    title = 'Interactive content placeholder',
  },
  note = {color = 'blue!5!white', frame = 'blue!75!black', title = 'Note'},
  important = {color = 'blue!5!white', frame = 'blue!75!black', title = 'Important'},
  seealso = {color = 'blue!5!white', frame = 'blue!75!black', title = 'See also'},
  tip = {color = 'green!5!white', frame = 'green!75!black', title = 'Tip'},
  hint = {color = 'green!5!white', frame = 'green!75!black', title = 'Hint'},
  warning = {color = 'orange!5!white', frame = 'orange!75!black', title = 'Warning'},
  attention = {color = 'orange!5!white', frame = 'orange!75!black', title = 'Attention'},
  caution = {color = 'orange!5!white', frame = 'orange!75!black', title = 'Caution'},
  error = {color = 'red!10!white', frame = 'red!50!black', title = 'Error'},
  danger = {color = 'red!10!white', frame = 'red!50!black', title = 'Danger'},
}

local function default_style (name)
  return {
    color = 'gray!5!white',
    frame = 'gray!75!black',
    title = name:gsub('^%l', string.upper),
  }
end

local function trim (s)
  return (s:gsub('^%s*(.-)%s*$', '%1'))
end

--- Escape a string that will be typeset as LaTeX text.
--
-- Directive arguments are URLs and file paths taken verbatim from the source;
-- they reach the output as raw LaTeX and so must not be able to inject it.
local function escape_latex (s)
  return (s:gsub('[\\{}%$&#%^_%%~]', {
    ['\\'] = '\\textbackslash{}',
    ['{'] = '\\{',
    ['}'] = '\\}',
    ['$'] = '\\$',
    ['&'] = '\\&',
    ['#'] = '\\#',
    ['^'] = '\\textasciicircum{}',
    ['_'] = '\\_',
    ['%'] = '\\%',
    ['~'] = '\\textasciitilde{}',
  }))
end

--- A LaTeX label must survive `\label{}`; keep it to characters that can.
local function safe_label (label)
  if not label or label == '' then
    return nil
  end
  return label:match '^[%w%-_:%.]+$' and label or nil
end

--- Does this text open a fence? Returns the fence's colon run and its type.
local function fence_open (text)
  local colons, name = text:match '^(:::+)%s*{%s*([%w%-_]+)%s*}'
  return colons, name
end

--- Does this text close a fence of exactly `width` colons?
--
-- Returns the content that precedes the closing run. A closing fence is often
-- glued to the last paragraph of the body ("...dashboard.\n:::"), because
-- pandoc joins those two source lines into one paragraph.
local function fence_close (text, width)
  local before, colons = text:match '^(.-)%s*(:::+)%s*$'
  if colons and #colons == width then
    return before or ''
  end
  return nil
end

--- Strip a trailing run of colons from a block's inlines.
--
-- Used when a closing fence shares a paragraph with the body text: the text
-- must be kept as parsed inlines, so it cannot simply be re-read from a string.
local function without_trailing_fence (block)
  if block.t ~= 'Para' and block.t ~= 'Plain' then
    return block
  end
  local inlines = block.content:clone()
  while #inlines > 0 do
    local last = inlines[#inlines]
    if last.t == 'Str' and last.text:match '^:::+$' then
      inlines:remove(#inlines)
    elseif last.t == 'Space' or last.t == 'SoftBreak' or last.t == 'LineBreak' then
      inlines:remove(#inlines)
    else
      break
    end
  end
  if #inlines == 0 then
    return nil
  end
  return pandoc.Para(inlines)
end

--- Pull `:label:` and the remaining `:key: value` options off an opening line.
--
-- The options follow the directive on their own source lines, but pandoc has
-- already joined them into the opening paragraph.
local function parse_options (opening)
  local label = opening:match ':label:%s*([%w%-_%.:]+)'
  local options = {}
  for key, value in opening:gmatch ':([%w%-_]+):%s*(%S+)' do
    if key ~= 'label' then
      options[key] = value
    end
  end
  return label, options
end

--- The directive's argument: everything between `{type}` and the first option.
local function parse_argument (opening)
  local rest = opening:match '^:::+%s*{%s*[%w%-_]+%s*}%s*(.*)$'
  if not rest or rest == '' then
    return nil
  end
  local argument = rest:match '^([^:]*)'
  -- A URL argument contains a colon, so stopping at the first one would cut
  -- `https://…` down to `https`. Options always start at a colon that begins a
  -- word, which lets the two cases be told apart.
  local url = rest:match '^(%a[%w+.-]*://%S+)'
  argument = trim(url or argument or '')
  return argument ~= '' and argument or nil
end

--- Is this argument a path to an image rather than a cell reference or URL?
local function is_image_path (argument)
  if not argument or argument == '' or argument:match '^#' then
    return false
  end
  return argument:match '%.%w+$' ~= nil or argument:match '[/\\]' ~= nil
end

--- Render inlines to LaTeX.
--
-- Only used where LaTeX demands a single argument -- a caption -- and a block
-- sequence therefore cannot be spliced in.
local function inlines_to_latex (inlines)
  return trim(pandoc.write(pandoc.Pandoc{pandoc.Plain(inlines)}, 'latex'))
end

local function raw (text)
  return pandoc.RawBlock('latex', text)
end

--- Open a tcolorbox.
--
-- The title is braced: it may hold a comma or a bracket, either of which would
-- otherwise terminate the key-value list.
local function open_box (style, title)
  return raw('\\begin{tcolorbox}[colback=' .. style.color
    .. ',colframe=' .. style.frame
    .. ',title={' .. title .. '}]')
end

local CLOSE_BOX = '\\end{tcolorbox}'

--- Body blocks, preceded by a rule of space when there is anything above them.
local function with_leading_gap (body)
  if #body == 0 then
    return pandoc.List{}
  end
  local blocks = pandoc.List{raw('\\vspace{1em}')}
  blocks:extend(body)
  return blocks
end

--- A figure whose image exists on disk.
--
-- Emitted as raw LaTeX rather than a pandoc Figure so that the float placement
-- and `width=\linewidth` survive: pandoc's writer will not pass a LaTeX length
-- through as an image width, and drops it instead.
--
-- Inside another box the `figure` float cannot be used -- a float may not start
-- in restricted horizontal mode, and tcolorbox puts us there -- so the nested
-- form is a centred graphic with `\captionof`, which the template's `caption`
-- package provides and which steps the same counter.
--
-- The caption is written out here, which means a cross reference inside it is
-- fixed before myst-references.lua runs and so stays unresolved. Captions of
-- the *placeholder* figures, which is where submissions actually put cross
-- references, keep their blocks and do resolve.
local function figure_with_image (image_path, label, caption_blocks, nested)
  local caption_inlines = pandoc.Inlines{}
  for _, block in ipairs(caption_blocks) do
    if block.content and block.t ~= 'RawBlock' then
      if #caption_inlines > 0 then
        caption_inlines:insert(pandoc.Space())
      end
      caption_inlines:extend(block.content)
    end
  end
  local caption = #caption_inlines > 0 and inlines_to_latex(caption_inlines) or nil
  local graphic = '\\includegraphics[width=\\linewidth]{' .. image_path .. '}'
  local labelled = label and ('\\label{' .. label .. '}\n') or ''

  if nested then
    return pandoc.List{raw(
      '\\begin{center}\n' .. graphic .. '\n'
      .. (caption and ('\\captionof{figure}{' .. caption .. '}\n') or '')
      .. labelled .. '\\end{center}'
    )}
  end

  return pandoc.List{raw(
    '\\begin{figure}[htbp]\n\\centering\n' .. graphic .. '\n'
    .. (caption and ('\\caption{' .. caption .. '}\n') or '')
    .. labelled .. '\\end{figure}'
  )}
end

--- A figure that only exists in the living preprint.
local function figure_placeholder (label, body, article_doi)
  local style = admonition_styles.figure
  local title = style.title
  if label then
    title = '\\refstepcounter{figure}Figure~\\thefigure: ' .. title
      .. ' \\label{' .. label .. '}'
  end

  local blocks = pandoc.List{
    open_box(style, title),
    pandoc.Para{
      pandoc.Str 'Please see ',
      pandoc.Link(
        pandoc.Inlines{pandoc.Str 'the living preprint'},
        'https://preprint.neurolibre.org/' .. article_doi
      ),
      pandoc.Str ' to interact with this figure.',
    },
  }
  blocks:extend(with_leading_gap(body))
  blocks:insert(raw(CLOSE_BOX))
  return blocks
end

--- An embedded page. Print cannot show it, so link out to it instead.
local function iframe (url, label, body)
  local style = admonition_styles.iframe
  local title = style.title
  if label then
    title = title .. ' \\label{' .. label .. '}'
  end

  local lead
  if url then
    lead = pandoc.Para{
      pandoc.Str 'This content is interactive in the living preprint. Open it at ',
      pandoc.Link(pandoc.Inlines{pandoc.Str(url)}, url),
      pandoc.Str '.',
    }
  else
    lead = pandoc.Para{
      pandoc.Str 'This content is interactive in the living preprint.',
    }
  end

  local blocks = pandoc.List{open_box(style, title), lead}
  blocks:extend(with_leading_gap(body))
  blocks:insert(raw(CLOSE_BOX))
  return blocks
end

--- Notebook cell outputs, keyed by the cell's label. Filled on first use.
local notebook_outputs = nil

--- Folders that never hold a submission's notebooks, only copies or caches.
local skipped_folders = {
  _build = true,
  node_modules = true,
  __pycache__ = true,
}

--- Every `.ipynb` under `dir`, a few levels deep.
local function find_notebooks (dir, depth, found)
  local ok, entries = pcall(pandoc.system.list_directory, dir)
  if not ok then
    return found
  end
  for _, name in ipairs(entries) do
    local path = dir == '.' and name or pandoc.path.join{dir, name}
    if name:match '%.ipynb$' then
      found:insert(path)
    elseif depth > 0 and not name:match '^%.' and not skipped_folders[name] then
      find_notebooks(path, depth - 1, found)
    end
  end
  return found
end

--- A notebook field holds either one string or a list of lines.
local function joined (value)
  if type(value) == 'table' then
    return table.concat(value)
  end
  return value
end

--- The label MyST knows a cell by: a `#| label:` line, or `label` in metadata.
local function cell_label (cell)
  local source = joined(cell.source) or ''
  local label = source:match '^#|%s*label:%s*(%S+)'
    or source:match '\n#|%s*label:%s*(%S+)'
  if not label and type(cell.metadata) == 'table' then
    label = cell.metadata.label
  end
  return label
end

--- Size a table's columns by what they hold.
--
-- A wide pipe table gets its column widths from the length of its `---`
-- separators, which pandas pads to the header. A short header over long values
-- then gets a narrow column, and every value in it wraps. Sizing each column
-- by its longest value, or the longest word of its header, keeps rows on one
-- line and lets only the headers wrap.
local function size_columns (tbl)
  -- A table narrow enough for the line keeps pandoc's natural column widths.
  for _, colspec in ipairs(tbl.colspecs) do
    if type(colspec[2]) ~= 'number' then
      return tbl
    end
  end

  local widths = {}
  local function measure (rows, whole_cell)
    for _, row in ipairs(rows) do
      for i, cell in ipairs(row.cells) do
        local text = stringify(cell.contents)
        local width = 0
        if whole_cell then
          width = utf8.len(text) or #text
        else
          for word in text:gmatch '%S+' do
            width = math.max(width, utf8.len(word) or #word)
          end
        end
        widths[i] = math.max(widths[i] or 1, width)
      end
    end
  end
  measure(tbl.head.rows, false)
  for _, body in ipairs(tbl.bodies) do
    measure(body.body, true)
  end

  local total = 0
  for i = 1, #tbl.colspecs do
    total = total + (widths[i] or 1)
  end
  for i, colspec in ipairs(tbl.colspecs) do
    tbl.colspecs[i] = {colspec[1], (widths[i] or 1) / total}
  end
  return tbl
end

--- Map each labelled cell to the blocks its saved output reads as.
--
-- A MyST embed such as `![](#notebook_tbl)` shows a cell's output, which only
-- the living preprint can execute. The notebook usually still carries the
-- output from its last run, and a table is saved in a form pandoc can read --
-- markdown from `DataFrame.to_markdown`, or the HTML pandas renders -- so the
-- PDF can show the same table.
local function load_notebook_outputs ()
  local outputs = {}
  for _, path in ipairs(find_notebooks('.', 3, pandoc.List{})) do
    local fh = io.open(path, 'r')
    local ok, notebook = false, nil
    if fh then
      ok, notebook = pcall(pandoc.json.decode, fh:read 'a', false)
      fh:close()
    end
    if ok and type(notebook) == 'table' and type(notebook.cells) == 'table' then
      for _, cell in ipairs(notebook.cells) do
        local label = cell.cell_type == 'code' and cell_label(cell)
        if label and not outputs[label] then
          for _, output in ipairs(cell.outputs or {}) do
            local data = type(output) == 'table' and output.data
            if type(data) == 'table' then
              local markdown = joined(data['text/markdown'])
              local html = joined(data['text/html'])
              if markdown then
                outputs[label] = pandoc.read(markdown, 'markdown').blocks
              elseif html then
                outputs[label] = pandoc.read(html, 'html').blocks
              end
              if outputs[label] then
                outputs[label] = outputs[label]:walk{Table = size_columns}
                break
              end
            end
          end
        end
      end
    end
  end
  return outputs
end

--- The cell label of a block that is nothing but an embed, `![](#label)`.
local function embed_label (block)
  if block.t == 'Figure' and #block.content == 1 then
    block = block.content[1]
  end
  if (block.t ~= 'Para' and block.t ~= 'Plain') or #block.content ~= 1 then
    return nil
  end
  local image = block.content[1]
  local label = image.t == 'Image' and image.src:match '^#(.+)$'
  if not label then
    return nil
  end
  -- The reader appends `default-image-extension` to any image path without
  -- one, and a cell label never has one, so `#cell` arrives as `#cell.png`.
  local extension = PANDOC_READER_OPTIONS.default_image_extension or ''
  if extension ~= '' and label:sub(-#extension) == extension then
    label = label:sub(1, -#extension - 1)
  end
  return label
end

--- Replace embeds with the outputs they point at, where those were saved.
local function resolve_embeds (blocks)
  local result = pandoc.List{}
  for _, block in ipairs(blocks) do
    local label = embed_label(block)
    if label then
      notebook_outputs = notebook_outputs or load_notebook_outputs()
      if notebook_outputs[label] then
        result:extend(notebook_outputs[label]:clone())
      else
        io.stderr:write(
          '[WARNING] myst-admonitions: no saved notebook output for #' .. label .. '\n'
        )
      end
    else
      result:insert(block)
    end
  end
  return result
end

--- A table, captioned with the directive's title and any text in its body.
--
-- MyST puts the title in the caption and treats the body's paragraphs as a
-- legend. A LaTeX caption is a single paragraph, so the title leads in bold and
-- the legend follows it.
--
-- When the body holds no table -- the usual reason being an embed whose output
-- was never saved -- the table is shown as a placeholder pointing at the living
-- preprint, numbered as a table so references to it still resolve.
local function table_directive (title, label, body, article_doi)
  local blocks = resolve_embeds(body)
  local tbl = nil
  local legend = pandoc.List{}
  local rest = pandoc.List{}
  for _, block in ipairs(blocks) do
    if block.t == 'Table' and not tbl then
      tbl = block
    elseif block.t == 'Para' or block.t == 'Plain' then
      legend:insert(block)
    else
      rest:insert(block)
    end
  end

  if not tbl then
    local style = admonition_styles.table
    local heading = '\\refstepcounter{table}Table~\\thetable: '
      .. (title and escape_latex(title) or style.title)
      .. (label and (' \\label{' .. label .. '}') or '')
    local result = pandoc.List{
      open_box(style, heading),
      pandoc.Para{
        pandoc.Str 'Please see ',
        pandoc.Link(
          pandoc.Inlines{pandoc.Str 'the living preprint'},
          'https://preprint.neurolibre.org/' .. article_doi
        ),
        pandoc.Str ' to view this table.',
      },
    }
    result:extend(with_leading_gap(legend))
    result:insert(raw(CLOSE_BOX))
    return result
  end

  local caption = pandoc.Inlines{}
  if title then
    local parsed = pandoc.read(title, 'markdown').blocks
    caption = parsed[1] and parsed[1].content or pandoc.Inlines{pandoc.Str(title)}
  end
  if #legend > 0 and #caption > 0 then
    if not stringify(caption):match '[%.%?!:]$' then
      caption:insert(pandoc.Str '.')
    end
    caption = pandoc.Inlines{pandoc.Strong(caption)}
  end
  for _, para in ipairs(legend) do
    if #caption > 0 then
      caption:insert(pandoc.Space())
    end
    caption:extend(para.content)
  end

  tbl.caption.long = #caption > 0 and pandoc.Blocks{pandoc.Plain(caption)} or pandoc.Blocks{}
  tbl.identifier = label or tbl.identifier

  local result = pandoc.List{tbl}
  result:extend(rest)
  return result
end

local process_blocks

--- Turn one directive into a list of blocks.
--
-- The body is spliced in as blocks rather than written out as LaTeX, so that
-- the filters after this one -- myst-references.lua above all -- can still see
-- and rewrite what is inside a box.
local function render (name, opening, body_blocks, article_doi, nested)
  local label = safe_label(select(1, parse_options(opening)))
  local argument = parse_argument(opening)
  local body = process_blocks(body_blocks, article_doi, true)

  if name == 'iframe' then
    return iframe(argument, label, body)
  end

  if name == 'figure' then
    if is_image_path(argument) then
      return figure_with_image(argument, label, body, nested)
    end
    return figure_placeholder(label, body, article_doi)
  end

  if name == 'table' then
    return table_directive(argument, label, body, article_doi)
  end

  -- `:::{note} A title of its own` names the box; MyST shows that in place of
  -- the type's default title, and the frame colour still conveys the type.
  local style = admonition_styles[name] or default_style(name)
  local title = argument and escape_latex(argument) or style.title
  if label then
    title = title .. ' \\label{' .. label .. '}'
  end

  local blocks = pandoc.List{open_box(style, title)}
  blocks:extend(body)
  blocks:insert(raw(CLOSE_BOX))
  return blocks
end

--- Split a paragraph's inlines into the source lines they came from.
--
-- Everything about a directive is line-oriented -- the fence, its options, the
-- body -- but pandoc joins consecutive source lines into one paragraph. The
-- SoftBreaks it leaves behind are the only record of where the lines were.
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

--- Rejoin lines into a single paragraph, or nil if nothing is left.
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

--- Is this line one of the directive's `:key: value` options?
local function is_option_line (text)
  return text:match '^:[%w%-_]+:' ~= nil
end

local process_blocks_impl

--- Consume a directive that begins at `lines[1]` of a paragraph.
--
-- Returns the rendered blocks and the index of the last document block used.
-- A directive may be self-contained in its paragraph -- with no blank lines
-- anywhere, pandoc puts the fence, the body and the closing fence in a single
-- one -- or run on across the blocks that follow.
local function take_paragraph_directive (blocks, i, lines, colons, name, article_doi, nested)
  local width = #colons
  local opening = pandoc.utils.stringify(lines[1])
  local body = pandoc.List{}

  -- Option lines belong to the opening, not to the body.
  local first_body = 2
  while lines[first_body] and is_option_line(pandoc.utils.stringify(lines[first_body])) do
    opening = opening .. ' ' .. pandoc.utils.stringify(lines[first_body])
    first_body = first_body + 1
  end

  -- Body lines inside this same paragraph, up to a closing fence if it is here.
  local inner = pandoc.List{}
  local closed = false
  for j = first_body, #lines do
    local text = pandoc.utils.stringify(lines[j])
    local before = fence_close(text, width)
    if before ~= nil then
      if before:match '%S' then
        local trimmed = without_trailing_fence(pandoc.Para(lines[j]))
        if trimmed then
          inner:insert(trimmed.content)
        end
      end
      closed = true
      break
    end
    inner:insert(lines[j])
  end

  local inner_para = from_lines(inner)
  if inner_para then
    body:insert(inner_para)
  end

  local last = i
  if not closed then
    local j = i + 1
    while j <= #blocks do
      local candidate = blocks[j]
      local before = fence_close(pandoc.utils.stringify(candidate), width)
      if before ~= nil then
        closed = true
        if before:match '%S' then
          local trimmed = without_trailing_fence(candidate)
          if trimmed then
            body:insert(trimmed)
          end
        end
        break
      end
      body:insert(candidate)
      j = j + 1
    end
    last = closed and j or i
  end

  if not closed then
    io.stderr:write(
      '[WARNING] myst-admonitions: unclosed ' .. colons .. '{' .. name .. '} fence\n'
    )
    return nil, i
  end

  return render(name, opening, body, article_doi, nested), last
end

--- A `:::{type}` fence with no argument is valid `fenced_divs`, and pandoc has
--- already turned it into a Div whose sole class is the braced type.
local function div_directive_name (block)
  if block.t ~= 'Div' or #block.classes ~= 1 then
    return nil
  end
  return block.classes[1]:match '^{%s*([%w%-_]+)%s*}$'
end

--- Turn such a Div into the same shape the paragraph path produces.
local function take_div_directive (block, name, article_doi, nested)
  local body = block.content:clone()
  local opening = ':::{' .. name .. '}'

  -- Options survive as the first lines of the Div's first paragraph.
  if #body > 0 and (body[1].t == 'Para' or body[1].t == 'Plain') then
    local lines = to_lines(body[1].content)
    local consumed = 0
    while lines[consumed + 1]
      and is_option_line(pandoc.utils.stringify(lines[consumed + 1]))
    do
      consumed = consumed + 1
      opening = opening .. ' ' .. pandoc.utils.stringify(lines[consumed])
    end
    if consumed > 0 then
      local rest = pandoc.List{}
      for j = consumed + 1, #lines do
        rest:insert(lines[j])
      end
      local para = from_lines(rest)
      if para then
        body[1] = para
      else
        body:remove(1)
      end
    end
  end

  if block.identifier ~= '' then
    opening = opening .. ' :label: ' .. block.identifier
  end

  return render(name, opening, body, article_doi, nested)
end

--- Replace every directive in `blocks`, recursing into their bodies.
process_blocks_impl = function (blocks, article_doi, nested)
  local result = pandoc.List{}
  local i = 1
  while i <= #blocks do
    local block = blocks[i]
    local handled = false

    local div_name = div_directive_name(block)
    if div_name then
      result:extend(take_div_directive(block, div_name, article_doi, nested))
      handled = true
    elseif block.t == 'Para' or block.t == 'Plain' then
      local lines = to_lines(block.content)
      local colons, name = fence_open(pandoc.utils.stringify(lines[1]))
      if colons then
        local rendered, last =
          take_paragraph_directive(blocks, i, lines, colons, name, article_doi, nested)
        if rendered then
          result:extend(rendered)
          i = last
          handled = true
        end
      end
    end

    if not handled then
      -- Not a directive, or one that never closed: leave the source alone
      -- rather than swallow the rest of the document.
      result:insert(block)
    end
    i = i + 1
  end
  return result
end

process_blocks = process_blocks_impl

--- MyST inline roles with a direct counterpart in pandoc, keyed by role name.
--
-- Each handler takes the role's content and returns an inline, or nil to leave
-- the role as written.
local role_handlers = {}

--- `{button}` becomes an ordinary link. A button cannot be pressed on paper,
--- but the destination is still worth reaching, and a link is how print says so.
role_handlers.button = function (content)
  local label, url = content:match '^%s*(.-)%s*<(%S+)>%s*$'
  if not url then
    return nil
  end
  return pandoc.Link(pandoc.Inlines{pandoc.Str(label ~= '' and label or url)}, url)
end

role_handlers.sup = function (content)
  return pandoc.Superscript(pandoc.Inlines(content))
end
role_handlers.superscript = role_handlers.sup

role_handlers.sub = function (content)
  return pandoc.Subscript(pandoc.Inlines(content))
end
role_handlers.subscript = role_handlers.sub

role_handlers.u = function (content)
  return pandoc.Underline(pandoc.Inlines(content))
end
role_handlers.underline = role_handlers.u

role_handlers.del = function (content)
  return pandoc.Strikeout(pandoc.Inlines(content))
end
role_handlers.strike = role_handlers.del

role_handlers.smallcaps = function (content)
  return pandoc.SmallCaps(pandoc.Inlines(content))
end
role_handlers.sc = role_handlers.smallcaps

role_handlers.math = function (content)
  return pandoc.Math('InlineMath', content)
end

--- `{abbr}` is written ``{abbr}`MD (mean diffusivity)` ``. The web shows the
--- expansion on hover; print can only show the abbreviation.
role_handlers.abbr = function (content)
  local short = content:match '^%s*(.-)%s*%b()%s*$'
  return pandoc.Str(short and short ~= '' and short or content)
end

--- Turn MyST inline roles into the pandoc inlines they stand for.
--
-- A role is written ``{name}`content` ``. Pandoc has no notion of roles, so it
-- reads the name as plain text and the content as a code span. The name is
-- often glued to the word before it, as in ``10{sup}`-7` ``, so it is matched
-- at the end of a Str rather than as a whole one. Roles without a handler are
-- left as written.
local function roles (inlines)
  local result = pandoc.List{}
  local i = 1
  while i <= #inlines do
    local inline = inlines[i]
    local next_inline = inlines[i + 1]
    if inline.t == 'Str' and next_inline and next_inline.t == 'Code' then
      local before, name = inline.text:match '^(.-){([%w%-:]+)}$'
      local handler = name and role_handlers[name]
      local replacement = handler and handler(next_inline.text)
      if replacement then
        if before ~= '' then
          result:insert(pandoc.Str(before))
        end
        result:insert(replacement)
        i = i + 2
        goto continue
      end
    end
    result:insert(inline)
    i = i + 1
    ::continue::
  end
  return result
end

function Pandoc (doc)
  local article_doi = ''
  if doc.meta.article and doc.meta.article.doi then
    article_doi = stringify(doc.meta.article.doi)
  end
  -- Before the fences: an admonition body is rendered to raw LaTeX as its box
  -- is built, and nothing can rewrite its inlines afterwards.
  doc = doc:walk{Inlines = roles}
  doc.blocks = process_blocks(doc.blocks, article_doi, false)
  return doc
end
