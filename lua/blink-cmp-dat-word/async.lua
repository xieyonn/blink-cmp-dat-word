---@class datword.async
local M = {}

local function resume_process(resume, co, callback, ...)
  local packed = vim.F.pack_len(...)
  local ok = packed[1]

  if ok == false then
    if callback then
      callback(packed[2])
      return
    end

    error(packed[2], 0)
  end

  if coroutine.status(co) == "dead" then
    if callback then
      callback(nil, unpack(packed, 2, packed.n))
    end
    return
  end

  local f = packed[2]
  if vim.is_callable(f) then
    packed[packed.n + 1] = resume
    packed.n = packed.n + 1
    f(unpack(packed, 3, packed.n))
  end

  return true
end

local function run(fn, schedule_wrap, callback)
  local co = coroutine.create(fn)

  local resume
  resume = function(...)
    resume_process(resume, co, callback, coroutine.resume(co, ...))
  end

  if schedule_wrap == true then
    resume = vim.schedule_wrap(resume)
  end

  resume()
end

---Call async function (last param accept a callable var) `async_func` in sync
---style, get rid of callback hell.
---
---@see datword.async.run
---@see datword.async.schedule
---
---@param async_func fun(...) Async func, last param is a callback function.
---@param ... any All values are passed to {async_func}.
---@return ... any The params of callback function.
function M.await(async_func, ...)
  vim.validate("async_func", async_func, "callable")

  if not coroutine.running() then
    error("async.await() must be called in a coroutine")
  end

  return coroutine.yield(async_func, ...)
end

---Run async function in sync style.
---
---Examples:
---
---```lua
---local callback = function(ok, err)
---  assert(ok)
---end
---
---local async = require("async")
---
---async(function()
---  local err, fd = async.await(vim.uv.fs_open, "filepath", "r", 438)
---  assert(not err, err)
---
---  local err, ok = async.await(vim.uv.fs_close, "filepath")
---  assert(not err, err)
---end, callback)
---```
---
---@async
---
---@param fn fun(): ... any The return values are passed to {callback} function.
---@param callback? fun(err: nil|string, ...) The {callback} runs after {fn} finish.
---If {fn} runs without any error, the `err` is `nil` and the rest are returned
---values of {fn}. If {fn} has any error, the `err` is is the error message.
function M.run(fn, callback)
  vim.validate("fn", fn, "callable")
  vim.validate("callback", callback, "callable", true)

  run(fn, false, callback)
end

---Same as `async.run`. Use `vim.schedule` in the callback of async function
---in {fn}.
---
---@see datword.async.run
---
---@param fn fun(): ... any The return values are passed to {callback} function.
---@param callback? fun(err: nil|string, ...) The {callback} runs after {fn} finish.
---If {fn} runs without any error, the `err` is `nil` and the rest are returned
---values of {fn}. If {fn} has any error, the `err` is is the error message.
function M.schedule(fn, callback)
  vim.validate("fn", fn, "callable")
  vim.validate("callback", callback, "callable", true)

  run(fn, true, callback)
end

return M
