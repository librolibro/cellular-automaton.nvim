---@alias _CA_Buffers [integer, integer]

--- Highlight group parameters (needed for
--- proper 'nvim_buf_set_extmark()' call)
---
---@class CellularAutomatonHl
---
--- Name of the highlight group
---@field name string
---
--- Highlight group priority (see
--- 'vim.highlight.priorities' for default values)
---@field priority integer
---
--- TODO: Need to add 'source' field?
--- TODO: Add 'conceal' field when
---   conceal will be supported

--- Single cellular automaton's cell
---
---@class CellularAutomatonCell
---
--- Char representing one cell
--- NOTE: it always occupies one virtual column
---   but may consist of several bytes (maybe
---   composing characters as well)
---@field char string
---
--- Highlight group for cell (usually requested via
--- 'inspect_pos()') (might be empty if no highlights needed)
---@field hl_groups CellularAutomatonHl[]

--- Cellular automaton's (and animation's) common configuration
---
---@class CellularAutomatonConfig
---
--- Animation name
---@field name string
---
--- Frames per seconds for animation
---@field fps integer
---
--- (Optional) function for grid initialization
---@field init? fun(self: CellularAutomatonConfig, grid: CellularAutomatonCell[][])
---
--- Update function. Return true to notify that automaton
--- state has been changed and further processing needed
---@field update fun(self: CellularAutomatonConfig, grid: CellularAutomatonCell[][]):boolean
