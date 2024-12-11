function Meta(meta)
    -- Check if each DOI is present and not set to 'N/A'
    print("Repository DOI value:", tostring(meta.repository_doi and meta.repository_doi.text or "nil"))
    if meta.repository_doi and meta.repository_doi.text ~= 'N/A' then
      meta.include_repository_doi = true
      print("Including repository DOI")
    end

    print("Data DOI value:", tostring(meta.data_doi and meta.data_doi.text or "nil"))
    if meta.data_doi and meta.data_doi.text ~= 'N/A' then
      meta.include_data_doi = true
      print("Including data DOI")
    end

    print("Book DOI value:", tostring(meta.book_doi and meta.book_doi.text or "nil"))
    if meta.book_doi and meta.book_doi.text ~= 'N/A' then
      meta.include_book_doi = true
      print("Including book DOI")
    end

    print("Docker DOI value:", tostring(meta.docker_doi and meta.docker_doi.text or "nil"))
    if meta.docker_doi and meta.docker_doi.text ~= 'N/A' then
      meta.include_docker_doi = true
      print("Including docker DOI")
    end

    print("Software review URL value:", tostring(meta.software_review_url and meta.software_review_url.text or "nil"))
    if meta.software_review_url and meta.software_review_url.text ~= 'N/A' then
      meta.include_software_review = true
      print("Including software review")
    end

    print("Book exec URL value:", tostring(meta.book_exec_url and meta.book_exec_url.text or "nil"))
    if meta.book_exec_url and meta.book_exec_url.text ~= 'N/A' then
      meta.include_book_exec = true
      print("Including book exec")
    end

    return meta
end