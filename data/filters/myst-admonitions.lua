-- Define styles for known admonition types
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
        title = "Note"
    },
    warning = {
        color = "orange!5!white",
        frame = "orange!75!black",
        title = "Warning"
    },
    tip = {
        color = "green!5!white",
        frame = "green!75!black",
        title = "Tip"
    },
    error = {
        color = "red!10!white",
        frame = "red!50!black",
        title = "Error"
    }
}

-- Utility: check if a string looks like a path to an image
local function is_image_path(str)
    return str and str:match("^[%w%./_-]+%.[pjgsvgPJGSVC]+$")
end

-- Utility: extract the :label: value from content lines
local function extract_label(lines)
    for i, line in ipairs(lines) do
        local label = line:match("^%s*:label:%s*(%S+)")
        if label then
            table.remove(lines, i)
            return label
        end
    end
    return nil
end

-- Build LaTeX output for a figure path
local function render_image_figure(path, caption, label)
    local latex = "\\begin{figure}[htbp]\n\\centering\n"
    latex = latex .. "\\includegraphics[width=\\linewidth]{" .. path .. "}\n"
    if caption and caption ~= "" then
        latex = latex .. "\\caption{" .. caption .. "}\n"
    end
    if label and label ~= "" then
        latex = latex .. "\\label{" .. label .. "}\n"
    end
    latex = latex .. "\\end{figure}"
    return latex
end

-- Build LaTeX output for a tcolorbox-based admonition
local function render_tcolorbox(admonition_type, label, content_lines, article_doi)
    local style = admonition_styles[admonition_type] or {
        color = "gray!5!white",
        frame = "gray!75!black",
        title = admonition_type:gsub("^%l", string.upper)
    }

    local content = table.concat(content_lines, "\n")
    if style.use_special_content and admonition_type == "figure" then
        content = "Please see \\href{https://preprint.neurolibre.org/" .. article_doi ..
                  "}{the living preprint} to interact with this figure.\n\n\\vspace{1em}\n\n" .. content
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

-- Main Pandoc filter
function Pandoc(doc)
    local newblocks = {}
    local i = 1

    local article_doi = ""
    if doc.meta.article and doc.meta.article.doi then
        article_doi = pandoc.utils.stringify(doc.meta.article.doi)
    end

    while i <= #doc.blocks do
        local block = doc.blocks[i]
        local blocktext = pandoc.utils.stringify(block)

        local admonition_type, raw_arg = blocktext:match("^:::{([%w%-_]+)}%s*([%S]*)")
        if admonition_type then
            i = i + 1
            local content_lines = {}
            while i <= #doc.blocks do
                local line = pandoc.utils.stringify(doc.blocks[i])
                if line:match("^:::%s*$") then
                    break
                else
                    table.insert(content_lines, line)
                end
                i = i + 1
            end

            -- Extract label (e.g., from :label: fig1)
            local label = extract_label(content_lines)

            -- Handle figure type separately
            if admonition_type == "figure" then
                if is_image_path(raw_arg) then
                    local caption = table.concat(content_lines, "\n")
                    local latex = render_image_figure(raw_arg, caption, label)
                    table.insert(newblocks, pandoc.RawBlock("latex", latex))
                else
                    -- Ignore #id style fallback completely, per user instruction
                    local latex = render_tcolorbox("figure", label, content_lines, article_doi)
                    table.insert(newblocks, pandoc.RawBlock("latex", latex))
                end
            else
                local latex = render_tcolorbox(admonition_type, label, content_lines, article_doi)
                table.insert(newblocks, pandoc.RawBlock("latex", latex))
            end
        else
            table.insert(newblocks, block)
        end
        i = i + 1
    end

    doc.blocks = newblocks
    return doc
end