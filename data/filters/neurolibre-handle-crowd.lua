local stringify = pandoc.utils.stringify

function CountAuthors(meta)
  if meta['author'] then
    -- Check if there is a single author or multiple authors
    if type(meta['author']) == 'table' then
      num_authors = #meta['author']
    else
      num_authors = 1
    end
  end
  return num_authors
end

function joinTableToString(table)
  -- Check if the table is empty
  if #table == 0 then
      return ""
  end
  
  -- Initialize an empty string to hold the joined elements
  local joinedString = stringify(table[1])
  
  -- Iterate over the elements of the table and concatenate them with commas and spaces
  for i = 2, #table do
      joinedString = joinedString .. ", " .. stringify(table[i])
  end
  
  return joinedString
end

--- Removes and alters metadata for draft output
function Meta (meta)
  
  local authors = meta['author']
  local authorString = ""
  for i, author in ipairs(authors) do
    if author['equal-contrib'] then
      authorString = authorString .. "*"
    end
    authorString = authorString .. "{\\Authfont " .. author.name .. "}"
    -- authorString = authorString .. author.name
    for j, affiliation in ipairs(author.affiliation) do
      authorString = authorString .. "\\textsuperscript{" .. affiliation .. "}"
      if j < #author.affiliation then
        authorString = authorString .. "\\textsuperscript{,}"
      end
    end
    if i < #authors then
      authorString = authorString .. ", "
    end
  end

  local affiliations = meta.affiliations
  local affiliationString = ""

  for i, aff in ipairs(affiliations) do
    -- affiliationString = affiliationString .. i .. tmp .. "\n"
    affiliationString = affiliationString .. " {\\bfseries " .. stringify(i) .. "}\\hspace{3pt}  " .. stringify(aff.name)
    -- if i < #affiliations then
    --   affiliationString = affiliationString .. "\n"
    -- end
  end

  meta.affiliationsList = pandoc.RawInline("latex",affiliationString)
  meta.authorsWithAffiliations = pandoc.RawInline("latex",authorString)

  -- Check if there are more than 10 authors
  meta.moreThanTenAuthors = #authors > 10
  meta.noMoreThanTenAuthors = #authors <= 10

  return meta
end