local M = {}

--- Get milisecs from some
--- arbitray point in time
---@return number
M.time = function()
  -- return vim.fn.reltimefloat(vim.fn.reltime()) * 1000
  ---@diagnostic disable-next-line: undefined-field
  return vim.uv.now()
end

---@return integer
M.round = function(x)
  return math.floor(x + 0.5)
end

return M
