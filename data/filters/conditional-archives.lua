function Meta(meta)
    if meta.draft and meta.draft ~= '' then
        meta.include_repository_doi = true
        meta.include_data_doi = true
        meta.include_book_doi = true
        meta.include_docker_doi = true
        meta.include_software_review = true
        meta.include_book_exec = true
    else    

        -- Helper function to check and set field
        local function check_and_set_field(field_name, include_name)
            local field = meta[field_name]
            print(field_name .. " value:", field and type(field[1]) == "table" and field[1].text or "nil")
            
            if field and type(field[1]) == "table" and field[1].text and field[1].text ~= 'N/A' then
                meta[include_name] = true
                print("Including " .. field_name)
            end
        end

        -- Check all fields
        check_and_set_field("repository_doi", "include_repository_doi")
        check_and_set_field("data_doi", "include_data_doi")
        check_and_set_field("book_doi", "include_book_doi")
        check_and_set_field("docker_doi", "include_docker_doi")
        check_and_set_field("software_review_url", "include_software_review")
        check_and_set_field("book_exec_url", "include_book_exec")
    end
    return meta
end