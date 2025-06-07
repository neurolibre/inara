function Div(el)
    -- Check for divs with the class "figure"
    if el.classes:includes("figure") then
        -- Get the content of the div
        local content = pandoc.utils.stringify(el.content)
        
        -- Create a LaTeX box with the content
        local box_content = "\\begin{tcolorbox}[colback=gray!5!white,colframe=gray!75!black,title=Figure"
        
        -- Add the ID as a label if it exists
        if el.identifier and el.identifier ~= "" then
            box_content = box_content .. " \\label{" .. el.identifier .. "}"
        end
        
        box_content = box_content .. "]\n" .. content .. "\n\\end{tcolorbox}"
        
        -- Return the content wrapped in a LaTeX box
        return pandoc.RawBlock("latex", box_content)
    end
end