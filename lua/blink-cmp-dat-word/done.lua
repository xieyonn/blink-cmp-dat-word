---@class datword.Done
local M = {}
M.__index = M

function M.new()
  return setmetatable({
    _done = false,
  }, M)
end

---Wait for {time} in milliseconds until `done()` is called. Check {done}
---status every {interval} milliseconds.
---@param time? number default is 1000.
---@param interval? number default is {time} / 10.
function M:wait(time, interval)
  vim.validate("time", time, function()
    return time == nil or time > 0
  end, true, "time should > 0")
  vim.validate("interval", interval, "number", true)

  if time == nil then
    time = 1000
  end
  if interval == nil then
    interval = time / 10
  end

  vim.wait(time, function()
    return self._done
  end, interval)
end

---Mark done.
function M:done()
  self._done = true
end

---Mark reset.
function M:reset()
  self._done = false
end

return M
