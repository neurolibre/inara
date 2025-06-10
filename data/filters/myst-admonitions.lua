local admonition_styles = {
    figure = {
        color = "red!5!white",
        frame = "red!75!black",
        title = "Figure placeholder",
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

-- Utility: check if a string looks like an image path (has a slash or image extension)
local function is_image_path(s)
    if s:match("[/\\]") then
        return true
    end
    -- common image extensions (case insensitive)
    local ext = s:match("%.([a-zA-Z0-9]+)$")
    if ext then
        ext = ext:lower()
        local image_exts = { "png", "jpg", "jpeg", "pdf", "eps", "svg" }
        for _, v in ipairs(image_exts) do
            if ext == v then return true end
        end
    end
    return false
end

function process_admonition(admonition_type, argument, label, content_blocks, article_doi)
    local style = admonition_styles[admonition_type] or {
        color = "gray!5!white",
        frame = "gray!75!black",
        title = admonition_type:gsub("^%l", string.upper),
        use_special_content = false
    }
    
    -- Flatten content blocks into LaTeX string
    local content = table.concat(content_blocks, "\n\n")

    -- Handle figure with image path argument: render figure with image and caption
    if admonition_type == "figure" and argument and is_image_path(argument) then
        -- caption is content, label if present
        local latex = "\\begin{figure}[htbp]\n\\centering\n"
        latex = latex .. "\\includegraphics[width=\\linewidth]{" .. argument .. "}\n"
        if content ~= "" then
            latex = latex .. "\\caption{" .. content .. "}\n"
        end
        if label and label ~= "" then
            latex = latex .. "\\label{" .. label .. "}\n"
        end
        latex = latex .. "\\end{figure}"
        return latex
    end

    -- For figures without image path, render tcolorbox with DOI link + content
    if admonition_type == "figure" then
        local latex = "\\begin{tcolorbox}[colback=" .. style.color .. ",colframe=" .. style.frame
        if label and label ~= "" then
            latex = latex .. ",title=" .. style.title .. " \\label{" .. label .. "}"
        else
            latex = latex .. ",title=" .. style.title
        end
        latex = latex .. "]\n"
        latex = latex .. "Please see \\href{https://preprint.neurolibre.org/" .. article_doi .. "}{the living preprint} to interact with this figure.\n\n"
        if content ~= "" then
            latex = latex .. "\\vspace{1em}\n" .. content .. "\n"
        end
        latex = latex .. "\\end{tcolorbox}"
        return latex
    end

    -- Other admonitions: simple tcolorbox with content and optional label in title
    local latex = "\\begin{tcolorbox}[colback=" .. style.color .. ",colframe=" .. style.frame
    if label and label ~= "" then
        latex = latex .. ",title=" .. style.title .. " \\label{" .. label .. "}"
    else
        latex = latex .. ",title=" .. style.title
    end
    latex = latex .. "]\n" .. content .. "\n\\end{tcolorbox}"

    return latex
end

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

        -- Match opening fence: :::type [argument] (argument can be empty)
        local admonition_type, argument = blocktext:match("^:::%s*([%w%-_]+)%s*(.-)%s*$")

        if admonition_type then
            -- Collect attributes lines like :label: ...
            local label = ""

            -- We'll collect content blocks between the opening ::: and closing :::

            local content_blocks = {}

            -- Move to next block (skip opening fence)
            i = i + 1

            -- Collect lines starting with :label: and remove them from content_blocks
            local attr_lines = {}

            -- Collect content lines, and detect attribute lines at the beginning
            while i <= #doc.blocks do
                local b = doc.blocks[i]
                local text = pandoc.utils.stringify(b)

                if text:match("^:::%s*$") then
                    -- Closing fence found, end
                    break
                elseif text:match("^:label:%s*(%S+)") then
                    label = text:match("^:label:%s*(%S+)")
                    -- skip adding this line to content
                else
                    table.insert(content_blocks, text)
                end

                i = i + 1
            end

            -- Sanity: if label is empty or whitespace only, clear it
            if label then
                label = label:gsub("^%s*(.-)%s*$", "%1")
                if label == "" then label = nil end
            end

            -- Process the admonition
            local latex = process_admonition(admonition_type, argument, label, content_blocks, article_doi)
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