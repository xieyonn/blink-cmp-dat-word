local d = require("blink-cmp-dat-word.done")
local dattree = require("blink-cmp-dat-word.dat")
local t = require("t")
local eq = t.eq
local neq = t.neq

local words = {
  "a",
  "aa",
  "aa",
  "aab",
  "ab",
  "abc",
  "b",
  "be",
  "bef",
  "ccc",
}

describe("dat #dat", function()
  local build = function()
    local dat = dattree.new()

    for _, word in ipairs(words) do
      dat:_insert(word)
    end

    return dat
  end

  it("build tire tree", function()
    local dat = build()
    for _, word in ipairs(words) do
      eq(true, dat:contains(word))
    end

    eq(false, dat:contains("zzz"))
    eq(false, dat:contains("aaa"))
  end)

  it("completion", function()
    local dat = build()
    local completion = dat:bfs_search("aab", 20)
    eq(1, #completion)
    eq(completion[1], "aab")

    completion = dat:bfs_search("a", 20)
    eq(5, #completion)
  end)

  it("file serialize", function()
    local done = d.new()

    local dat = build()
    local filepath = os.tmpname()
    dat:save(filepath, function(err)
      eq(nil, err)
      done:done()
    end)
    done:wait()

    local file = vim.uv.fs_open(filepath, "r", 438)
    assert(file)
    neq(nil, file)
    local stat = vim.uv.fs_stat(filepath)
    assert(stat, "file exist")
    eq(true, stat.size > 0)
    local ok2 = vim.uv.fs_close(file)
    neq(nil, ok2)
    eq(true, ok2)

    done:reset()
    local dat2 = dattree.new()
    dat2:load_datafile(filepath, function(err, ok)
      eq(nil, err)
      eq(true, ok)
      done:done()
    end)
    done:wait()

    for _, word in ipairs(words) do
      eq(true, dat2:contains(word))
    end
    eq(false, dat2:contains("zzz"))

    local ok4 = vim.uv.fs_unlink(filepath)
    eq(true, ok4)
  end)

  it("build", function()
    local done = d.new()
    local dictfile = vim.fs.joinpath(vim.env.ROOT_DIR, "data/word.txt")

    local dat = dattree.new()
    dat:build(dictfile, true, function(err)
      eq(nil, err)

      done:done()
    end)

    done:wait()
  end)
end)
