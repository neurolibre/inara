-- Robust MyST markdown admonitions filter with nested support
-- Handles complex nested structures, proper validation, and security

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

-- Logging function (can be disabled by setting to false)
local ENABLE_LOGGING = false
local function log(message)
    if ENABLE_LOGGING then
        io.stderr:write("[MyST-Admonitions] " .. message .. "\n")
    end
end

-- Input sanitization functions
local function sanitize_latex_string(str)
    if not str or str == "" then
        return ""
    end
    -- Escape special LaTeX characters
    str = str:gsub("\\", "\\textbackslash{}")
    str = str:gsub("{", "\\{")
    str = str:gsub("}", "\\}")
    str = str:gsub("%$", "\\$")
    str = str:gsub("&", "\\&")
    str = str:gsub("%%", "\\%")
    str = str:gsub("#", "\\#")
    str = str:gsub("%^", "\\textasciicircum{}")
    str = str:gsub("_", "\\_")
    str = str:gsub("~", "\\textasciitilde{}")
    return str
end

local function sanitize_file_path(path)
    if not path or path == "" then
        return ""
    end
    -- Remove potentially dangerous characters and sequences
    path = path:gsub("%.%./", "") -- Remove ../ sequences
    path = path:gsub("%.%.\\", "") -- Remove ..\ sequences
    path = path:gsub("|", "") -- Remove pipes
    path = path:gsub(";", "") -- Remove semicolons
    path = path:gsub("`", "") -- Remove backticks
    -- Only allow alphanumeric, dots, dashes, underscores, and path separators
    path = path:gsub("[^%w%.%-_/\\]", "")
    return path
end

local function sanitize_url_component(component)
    if not component or component == "" then
        return ""
    end
    -- Allow only alphanumeric, dots, dashes, and underscores for URL components
    return component:gsub("[^%w%.%-_]", "")
end

-- Validation functions
local function is_valid_admonition_type(type_name)
    return type_name and type_name:match("^[%w%-_]+$") and #type_name > 0 and #type_name <= 50
end

local function is_valid_label(label)
    return label and label:match("^[%w%-_]+$") and #label > 0 and #label <= 100
end

local function is_image_path(arg)
    if not arg or arg == "" then
        return false
    end
    
    -- Check for common image extensions
    local has_extension = arg:match("%.%w+$")
    -- Check for path separators
    local has_path_separator = arg:match("/") or arg:match("\\")
    -- Check for common image file extensions
    local is_image_extension = arg:match("%.(png|jpg|jpeg|gif|svg|pdf|eps|tiff?|bmp)$")
    
    return has_extension or has_path_separator or is_image_extension
end

-- Fence parsing with proper nesting support
local function parse_fence_line(line)
    local fence_match = line:match("^(:+){([^}]*)}(.*)$")
    if not fence_match then
        return nil
    end
    
    local colons, type_name, remainder = line:match("^(:+){([^}]*)}(.*)$")
    if not colons or not type_name then
        return nil
    end
    
    local depth = #colons
    if depth < 3 then
        return nil -- Invalid fence
    end
    
    return {
        depth = depth,
        type = type_name:match("^%s*(.-)%s*$"), -- Trim whitespace
        remainder = remainder:match("^%s*(.-)%s*$"), -- Trim whitespace
        is_opening = true
    }
end

local function parse_closing_fence(line)
    local colons = line:match("^(:+)%s*$")
    if not colons then
        return nil
    end
    
    local depth = #colons
    if depth < 3 then
        return nil
    end
    
    return {
        depth = depth,
        is_closing = true
    }
end

-- Attribute parsing with validation
local function parse_attributes(text)
    local attributes = {}
    local label = nil
    
    -- Parse :key: value patterns
    for attr_name, attr_value in text:gmatch(":([%w%-_]+):%s*([%w%-_.]+)") do
        if is_valid_label(attr_name) and is_valid_label(attr_value) then
            if attr_name == "label" then
                label = attr_value
            else
                attributes[attr_name] = attr_value
            end
        else
            log("Invalid attribute: " .. tostring(attr_name) .. "=" .. tostring(attr_value))
        end
    end
    
    return label, attributes
end

-- Content processing functions
local function process_figure_with_image(image_path, label, caption_content)
    local safe_path = sanitize_file_path(image_path)
    local safe_label = label and sanitize_latex_string(label) or ""
    local safe_caption = caption_content and sanitize_latex_string(caption_content) or ""
    
    log("Processing figure with image: " .. safe_path)
    
    local latex = "\\begin{figure}[htbp]\n\\centering\n"
    latex = latex .. "\\includegraphics[width=\\linewidth]{" .. safe_path .. "}\n"
    
    if safe_caption ~= "" then
        latex = latex .. "\\caption{" .. safe_caption .. "}\n"
    end
    
    if safe_label ~= "" then
        latex = latex .. "\\label{" .. safe_label .. "}\n"
    end
    
    latex = latex .. "\\end{figure}"
    return latex
end

local function process_figure_placeholder(label, content_blocks, article_doi)
    local safe_label = label and sanitize_latex_string(label) or ""
    local safe_doi = sanitize_url_component(article_doi or "")
    
    log("Processing figure placeholder with label: " .. safe_label)
    
    local style = admonition_styles.figure
    local content = "Please see \\href{https://preprint.neurolibre.org/" .. safe_doi .. "}{the living preprint} to interact with this figure."
    
    -- Add content blocks if they exist
    if #content_blocks > 0 then
        local safe_content = {}
        for _, block in ipairs(content_blocks) do
            table.insert(safe_content, sanitize_latex_string(block))
        end
        content = content .. "\n\n\\vspace{1em}\n\n" .. table.concat(safe_content, "\n")
    end
    
    local latex = "\\begin{tcolorbox}[colback=" .. style.color .. ",colframe=" .. style.frame
    
    if safe_label ~= "" then
        latex = latex .. ",title=\\refstepcounter{figure}Figure~\\thefigure: " .. style.title .. " \\label{" .. safe_label .. "}"
    else
        latex = latex .. ",title=" .. style.title
    end
    
    latex = latex .. "]\n" .. content .. "\n\\end{tcolorbox}"
    return latex
end

local function process_regular_admonition(admonition_type, label, content_blocks)
    local safe_label = label and sanitize_latex_string(label) or ""
    
    log("Processing regular admonition: " .. admonition_type)
    
    local style = admonition_styles[admonition_type]
    if not style then
        -- Unknown admonition type, use default styling
        style = {
            color = "gray!5!white",
            frame = "gray!75!black",
            title = sanitize_latex_string(admonition_type:gsub("^%l", string.upper)),
            use_special_content = false
        }
    end
    
    -- Sanitize content blocks
    local safe_content_blocks = {}
    for _, block in ipairs(content_blocks) do
        table.insert(safe_content_blocks, sanitize_latex_string(block))
    end
    local content = table.concat(safe_content_blocks, "\n")
    
    local latex = "\\begin{tcolorbox}[colback=" .. style.color .. ",colframe=" .. style.frame
    
    if safe_label ~= "" then
        latex = latex .. ",title=" .. style.title .. " \\label{" .. safe_label .. "}"
    else
        latex = latex .. ",title=" .. style.title
    end
    
    latex = latex .. "]\n" .. content .. "\n\\end{tcolorbox}"
    return latex
end

-- Hierarchical admonition processing with proper nesting
local function process_admonition_stack(stack, article_doi)
    local results = {}
    
    for _, admonition in ipairs(stack) do
        local admonition_type = admonition.type
        local label = admonition.label
        local content_blocks = admonition.content_blocks
        local argument = admonition.argument
        
        if not is_valid_admonition_type(admonition_type) then
            log("Invalid admonition type: " .. tostring(admonition_type))
            goto continue
        end
        
        if label and not is_valid_label(label) then
            log("Invalid label: " .. tostring(label))
            label = nil
        end
        
        local latex
        if admonition_type == "figure" then
            if argument and is_image_path(argument) then
                latex = process_figure_with_image(argument, label, table.concat(content_blocks, "\n"))
            else
                latex = process_figure_placeholder(label, content_blocks, article_doi)
            end
        else
            latex = process_regular_admonition(admonition_type, label, content_blocks)
        end
        
        table.insert(results, pandoc.RawBlock("latex", latex))
        
        ::continue::
    end
    
    return results
end

-- Main document processing with hierarchical parsing
function Pandoc(doc)
    log("Starting MyST admonitions processing")
    
    local newblocks = {}
    local admonition_stack = {}
    local current_admonition = nil
    
    -- Get article DOI from metadata
    local article_doi = ""
    if doc.meta.article and doc.meta.article.doi then
        article_doi = pandoc.utils.stringify(doc.meta.article.doi)
    end
    
    for i, block in ipairs(doc.blocks) do
        local blocktext = pandoc.utils.stringify(block)
        
        -- Try to parse as opening fence
        local opening_fence = parse_fence_line(blocktext)
        if opening_fence then
            local admonition_type = opening_fence.type
            local remainder = opening_fence.remainder
            
            log("Found opening fence: " .. admonition_type .. " at depth " .. opening_fence.depth)
            
            -- Parse label and attributes from remainder
            local label, attributes = parse_attributes(remainder)
            
            -- Extract argument (everything before first attribute)
            local argument = remainder:match("^([^:]*)")
            if argument then
                argument = argument:match("^%s*(.-)%s*$") -- Trim whitespace
                if argument == "" then argument = nil end
            end
            
            -- Create new admonition
            local new_admonition = {
                type = admonition_type,
                depth = opening_fence.depth,
                label = label,
                attributes = attributes,
                argument = argument,
                content_blocks = {},
                parent = current_admonition
            }
            
            -- Handle nesting
            if current_admonition then
                -- We're inside another admonition, add this as nested content
                table.insert(current_admonition.content_blocks, "NESTED_ADMONITION_PLACEHOLDER_" .. #admonition_stack)
            end
            
            table.insert(admonition_stack, new_admonition)
            current_admonition = new_admonition
            
            goto continue
        end
        
        -- Try to parse as closing fence
        local closing_fence = parse_closing_fence(blocktext)
        if closing_fence and current_admonition then
            log("Found closing fence at depth " .. closing_fence.depth)
            
            -- Find matching opening fence by depth
            local matched_admonition = nil
            for j = #admonition_stack, 1, -1 do
                if admonition_stack[j].depth == closing_fence.depth then
                    matched_admonition = admonition_stack[j]
                    break
                end
            end
            
            if matched_admonition then
                -- Process and remove matched admonition and all nested ones
                local to_process = {}
                while #admonition_stack > 0 do
                    local admonition = table.remove(admonition_stack)
                    table.insert(to_process, 1, admonition) -- Insert at beginning to maintain order
                    if admonition == matched_admonition then
                        break
                    end
                end
                
                -- Process the completed admonitions
                local processed = process_admonition_stack(to_process, article_doi)
                for _, processed_block in ipairs(processed) do
                    table.insert(newblocks, processed_block)
                end
                
                -- Update current admonition
                current_admonition = #admonition_stack > 0 and admonition_stack[#admonition_stack] or nil
            else
                log("No matching opening fence found for closing fence at depth " .. closing_fence.depth)
                -- No matching opening fence, treat as regular content
                if current_admonition then
                    table.insert(current_admonition.content_blocks, blocktext)
                else
                    table.insert(newblocks, block)
                end
            end
            
            goto continue
        end
        
        -- Regular content
        if current_admonition then
            -- We're inside an admonition, add to content
            table.insert(current_admonition.content_blocks, blocktext)
        else
            -- Outside any admonition, keep block as is
            table.insert(newblocks, block)
        end
        
        ::continue::
    end
    
    -- Handle any unclosed admonitions
    if #admonition_stack > 0 then
        log("Warning: Found " .. #admonition_stack .. " unclosed admonitions")
        local processed = process_admonition_stack(admonition_stack, article_doi)
        for _, processed_block in ipairs(processed) do
            table.insert(newblocks, processed_block)
        end
    end
    
    log("Completed MyST admonitions processing")
    doc.blocks = newblocks
    return doc
end