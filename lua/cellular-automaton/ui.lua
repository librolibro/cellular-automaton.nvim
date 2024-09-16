local M = {}

---@param winid integer
---@param wininfo vim.fn.getwininfo.ret.item
local configure_window = function(winid, wininfo)
  vim.wo[winid].cursorline = false
  vim.wo[winid].colorcolumn = ""
  -- Reproducing host_window's textoff
  -- using big fixed 'nuw', 'scl' and 'fdc'
  vim.wo[winid].relativenumber = false
  if wininfo.textoff == 0 then
    vim.wo[winid].number = false
    vim.wo[winid].signcolumn = "no"
    vim.wo[winid].foldcolumn = "0"
  else
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
        vim.wo[winid].number = false
      end
      if nuw then
        vim.wo[winid].number = true
        vim.wo[winid].numberwidth = nuw
        textoff_left = textoff_left - nuw
      end
    end

    if textoff_left > 0 then
      local scl_width = math.min(textoff_left, 9 * 2)
      if math.fmod(scl_width, 2) == 1 then
        scl_width = scl_width - 1
      end
      vim.wo[winid].signcolumn = string.format("yes:%d", scl_width / 2)
      textoff_left = textoff_left - scl_width
    end

    if textoff_left > 0 then
      local fdc_width = math.min(textoff_left, 9)
      vim.wo[winid].foldcolumn = tostring(fdc_width)
      textoff_left = textoff_left - fdc_width
    end

    if textoff_left > 0 then
      error(string.format("textoff_left=%d (textoff=%d)", textoff_left, wininfo.textoff))
    end
  end

  vim.wo[winid].winhl = "Normal:CellularAutomatonNormal"
  vim.wo[winid].list = false
end

--- Create new floating window and
--- buffers for cellular automaton
---@param host_winid integer?
---@return integer
---@return integer[]
M.prepare_window_and_buffers = function(host_winid)
  if host_winid == nil or host_winid == 0 then
    host_winid = vim.api.nvim_get_current_win()
  end

  local buffers = {
    vim.api.nvim_create_buf(false, true),
    vim.api.nvim_create_buf(false, true),
  }
  -- make it always on top of the host window (when it's floating)
  local zindex = vim.api.nvim_win_get_config(host_winid).zindex
  if zindex ~= nil then
    zindex = zindex + 1
  end
  local wininfo = vim.fn.getwininfo(host_winid)[1]
  local winid = vim.api.nvim_open_win(buffers[1], true, {
    relative = "win",
    win = host_winid,
    width = wininfo.width,
    height = wininfo.height,
    border = "none",
    row = 0,
    col = 0,
    zindex = zindex,
  })

  local ok, err = pcall(configure_window, winid, wininfo)
  if not ok then
    M.clean(winid, buffers)
    error(err)
  end
  return winid, buffers
end

---@param grid CellularAutomatonCell[][]
---@param ctx CellularAutomatonContext
M.render_frame = function(grid, ctx)
  -- quit if animation already interrupted
  if ctx.interrupted or not vim.api.nvim_win_is_valid(ctx.winid) then
    return
  end
  local bufnr = ctx.next_bufnr()
  -- update data
  local lines = {}
  for _, row in ipairs(grid) do
    local chars = {}
    for _, cell in ipairs(row) do
      table.insert(chars, cell.char)
    end
    table.insert(lines, table.concat(chars, ""))
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, vim.api.nvim_win_get_height(ctx.winid), false, lines)
  -- update highlights
  vim.api.nvim_buf_clear_namespace(bufnr, ctx.hl_ns_id, 0, -1)
  for i, row in ipairs(grid) do
    local offset = 0
    for j, cell in ipairs(row) do
      local char_len = string.len(cell.char)
      local col_start = j - 1 + offset
      for _, hl_group in ipairs(cell.hl_groups) do
        vim.api.nvim_buf_set_extmark(bufnr, ctx.hl_ns_id, i - 1, col_start, {
          end_row = i - 1,
          end_col = col_start + char_len,
          priority = hl_group.priority,
          hl_group = hl_group.name,
          conceal = nil,
          spell = false,
        })
      end
      if char_len > 1 then
        offset = offset + char_len - 1
      end
    end
  end
  -- swap buffers
  vim.api.nvim_win_set_buf(ctx.winid, bufnr)
end

---@param winid integer
---@param buffers integer[]
M.clean = function(winid, buffers)
  for _, buffnr in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(buffnr) then
      vim.api.nvim_buf_delete(buffnr, { force = true })
    end
  end
  if vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_close(winid, true)
  end
end

return M
