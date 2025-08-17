local M = {}

local LETTERS = "abcdefghijklmnopqrstuvwxyz"
local MAX_SPELL_CHECK_LENGTH = 8

---Generate candidates with Damerau-Levenshtein spell distance.
---
---@param input string
---@return string[]
local function generate_approximate_words(input)
  local prefixes = {}
  local len = #input

  for i = 1, len do
    local original = input:sub(i, i)
    for c in LETTERS:gmatch(".") do
      if c ~= original then
        -- replace
        table.insert(prefixes, input:sub(1, i - 1) .. c .. input:sub(i + 1))
      end

      -- insert
      table.insert(prefixes, input:sub(1, i) .. c .. input:sub(i + 1))
    end

    -- delete
    table.insert(prefixes, input:sub(1, i - 1) .. input:sub(i + 1))
  end

  -- exchange
  if len >= 2 then
    for i = 1, len - 1 do
      local a = input:sub(i, i)
      local b = input:sub(i + 1, i + 1)
      if a ~= b then
        local new_str
        if i + 2 > len then
          new_str = input:sub(1, i - 1) .. b .. a
        else
          new_str = input:sub(1, i - 1) .. b .. a .. input:sub(i + 2)
        end
        table.insert(prefixes, new_str)
      end
    end
  end

  local duplicated = {}
  local unique = {}
  for _, p in ipairs(prefixes) do
    if not duplicated[p] then
      duplicated[p] = true
      table.insert(unique, p)
    end
  end

  return unique
end

---Query candidates.
---
---@param dat datword.Dat
---@param input string
---@param limit number
---@param spellsuggest boolean
---@return string[]
function M.query(dat, input, limit, spellsuggest)
  local data = dat:bfs_search(input, limit)
  if #data >= limit then
    return data
  end

  if not spellsuggest then
    return data
  end

  -- Avoid too many unnecessary queries.
  if #input > MAX_SPELL_CHECK_LENGTH then
    return data
  end

  local approx_words = generate_approximate_words(input)

  local duplicated = {}
  for _, word in ipairs(data) do
    duplicated[word] = true
  end
  for _, approx_word in ipairs(approx_words) do
    for _, word in ipairs(dat:bfs_search(approx_word)) do
      if not duplicated[word] then
        duplicated[word] = true
        table.insert(data, word)
      end
    end
  end

  return data
end

return M
