--- Removes and alters metadata for draft output
function Meta (meta)
  if meta.draft and meta.draft ~= '' then
    meta.article.doi = '10.xxxxxx/draft'
    meta.article.issue = '0'
    meta.article.volume = '0'
    meta.published = 'unpublished'
    meta.published_parts = os.date('*t')
    meta.data_doi = '10.5281/zenodo.xxxxxx'
    meta.book_doi = '10.5281/zenodo.xxxxxx'  
    meta.docker_doi = '10.xxxxxx/draft'
    meta.repository_doi = '10.xxxxxx/draft'
    meta.software_review = 'https://github.com/neurolibre/neurolibre-reviews'
    meta.book_exec = 'https://preprint.neurolibre.org'
    return meta
  end
end