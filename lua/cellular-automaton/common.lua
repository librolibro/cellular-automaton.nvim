local M = {}

---@param winid integer
---@return boolean
M.is_floating = function(winid)
  return vim.api.nvim_win_get_config(winid).relative ~= ""
end

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

---@param cell CellularAutomatonCell
---@param ... string
---@return boolean
M.cell_hl_matches = function(cell, ...)
  for _, pattern in ipairs({ ... }) do
    for _, hl_group in ipairs(cell.hl_groups) do
      if hl_group.name:find(pattern) then
        return true
      end
    end
  end
  return false
end

return M
