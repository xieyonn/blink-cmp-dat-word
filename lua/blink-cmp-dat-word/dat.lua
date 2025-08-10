---DAT Double Array Trie Tree.

local async = require("blink-cmp-dat-word.async")
local fs = require("blink-cmp-dat-word.fs")

local ffi = require("ffi")

local DAT_SIZE_DEFAULT = 4096
local RESIZE_SCALE_RATIO = 2
local RESIZE_SCALE_MAX = 65536
local RESIZE_SCALE_NEW = 256
local BATCH_INSERT = 1000

local MAGIC = "DAT1.0.0"
local FILE_HEADER =
  string.format("struct { char magic[%s]; uint32_t size; }", #MAGIC)
local FILE_MODE = 384
local DATA_FILE_DIR = vim.fn.stdpath("data")

local ROOT_INDEX = 1

---@class datword.Dat
---@field default_charset string[]
local DAT = {}
DAT.__index = DAT

-- [a-z], [A-Z], [-|'|&|.], [0-9]
DAT.default_charset = {}
for c = 97, 122 do
  table.insert(DAT.default_charset, string.char(c))
end
for c = 65, 90 do
  table.insert(DAT.default_charset, string.char(c))
end
for i = 0, 9 do
  table.insert(DAT.default_charset, tostring(i))
end
for _, v in ipairs({ "-", "'", "&", ".", "~" }) do
  table.insert(DAT.default_charset, v)
end

---@class datword.Opts
---@field charset? string[]
---@field data_file_dir? string DAT binary file dir.
local DEFAULT_OPTS = {
  charset = DAT.default_charset,
  data_file_dir = DATA_FILE_DIR,
}

---Init a DAT Tree.
---@param o? datword.Opts
---@return datword.Dat
function DAT.new(o)
  ---@class datword.Dat
  local dat = setmetatable({}, DAT)
  dat.size = DAT_SIZE_DEFAULT + 1
  dat.char_count = 0
  dat.word_count = 0

  dat.base = ffi.new("int32_t[?]", dat.size)
  dat.check = ffi.new("int32_t[?]", dat.size)
  for i = 0, dat.size do
    dat.base[i] = 0
    dat.check[i] = 0
  end
  dat.base[ROOT_INDEX] = 1
  dat.last_base = 1
  dat.children = {}
  dat:apply_opts(o)

  --TODO delete
  dat.find_base_times = 0
  dat.resize_times = 0
  dat.conflict = 0

  return dat
end

function DAT:apply_opts(o)
  self.opts = vim.tbl_deep_extend("force", DEFAULT_OPTS, o or {})

  self.char_to_index = {}
  for idx, char in ipairs(self.opts.charset) do
    self.char_to_index[char] = idx
  end
end

function DAT:_get_data_filepath(filepath)
  return vim.fs.joinpath(
    self.opts.data_file_dir,
    "blink-cmp-dat-word",
    vim.fn.sha256(filepath) .. ".dat"
  )
end

---Build DAT from a source file.
---
---@async
---
---@param filepath string
---@param callback? fun(err: nil|string)
function DAT:build(filepath, callback)
  vim.validate("filepath", filepath, "string")
  vim.validate("callback", callback, "callable", true)

  filepath = vim.fs.normalize(filepath)

  local f = function()
    local err, fstat = async.await(vim.uv.fs_stat, filepath)
    if err or not fstat then
      error(string.format("file %s is not exist", filepath))
    end

    local data_filepath = self:_get_data_filepath(filepath)
    local data_fstat
    err, data_fstat = async.await(vim.uv.fs_stat, data_filepath)

    if err or not data_fstat then
      err = async.await(self._build_from_file, self, filepath)
      assert(not err, err)
      return
    end

    if fstat.mtime.sec > data_fstat.mtime.sec then
      err = async.await(self._build_from_file, self, filepath)
      assert(not err, err)
      return
    end

    --load data file
    local ok
    err, ok = async.await(self.load_datafile, self, data_filepath)
    if err then
      error(
        string.format(
          "[DatWord] load data file %s fail, err: %s",
          data_filepath,
          err
        )
      )
    end

    if ok then
      return
    end

    err = async.await(self._build_from_file, self, filepath)
    assert(not err, err)
  end

  async.schedule(f, callback)
end

function DAT:_build_from_file(filepath, callback)
  async.schedule(function()
    local err, data = async.await(fs.read_bigfile, filepath, nil)
    if err then
      error(err)
    end

    if #data == 0 then
      return
    end

    local words = {}
    for word in vim.gsplit(data, "\r?\n", { trimempty = true }) do
      if word ~= "" then
        table.insert(words, word)
      end
    end

    local do_insert = function(word)
      self:_insert(word)
    end
    async.await(self._batch, words, BATCH_INSERT, do_insert)

    if self.size == 0 then
      return
    end

    err = async.await(self.save, self, self:_get_data_filepath(filepath))
    if err then
      error(err)
    end
  end, callback)
end

---Batch process a table variable {tb}, handling {batch_size} elements at a time
---using `vim.schedule` for asynchronous execution.
---
---@async
---
---@generic T
---@param tb T[]
---@param batch_size integer
---@param handle fun(item: T)
---@param callback fun() called when all done.
function DAT._batch(tb, batch_size, handle, callback)
  local length = #tb

  local index = 1
  local do_handle
  do_handle = function()
    if index > length then
      callback()
      return
    end

    for i = index, math.min(length, index + batch_size - 1) do
      handle(tb[i])
    end

    index = index + batch_size
    vim.schedule(do_handle)
  end

  do_handle()
end

---Load DAT from data file.
---@async
---
---@param filepath string
---@param callback? fun(err: nil|string, ok: boolean)
function DAT:load_datafile(filepath, callback)
  vim.validate("filepath", filepath, "string")
  vim.validate("callback", callback, "callable", true)

  async.run(function()
    local err, data = async.await(fs.read_bigfile, filepath, nil)
    if err or #data == 0 then
      --cache not exist
      return false
    end

    local header_size = ffi.sizeof(FILE_HEADER)
    local header_buf = data:sub(1, header_size)
    if not header_buf or #header_buf < header_size then
      --not a cache file
      return false
    end

    ---@type table<string, any>
    local header = ffi.cast(string.format("%s*", FILE_HEADER), header_buf)
    if ffi.string(header.magic, #MAGIC) ~= MAGIC then
      --version not match
      return false
    end

    local size = header.size
    self.size = size
    self.base = ffi.new("int32_t[?]", size)
    self.check = ffi.new("int32_t[?]", size)

    local arr_size = ffi.sizeof("int32_t") * size
    ffi.copy(
      self.base,
      data:sub(header_size + 1, header_size + arr_size),
      arr_size
    )
    ffi.copy(
      self.check,
      data:sub(header_size + 1 + arr_size, header_size + arr_size * 2),
      arr_size
    )

    return true
  end, callback)
end

---Resize DAT tree.
---@param required_pos integer new required position.
function DAT:_resize(required_pos)
  if required_pos < self.size then
    return
  end

  local new_size = math.max(
    math.floor(self.size * RESIZE_SCALE_RATIO),
    required_pos + RESIZE_SCALE_NEW,
    self.size + #self.opts.charset * 4
  )
  new_size = math.min(new_size, self.size + RESIZE_SCALE_MAX)

  local new_base = ffi.new("int32_t[?]", new_size)
  local new_check = ffi.new("int32_t[?]", new_size)

  ffi.copy(new_base, self.base, ffi.sizeof("int32_t") * self.size)
  ffi.copy(new_check, self.check, ffi.sizeof("int32_t") * self.size)

  for i = self.size, new_size - 1 do
    new_base[i] = 0
    new_check[i] = 0
  end

  self.resize_times = self.resize_times + 1

  self.base = new_base
  self.check = new_check
  self.size = new_size
end

---Find new base value.
---@param children integer[]
---@return integer
function DAT:_find_base(children)
  local max_child = 0
  for _, c in ipairs(children) do
    max_child = math.max(max_child, c)
  end

  local start = math.max(1, self.last_base - #self.opts.charset)
  local step = math.max(1, math.floor(math.sqrt(#children)))

  while true do
    local ok = true

    self.find_base_times = self.find_base_times + 1
    local pos_max = start + max_child
    if pos_max >= self.size then
      self:_resize(pos_max)
    end

    if self.check[pos_max] ~= 0 then
      ok = false
    else
      local children_length = #children
      for i = 1, children_length, step do
        local pos = start + children[i]
        if pos >= self.size then
          self:_resize(pos)
        end
        if self.check[pos] ~= 0 then
          ok = false
          break
        end
      end
    end

    if ok and step > 1 then
      for _, c in ipairs(children) do
        if self.check[start + c] ~= 0 then
          ok = false
          break
        end
      end
    end

    if ok then
      self.last_base = start
      return start
    end

    start = start + step
    if start > self.size * 0.95 then
      self:_resize(math.floor(self.size * RESIZE_SCALE_RATIO) + max_child)
    end
  end
end

---Insert a word.
---@param word string
function DAT:_insert(word)
  vim.validate("word", word, "string")
  if #word == 0 then
    return
  end

  local s = ROOT_INDEX
  local word_length = #word
  for i = 1, word_length do
    local char = word:sub(i, i)
    local c = self.char_to_index[char]
    if not c then
      return
    end

    local s_base = math.abs(self.base[s])
    local t = s_base + c

    if t >= self.size then
      self:_resize(t)
    end

    --conflict
    if self.check[t] ~= 0 and self.check[t] ~= s then
      self.conflict = self.conflict + 1
      --find children nodes of s
      local children = self.children[s] or {}
      table.insert(children, c)

      local new_base = self:_find_base(children)

      if self.base[s] < 0 then
        self.base[s] = -new_base
      else
        self.base[s] = new_base
      end
      t = new_base + c

      --move all children nodes exclude current node(NOT inserted yet)
      table.remove(children)
      for _, child_char in ipairs(children) do
        local old_t = s_base + child_char
        local new_t = new_base + child_char

        if new_t >= self.size then
          self:_resize(new_t)
        end

        self.base[new_t] = self.base[old_t]
        self.check[new_t] = self.check[old_t]

        self.base[old_t] = 0
        self.check[old_t] = 0

        if self.children[old_t] then
          self.children[new_t] = self.children[old_t]
          self.children[old_t] = {}
        end

        -- update grand children check value to new_pos
        local child_base = math.abs(self.base[new_t])
        if child_base > 0 then
          for gc = 1, #self.opts.charset do
            local gc_pos = child_base + gc
            if gc_pos < self.size and self.check[gc_pos] == old_t then
              self.check[gc_pos] = new_t
            end
          end
        end
      end
    end

    --insert new char
    if self.check[t] == 0 then
      self.check[t] = s
      self.base[t] = 1

      self.char_count = self.char_count + 1
      if not self.children[s] then
        self.children[s] = {}
      end
      table.insert(self.children[s], c)
    end

    s = t
  end

  --leaf node use nagetive value.
  self.base[s] = -math.abs(self.base[s])
  self.word_count = self.word_count + 1
end

function DAT:_compact()
  local size = self.size
  for i = size - 1, 0, -1 do
    if self.check[i] ~= 0 then
      size = i
      break
    end
  end

  size = size + 1
  local base = ffi.new("int32_t[?]", size)
  local check = ffi.new("int32_t[?]", size)
  for i = 0, size - 1 do
    base[i] = 0
    check[i] = 0
  end
  ffi.copy(base, self.base, ffi.sizeof("int32_t") * size)
  ffi.copy(check, self.check, ffi.sizeof("int32_t") * size)
  self.base = base
  self.check = check
  self.size = size
end

---BFS search, used in completion.
---@param prefix string
---@param limit? integer default 20.
---@return string[]
function DAT:bfs_search(prefix, limit)
  vim.validate("prefix", prefix, "string")
  vim.validate("limit", limit, "number", true)

  if #prefix == 0 then
    error("[DatWord] prefix should not be empty")
  end

  limit = limit or 20
  local pos = ROOT_INDEX
  local results = {}
  local prefix_length = #prefix

  for i = 1, prefix_length do
    local char = prefix:sub(i, i)
    local c = self.char_to_index[char]
    if not c then
      return results
    end

    local parent = pos
    pos = math.abs(self.base[pos]) + c
    if pos >= self.size or self.check[pos] ~= parent then
      return results
    end
  end

  local queue = { { node = pos, path = prefix } }
  while #queue > 0 and #results < limit do
    local current = table.remove(queue, 1)
    local node_idx = current.node
    local path = current.path

    if self.base[node_idx] < 0 then
      table.insert(results, path)
    end

    local base = math.abs(self.base[node_idx])
    for char_idx = 1, #self.opts.charset do
      local next_pos = base + char_idx

      if next_pos < self.size and self.check[next_pos] == node_idx then
        table.insert(queue, {
          node = next_pos,
          path = path .. self.opts.charset[char_idx],
        })
      end
    end
  end

  return results
end

---Check word is in DAT tree.
---@param word string
---@return boolean
function DAT:contains(word)
  vim.validate("word", word, "string")

  if #word == 0 then
    return false
  end

  local node = ROOT_INDEX
  local word_length = #word

  for i = 1, word_length do
    local char = word:sub(i, i)
    local c = self.char_to_index[char]

    if not c then
      return false
    end

    local next_pos = math.abs(self.base[node]) + c

    if next_pos >= self.size then
      return false
    end

    if self.check[next_pos] ~= node then
      return false
    end

    node = next_pos
  end

  return self.base[node] < 0
end

---Save DAT to file.
---@async
---
---@param filepath string filepath
---@param callback? fun(err: nil|string)
function DAT:save(filepath, callback)
  vim.validate("filepath", filepath, "string")
  vim.validate("callback", callback, "callable", true)

  self:_compact()

  fs.mkdir(filepath, tonumber("755", 8))
  async.schedule(function()
    local err, fd = async.await(vim.uv.fs_open, filepath, "w", FILE_MODE)
    if err or not fd then
      error(
        string.format("[DatWord] Open file %s fail, err: %s", filepath, err)
      )
    end

    local data = ""
    local header = ffi.new(FILE_HEADER, { magic = MAGIC, size = self.size })

    data = data .. ffi.string(header, ffi.sizeof(header))
    data = data .. ffi.string(self.base, ffi.sizeof("int32_t") * self.size)
    data = data .. ffi.string(self.check, ffi.sizeof("int32_t") * self.size)

    err = async.await(fs.write_bigfile, filepath, data, nil)
    if err then
      error(
        string.format("[DatWord] Write file %s fail, err: %s", filepath, err)
      )
    end

    err = async.await(vim.uv.fs_close, fd)
    if err then
      error(
        string.format("[DatWord] Close file %s fail, err: %s", filepath, err)
      )
    end
  end, callback)
end

function DAT:density()
  local count = 0
  for i = 1, self.size do
    if self.check[i] ~= 0 then
      count = count + 1
    end
  end

  return string.format("%.2f%%", (count / self.size) * 100)
end

return DAT
