function Meta(meta)
    if meta.draft and meta.draft ~= '' then
        print("Draft mode, skipping conditional archive rules.")
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
            
            -- Debug: Print detailed information about the field
            print("=== DEBUG: " .. field_name .. " ===")
            print("Field exists:", field ~= nil)
            
            if field then
                print("Field type:", type(field))
                
                if type(field) == "table" then
                    print("Field is table with length:", #field)
                    for i, v in pairs(field) do
                        print("  Index " .. tostring(i) .. ":", type(v), v)
                        if type(v) == "table" and v.text then
                            print("    v.text:", v.text)
                        end
                    end
                elseif type(field) == "string" then
                    print("Field string value:", field)
                else
                    print("Field value:", tostring(field))
                end
            else
                print("Field is nil")
            end
            
            -- Original condition check
            print("Original condition result:", field and type(field[1]) == "table" and field[1].text and field[1].text ~= 'N/A')
            
            -- Try alternative access patterns
            local value = nil
            if field then
                if type(field) == "string" then
                    value = field
                elseif type(field) == "table" and field[1] and type(field[1]) == "table" and field[1].text then
                    value = field[1].text
                elseif type(field) == "table" and field.text then
                    value = field.text
                elseif type(field) == "table" and field[1] then
                    -- Handle Pandoc Str objects
                    value = pandoc.utils.stringify(field[1])
                end
            end
            
            print("Extracted value:", value)
            print("========================")
            
            if value and value ~= 'N/A' and value ~= '' then
                meta[include_name] = true
                print("Including " .. field_name)
            else
                print("NOT including " .. field_name .. " (value: " .. tostring(value) .. ")")
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