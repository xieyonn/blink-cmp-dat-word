--- @module 'blink.cmp'
---
--- @class blink.cmp.Source
---
--- @class blink.cmp.Source.DatWord: blink.cmp.Source
--- @field opts blink.cmp.Source.DatWord.Opts
--- @field config table
--- @field dats datword.Dat[]
local source = {}
source.__index = source

local MAX_ITEMS = 20
local KIND = require("blink.cmp.types").CompletionItemKind.Text

local d = require("blink-cmp-dat-word.dat")

---@class blink.cmp.Source.DatWord.Opts
---@field data_file_dir string
---@field paths string[]
---@field max_items? number
---@field min_keyword_length? number
---@field build_command? string
local default_opts = {
  data_file_dir = vim.fn.stdpath("data"),
  paths = {},
}

---New Source.
---
---@param o? blink.cmp.Source.DatWord.Opts
---@param config table From `sources.providers.datword`.
function source.new(o, config)
  if not jit then
    error("blink-cmp-dat-word need jit support")
  end

  local s = setmetatable({}, source)
  s.opts = vim.tbl_deep_extend("force", default_opts, o or {})
  s.config = config
  s.dats = {}

  s.opts.max_items = s:get_config_by_key("max_items", MAX_ITEMS)
  s.opts.min_keyword_length = s:get_config_by_key("min_keyword_length", 1)

  s:init()

  return s
end

function source:init()
  if #self.opts.paths == 0 then
    return
  end

  self.dats = {}
  for i, path in ipairs(self.opts.paths) do
    local dat = d.new({ data_file_dir = self.opts.data_file_dir })
    self.dats[i] = dat

    dat:build(path)
  end

  if self.opts.build_command and self.opts.build_command ~= "" then
    self:register_cmd()
  end
end

function source:register_cmd()
  vim.api.nvim_create_user_command(self.opts.build_command, function(opts)
    local count = #self.opts.paths
    if count == 0 then
      vim.notify("[DatWord] source file paths is empty.")
      return
    end

    local done = 0
    local dats = {}
    local cb = function()
      done = done + 1
      if done == count then
        vim.notify("[DatWord] build words done.")
        self.dats = dats
      end
    end

    for i, path in ipairs(self.opts.paths) do
      local dat = d.new({ data_file_dir = self.opts.data_file_dir })
      dats[i] = dat

      dat:build(path, opts.bang, cb)
    end
  end, {
    desc = "build blink.cmp source datword",
    bang = true,
  })
end

function source:query_dat(keyword)
  local words = {}
  local duplicate = {}
  local count = 0
  for _, dat in ipairs(self.dats) do
    for _, word in ipairs(dat:bfs_search(keyword, self.opts.max_items)) do
      if not duplicate[word] then
        count = count + 1
        duplicate[word] = true
        table.insert(words, word)
      end

      if count >= self.opts.max_items then
        return words
      end
    end
  end

  return words
end

function source:get_completions(ctx, callback)
  local keyword = ctx:get_keyword()
  if #keyword < self.opts.min_keyword_length then
    callback({
      items = {},
      is_incomplete_backward = false,
      is_incomplete_forward = true,
    })
    return
  end

  local words = self:query_dat(keyword)

  --- @type lsp.CompletionItem[]
  local items = {}
  for _, word in ipairs(words) do
    local item = {
      label = word,
      kind = KIND,
    }
    table.insert(items, item)
  end

  callback({
    items = items,
    is_incomplete_backward = true,
    is_incomplete_forward = true,
  })
end

function source:get_config_by_key(key, default_value)
  if self.config == nil then
    return default_value
  end

  local val = self.config[key]
  if val then
    local v_type = type(val)
    if v_type == "function" then
      return val()
    else
      return val
    end
  end

  return default_value
end

return source
