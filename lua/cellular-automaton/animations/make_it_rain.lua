local cell_hl_matches = require("cellular-automaton.common").cell_hl_matches

---@class _CA_MakeItRainCell: CellularAutomatonCell
---@field disperse_direction? -1|1
---@field should_not_fall boolean
---@field processed boolean
---@field empty boolean

---@class _CA_MakeItRainGrid
---@field [integer] _CA_MakeItRainCell[]
---@field frame integer

---@alias _CA_ModifyCellFunc fun(cell: _CA_MakeItRainCell, i: integer, j: integer, rows: integer, cols: integer)

---@class _CA_MakeItRainConfig: CellularAutomatonConfig
---@field default_modify_cell_func _CA_ModifyCellFunc
---@field modify_cell nil|_CA_ModifyCellFunc
---@field side_noise boolean
---@field disperse_rate integer

---@param cell _CA_MakeItRainCell
local default_modify_cell_func = function(cell)
  if not cell.should_not_fall then
    cell.should_not_fall = cell_hl_matches(cell, "[cC]omment")
  end
end

---@type _CA_MakeItRainConfig
local M = {
  fps = 50,
  name = "",
  side_noise = true,
  disperse_rate = 3,
  modify_cell = default_modify_cell_func,
  default_modify_cell_func = default_modify_cell_func,
}

---@param cell _CA_MakeItRainCell
---@return boolean
local init_empty = function(cell)
  if cell.char ~= " " then
    return false
  end
  for _, hl_group in ipairs(cell.hl_groups) do
    local hl_id = vim.fn.synIDtrans(vim.fn.hlID(hl_group.name))
    if
      vim.fn.synIDattr(hl_id, "bg") ~= ""
      or vim.fn.synIDattr(hl_id, "underline") == "1"
      or vim.fn.synIDattr(hl_id, "undercurl") == "1"
      or vim.fn.synIDattr(hl_id, "underdouble") == "1"
      or vim.fn.synIDattr(hl_id, "underdotted") == "1"
      or vim.fn.synIDattr(hl_id, "underdashed") == "1"
      or vim.fn.synIDattr(hl_id, "strikethrough") == "1"
    then
      return false
    end
  end
  return true
end

---@param grid _CA_MakeItRainGrid
---@param x integer
---@param y integer
---@return boolean
local cell_empty = function(grid, x, y)
  return x > 0 and x <= #grid and y > 0 and y <= #grid[x] and grid[x][y].empty
end

---@param grid _CA_MakeItRainGrid
---@param x1 integer
---@param y1 integer
---@param x2 integer
---@param y2 integer
local swap_cells = function(grid, x1, y1, x2, y2)
  grid[x1][y1], grid[x2][y2] = grid[x2][y2], grid[x1][y1]
end

---@param grid _CA_MakeItRainGrid
function M:init(grid)
  grid.frame = 1
  local modify_cell_func = self.modify_cell
  local rows = #grid
  local cols = #grid[1]
  for i = 1, rows do
    for j = 1, cols do
      local cell = grid[i][j]
      cell.processed = false
      cell.empty = init_empty(cell)
      cell.should_not_fall = cell.empty
      if modify_cell_func then
        modify_cell_func(cell, i, j, rows, cols)
      end
    end
  end
end

---@param grid _CA_MakeItRainGrid
---@return boolean
function M:update(grid)
  grid.frame = grid.frame + 1
  local frame = grid.frame
  -- reset 'processed' flag
  for i = 1, #grid, 1 do
    for j = 1, #grid[i] do
      grid[i][j].processed = false
    end
  end
  local was_state_updated = false
  for x0 = #grid - 1, 1, -1 do
    for i = 1, #grid[x0] do
      -- iterate through grid from bottom
      -- to top using snake move
      -- >>>>>>>>>>>>
      -- ^<<<<<<<<<<<
      -- >>>>>>>>>>>^
      local y0
      if (frame + x0) % 2 == 0 then
        y0 = i
      else
        y0 = #grid[x0] + 1 - i
      end
      local cell = grid[x0][y0]

      -- skip comments or already proccessed cells
      if cell.empty or cell.should_not_fall or cell.processed == true then
        goto continue
      end

      cell.processed = true

      -- to introduce some randomness sometimes step aside
      if self.side_noise then
        local random = math.random()
        local side_step_probability = 0.05
        if random < side_step_probability then
          was_state_updated = true
          if cell_empty(grid, x0, y0 + 1) then
            swap_cells(grid, x0, y0, x0, y0 + 1)
          end
        elseif random < 2 * side_step_probability then
          was_state_updated = true
          if cell_empty(grid, x0, y0 - 1) then
            swap_cells(grid, x0, y0, x0, y0 - 1)
          end
        end
      end

      -- either go one down
      if cell_empty(grid, x0 + 1, y0) then
        swap_cells(grid, x0, y0, x0 + 1, y0)
        was_state_updated = true
      else
        -- or to the side
        local disperse_direction = cell.disperse_direction or ({ -1, 1 })[math.random(1, 2)]
        local last_pos = { x0, y0 }
        for d = 1, self.disperse_rate do
          local y = y0 + disperse_direction * d
          -- prevent teleportation
          if not cell_empty(grid, x0, y) then
            cell.disperse_direction = disperse_direction * -1
            break
          elseif last_pos[1] == x0 then
            swap_cells(grid, last_pos[1], last_pos[2], x0, y)
            was_state_updated = true
            last_pos = { x0, y }
          end
          if cell_empty(grid, x0 + 1, y) then
            swap_cells(grid, last_pos[1], last_pos[2], x0 + 1, y)
            was_state_updated = true
            last_pos = { x0 + 1, y }
          end
        end
      end
      ::continue::
    end
  end
  return was_state_updated
end

return M
