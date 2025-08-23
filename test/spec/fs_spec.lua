local async = require("blink-cmp-dat-word.async")
local d = require("blink-cmp-dat-word.done")
local fs = require("blink-cmp-dat-word.fs")
local t = require("t")
local eq = t.eq
local neq = t.neq

local FILE_CHUNK_SIZE = 64 * 1024

describe("fs #fs", function()
  local create_file = function(filename, size)
    local fd = vim.uv.fs_open(filename, "w", tonumber("755", 8))
    assert(fd, string.format("open file %s failed", filename))
    for _ = 1, size do
      local ok = vim.uv.fs_write(fd, string.rep("a", 1024))
      assert(ok)
    end
    assert(vim.uv.fs_close(fd), string.format("close file %s failed", filename))
  end

  it("read_bigfile", function()
    local filename = os.tmpname()
    local done = d.new()
    local size = 300
    create_file(filename, size)

    async.run(function()
      local err, content = async.await(fs.read_bigfile, filename, {})
      eq(nil, err)
      eq(size * 1024, #content)

      done:done()
    end)

    done:wait()
    local ok = vim.uv.fs_unlink(filename)
    eq(true, ok)
  end)

  it("read_bigfile, file not exist", function()
    local filename = os.tmpname()
    local done = d.new()

    async.run(function()
      local err = async.await(fs.read_bigfile, filename .. "aa", {})
      neq(nil, err)
      done:done()
    end)

    done:wait()
    local ok = vim.uv.fs_unlink(filename)
    eq(true, ok)
  end)

  it("read_bigfile, file size < chunk_size", function()
    local filename = os.tmpname()
    local done = d.new()
    local size = FILE_CHUNK_SIZE / 1024 - 10
    create_file(filename, size)

    async.run(function()
      local err, content = async.await(fs.read_bigfile, filename, {})
      eq(nil, err)
      eq(size * 1024, #content)

      done:done()
    end)

    done:wait()
    local ok = vim.uv.fs_unlink(filename)
    eq(true, ok)
  end)

  it("write bigfile", function()
    local filename = os.tmpname()
    local done = d.new()
    local data = ""

    for _ = 1, 3000 do
      data = data .. string.rep("a", 1024)
    end

    async.run(function()
      local err = async.await(fs.write_bigfile, filename, data, nil)
      eq(nil, err)

      local fs_stat = vim.uv.fs_stat(filename)
      neq(nil, fs_stat)
      assert(fs_stat)

      eq(3000 * 1024, fs_stat.size)

      local err2 = vim.uv.fs_unlink(filename)
      eq(true, err2)

      done:done()
    end)

    done:wait()
  end)

  it("mkdir", function()
    local dir = vim.uv.fs_mkdtemp("/tmp/mkdir_XXXXXX")
    assert(dir, "create tmp dir fail")

    local tmpdir = vim.fs.joinpath(dir, "a/b/c")
    fs.mkdir(tmpdir, tonumber("755", 8))

    local fstat = vim.uv.fs_stat(vim.fs.joinpath(dir, "a/b"))
    neq(nil, fstat)

    vim.fn.delete(dir, "rf")
  end)
end)
