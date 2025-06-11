local article_doi = "10.xxxxxx/draft"

local styles = {
  figure = { color = "red!5!white", frame = "red!75!black", title = "Figure placeholder" },
  note =   { color = "blue!5!white", frame = "blue!75!black", title = "Note" },
  tip =    { color = "green!5!white", frame = "green!75!black", title = "Tip" },
  warning ={ color = "orange!5!white", frame = "orange!75!black", title = "Warning" },
  error =  { color = "red!10!white", frame = "red!50!black", title = "Error" }
}

function RawBlock(el)
  if el.format ~= "markdown" then return nil end

  local output = {}
  local lines = {}
  for line in el.text:gmatch("([^\r\n]*)\r?\n?") do
    table.insert(lines, line)
  end

  local i = 1
  while i <= #lines do
    local line = lines[i]
    local open_type, id = line:match("^:::%{([%w%-_]+)%}%s*#?([%S]*)")
    if open_type then
      local style = styles[open_type] or {
        color = "gray!5!white", frame = "gray!75!black", title = open_type
      }

      local label = nil
      local content_lines = {}
      i = i + 1

      -- Collect all lines until closing ::: is found
      while i <= #lines do
        local l = lines[i]
        if l:match("^:::%s*$") then
          break
        end

        -- Capture and remove :label:
        local lbl = l:match("^%s*:label:%s*(.+)%s*$")
        if lbl then
          label = lbl
        else
          table.insert(content_lines, l)
        end

        i = i + 1
      end

      local content = table.concat(content_lines, "\n")
      local box = ""

      -- Special case: figure + image path
      if open_type == "figure" and id:match("^.+%.[a-zA-Z]+$") then
        box = string.format("\\begin{figure}[ht]\n\\centering\n\\includegraphics[width=0.9\\textwidth]{%s}", id)
        if label then box = box .. string.format("\n\\label{%s}", label) end
        if content:match("%S") then box = box .. "\n" .. content end
        box = box .. "\n\\end{figure}"
      else
        box = string.format(
          "\\begin{tcolorbox}[colback=%s,colframe=%s,title=%s%s]\n",
          style.color, style.frame, style.title,
          label and (" \\label{" .. label .. "}") or ""
        )

        if open_type == "figure" then
          box = box .. string.format(
            "Please see \\href{https://preprint.neurolibre.org/%s}{the living preprint} to interact with this figure.\n\n\\vspace{1em}\n\n",
            article_doi
          )
        end

        box = box .. content .. "\n\\end{tcolorbox}"
      end

      table.insert(output, pandoc.RawBlock("latex", box))
    else
      -- Pass through unrelated lines (not inside ::: blocks)
      table.insert(output, pandoc.RawBlock("latex", line))
    end
    i = i + 1
  end

  return output
end
