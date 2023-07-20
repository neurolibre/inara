local function CountAuthors(elem)
  if elem.t == 'MetaList' and elem[1].t == 'MetaInlines' then
    local count = #elem
    return pandoc.MetaList({pandoc.MetaInlines(pandoc.SmallCaps({pandoc.Str(tostring(count))}))})
  end
end

--- Removes and alters metadata for draft output
function Meta (meta)
  if meta.draft and meta.draft ~= '' then
    meta.article.doi = '10.xxxxxx/draft'
    meta.article.issue = '0'
    meta.article.volume = '0'
    meta.published = 'unpublished'
    meta.published_parts = os.date('*t')
    meta.author_number = CountAuthors(meta.authors)
    return meta
  end
end