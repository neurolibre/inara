-- MyST markdown admonitions filter with nested support and security fixes
-- Define admonition types and their LaTeX styling
local admonition_styles = {
    figure = {
        color = "red!5!white",
        frame = "red!75!black",
        title = "Interactive content placeholder",
        use_special_content = true
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

-- Security: Input sanitization functions
local function sanitize_latex_string(str)
    if not str or str == "" then
        return ""
    end
    -- Escape special LaTeX characters using function form to avoid replacement string issues
    str = str:gsub("\\", function() return "\\textbackslash{}" end)
    str = str:gsub("{", function() return "\\{" end)
    str = str:gsub("}", function() return "\\}" end)
    str = str:gsub("%$", function() return "\\$" end)
    str = str:gsub("&", function() return "\\&" end)
    str = str:gsub("%%", function() return "\\%" end)
    str = str:gsub("#", function() return "\\#" end)
    str = str:gsub("%^", function() return "\\textasciicircum{}" end)
    str = str:gsub("_", function() return "\\_" end)
    str = str:gsub("~", function() return "\\textasciitilde{}" end)
    return str
end

local function sanitize_file_path(path)
    if not path or path == "" then
        return ""
    end
    -- Remove potentially dangerous characters
    path = path:gsub("%.%./", "")
    path = path:gsub("%.%.\\", "")
    path = path:gsub("[|;`]", "")
    path = path:gsub("[^%w%.%-_/\\]", "")
    return path
end

local function sanitize_url_component(component)
    if not component or component == "" then
        return ""
    end
    return component:gsub("[^%w%.%-_]", "")
end

-- Function to check if a string looks like an image path
function is_image_path(arg)
    if not arg or arg == "" then
        return false
    end
    
    local has_extension = arg:match("%.%w+$")
    local has_path_separator = arg:match("/") or arg:match("\\")
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
        -- Validate label
        if extracted_label:match("^[%w%-_]+$") and #extracted_label <= 100 then
            label = extracted_label
        end
    end
    
    -- Extract other attributes
    for attr_name, attr_value in block_text:gmatch(":([%w%-_]+):%s*([%w%-_]+)") do
        if attr_name ~= "label" and attr_name:match("^[%w%-_]+$") and attr_value:match("^[%w%-_]+$") then
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
        local extracted_label = block:match("^:label:%s*([%w%-_]+)%s*$")
        if extracted_label and extracted_label:match("^[%w%-_]+$") and #extracted_label <= 100 then
            label = extracted_label
        else
            table.insert(filtered_blocks, block)
        end
    end
    
    return label, filtered_blocks
end

-- Function to process a figure with image path
function process_figure_with_image(image_path, label, caption_content)
    local safe_path = sanitize_file_path(image_path)
    local safe_label = label and sanitize_latex_string(label) or ""
    local safe_caption = caption_content and sanitize_latex_string(caption_content) or ""
    
    local latex = "\\begin{figure}[htbp]\\n\\centering\\n"
    latex = latex .. "\\includegraphics[width=\\linewidth]{" .. safe_path .. "}\\n"
    
    if safe_caption ~= "" then
        latex = latex .. "\\caption{" .. safe_caption .. "}\\n"
    end
    
    if safe_label ~= "" then
        latex = latex .. "\\label{" .. safe_label .. "}\\n"
    end
    
    latex = latex .. "\\end{figure}"
    return latex
end

-- Function to process a figure placeholder
function process_figure_placeholder(label, content_blocks, article_doi)
    local safe_label = label and sanitize_latex_string(label) or ""
    local safe_doi = sanitize_url_component(article_doi or "")
    
    local style = admonition_styles.figure
    local content = "Please see \\href{https://preprint.neurolibre.org/" .. safe_doi .. "}{the living preprint} to interact with this figure."
    
    -- Add content blocks if they exist
    if #content_blocks > 0 then
        local safe_content = {}
        for _, block in ipairs(content_blocks) do
            table.insert(safe_content, sanitize_latex_string(block))
        end
        content = content .. "\\n\\n\\vspace{1em}\\n\\n" .. table.concat(safe_content, "\\n")
    end
    
    local latex = "\\begin{tcolorbox}[colback=" .. style.color .. ",colframe=" .. style.frame
    
    if safe_label ~= "" then
        latex = latex .. ",title=\\refstepcounter{figure}Figure~\\thefigure: " .. style.title .. " \\label{" .. safe_label .. "}"
    else
        latex = latex .. ",title=" .. style.title
    end
    
    latex = latex .. "]\\n" .. content .. "\\n\\end{tcolorbox}"
    return latex
end

-- Function to process an admonition block
function process_admonition(admonition_type, opening_block_text, content_blocks, article_doi)
    -- Validate admonition type
    if not admonition_type or not admonition_type:match("^[%w%-_]+$") or #admonition_type > 50 then
        return nil
    end
    
    local style = admonition_styles[admonition_type]
    if not style then
        style = {
            color = "gray!5!white",
            frame = "gray!75!black",
            title = sanitize_latex_string(admonition_type:gsub("^%l", string.upper)),
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
        local after_figure = opening_block_text:match("^:+{[^}]+}%s*(.+)")
        
        if after_figure then
            local argument = after_figure:match("^([^:]+)")
            if argument then
                argument = argument:match("^%s*(.-)%s*$")
                
                if argument and is_image_path(argument) then
                    return process_figure_with_image(argument, label, table.concat(content_blocks, "\\n"))
                else
                    return process_figure_placeholder(label, content_blocks, article_doi)
                end
            end
        end
        
        return process_figure_placeholder(label, content_blocks, article_doi)
    end
    
    -- Handle regular admonitions
    local safe_content_blocks = {}
    for _, block in ipairs(content_blocks) do
        table.insert(safe_content_blocks, sanitize_latex_string(block))
    end
    local content = table.concat(safe_content_blocks, "\\n")
    
    local latex = "\\begin{tcolorbox}[colback=" .. style.color .. ",colframe=" .. style.frame
    
    if label and label ~= "" then
        latex = latex .. ",title=" .. style.title .. " \\label{" .. sanitize_latex_string(label) .. "}"
    else
        latex = latex .. ",title=" .. style.title
    end
    
    latex = latex .. "]\\n" .. content .. "\\n\\end{tcolorbox}"
    return latex
end

-- Improved fence matching with nesting support
function find_matching_fence(blocks, start_index, opening_fence_depth)
    local nesting_level = 0
    
    for i = start_index + 1, #blocks do
        local block = blocks[i]
        local blocktext = pandoc.utils.stringify(block)
        
        -- Check for opening fence
        local opening_colons = blocktext:match("^(:+){[^}]+}")
        if opening_colons and #opening_colons >= 3 then
            nesting_level = nesting_level + 1
        end
        
        -- Check for closing fence
        local closing_colons = blocktext:match("^(:+)%s*$")
        if closing_colons and #closing_colons >= 3 then
            if nesting_level == 0 and #closing_colons == opening_fence_depth then
                -- Found matching closing fence
                return i
            elseif nesting_level > 0 then
                nesting_level = nesting_level - 1
            end
        end
    end
    
    return nil -- No matching fence found
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
        
        -- Check for admonition opening
        local admonition_type = blocktext:match("^(:+){([%w%-_]+)}")
        local opening_fence_depth = nil
        
        if admonition_type then
            local colons = blocktext:match("^(:+){")
            opening_fence_depth = colons and #colons or 0
            admonition_type = blocktext:match("^:+{([%w%-_]+)}")
        end
        
        if admonition_type and opening_fence_depth and opening_fence_depth >= 3 then
            -- Find matching closing fence
            local closing_index = find_matching_fence(doc.blocks, i, opening_fence_depth)
            
            if closing_index then
                -- Collect content blocks between opening and closing
                local content_blocks = {}
                
                for j = i + 1, closing_index - 1 do
                    local content_block = doc.blocks[j]
                    local content_text = pandoc.utils.stringify(content_block)
                    table.insert(content_blocks, content_text)
                end
                
                -- Process the admonition
                local latex = process_admonition(admonition_type, blocktext, content_blocks, article_doi)
                if latex then
                    table.insert(newblocks, pandoc.RawBlock("latex", latex))
                else
                    -- If processing failed, keep original blocks
                    for j = i, closing_index do
                        table.insert(newblocks, doc.blocks[j])
                    end
                end
                
                -- Skip to after the closing fence
                i = closing_index + 1
            else
                -- No matching closing fence, keep original block
                table.insert(newblocks, block)
                i = i + 1
            end
        else
            -- Not an admonition block, keep as is
            table.insert(newblocks, block)
            i = i + 1
        end
    end
    
    doc.blocks = newblocks
    return doc
end