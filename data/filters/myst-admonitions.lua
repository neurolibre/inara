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

-- Extracts the :label: value and returns cleaned content
function extract_label_and_content(content_blocks)
    local label = nil
    local cleaned_lines = {}

    for _, block in ipairs(content_blocks) do
        local lines = pandoc.utils.stringify(block):split("\n")
        for _, line in ipairs(lines) do
            local found_label = line:match("^%s*:label:%s*(.+)%s*$")
            if found_label then
                label = found_label
            else
                table.insert(cleaned_lines, line)
            end
        end
    end

    return label, table.concat(cleaned_lines, "\n")
end

-- Function to process an admonition block
function process_admonition(admonition_type, content_blocks, article_doi)
    local style = admonition_styles[admonition_type] or {
        color = "gray!5!white",
        frame = "gray!75!black",
        title = admonition_type:gsub("^%l", string.upper),
        use_special_content = false
    }

    local label, content = extract_label_and_content(content_blocks)

    local full_content = content
    if style.use_special_content and article_doi and article_doi ~= "" then
        local doi_message = "Please see \\href{https://preprint.neurolibre.org/" .. article_doi .. "}{the living preprint} to interact with this figure."
        if content and content ~= "" then
            full_content = doi_message .. "\n\n\\vspace{1em}\n\n" .. content
        else
            full_content = doi_message
        end
    end

    local latex = "\\begin{tcolorbox}[colback=" .. style.color .. ",colframe=" .. style.frame
    if label and label ~= "" then
        latex = latex .. ",title=" .. style.title .. " \\label{" .. label .. "}"
    else
        latex = latex .. ",title=" .. style.title
    end

    latex = latex .. "]\n" .. full_content .. "\n\\end{tcolorbox}"
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

        -- Check for admonition pattern :::{type}
        local admonition_type = blocktext:match("^:::{([%w%-_]+)}")

        if admonition_type then
            local content_blocks = {}
            i = i + 1

            while i <= #doc.blocks do
                local content_block = doc.blocks[i]
                local content_text = pandoc.utils.stringify(content_block)

                if content_text:match("^:::%s*$") then
                    break
                else
                    table.insert(content_blocks, content_block)
                end
                i = i + 1
            end

            local latex = process_admonition(admonition_type, content_blocks, article_doi)
            table.insert(newblocks, pandoc.RawBlock("latex", latex))
        else
            table.insert(newblocks, block)
        end

        i = i + 1
    end

    doc.blocks = newblocks
    return doc
end

-- Helper to split string
function string:split(sep)
    local fields = {}
    local pattern = string.format("([^%s]+)", sep)
    self:gsub(pattern, function(c) fields[#fields + 1] = c end)
    return fields
end