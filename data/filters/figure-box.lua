function Div(el)
    -- Check for divs with the class "figure"
    if el.classes:includes("figure") then
      -- Replace contents with a gray box LaTeX raw block
      return pandoc.RawBlock("latex", "\\fbox{\\parbox{\\linewidth}{\\textcolor{gray}{\\textit{[See the living version]}}}}")
    end
  end