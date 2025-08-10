local async = require("blink-cmp-dat-word.async")

---@class datword.fs
local M = {}

local FILE_MODE = 384
local FILE_CHUNK_SIZE = 64 * 1024

---@class datword.fs.ReadBigfileOpts
---@field chunk_size? integer
---@field file_mode? integer

---Read a large file in chunks.
---
---@async
---
---@param filepath string
---@param opts? datword.fs.ReadBigfileOpts
---@param callback fun(err: nil|string, content: string)
function M.read_bigfile(filepath, opts, callback)
  vim.validate("filepath", filepath, "string")
  vim.validate("opts", opts, "table", true)
  vim.validate("callback", callback, "callable")

  local chunk_size = FILE_CHUNK_SIZE
  local file_mode = FILE_MODE
  if opts then
    if opts.chunk_size then
      chunk_size = opts.chunk_size
    end
    if opts.file_mode then
      file_mode = opts.file_mode
    end
  end

  if chunk_size < 0 then
    error("chunk_size should > 0")
  end

  local do_read = function()
    local content = ""

    local err, fd = async.await(vim.uv.fs_open, filepath, "r", file_mode)
    if not fd or err then
      error(string.format("open file %s fail", filepath))
    end

    local close_file = function()
      local ok
      err, ok = async.await(vim.uv.fs_close, fd)
      if ok == false or err then
        error(string.format("close file %s fail, err: %s", filepath, err))
      end
    end

    local stat
    err, stat = async.await(vim.uv.fs_fstat, fd)
    if not stat then
      close_file()
      error(string.format("file %s is not exist", filepath))
    end

    local filesize = stat.size
    if filesize <= 0 then
      return
    end

    local offset = 0
    while offset < filesize do
      local chunk
      err, chunk = async.await(vim.uv.fs_read, fd, chunk_size, offset)
      if err then
        close_file()
        error(
          string.format(
            "read file %s fail, offset: %s, chunk_size: %s",
            filepath,
            offset,
            chunk_size
          )
        )
      end

      content = content .. chunk
      offset = offset + chunk_size
    end

    close_file()

    return content
  end

  async.schedule(do_read, callback)
end

---@class datword.fs.WriteBigfileOpts
---@field chunk_size? integer
---@field file_mode? integer

---Write big file
---
---@param filepath string
---@param data string
---@param opts? datword.fs.WriteBigfileOpts
---@param callback fun(err: nil|string)
function M.write_bigfile(filepath, data, opts, callback)
  vim.validate("filepath", filepath, "string")
  vim.validate("data", data, "string")
  vim.validate("opts", opts, "table", true)
  vim.validate("callback", callback, "callable")

  local chunk_size = FILE_CHUNK_SIZE
  local file_mode = FILE_MODE
  if opts then
    if opts.chunk_size then
      chunk_size = opts.chunk_size
    end
    if opts.file_mode then
      file_mode = opts.file_mode
    end
  end

  if chunk_size < 0 then
    error("chunk_size should > 0")
  end

  local do_write = function()
    local err, fd = async.await(vim.uv.fs_open, filepath, "w", file_mode)
    if err or not fd then
      error(string.format("open file %s fail, err: %s", filepath, err))
    end

    local close_file = function()
      local ok
      err, ok = async.await(vim.uv.fs_close, fd)
      if ok == false or err then
        error(string.format("close file %s fail, err: %s", filepath, err))
      end
    end

    local offset = 0
    local length = #data

    while offset < length do
      local end_pos = math.min(offset + chunk_size, length)
      local chunk = data:sub(offset + 1, end_pos)

      local written
      err, written = async.await(vim.uv.fs_write, fd, chunk, offset)
      if err then
        close_file()
        error(
          string.format(
            "write file %s fail, offset: %s, err: %s",
            filepath,
            offset,
            err
          )
        )
      end
      offset = offset + written
    end

    close_file()
  end

  async.schedule(do_write, callback)
end

---Recursively create directories
---
---@param filepath string
---@param mode number
function M.mkdir(filepath, mode)
  vim.validate("filepath", filepath, "string")
  vim.validate("mode", mode, "number")

  local do_mkdir
  do_mkdir = function(path)
    local dirname = vim.fs.dirname(path)
    if dirname == nil then
      return
    end

    local fstat = vim.uv.fs_stat(dirname)
    if fstat and fstat.type == "directory" then
      return
    end

    do_mkdir(dirname)

    local ok = vim.uv.fs_mkdir(dirname, mode)
    if ok ~= true and ok:match("File exists") then
      return true
    elseif ok == false then
      error(string.format("mkdir %s failed: %s", dirname, tostring(ok)))
    end
  end

  do_mkdir(filepath)
end

return M
