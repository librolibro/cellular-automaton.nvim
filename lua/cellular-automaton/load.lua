local unpack = unpack or table.unpack

local M = {}

---@param name string
---@return boolean
local is_hl_group_a_spell = function(name)
  return name:find("^@?spell$") ~= nil or name:find("^@?nospell$") ~= nil
end

--- table<priority, {total: amount_of_hls_with_this_priority, current_offset: current_offset}>
---@alias _CA_PriorityCounters table<integer, {total: integer, current_offset: integer}>

---@param name string
---@param priority integer
---@param hl_groups CellularAutomatonHl[]
---@param priority_counters _CA_PriorityCounters
local new_hl_group = function(name, priority, hl_groups, priority_counters)
  hl_groups[#hl_groups + 1] = {
    name = name,
    priority = priority,
  }
  if priority_counters[priority] ~= nil then
    priority_counters[priority].total = priority_counters[priority].total + 1
  else
    priority_counters[priority] = { total = 1, current_offset = 0 }
  end
end

--- Get old-style most dominant highlight group (if old-style syntax
--- highlighting is using) and all extended marks (TS highlighting,
--- LSP semantic tokens and any other kinds of extmarks with hl group)
---@param buffer integer
---@param cell CellularAutomatonCell
---@param i integer line number (1-based)
---@param j integer column number (byte index, 1-based)
local get_dominant_hl_group = function(buffer, cell, i, j)
  if not vim.tbl_isempty(cell.hl_groups) then
    -- Cell was already initialized
    return
  end
  local hl_groups = cell.hl_groups
  local items = vim.inspect_pos(buffer, i - 1, j - 1, {
    syntax = true,
    treesitter = true,
    semantic_tokens = true,
    extmarks = true,
  })

  ---@type _CA_PriorityCounters
  local priority_counters = {}

  if not vim.tbl_isempty(items.syntax) then
    new_hl_group(
      assert(items.syntax[#items.syntax].hl_group),
      vim.highlight.priorities.syntax,
      hl_groups,
      priority_counters
    )
  end

  for _, item in ipairs(items.treesitter) do
    if not is_hl_group_a_spell(item.capture) then
      new_hl_group(
        assert(item.hl_group),
        tonumber(item.metadata.priority) or vim.highlight.priorities.treesitter,
        hl_groups,
        priority_counters
      )
    end
  end

  for _, item in ipairs(items.semantic_tokens) do
    new_hl_group(
      assert(item.opts.hl_group),
      item.opts.priority or vim.highlight.priorities.semantic_tokens,
      hl_groups,
      priority_counters
    )
  end

  for _, item in ipairs(items.extmarks) do
    new_hl_group(
      assert(item.opts.hl_group),
      item.opts.priority or vim.highlight.priorities.user,
      hl_groups,
      priority_counters
    )
  end

  -- Tricky part now ... We need to make all priority values unique and also save their order
  -- (see https://github.com/nvim-treesitter/nvim-treesitter-context/blob/e6cc783b74606d97ca9eff6494e3f5c2ca603a50/lua/treesitter-context/render.lua#L167
  -- if you want to know why it's important for extmark-based highlighting reproducing)

  for _, hl_group in ipairs(hl_groups) do
    local orig_priority = hl_group.priority
    for priority, prio in pairs(priority_counters) do
      if priority == orig_priority then
        hl_group.priority = hl_group.priority + prio.current_offset
        prio.current_offset = prio.current_offset + 1
      elseif priority < orig_priority then
        hl_group.priority = hl_group.priority + prio.total
      end
    end
  end
end

---@param translated string
---@param expected_len integer
---@return boolean
local strtrans_valid = function(translated, expected_len)
  local len = translated:len()
  if len ~= expected_len then
    return false
  end
  for i = 1, len do
    if vim.fn.strdisplaywidth(translated:sub(i, i), 0) ~= 1 then
      return false
    end
  end
  return true
end

--- Load base grid (replace multicell
--- symbols and tabs with replacers)
---@param window integer?
---@param buffer integer?
---@return CellularAutomatonGrid
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
  local window_width = wininfo.width - wininfo.textoff
  local first_lineno = wininfo.topline - 1

  local first_visible_virtcol = vim.fn.winsaveview().leftcol + 1
  local last_visible_virtcol = first_visible_virtcol + window_width

  -- initialize the grid
  ---@type CellularAutomatonGrid
  local grid = {}
  for i = 1, wininfo.height do
    grid[i] = {}
    for j = 1, window_width do
      grid[i][j] = { char = " ", hl_groups = {} }
    end
  end
  local data = vim.api.nvim_buf_get_lines(buffer, first_lineno, first_lineno + wininfo.height, false)

  -- update with buffer data
  for i, line in ipairs(data) do
    local jj = 0
    local col = 0
    local virtcol = 0
    local lineno = first_lineno + i

    ---@type CellularAutomatonCell
    local cell

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
        columns_occupied = #char
      end

      local is_tab = char == "\t"
      if is_tab or columns_occupied > 1 then
        if not is_tab then
          local translated_char = vim.fn.strtrans(char)
          if strtrans_valid(translated_char, columns_occupied) then
            -- for cindex = char_screen_col_start, char_screen_col_end do
            for cindex = 1, columns_occupied do
              if cindex < (first_visible_virtcol - char_screen_col_start + 1) then
                goto to_next_strtrans_char
              end
              jj = jj + 1
              if jj > window_width then
                goto to_next_line
              end
              cell = grid[i][jj]
              cell.char = translated_char:sub(cindex, cindex)
              cell.hl_groups[#cell.hl_groups + 1] = {
                name = "SpecialKey",
                priority = vim.highlight.priorities.user,
              }
              ::to_next_strtrans_char::
            end
            goto to_next_char
          end
        end
        local replacer = is_tab and " " or "@"
        local hl_group = is_tab and "" or "WarningMsg"
        for _ = math.max(first_visible_virtcol, char_screen_col_start), char_screen_col_end do
          jj = jj + 1
          if jj > window_width then
            goto to_next_line
          end
          cell = grid[i][jj]
          cell.char = replacer
          cell.hl_groups[#cell.hl_groups + 1] = {
            name = hl_group,
            priority = vim.highlight.priorities.user,
          }
        end
      else
        jj = jj + 1
        if jj > window_width then
          goto to_next_line
        end
        cell = grid[i][jj]
        cell.char = char
        if char ~= " " then
          get_dominant_hl_group(buffer, cell, lineno, virtcol)
        end
      end
      ::to_next_char::
    end
    ::to_next_line::
  end
  return grid
end

return M
