-- Generalized filter for MyST markdown admonitions
-- Define admonition types and their LaTeX styling
local admonition_styles = {
    figure = {
        color = "red!5!white",
        frame = "red!75!black",
        title = "🎚️ Interactive content placeholder",
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
    -- Check for common image extensions or path separators
    return arg:match("%.%w+$") or arg:match("/") or arg:match("\\")
end

-- Function to extract label from content blocks
function extract_label_from_content(content_blocks)
    local label = nil
    local filtered_blocks = {}

    print("=== DEBUG: extract_label_from_content ===")
    print("Number of content blocks: " .. #content_blocks)

    for i, block in ipairs(content_blocks) do
        local block_text = pandoc.utils.stringify(block)
        print("Block " .. i .. ": '" .. block_text .. "'")

        local extracted_label = block_text:match("^:label:%s*([%w%-_]+)%s*$")
        if extracted_label then
            print("  FOUND LABEL: '" .. extracted_label .. "'")
            label = extracted_label
        else
            table.insert(filtered_blocks, block)
        end
    end

    print("Final label: '" .. tostring(label) .. "'")
    print("Filtered blocks count: " .. #filtered_blocks)
    print("=== END DEBUG ===")

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
function process_admonition(admonition_type, argument, content_blocks, article_doi)
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
    
    -- Check if argument is actually a label (starts with #)
    local label = nil
    if argument and argument:match("^#") then
        label = argument:sub(2) -- Remove the # prefix
    end
    
    -- Extract label from content blocks (handles :label: attribute) if not found in argument
    local content_label, filtered_content = extract_label_from_content(content_blocks)
    if not label and content_label then
        label = content_label
    end
    
    -- Handle figures specially
    if admonition_type == "figure" then
        if is_image_path(argument) then
            -- Type 3: Figure with image path
            return process_figure_with_image(argument, label, table.concat(filtered_content, "\n"))
        else
            -- Type 4: Figure with random argument (placeholder)
            return process_figure_placeholder(label, filtered_content, article_doi)
        end
    end
    
    -- Handle regular admonitions (note, warning, tip, error)
    local content = table.concat(filtered_content, "\n")
    
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

        print("=== MAIN LOOP DEBUG ===")
        print("Processing block " .. i .. ":")
        print("Block text: '" .. blocktext .. "'")

        -- Match ::: {type} or ::: {type} #label or ::: {type} argument
        local admonition_type, argument_or_label = blocktext:match("^:::{([%w%-_]+)}%s*(.*)")

        if admonition_type then
            print("Found admonition type: " .. admonition_type)
            print("Argument/label: '" .. tostring(argument_or_label) .. "'")

            local content_blocks = {}
            local found_closing = false
            i = i + 1

            -- Collect blocks until we hit a closing :::
            while i <= #doc.blocks do
                local content_block = doc.blocks[i]
                local content_text = pandoc.utils.stringify(content_block)

                print("  Checking content block " .. i .. ": '" .. content_text .. "'")

                if content_text:match("^:::%s*$") then
                    print("  Found closing :::, stopping collection")
                    found_closing = true
                    i = i + 1
                    break
                else
                    print("  Adding block " .. i)
                    table.insert(content_blocks, content_block)
                    i = i + 1
                end
            end

            print("Total content blocks collected: " .. #content_blocks)

            if found_closing then
                local latex = process_admonition(admonition_type, argument_or_label, content_blocks, article_doi)
                table.insert(newblocks, pandoc.RawBlock("latex", latex))
            else
                -- malformed directive, just keep original
                table.insert(newblocks, block)
            end
        else
            -- not a directive
            table.insert(newblocks, block)
            i = i + 1
        end
    end

    return pandoc.Pandoc(newblocks, doc.meta)
end