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

--- Turn MyST's `{button}` role into an ordinary link.
--
-- The role is written ``{button}`Label <https://example.org>` ``. Pandoc has no
-- notion of it, so it reaches the output as the literal text `{button}` beside
-- a code span. A button cannot be pressed on paper, but the destination is
-- still worth reaching, and a link is how print says so.
local function buttons (inlines)
  local result = pandoc.List{}
  local i = 1
  while i <= #inlines do
    local inline = inlines[i]
    local next_inline = inlines[i + 1]
    if inline.t == 'Str' and inline.text == '{button}'
      and next_inline and next_inline.t == 'Code'
    then
      local label, url = next_inline.text:match '^%s*(.-)%s*<(%S+)>%s*$'
      if url then
        result:insert(pandoc.Link(
          pandoc.Inlines{pandoc.Str(label ~= '' and label or url)},
          url
        ))
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
  doc = doc:walk{Inlines = buttons}
  doc.blocks = process_blocks(doc.blocks, article_doi, false)
  return doc
end
