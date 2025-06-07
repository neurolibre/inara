-- Process the entire document to find and replace :::{figure} patterns
function Pandoc(doc)
    local newblocks = {}
    local i = 1
    
    while i <= #doc.blocks do
        local block = doc.blocks[i]
        local blocktext = pandoc.utils.stringify(block)
        
        -- Check if this block contains :::{figure}
        if blocktext:match(":::{figure}") then
            -- This block starts a figure, collect all blocks until we find closing :::
            local figure_blocks = {}
            local figure_id = blocktext:match(":::{figure}%s*#([%w%-_]+)")
            
            -- Skip the opening :::{figure} line
            i = i + 1
            
            -- Collect content blocks until we find closing :::
            while i <= #doc.blocks do
                local content_block = doc.blocks[i]
                local content_text = pandoc.utils.stringify(content_block)
                
                if content_text:match("^:::%s*$") then
                    -- Found closing :::, stop collecting
                    break
                else
                    -- Add this block's content to figure content
                    table.insert(figure_blocks, content_text)
                end
                i = i + 1
            end
            
            -- Create LaTeX box with collected content
            local content = table.concat(figure_blocks, "\n")
            local latex = "\\begin{tcolorbox}[colback=gray!5!white,colframe=gray!75!black"
            if figure_id then
                latex = latex .. ",title=Figure \\label{" .. figure_id .. "}"
            end
            latex = latex .. "]\n" .. content .. "\n\\end{tcolorbox}"
            
            table.insert(newblocks, pandoc.RawBlock("latex", latex))
        else
            -- Not a figure block, keep as is
            table.insert(newblocks, block)
        end
        
        i = i + 1
    end
    
    doc.blocks = newblocks
    return doc
end