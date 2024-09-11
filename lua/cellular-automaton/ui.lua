local M = {}

-- NOTE: When nested animations will
--   be supported make a table of these

--- Number of floating window for animation (if present)
---
---@type integer?
local window_id = nil

---@type Buffers?
local buffers = nil

local namespace = vim.api.nvim_create_namespace("cellular-automaton")

-- Each frame is rendered in different buffer to avoid flickering
-- caused by lack of higliths right after setting the buffer data.
-- Thus we are switching between two buffers throughtout the animation
---@type fun():integer
local get_buffer = (function()
  local count = 0
  return function()
    count = count + 1
    return buffers--[[@as Buffers]][count % 2 + 1]
  end
end)()

--- Create new floating window and
--- buffers for cellular automaton
---@param host_window integer?
---@return integer
---@return Buffers
M.open_window = function(host_window)
  if host_window == nil or host_window == 0 then
    host_window = vim.api.nvim_get_current_win()
  end

  buffers = {
    vim.api.nvim_create_buf(false, true),
    vim.api.nvim_create_buf(false, true),
  }
  local buffnr = get_buffer()
  local wininfo = vim.fn.getwininfo(host_window)[1]
  window_id = vim.api.nvim_open_win(buffnr, true, {
    relative = "win",
    width = vim.api.nvim_win_get_width(host_window),
    height = wininfo.height,
    border = "none",
    row = 0,
    col = 0,
  })

  vim.wo[window_id].relativenumber = false
  if wininfo.textoff == 0 then
    vim.wo[window_id].number = false
    vim.wo[window_id].signcolumn = "no"
    vim.wo[window_id].foldcolumn = "0"
  else
    -- Reproducing host_window's textoff
    -- using big fixed 'nuw', 'scl' and 'fdc'
    local textoff_left = wininfo.textoff

    local nuw_limit = 20
    local calc_nuw = tostring(wininfo.height):len() + 1
    assert(calc_nuw <= nuw_limit)

    if textoff_left >= calc_nuw then
      ---@type integer?
      local nuw = nil
      if textoff_left >= nuw_limit then
        nuw = nuw_limit
      elseif textoff_left >= calc_nuw then
        nuw = textoff_left
      else
        vim.wo[window_id].number = false
      end
      if nuw then
        vim.wo[window_id].number = true
        vim.wo[window_id].numberwidth = nuw
        textoff_left = textoff_left - nuw
      end
    end

    if textoff_left > 0 then
      local scl_width = math.min(textoff_left, 9 * 2)
      if math.fmod(scl_width, 2) == 1 then
        scl_width = scl_width - 1
      end
      vim.wo[window_id].signcolumn = string.format("yes:%d", scl_width / 2)
      textoff_left = textoff_left - scl_width
    end

    if textoff_left > 0 then
      local fdc_width = math.min(textoff_left, 9)
      vim.wo[window_id].foldcolumn = tostring(fdc_width)
      textoff_left = textoff_left - fdc_width
    end

    if textoff_left > 0 then
      error(string.format("textoff_left=%d (textoff=%d)", textoff_left, wininfo.textoff))
    end
  end

  vim.wo[window_id].winhl = "Normal:CellularAutomatonNormal"
  vim.wo[window_id].list = false
  return window_id, buffers
end

---@param grid CellularAutomatonGrid
M.render_frame = function(grid)
  -- quit if animation already interrupted
  if window_id == nil or not vim.api.nvim_win_is_valid(window_id) then
    return
  end
  local buffnr = get_buffer()
  -- update data
  local lines = {}
  for _, row in ipairs(grid) do
    local chars = {}
    for _, cell in ipairs(row) do
      table.insert(chars, cell.char)
    end
    table.insert(lines, table.concat(chars, ""))
  end
  vim.api.nvim_buf_set_lines(buffnr, 0, vim.api.nvim_win_get_height(window_id), false, lines)
  -- update highlights
  vim.api.nvim_buf_clear_namespace(buffnr, namespace, 0, -1)
  for i, row in ipairs(grid) do
    local offset = 0
    for j, cell in ipairs(row) do
      local char_len = string.len(cell.char)
      local col_start = j - 1 + offset
      if cell.hl_group and cell.hl_group ~= "" then
        vim.api.nvim_buf_add_highlight(buffnr, namespace, cell.hl_group, i - 1, col_start, col_start + char_len)
      end
      if char_len > 1 then
        offset = offset + char_len - 1
      end
    end
  end
  -- swap buffers
  vim.api.nvim_win_set_buf(window_id, buffnr)
end

M.clean = function()
  if buffers then
    for _, buffnr in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buffnr) then
        vim.api.nvim_buf_delete(buffnr, { force = true })
      end
    end
    buffers = nil
  end
  window_id = nil
end

return M
