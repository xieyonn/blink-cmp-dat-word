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
end

local function get_max_items(config)
  if config and config.max_items then
    if type(config.max_items) == "function" then
      return config.max_items()
    elseif type(config.max_items) == "number" then
      return config.max_items
    end
  end

  return MAX_ITEMS
end

function source:get_completions(ctx, callback)
  local limit = get_max_items(self.config)
  local keyword = ctx:get_keyword()
  if #keyword == 0 then
    return
  end

  local words = {}
  local count = 0
  for _, dat in ipairs(self.dats) do
    for _, word in ipairs(dat:bfs_search(keyword, limit)) do
      table.insert(words, word)
      count = count + 1

      if count > limit then
        break
      end
    end
  end

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

return source
