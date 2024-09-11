local unpack = unpack or table.unpack

local M = {}

local get_dominant_hl_group = function(buffer, i, j)
  local captures = vim.treesitter.get_captures_at_pos(buffer, i - 1, j - 1)
  for c = #captures, 1, -1 do
    if captures[c].capture ~= "spell" and captures[c].capture ~= "@spell" then
      return "@" .. captures[c].capture
    end
  end
  return ""
end

---Load base grid (replace multicell
---symbols and tabs with replacers)
---@param window integer?
---@param buffer integer?
---@return { char: string, hl_group: string}[][]
M.load_base_grid = function(window, buffer)
  if window == nil or window == 0 then
    -- NOTE: virtcol call with *winid*
    --   arg == 0 always returns zeros
    window = vim.api.nvim_get_current_win()
  end
  if buffer == nil or buffer == 0 then
    buffer = vim.api.nvim_get_current_buf()
  end

  local wininfo = vim.fn.getwininfo(window)[1]
  local window_width = vim.api.nvim_win_get_width(window) - wininfo.textoff
  local first_lineno = wininfo.topline - 1

  local first_visible_virtcol = vim.fn.winsaveview().leftcol + 1
  local last_visible_virtcol = first_visible_virtcol + window_width

  -- initialize the grid
  ---@type {char: string, hl_group: string}[][]
  local grid = {}
  for i = 1, vim.api.nvim_win_get_height(window) do
    grid[i] = {}
    for j = 1, window_width do
      grid[i][j] = { char = " ", hl_group = "" }
    end
  end
  local data = vim.api.nvim_buf_get_lines(buffer, first_lineno, first_lineno + wininfo.height, false)

  -- update with buffer data
  for i, line in ipairs(data) do
    local jj = 0
    local col = 0
    local virtcol = 0
    local lineno = first_lineno + i

    ---@type integer
    local char_screen_col_start

    ---@type integer
    local char_screen_col_end

    while true do
      col = col + 1
      virtcol = virtcol + 1
      char_screen_col_start, char_screen_col_end = unpack(vim.fn.virtcol({ lineno, virtcol }, 1, window))
      if char_screen_col_start == 0 and char_screen_col_end == 0 or char_screen_col_start > last_visible_virtcol then
        break
      end

      -- TODO: Make 2 strcharpart() calls (with *skipcc* and without it)
      --   in order to remove all non-leading VS-15/VS-16 chars?
      ---@type string
      local char = vim.fn.strcharpart(line, col - 1, 1, 1)
      if char == "" then
        break
      end
      virtcol = virtcol + #char - 1

      if char_screen_col_end < first_visible_virtcol then
        goto to_next_char
      end
      local columns_occupied = char_screen_col_end - char_screen_col_start + 1
      if
        #char == 3
        and char:byte(1) == 0XEF
        and char:byte(2) == 0xB8
        -- VS-15 (0xFE0E, ef b8 8e in UTF-8)
        -- VS-16 (0xFE0F, ef b8 8f in UTF-8)
        and (char:byte(3) == 0x8E or char:byte(3) == 0x8F)
      then
        -- NOTE: it's better to replace these here because once one
        --   of then will stay after another symbol its width will
        --   become to zero and line will become shorter
        char = " "
      end

      local is_tab = char == "\t"
      if is_tab or columns_occupied > 1 then
        local replacer = is_tab and " " or "@"
        local hl_group = is_tab and "" or "WarningMsg"
        for _ = math.max(first_visible_virtcol, char_screen_col_start), char_screen_col_end do
          jj = jj + 1
          if jj > window_width then
            goto to_next_line
          end
          grid[i][jj].char = replacer
          grid[i][jj].hl_group = hl_group
        end
      else
        jj = jj + 1
        if jj > window_width then
          goto to_next_line
        end
        grid[i][jj].char = char
        if char ~= " " then
          grid[i][jj].hl_group = get_dominant_hl_group(buffer, lineno, virtcol)
        end
      end
      ::to_next_char::
    end
    ::to_next_line::
  end
  return grid
end

return M
