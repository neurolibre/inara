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

--- Removes and alters metadata for draft output
function Meta (meta)
  if meta.draft and meta.draft ~= '' then
    meta.article.doi = '10.xxxxxx/draft'
    meta.article.issue = '0'
    meta.article.volume = '0'
    meta.published = 'unpublished'
    meta.published_parts = os.date('*t')
    meta.author_number = CountAuthors(meta)
    return meta
  end
end