local t = require("t")
local eq = t.eq
local neq = t.neq
local datword = require("blink-cmp-dat-word")

describe("query", function()
  it("prefix match", function()
    local source = datword.new({
      paths = { vim.fs.joinpath(vim.env["ROOT_DIR"], "data/word.txt") },
      spellsuggest = false,
    }, {
      max_items = 1,
    })

    vim.wait(100)

    local words = source:query("that")
    eq(1, #words)
    eq("that", words[1], words[1])
  end)

  it("spell suggest", function()
    local source = datword.new({
      paths = { vim.fs.joinpath(vim.env["ROOT_DIR"], "data/word.txt") },
      spellsuggest = true,
    }, {
      max_items = 1,
    })

    vim.wait(100)

    for _, word in ipairs({ "that", "htat", "thta", "taht" }) do
      local words = source:query(word)
      eq(1, #words)
      eq("that", words[1], words[1])
    end
  end)
end)
