--- Give the bibliography a heading when the paper does not.
--
-- citeproc drops the reference list into a `refs` Div wherever the paper puts
-- it, or at the end of the document if the paper says nothing. A submission
-- that never writes `# References` therefore ends with entries running straight
-- on from the last section -- in one real preprint, out of Acknowledgements --
-- with nothing to mark where the bibliography begins.
--
-- Add the heading in that case, and only in that case: a paper that already has
-- one must not get a second.
--
-- For JATS and docx the opposite is wanted; those formats strip the heading
-- again with remove-references-heading.lua, so this filter is registered only
-- for the formats that typeset a bibliography.

local stringify = pandoc.utils.stringify

local IDENTIFIER = 'references'
local TITLE = 'References'

--- Index of the citeproc bibliography in `blocks`, or nil.
local function bibliography_index (blocks)
  for i, block in ipairs(blocks) do
    if block.t == 'Div' and block.identifier == 'refs' then
      return i
    end
  end
  return nil
end

--- Does the paper already head its bibliography?
--
-- Matched on the rendered text as well as the identifier, because a heading
-- written in the paper may carry a different id, or none.
local function has_heading (blocks)
  for _, block in ipairs(blocks) do
    if block.t == 'Header' then
      if block.identifier == IDENTIFIER
        or stringify(block):lower():match '^%s*references%s*$'
      then
        return true
      end
    end
  end
  return false
end

function Pandoc (doc)
  local index = bibliography_index(doc.blocks)
  if not index or has_heading(doc.blocks) then
    return nil
  end

  local heading = pandoc.Header(
    1,
    pandoc.Inlines{pandoc.Str(TITLE)},
    pandoc.Attr(IDENTIFIER)
  )
  doc.blocks:insert(index, heading)
  io.stderr:write('[INFO] add-references-heading: added a References heading\n')
  return doc
end
