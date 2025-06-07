function RawBlock(el)
  if el.format ~= "markdown" then return end

  local lines = {}
  for line in el.text:gmatch("[^\r\n]*") do
    table.insert(lines, line)
  end

  local output_blocks = {}
  local i = 1
  while i <= #lines do
    -- Match opening: :::{figure} or :::{figure} #id
    local open, id = lines[i]:match("^:::%s*{?figure}?%s*#?([%w%-_]*)")
    if lines[i]:match("^:::%s*{?figure}?") then
      -- Found opening
      local figure_id = lines[i]:match("#([%w%-_]+)")
      local content_lines = {}
      i = i + 1
      -- Collect until closing ::: or end of file
      while i <= #lines and not lines[i]:match("^:::%s*$") do
        table.insert(content_lines, lines[i])
        i = i + 1
      end
      -- Skip the closing ::: if present
      if i <= #lines and lines[i]:match("^:::%s*$") then
        i = i + 1
      end
      -- Prepare LaTeX box
      local latex = "\\begin{tcolorbox}[colback=gray!5!white,colframe=gray!75!black"
      if figure_id then
        latex = latex .. ",title=Figure \\label{" .. figure_id .. "}"
      end
      latex = latex .. "]\n" .. table.concat(content_lines, "\n") .. "\n\\end{tcolorbox}"
      table.insert(output_blocks, pandoc.RawBlock("latex", latex))
    else
      -- Not a figure block, output as markdown
      if lines[i] ~= "" then
        table.insert(output_blocks, pandoc.RawBlock("markdown", lines[i]))
      end
      i = i + 1
    end
  end

  return output_blocks
end