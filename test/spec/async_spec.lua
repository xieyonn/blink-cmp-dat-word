local async = require("blink-cmp-dat-word.async")
local d = require("blink-cmp-dat-word.done")

describe("async test #async", function()
  local file
  local test_file
  local done = d.new()
  local test_content =
    "This is a test file content for async file operations.\n"

  before_each(function()
    done:reset()
    file, test_file = vim.uv.fs_mkstemp("/tmp/async_test.XXXXXX")
    assert.is_not_nil(test_file)
    assert.is_not_nil(file)
    if file then
      vim.uv.fs_close(file)
    end
  end)

  after_each(function()
    vim.uv.fs_unlink(test_file)
  end)

  it("should write and read a file asynchronously", function()
    async.run(function()
      local err_open, fd_write =
        async.await(vim.uv.fs_open, test_file, "w", 438)
      assert.is_nil(err_open)
      assert(fd_write, "Failed to open file for writing " .. test_file)

      local err_write, write_ok =
        async.await(vim.uv.fs_write, fd_write, test_content, -1)
      assert.is_nil(err_write)
      assert(write_ok == #test_content, "Failed to write full content")

      local err_close, ok = async.await(vim.uv.fs_close, fd_write)
      assert.is_nil(err_close)
      assert.is_true(ok)

      local err_open2, fd_read =
        async.await(vim.uv.fs_open, test_file, "r", 438)
      assert.is_nil(err_open2)
      assert(fd_read, "Failed to open file for reading")

      local err_stat, stat = async.await(vim.uv.fs_fstat, fd_read)
      assert.is_nil(err_stat)
      assert(stat.size > 0, "File should not be empty")

      local err_read, data = async.await(vim.uv.fs_read, fd_read, stat.size, 0)
      assert.is_nil(err_read)
      assert(data == test_content, "Read content is not equal to write content")

      local err_close2, ok2 = async.await(vim.uv.fs_close, fd_read)
      assert.is_nil(err_close2)
      assert.is_true(ok2)

      done:done()
    end)

    done:wait()
  end)

  it("should handle file not found errors", function()
    async.run(function()
      local res = async.await(vim.uv.fs_open, "non_existent_file.txt", "r", 438)
      assert.matches("ENOENT", res)

      done:done()
    end)
    done:wait()
  end)

  it("should handle concurrent file operations", function()
    async.run(function()
      local results = {}

      for i = 1, 3 do
        local filename = test_file .. "_" .. i
        local content = "File " .. i .. ": " .. test_content

        local err_open, fd = async.await(vim.uv.fs_open, filename, "w", 438)
        assert.is_nil(err_open)
        local err_write = async.await(vim.uv.fs_write, fd, content, -1)
        assert.is_nil(err_write)
        local err_close, ok = async.await(vim.uv.fs_close, fd)
        assert.is_nil(err_close)
        assert.is_true(ok)

        local err_open2, fd_read =
          async.await(vim.uv.fs_open, filename, "r", 438)
        assert.is_nil(err_open2)
        local err_stat, stat = async.await(vim.uv.fs_fstat, fd_read)
        assert.is_nil(err_stat)
        local err_read, data =
          async.await(vim.uv.fs_read, fd_read, stat.size, 0)
        assert.is_nil(err_read)
        local err_close2, ok2 = async.await(vim.uv.fs_close, fd_read)
        assert.is_nil(err_close2)
        assert.is_true(ok2)

        results[i] = { filename = filename, content = data }
        local err_unlink, ok3 = async.await(vim.uv.fs_unlink, filename)
        assert.is_nil(err_unlink)
        assert.is_true(ok3)
      end

      for i = 1, 3 do
        local expected = "File " .. i .. ": " .. test_content
        assert.are.equal(expected, results[i].content)
      end

      done:done()
    end)
    done:wait()
  end)

  it("should handle file append operations", function()
    local additional_content = "\nAdditional content appended!"

    async.run(function()
      local err_oepn, fd = async.await(vim.uv.fs_open, test_file, "w", 438)
      assert.is_nil(err_oepn)
      local err_write = async.await(vim.uv.fs_write, fd, test_content, -1)
      assert.is_nil(err_write)
      local err_close = async.await(vim.uv.fs_close, fd)
      assert.is_nil(err_close)

      local err_open2, fd_append =
        async.await(vim.uv.fs_open, test_file, "a", 438)
      assert.is_nil(err_open2)
      local err_write2 =
        async.await(vim.uv.fs_write, fd_append, additional_content, -1)
      assert.is_nil(err_write2)
      local err_close2 = async.await(vim.uv.fs_close, fd_append)
      assert.is_nil(err_close2)

      local err_read, fd_read = async.await(vim.uv.fs_open, test_file, "r", 438)
      assert.is_nil(err_read)
      local err_stat, stat = async.await(vim.uv.fs_fstat, fd_read)
      assert.is_nil(err_stat)
      local err_read2, data = async.await(vim.uv.fs_read, fd_read, stat.size, 0)
      assert.is_nil(err_read2)
      local err_close3, ok = async.await(vim.uv.fs_close, fd_read)
      assert.is_nil(err_close3)
      assert.is_true(ok)

      local expected = test_content .. additional_content
      assert.are.equal(expected, data)

      done:done()
    end)

    done:wait()
  end)

  it("no callback, fn has error", function()
    local fn = function()
      async.run(function()
        error("test error")
      end)
    end

    assert.has_error(fn)
  end)

  it("callback, fn return val", function()
    async.run(function()
      return "a", "b"
    end, function(err, a, b)
      assert.is_nil(err)
      assert.equal(a, "a")
      assert.equal(b, "b")

      done:done()
    end)

    done:wait()
  end)

  it("callback, fn has error", function()
    async.run(function()
      error("test error")
    end, function(err)
      assert.is_not_nil(err)
      done:done()
    end)
    done:wait()
  end)

  it("callback, async.schedule", function()
    async.schedule(function()
      return "a", "b"
    end, function(err, a, b)
      assert.is_nil(err)
      assert.equal("a", a)
      assert.equal("b", b)
      done:done()
    end)
    done:wait()
  end)
end)
