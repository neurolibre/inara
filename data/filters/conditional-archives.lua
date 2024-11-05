function Meta(meta)
    -- Check if each DOI is present and not set to 'N/A'
    if meta.repository_doi and meta.repository_doi ~= 'N/A' then
      meta.include_repository_doi = true
    end
    if meta.data_doi and meta.data_doi ~= 'N/A' then
      meta.include_data_doi = true
    end
    if meta.book_doi and meta.book_doi ~= 'N/A' then
      meta.include_book_doi = true
    end
    if meta.docker_doi and meta.docker_doi ~= 'N/A' then
      meta.include_docker_doi = true
    end
    if meta.software_review_url and meta.software_review_url ~= 'N/A' then
      meta.include_software_review = true
    end
    if meta.book_exec_url and meta.book_exec_url ~= 'N/A' then
      meta.include_book_exec = true
    end
    return meta
end