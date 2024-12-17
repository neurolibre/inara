function Meta(meta)
    -- Check repository DOI
    print("Repository DOI value:", meta.repository_doi and type(meta.repository_doi[1]) == "table" and meta.repository_doi[1].text or "nil")
    if meta.repository_doi and type(meta.repository_doi[1]) == "table" and meta.repository_doi[1].text and meta.repository_doi[1].text ~= 'N/A' then
        meta.include_repository_doi = true
        print("Including repository DOI")
    end

    -- Check data DOI
    print("Data DOI value:", meta.data_doi and type(meta.data_doi[1]) == "table" and meta.data_doi[1].text or "nil")
    if meta.data_doi and type(meta.data_doi[1]) == "table" and meta.data_doi[1].text and meta.data_doi[1].text ~= 'N/A' then
        meta.include_data_doi = true
        print("Including data DOI")
    end

    -- Check book DOI
    print("Book DOI value:", meta.book_doi and type(meta.book_doi[1]) == "table" and meta.book_doi[1].text or "nil")
    if meta.book_doi and type(meta.book_doi[1]) == "table" and meta.book_doi[1].text and meta.book_doi[1].text ~= 'N/A' then
        meta.include_book_doi = true
        print("Including book DOI")
    end

    -- Check docker DOI
    print("Docker DOI value:", meta.docker_doi and type(meta.docker_doi[1]) == "table" and meta.docker_doi[1].text or "nil")
    if meta.docker_doi and type(meta.docker_doi[1]) == "table" and meta.docker_doi[1].text and meta.docker_doi[1].text ~= 'N/A' then
        meta.include_docker_doi = true
        print("Including docker DOI")
    end

    -- Check software review URL
    print("Software review URL value:", meta.software_review_url and type(meta.software_review_url[1]) == "table" and meta.software_review_url[1].text or "nil")
    if meta.software_review_url and type(meta.software_review_url[1]) == "table" and meta.software_review_url[1].text and meta.software_review_url[1].text ~= 'N/A' then
        meta.include_software_review = true
        print("Including software review")
    end

    -- Check book exec URL
    print("Book exec URL value:", meta.book_exec_url and type(meta.book_exec_url[1]) == "table" and meta.book_exec_url[1].text or "nil")
    if meta.book_exec_url and type(meta.book_exec_url[1]) == "table" and meta.book_exec_url[1].text and meta.book_exec_url[1].text ~= 'N/A' then
        meta.include_book_exec = true
        print("Including book exec")
    end

    return meta
end