local utils = require 'pandoc.utils'

-- Map of styles for admonitions
local admonition_styles = {
  figure = {
    color = "red!5!white",
    frame = "red!75!black",
    title = "Figure placeholder"
  }
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

-- Render a LaTeX tcolorbox block
local function render_tcolorbox(content, label, doi)
  local style = admonition_styles["figure"]
  local box = "\\begin{tcolorbox}[colback=" .. style.color ..
              ",colframe=" .. style.frame ..
              ",title=" .. style.title

  if label and label ~= "" then
    box = box .. " \\label{" .. label .. "}"
  end
  box = box .. "]\n"

  box = box .. "Please see \\href{https://preprint.neurolibre.org/" ..
         doi .. "}{the living preprint} to interact with this figure.\n\n\\vspace{1em}\n\n"

  box = box .. content .. "\n\\end{tcolorbox}"
  return box
end

-- Handle Divs (e.g., ::: {figure})
function Div(el)
  if not el.classes:includes("figure") then
    return nil
  end

  local path = el.attributes[""] or ""
  if path:match("^#") then
    path = ""
  end

  local label = el.attributes["label"] or el.identifier or ""
  if label:match("^#") then
    label = "" -- sanitize invalid fallback labels
  end

  -- Extract plain text for caption (flatten blocks)
  local caption = pandoc.write(pandoc.Pandoc(el.content), "plain"):gsub("\n", " ")

  local doi = ""
  if PANDOC_DOCUMENT and PANDOC_DOCUMENT.meta.article and PANDOC_DOCUMENT.meta.article.doi then
    doi = utils.stringify(PANDOC_DOCUMENT.meta.article.doi)
  end

  if is_image_path(path) then
    return pandoc.RawBlock("latex", render_image_figure(path, caption, label))
  else
    local latex_content = pandoc.write(pandoc.Pandoc(el.content), "latex")
    return pandoc.RawBlock("latex", render_tcolorbox(latex_content, label, doi))
  end
end