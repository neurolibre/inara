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

-- Function to check if a string looks like an image path
function is_image_path(arg)
    if not arg or arg == "" then
        return false
    end
    -- Check for common image extensions
    local has_extension = arg:match("%.%w+$")
    -- Check for path separators (including forward and backward slashes)
    local has_path_separator = arg:match("/") or arg:match("\\")
    -- Check for common image file extensions
    local is_image_extension = arg:match("%.(png|jpg|jpeg|gif|svg|pdf|eps|tiff?|bmp)$")
    
    return has_extension or has_path_separator or is_image_extension
end

-- Function to extract label and other attributes from the opening block
function extract_attributes_from_opening_block(block_text)
    local label = nil
    local other_attributes = {}
    
    -- Extract label from :label: attribute
    local extracted_label = block_text:match(":label:%s*([%w%-_]+)")
    if extracted_label then
        label = extracted_label
    end
    
    -- Extract other attributes (like :aaa:, :ccc:, etc.)
    for attr_name, attr_value in block_text:gmatch(":([%w%-_]+):%s*([%w%-_]+)") do
        if attr_name ~= "label" then
            other_attributes[attr_name] = attr_value
        end
    end
    
    return label, other_attributes
end

-- Function to extract label from content blocks (for backward compatibility)
function extract_label_from_content(content_blocks)
    local label = nil
    local filtered_blocks = {}
    
    for i, block in ipairs(content_blocks) do
        -- Check for :label: pattern in content blocks
        local extracted_label = block:match("^:label:%s*([%w%-_]+)%s*$")
        if extracted_label then
            label = extracted_label
            -- Don't add this block to filtered_blocks since it's a label line
        else
            -- Keep this block if it's not a label line
            table.insert(filtered_blocks, block)
        end
    end
    
    return label, filtered_blocks
end

-- Function to process a figure with image path
function process_figure_with_image(image_path, label, caption_content)
    local latex = "\\begin{figure}[htbp]\n\\centering\n"
    latex = latex .. "\\includegraphics[width=\\linewidth]{" .. image_path .. "}\n"
    
    if caption_content and caption_content ~= "" then
        latex = latex .. "\\caption{" .. caption_content .. "}\n"
    end
    
    if label and label ~= "" then
        latex = latex .. "\\label{" .. label .. "}\n"
    end
    
    latex = latex .. "\\end{figure}"
    return latex
end

-- Function to process a figure placeholder
function process_figure_placeholder(label, content_blocks, article_doi)
    local style = admonition_styles.figure
    local content = "Please see \\href{https://preprint.neurolibre.org/" .. article_doi .. "}{the living preprint} to interact with this figure."
    
    -- Add content blocks if they exist
    if #content_blocks > 0 then
        content = content .. "\n\n\\vspace{1em}\n\n" .. table.concat(content_blocks, "\n")
    end
    
    local latex = "\\begin{tcolorbox}[colback=" .. style.color .. ",colframe=" .. style.frame
    
    if label and label ~= "" then
        latex = latex .. ",title=" .. style.title .. " \\label{" .. label .. "}"
    else
        latex = latex .. ",title=" .. style.title
    end
    
    latex = latex .. "]\n" .. content .. "\n\\end{tcolorbox}"
    return latex
end

-- Function to process an admonition block
function process_admonition(admonition_type, opening_block_text, content_blocks, article_doi)
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
    
    -- Extract label and other attributes from the opening block
    local label, other_attributes = extract_attributes_from_opening_block(opening_block_text)
    
    -- If no label found in opening block, check content blocks (backward compatibility)
    if not label then
        local content_label, filtered_content = extract_label_from_content(content_blocks)
        if content_label then
            label = content_label
            content_blocks = filtered_content
        end
    end
    
    -- Handle figures specially
    if admonition_type == "figure" then
        -- Extract the argument (could be image path or random argument)
        -- First, remove the opening :::{figure} part
        local after_figure = opening_block_text:match("^:::{[^}]+}%s*(.+)")
        if after_figure then
            -- Extract everything before the first attribute (starts with :)
            local argument = after_figure:match("^([^:]+)")
            if argument then
                -- Trim whitespace
                argument = argument:match("^%s*(.-)%s*$")
                
                if argument and is_image_path(argument) then
                    -- Type 3: Figure with image path
                    return process_figure_with_image(argument, label, table.concat(content_blocks, "\n"))
                else
                    -- Type 4: Figure with random argument (placeholder)
                    return process_figure_placeholder(label, content_blocks, article_doi)
                end
            end
        end
        
        -- Fallback: no argument found, treat as placeholder
        return process_figure_placeholder(label, content_blocks, article_doi)
    end
    
    -- Handle regular admonitions (note, warning, tip, error)
    local content = table.concat(content_blocks, "\n")
    
    local latex = "\\begin{tcolorbox}[colback=" .. style.color .. ",colframe=" .. style.frame
    
    if label and label ~= "" then
        latex = latex .. ",title=" .. style.title .. " \\label{" .. label .. "}"
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
        
        -- Updated pattern matching for admonition opening
        -- Handles: :::{type}, :::{type} #label, :::{type} argument :label: value
        local admonition_type = blocktext:match("^:::{([%w%-_]+)}")
        
        if admonition_type then
            -- This block starts an admonition, collect all blocks until we find closing :::
            local content_blocks = {}
            local found_closing = false
            
            -- Skip the opening :::{type} line
            i = i + 1
            
            -- Collect content blocks until we find closing :::
            while i <= #doc.blocks do
                local content_block = doc.blocks[i]
                local content_text = pandoc.utils.stringify(content_block)
                
                if content_text:match(":::%s*$") then
                    -- Found closing :::, stop collecting
                    found_closing = true
                    break
                else
                    -- Add this block's content
                    table.insert(content_blocks, content_text)
                end
                i = i + 1
            end
            
            -- Only process if we found the closing fence
            if found_closing then
                -- Process the admonition with the full opening block text
                local latex = process_admonition(admonition_type, blocktext, content_blocks, article_doi)
                table.insert(newblocks, pandoc.RawBlock("latex", latex))
            else
                -- If no closing fence found, keep the original block and continue
                table.insert(newblocks, block)
            end
        else
            -- Not an admonition block, keep as is
            table.insert(newblocks, block)
        end
        
        i = i + 1
    end
    
    doc.blocks = newblocks
    return doc
end