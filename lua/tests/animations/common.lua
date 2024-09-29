local assert = require("luassert")

local M = {}

---@param pattern string[]
---@return CellularAutomatonCell[][]
M.get_grid = function(pattern)
  ---@type CellularAutomatonCell[][]
  local grid = {}
  for _, line in ipairs(pattern) do
    local row = {}
    for i = 1, #line do
      local char = line:sub(i, i)
      ---@type CellularAutomatonCell
      local cell = { char = char, hl_groups = {} }
      if char == "#" then
        cell.hl_groups[#cell.hl_groups + 1] = {
          name = "@comment",
          priority = vim.highlight.priorities.user,
        }
      end
      table.insert(row, cell)
    end
    table.insert(grid, row)
  end
  return grid
end

---@param grid CellularAutomatonCell[][]
---@return string
local convert_grid_to_string = function(grid)
  local result = ""
  for _, row in ipairs(grid) do
    for _, cell in ipairs(row) do
      result = result .. cell.char
    end
    result = result .. "\n"
  end
  return string.sub(result, 1, -2)
end

---@param str string
---@return string
local replace_spaces = function(str)
  local result = ""
  for i = 1, #str do
    local char = string.sub(str, i, i)
    if char == " " then
      result = result .. "."
    else
      result = result .. char
    end
  end
  return result
end

---@param grid CellularAutomatonCell[][]
---@param pattern string[]
---@param error_msg? string
M.assert_grid_same = function(grid, pattern, error_msg)
  local got = "\n" .. convert_grid_to_string(grid) .. "\n"
  local expected = "\n" .. table.concat(pattern, "\n") .. "\n"
  assert.are.same(replace_spaces(expected), replace_spaces(got), error_msg)
end

---@param grid CellularAutomatonCell[][]
---@param pattern string[]
---@param error_msg? string
M.assert_grid_different = function(grid, pattern, error_msg)
  local got = "\n" .. convert_grid_to_string(grid) .. "\n"
  local expected = "\n" .. table.concat(pattern, "\n") .. "\n"
  assert.are.not_.same(replace_spaces(expected), replace_spaces(got), error_msg)
end

return M
