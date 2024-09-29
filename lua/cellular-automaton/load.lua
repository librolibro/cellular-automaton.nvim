local unpack = unpack or table.unpack

local M = {}

---@param name string
---@return boolean
local is_hl_group_a_spell = function(name)
  return name:find("^@?spell$") ~= nil or name:find("^@?nospell$") ~= nil
end

---@param hl_groups CellularAutomatonHl[]
---@return CellularAutomatonHl[]
local hl_groups_copy = function(hl_groups)
  local new_table = {}
  for i, hl in ipairs(hl_groups) do
    new_table[i] = {
      name = hl.name,
      priority = hl.priority,
    }
  end
  return new_table
end

---@class _CA_PCounter
---
--- Amount of highlight groups with this priority
---@field total integer
---
--- Current offset
---@field current_offset integer

---@alias _CA_PriorityCounters table<integer, _CA_PCounter>

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
---@param hl_groups CellularAutomatonHl[]
---@param i integer line number (1-based)
---@param j integer column number (byte index, 1-based)
local retrieve_hl_groups = function(buffer, hl_groups, i, j)
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

  -- Tricky part now ... We need to make all
  -- priority values unique and also save their
  -- order (see nvim-treesitter-context projects,
  -- lua/treesitter-context/render.lua#L167 if you want to know why
  -- it's important for extmark-based highlighting reproducing)

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

---@param cell CellularAutomatonCell
---@param char? string
local convert_to_nontext = function(cell, char)
  if char then
    cell.char = char
  end
  cell.hl_groups = {
    name = "NonText",
    priority = vim.highlight.priorities.syntax,
  }
end

---@param cell CellularAutomatonCell
local clear_cell = function(cell)
  cell.char = " "
  cell.hl_groups = {}
end

---@alias _lastline "lastline"|"truncate"|nil

---@param grid CellularAutomatonCell[][]
---@param lastline _lastline
---@param lastline_char string
---@param lines_wrapped integer
---@param textoff integer
local prepare_lastlines = function(
  grid,
  lastline,
  lastline_char,
  lines_wrapped,
  textoff
)
  local grid_height = #grid
  local grid_width = #grid[1]

  if not lastline then
    for row = grid_height - lines_wrapped, grid_height do
      convert_to_nontext(grid[row][1], lastline_char)
      for col = 2, grid_width do
        clear_cell(grid[row][col])
      end
    end
  elseif lastline == "lastline" then
    for col = grid_width, grid_width - math.min(grid_width, 3) + 1, -1 do
      convert_to_nontext(grid[grid_height][col], lastline_char)
    end
  else
    local chars_to_show = math.max(0, 3 - textoff)
    for col = 1, grid_width do
      if col <= chars_to_show then
        convert_to_nontext(grid[grid_height][col], lastline_char)
      else
        clear_cell(grid[grid_height][col])
      end
    end
  end
end

--- Load base grid (replace multicell
--- symbols and tabs with replacers)
---@param window integer?
---@param buffer integer?
---@return CellularAutomatonCell[][]
M.load_base_grid = function(window, buffer)
  if window == nil or window == 0 then
    -- NOTE: virtcol call with *winid*
    --   arg == 0 always returns zeros
    window = vim.api.nvim_get_current_win()
  end
  if buffer == nil or buffer == 0 then
    buffer = vim.api.nvim_get_current_buf()
  end

  ---@type string?, _lastline
  local lastline_char, lastline
  local wrap_enabled = vim.wo[window].wrap
  if wrap_enabled then
    for _, dy_opt in
      ipairs(vim.opt.display:get() --[=[@as string[]]=])
    do
      local is_truncate = dy_opt == "truncate"
      if not is_truncate and dy_opt ~= "lastline" then
        goto continue
      end

      if is_truncate then
        lastline = "truncate"
      elseif lastline ~= "truncate" then
        lastline = "lastline"
      end
      ::continue::
    end
    lastline_char = vim.wo[window].fillchars:match("lastline:([^,]+)") or "@"
    assert(vim.fn.strcharlen(lastline_char) == 1)
  end

  local winsaveview = vim.fn.winsaveview()
  local wininfo = vim.fn.getwininfo(window)[1]
  local window_width = wininfo.width - wininfo.textoff

  -- 0-based exclusive
  -- NOTE: since botline is last
  --   COMPLETED line take one more
  local first_lineno = wininfo.topline - 1
  local last_lineno = wininfo.botline + 1

  -- 1-based exclusive (for 'nowrap')
  local first_visible_virtcol = winsaveview.leftcol + 1
  local last_visible_virtcol = first_visible_virtcol + window_width

  -- initialize the grid
  ---@type CellularAutomatonCell[][]
  local grid = {}
  local grid_height = wininfo.height
  for i = 1, grid_height do
    grid[i] = {}
    for j = 1, window_width do
      grid[i][j] = { char = " ", hl_groups = {} }
    end
  end
  local data =
    vim.api.nvim_buf_get_lines(buffer, first_lineno, last_lineno, false)

  -- update with buffer data
  local i = 0
  for line_offset, line in ipairs(data) do
    local jj = 0
    local col = 0
    local virtcol = 0
    local lineno = first_lineno + line_offset
    local is_first_line = line_offset == 1
    local lines_wrapped = 0
    i = i + 1
    if i > grid_height then
      break
    end

    ---@type CellularAutomatonCell, integer, integer
    local cell, char_screen_col_start, char_screen_col_end

    while true do
      col = col + 1
      virtcol = virtcol + 1
      char_screen_col_start, char_screen_col_end = unpack(vim.fn.virtcol({
        lineno,
        virtcol,
      }, 1, window))
      if
        char_screen_col_start == 0
        or (not wrap_enabled and char_screen_col_start > last_visible_virtcol)
      then
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

      if
        (not wrap_enabled and char_screen_col_end < first_visible_virtcol)
        or (
          wrap_enabled
          and is_first_line
          and char_screen_col_end <= winsaveview.skipcol
        )
      then
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

      local cmp = (
        wrap_enabled and (is_first_line and winsaveview.skipcol or 0)
        or first_visible_virtcol - 1
      )
      local is_tab = char == "\t"
      if is_tab or columns_occupied > 1 then
        if not is_tab then
          local translated_char = vim.fn.strtrans(char)
          if strtrans_valid(translated_char, columns_occupied) then
            ---@type CellularAutomatonHl[]
            local strtrans_hl_groups = {
              -- NOTE: I thought that vim.highlight.priorities.syntax
              --   was more appropriate priority for this hl group
              --   but any of TS captures override it
              { name = "SpecialKey", priority = 5000 },
            }
            retrieve_hl_groups(buffer, strtrans_hl_groups, lineno, virtcol)
            for cindex = char_screen_col_start, char_screen_col_end do
              if cindex <= cmp then
                goto to_next_strtrans_char
              end
              jj = jj + 1
              if jj > window_width then
                if not wrap_enabled then
                  goto to_next_line
                end
                i = i + 1
                if i > grid_height then
                  if not is_first_line then
                    prepare_lastlines(
                      grid,
                      lastline,
                      lastline_char,
                      lines_wrapped,
                      wininfo.textoff
                    )
                  end
                  return grid
                end
                jj = 1
                lines_wrapped = lines_wrapped + 1
              end
              cell = grid[i][jj]
              local index = cindex - char_screen_col_start + 1
              cell.char = translated_char:sub(index, index)
              cell.hl_groups = hl_groups_copy(strtrans_hl_groups)
              ::to_next_strtrans_char::
            end
            goto to_next_char
          end
        end

        if not is_tab then
          -- NOTE: at the moment there are
          --   at most double-wide characters
          assert(columns_occupied == 2)
          if wrap_enabled then
            if window_width == 1 then
              for row = i + 1, grid_height do
                grid[row][1].char = ">"
                grid[row][1].hl_groups = {
                  {
                    name = "NonText",
                    priority = vim.highlight.priorities.syntax,
                  },
                }
              end
              return grid
            elseif jj + 1 == window_width then
              grid[i][window_width].char = ">"
              grid[i][window_width].hl_groups = {
                {
                  name = "NonText",
                  priority = vim.highlight.priorities.syntax,
                },
              }
              i = i + 1
              if i == grid_height then
                return grid
              end
              jj = 0
            end
          end
        end
        local replacer = is_tab and " " or "@"
        local hl_group = is_tab and "" or "WarningMsg"
        for cindex = char_screen_col_start, char_screen_col_end do
          if cindex <= cmp then
            goto to_next_replacer_char
          end
          jj = jj + 1
          if jj > window_width then
            if not wrap_enabled then
              goto to_next_line
            end
            i = i + 1
            if i > grid_height then
              if not is_first_line then
                prepare_lastlines(
                  grid,
                  lastline,
                  lastline_char,
                  lines_wrapped,
                  wininfo.textoff
                )
              end
              return grid
            end
            jj = 1
            lines_wrapped = lines_wrapped + 1
          end
          cell = grid[i][jj]
          cell.char = replacer
          cell.hl_groups[#cell.hl_groups + 1] = {
            name = hl_group,
            priority = vim.highlight.priorities.user,
          }
          ::to_next_replacer_char::
        end
      else
        jj = jj + 1
        if jj > window_width then
          if not wrap_enabled then
            goto to_next_line
          end
          i = i + 1
          if i > grid_height then
            if not is_first_line then
              prepare_lastlines(
                grid,
                lastline,
                lastline_char,
                lines_wrapped,
                wininfo.textoff
              )
            end
            return grid
          end
          jj = 1
          lines_wrapped = lines_wrapped + 1
        end
        cell = grid[i][jj]
        cell.char = char
        retrieve_hl_groups(buffer, cell.hl_groups, lineno, virtcol)
      end
      ::to_next_char::
    end
    ::to_next_line::
  end
  return grid
end

return M
