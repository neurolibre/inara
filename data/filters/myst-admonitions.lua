local utils = require 'pandoc.utils'

-- Style for 'figure' box
local figure_style = {
  color = "red!5!white",
  frame = "red!75!black",
  title = "Figure placeholder"
}

-- Determine if a string looks like a file path
local function is_image_path(str)
  return str and str:match("^.+%.[pjgsvgPJGSVC]+$")
end

-- Render a LaTeX figure block
local function render_image_figure(path, caption, label)
  local latex = "\\begin{figure}[htbp]\n\\centering\n"
  latex = latex .. "\\includegraphics[width=\\linewidth]{" .. path .. "}\n"
  if caption ~= "" then
    latex = latex .. "\\caption{" .. caption .. "}\n"
  end
  if label and label ~= "" then
    latex = latex .. "\\label{" .. label .. "}\n"
  end
  latex = latex .. "\\end{figure}"
  return latex
end

-- Render a tcolorbox
local function render_tcolorbox(content_blocks, label, doi)
  local header = "\\begin{tcolorbox}[colback=" .. figure_style.color ..
                 ",colframe=" .. figure_style.frame ..
                 ",title=" .. figure_style.title

  if label and label ~= "" then
    header = header .. " \\label{" .. label .. "}"
  end
  header = header .. "]\n"

  local preamble = "Please see \\href{https://preprint.neurolibre.org/" .. doi ..
                   "}{the living preprint} to interact with this figure.\n\n\\vspace{1em}\n\n"

  local body = pandoc.write(pandoc.Pandoc(content_blocks), "latex")
  local footer = "\\end{tcolorbox}"

  return header .. preamble .. body .. "\n" .. footer
end

-- Main Div handler
function Div(el)
  if not el.classes:includes("figure") then
    return nil
  end

  local raw_input = el.attributes[""] or ""
  local label = el.attributes["label"] or ""
  local doi = "10.xxxxxx/draft"

  if PANDOC_DOCUMENT and PANDOC_DOCUMENT.meta.article and PANDOC_DOCUMENT.meta.article.doi then
    doi = utils.stringify(PANDOC_DOCUMENT.meta.article.doi)
  end

  -- Ignore values like '#fig1cell'
  if raw_input:match("^#") then
    raw_input = ""
  end
  if label:match("^#") then
    label = ""
  end

  -- Handle as image figure
  if is_image_path(raw_input) then
    local caption = pandoc.utils.stringify(el.content)
    return pandoc.RawBlock("latex", render_image_figure(raw_input, caption, label))
  end

  -- Handle as figure box with blocks
  return pandoc.RawBlock("latex", render_tcolorbox(el.content, label, doi))
end
