-- Generalized filter for MyST markdown admonitions
-- Define admonition types and their LaTeX styling
local admonition_styles = {
    figure = {
        color = "red!5!white",
        frame = "red!75!black",
        title = "Figure placeholder",
        use_special_content = true -- Special flag for figures
    },
    note = {
        color = "blue!5!white",
        frame = "blue!75!black", 
        title = "Note",
        use_special_content = false
    },
    warning = {
        color = "orange!5!white",
        frame = "orange!75!black",
        title = "Warning", 
        use_special_content = false
    },
    tip = {
        color = "green!5!white",
        frame = "green!75!black",
        title = "Tip",
        use_special_content = false
    },
    error = {
        color = "red!10!white",
        frame = "red!50!black",
        title = "Error",
        use_special_content = false
    }
}

-- Function to process an admonition block
function process_admonition(admonition_type, admonition_id, content_blocks, article_doi)
    local style = admonition_styles[admonition_type]
    if not style then
        -- Unknown admonition type, use default styling
        style = {
            color = "gray!5!white",
            frame = "gray!75!black",
            title = admonition_type:gsub("^%l", string.upper), -- Capitalize first letter
            use_special_content = false
        }
    end
    
    -- For figures, extract label from content and filter out label directives
    local actual_content_blocks = {}
    local label_id = admonition_id -- Start with the original ID
    
    if admonition_type == "figure" then
        for _, content in ipairs(content_blocks) do
            -- Check for :label: directive (with more flexible matching)
            local label_match = content:match("^%s*:label:%s*(.-)%s*$")
            if label_match and label_match ~= "" then
                -- Found a label directive, use it as the ID
                label_id = label_match
            else
                -- Not a label directive, keep as content
                table.insert(actual_content_blocks, content)
            end
        end
    else
        -- For non-figure admonitions, use all content as-is
        actual_content_blocks = content_blocks
    end
    
    -- Determine content based on admonition type
    local content
    if style.use_special_content and admonition_type == "figure" then
        -- Special case for figures: combine user caption with DOI link message
        local user_content = table.concat(actual_content_blocks, "\n")
        local special_message = "Please see \\href{https://preprint.neurolibre.org/" .. article_doi .. "}{the living preprint} to interact with this figure."
        
        if user_content and user_content ~= "" then
            -- Combine user caption with special message
            content = user_content .. "\n\n" .. special_message
        else
            -- No user caption, just use special message
            content = special_message
        end
    else
        -- All other admonitions: use their actual content
        content = table.concat(actual_content_blocks, "\n")
    end
    
    local latex = "\\begin{tcolorbox}[colback=" .. style.color .. ",colframe=" .. style.frame
    
    if label_id and label_id ~= "" then
        latex = latex .. ",title=" .. style.title .. " \\label{" .. label_id .. "}"
    else
        latex = latex .. ",title=" .. style.title
    end
    
    latex = latex .. "]\n" .. content .. "\n\\end{tcolorbox}"
    return latex
end

-- Main document processing function
function Pandoc(doc)
    local newblocks = {}
    local i = 1
    
    -- Get article DOI from metadata
    local article_doi = ""
    if doc.meta.article and doc.meta.article.doi then
        article_doi = pandoc.utils.stringify(doc.meta.article.doi)
    end
    
    while i <= #doc.blocks do
        local block = doc.blocks[i]
        local blocktext = pandoc.utils.stringify(block)
        
        -- Check for any admonition pattern :::{type}
        local admonition_type, admonition_id = blocktext:match("^:::{([%w%-_]+)}%s*#?([%w%-_]*)")
        
        if admonition_type then
            -- This block starts an admonition, collect all blocks until we find closing :::
            local content_blocks = {}
            
            -- Skip the opening :::{type} line
            i = i + 1
            
            -- Collect content blocks until we find closing :::
            while i <= #doc.blocks do
                local content_block = doc.blocks[i]
                local content_text = pandoc.utils.stringify(content_block)
                
                if content_text:match("^:::%s*$") then
                    -- Found closing :::, stop collecting
                    break
                else
                    -- Add this block's content
                    table.insert(content_blocks, content_text)
                end
                i = i + 1
            end
            
            -- Process the admonition
            local latex = process_admonition(admonition_type, admonition_id, content_blocks, article_doi)
            table.insert(newblocks, pandoc.RawBlock("latex", latex))
        else
            -- Not an admonition block, keep as is
            table.insert(newblocks, block)
        end
        
        i = i + 1
    end
    
    doc.blocks = newblocks
    return doc
end