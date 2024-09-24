local assert = require("luassert")
local l = require("cellular-automaton.load")

---@param h integer
---@param w integer
---@param lines string[]
---@param ver_scroll integer
---@param hor_scroll integer
---@param win_options? string[]
local function setup_viewport(h, w, lines, ver_scroll, hor_scroll, win_options)
  local options = win_options or {}
  -- split the windows so that the main is resizable
  vim.api.nvim_command("bufdo bwipeout!")
  vim.api.nvim_command("vsplit")
  vim.api.nvim_command("split")
  local winid = 0
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(winid, bufnr)
  vim.api.nvim_win_set_width(winid, w)
  vim.api.nvim_win_set_height(winid, h)
  if ver_scroll > 0 then
    vim.cmd(string.format([[exec "normal! %s\<C-e>"]], ver_scroll))
  end
  -- set nowrap - otherwise horizontall scrolling doesnt work
  vim.wo[winid].wrap = false
  if hor_scroll > 0 then
    vim.cmd(string.format([[exec "normal! %szl"]], hor_scroll))
  end
  -- some of them may be overridden by win_options
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].foldcolumn = "0"
  for _, option in ipairs(options) do
    vim.cmd("set " .. option)
  end
end

---Retrieve the "char slice" from the specified grid
---@param grid CellularAutomatonCell[][]
---@param row integer
---@param col_start integer?
---@param col_end integer?
---@return string
local get_chars_from_grid = function(grid, row, col_start, col_end)
  col_start = col_start or 1
  col_end = col_end or #grid[row]

  assert.truthy(col_start > 0 and col_end > 0 and col_start <= col_end)
  assert.truthy(col_end <= #grid[row])

  return vim
    .iter(vim.fn.range(col_start, col_end))
    :map(function(col)
      return grid[row][col].char
    end)
    :join("")
end

---@param cell CellularAutomatonCell
---@param hl_name string
local assert_one_hl = function(cell, hl_name)
  assert.are.equal(#cell.hl_groups, 1)
  assert.are.same(cell.hl_groups[1].name, hl_name)
end

describe("load_base_grid:", function()
  local window_option_cases = {
    {
      options = {
        "numberwidth=4",
        "relativenumber",
        "number",
        "foldcolumn=0",
        "signcolumn=yes",
      },
      side_col_width = 4 + 2,
    },
    {
      options = {
        "numberwidth=4",
        "norelativenumber",
        "nonumber",
        "foldcolumn=1",
        "signcolumn=yes",
      },
      side_col_width = 2 + 1,
    },
    {
      options = {
        "numberwidth=3",
        "number",
        "norelativenumber",
        "foldcolumn=0",
        "signcolumn=no",
      },
      side_col_width = 3,
    },
    {
      options = {
        "numberwidth=5",
        "relativenumber",
        "number",
        "foldcolumn=2",
        "signcolumn=no",
      },
      side_col_width = 5 + 2,
    },
  }

  describe("chars:", function()
    it("loads grid from viewport", function()
      for idx, case in ipairs(window_option_cases) do
        local width = 20
        local height = 10
        setup_viewport(height, width, { "1234", "56789" }, 0, 0, case.options)
        local grid = l.load_base_grid(0, 0)
        assert.equals(height, #grid, idx)
        assert.equals(width - case.side_col_width, #grid[1], idx)
        assert.same("1", grid[1][1].char, idx)
        assert.same("9", grid[2][5].char, idx)
      end
    end)

    it("loads grid when buffer content is wider than viewport", function()
      for idx, case in ipairs(window_option_cases) do
        local width = 10
        local height = 20
        setup_viewport(height, width, { "1234567890abcde" }, 0, 0, case.options)
        local grid = l.load_base_grid(0, 0)
        assert.equals(height, #grid, idx)
        assert.equals(width - case.side_col_width, #grid[1], idx)
        assert.same("3", grid[1][3].char, idx)
      end
    end)

    it("loads grid when buffer content is longer than viewport", function()
      for idx, case in ipairs(window_option_cases) do
        local width = 10
        local height = 3
        setup_viewport(height, width, { "1", "2", "3", "4", "5" }, 0, 0, case.options)
        local grid = l.load_base_grid(0, 0)
        assert.equals(height, #grid, idx)
        assert.equals(width - case.side_col_width, #grid[1], idx)
        assert.same("3", grid[3][1].char, idx)
      end
    end)

    it("loads grid from vertically scrolled viewport", function()
      for idx, case in ipairs(window_option_cases) do
        local width = 10
        local height = 3
        setup_viewport(height, width, { "1", "2", "3", "4", "5" }, 2, 0, case.options)
        local grid = l.load_base_grid(0, 0)
        assert.equals(height, #grid, idx)
        assert.equals(width - case.side_col_width, #grid[1], idx)
        assert.same("3", grid[1][1].char, idx)
        assert.same("5", grid[3][1].char, idx)
      end
    end)

    it("loads grid from horizontally scrolled viewport", function()
      for idx, case in ipairs(window_option_cases) do
        local width = 10
        local height = 3
        setup_viewport(height, width, { "1234567890abcde" }, 0, 2, case.options)
        local grid = l.load_base_grid(0, 0)
        assert.equals(height, #grid, idx)
        assert.equals(width - case.side_col_width, #grid[1], idx)
        assert.same("3", grid[1][1].char, idx)
      end
    end)
  end)

  describe("multicell chars:", function()
    it("multi-byte but one-cell chars can entirely fit it *char* field", function()
      local width = 10
      local height = 10
      -- E.g. cyrillic symbols occupies one
      -- cell but contains of several bytes,
      -- also some math symbols, dyacritics etc.
      -- NOTE: Lines 1 and 2 are equal
      setup_viewport(height, width, { "\xce\xa9\xc3\x85", "ΩÅ", "ｶ¼аꜳ" }, 0, 0)
      local grid = l.load_base_grid(0, 0)

      assert.same("Ω", grid[1][1].char)
      assert.same("Å", grid[1][2].char)

      assert.same("Ω", grid[2][1].char)
      assert.same("Å", grid[2][2].char)

      assert.same("ｶ", grid[3][1].char)
      assert.same("¼", grid[3][2].char)
      assert.same("а", grid[3][3].char)
      assert.same("ꜳ", grid[3][4].char)
    end)
    it("one-/multi-byte and multicell chars should be replaced", function()
      local width = 10
      local height = 10

      -- Emojis, chinese/korean/japanese hyeroglyphs and lot more ...
      setup_viewport(height, width, { "💤", "諺文", "한글", "ハン" }, 0, 0)

      local grid = l.load_base_grid(0, 0)

      -- 2-cell emojis are "@@" now,
      -- not that pretty as it could be,
      -- but at least it's not breaking
      -- the cellular automaton logic
      assert.same("@", grid[1][1].char)
      assert.same("@", grid[1][2].char)
      assert.same(" ", grid[1][3].char)

      local end_ = 4
      for row = 2, 4 do
        for col = 1, end_ do
          -- Two chinese, two korean, two japanese
          -- hyeroglyphs ... Now they all are "@@@@"
          local desc = string.format("row %d, byte col %d", row, col)
          assert.same("@", grid[row][col].char, desc)
        end
        assert.same(" ", grid[row][end_ + 1].char)
      end
    end)
    it("'strtrans()' support", function()
      setup_viewport(2, 10, {
        -- Single byte 0x02 occupies
        -- 2 cells in vim and looks like "^B"
        "\x02",
        -- Two bytes 0xffff ("ef bf bf" in UTF-8) occupy
        -- 6 (!) cells in vim and look like "<ffff>"
        "\xef\xbf\xbf",
      }, 0, 0)

      local grid = l.load_base_grid(0, 0)

      assert.same("^B", get_chars_from_grid(grid, 1, 1, 2))
      assert.same(" ", grid[1][3].char)

      assert.same("<ffff>", get_chars_from_grid(grid, 2, 1, 6))
      assert.same(" ", grid[2][7].char)

      local expected_hl_name = "SpecialKey"
      assert_one_hl(grid[1][1], expected_hl_name)
      assert_one_hl(grid[1][2], expected_hl_name)
      for i = 1, 6 do
        assert_one_hl(grid[2][i], expected_hl_name)
      end
    end)
    it("tabs should be replaced (different tabstops)", function()
      local width = 19

      local ts_opt, grid
      setup_viewport(1, width, { "\tA" }, 0, 0)
      local bufnr = vim.api.nvim_get_current_buf()

      for ts = 1, 16 do
        vim.bo[bufnr].tabstop = ts
        ts_opt = "ts=" .. tostring(ts)

        grid = l.load_base_grid(0, bufnr)
        assert.truthy(#grid[1] >= (ts + 1))

        assert.same(string.rep(" ", ts) .. "A", get_chars_from_grid(grid, 1, 1, ts + 1), ts_opt)
      end
    end)
    it("tabs should be replaced (in the middle of the string + 'softtabstop')", function()
      local width = 19

      local ts = 16
      local ts_opts = { "ts=" .. tostring(ts), "sts=" .. tostring(ts) }
      local ts_opts_str = vim.inspect(ts_opts)
      local grid

      for shift_symbols = 0, ts - 1 do
        -- Each asterisk will "shrink" the tab symbol more
        -- and more since 'softtabstop' was set for the buffer
        setup_viewport(1, width, {
          string.rep("*", shift_symbols) .. "\tA",
        }, 0, 0, ts_opts)

        grid = l.load_base_grid(0, 0)
        assert.truthy(#grid[1] >= (ts + 1))

        assert.same(
          string.rep("*", shift_symbols) .. string.rep(" ", ts - shift_symbols) .. "A",
          get_chars_from_grid(grid, 1, 1, ts + 1),
          ts_opts_str .. ", shift_symbols=" .. tostring(shift_symbols)
        )
      end
    end)
    it("tabs should be replaced (tabstop + hscroll)", function()
      local width = 17
      local ts = 16

      -- NOTE: make the line at least twice longer than
      --   the buffer width to apply hscrolls later
      local ts_opt = "ts=" .. tostring(ts)
      setup_viewport(1, width, {
        "\tA" .. string.rep(" ", width),
      }, 0, 0, { ts_opt })

      -- Jump to the right to skip all tab cells + "A" letter, ...
      vim.cmd(string.format([[normal! %dzl]], ts + 1))
      for hscroll = ts, 0, -1 do
        -- ... then shift the view to the left cell by cell
        vim.cmd("normal! zh")

        local grid = l.load_base_grid(0, 0)
        assert.are.same(#grid[1], (ts + 1))

        -- print(vim.inspect(get_chars_from_grid(grid, 1)))
        assert.same(
          string.rep(" ", ts - hscroll) .. "A",
          get_chars_from_grid(grid, 1, 1, ts - hscroll + 1),
          ts_opt .. ", hscroll=" .. tostring(hscroll)
        )
      end
    end)
    it("'strtrans()' converted chars, with hscroll on them", function()
      local width = 10

      local ffff_symbol = "\xef\xbf\xbf"
      local ffff_symbol_width = vim.fn.strdisplaywidth(ffff_symbol, 0)
      assert.same(ffff_symbol_width, 6)

      -- Line content will be displayed as "<ffff>A"
      -- (+ trailing spaces to be able to shift the view)
      local expected_content = "<ffff>A"
      assert.same(#expected_content, ffff_symbol_width + 1)
      setup_viewport(1, width, {
        ffff_symbol .. "A" .. string.rep(" ", width),
      }, 0, 0)

      for hscroll = 0, (#expected_content - 1) do
        local grid = l.load_base_grid(0, 0)
        assert.same(
          expected_content:sub(hscroll + 1, -1),
          get_chars_from_grid(grid, 1, 1, #expected_content - hscroll),
          "hscroll=" .. tostring(hscroll)
        )
        vim.cmd("normal! zl")
      end
    end)
    it("'strtrans()' for char in the middle of the string", function()
      local width = 12

      local ffff_symbol = "\xef\xbf\xbf"
      local ffff_symbol_width = vim.fn.strdisplaywidth(ffff_symbol, 0)
      assert.same(ffff_symbol_width, 6)

      local expected_content = "AB<ffff>CD"
      assert.same(#expected_content, ffff_symbol_width + 4)
      setup_viewport(1, width, {
        "AB" .. ffff_symbol .. "CD" .. string.rep(" ", width),
      }, 0, 0)

      for hscroll = 0, (#expected_content - 1) do
        local grid = l.load_base_grid(0, 0)
        assert.same(
          expected_content:sub(hscroll + 1, -1),
          get_chars_from_grid(grid, 1, 1, #expected_content - hscroll),
          "hscroll=" .. tostring(hscroll)
        )
        vim.cmd("normal! zl")
      end
    end)
    it("multi-byte and multi-cell chars, with hscroll on them", function()
      local width = 10
      local height = 10

      setup_viewport(height, width, {
        "💤" .. string.rep(" ", width * 2),
        "諺文",
        "한글",
        "ハン",
        "\x02",
        "\xef\xbf\xbf",
      }, 0, 0)

      local grid = l.load_base_grid(0, 0)

      -- No horizontal offset here, ...
      assert.same({ "@@ ", "@@@@ ", "@@@@ ", "@@@@ ", "^B ", "<ffff> " }, {
        get_chars_from_grid(grid, 1, 1, 3),
        get_chars_from_grid(grid, 2, 1, 5),
        get_chars_from_grid(grid, 3, 1, 5),
        get_chars_from_grid(grid, 4, 1, 5),
        get_chars_from_grid(grid, 5, 1, 3),
        get_chars_from_grid(grid, 6, 1, 7),
      })

      -- ... now make some, ...
      vim.cmd("normal! zl")
      grid = l.load_base_grid(0, 0)
      assert.same({ "@ ", "@@@ ", "@@@ ", "@@@ ", "B ", "ffff> " }, {
        get_chars_from_grid(grid, 1, 1, 2),
        get_chars_from_grid(grid, 2, 1, 4),
        get_chars_from_grid(grid, 3, 1, 4),
        get_chars_from_grid(grid, 4, 1, 4),
        get_chars_from_grid(grid, 5, 1, 2),
        get_chars_from_grid(grid, 6, 1, 6),
      })

      -- ... and some more
      vim.cmd("normal! zl")
      grid = l.load_base_grid(0, 0)
      assert.same({ "  ", "@@  ", "@@  ", "@@  ", "  ", "fff>  " }, {
        get_chars_from_grid(grid, 1, 1, 2),
        get_chars_from_grid(grid, 2, 1, 4),
        get_chars_from_grid(grid, 3, 1, 4),
        get_chars_from_grid(grid, 4, 1, 4),
        get_chars_from_grid(grid, 5, 1, 2),
        get_chars_from_grid(grid, 6, 1, 6),
      })
    end)

    it("support composing characters", function()
      local width = 10

      -- Variation Selectors 15 (0xfe0e) and 16 (0xfe0f) by itself
      -- occupies one cell - but if they'll compose with another
      -- symbol then they will occupy zero cells
      local vs15 = "\xef\xb8\x8e"
      local vs16 = "\xef\xb8\x8f"

      local some_stuff = string.rep("A", 2 * width)
      setup_viewport(4, width, {
        -- Make the view horizontally scrollable
        vs15 .. some_stuff,
        vs16 .. some_stuff,
        "🤣" .. vs16 .. "AA",
        "A" .. vs15 .. "AA",
      }, 0, 0)

      local grid = l.load_base_grid(0, 0)

      -- Non-composed VS-15/VS-16 should be replaced with space
      assert.same(" " .. "AA", get_chars_from_grid(grid, 1, 1, 3))
      assert.same(" " .. "AA", get_chars_from_grid(grid, 2, 1, 3))
      assert.same("@@AA", get_chars_from_grid(grid, 3, 1, 4))
      -- NOTE: Yes, it's still here but since it's always will be
      --   behind another character it will not be displayed
      assert.same("A" .. vs15 .. "AA", get_chars_from_grid(grid, 4, 1, 3))

      vim.cmd("normal! zl")
      grid = l.load_base_grid(0, 0)
      assert.same("AAA", get_chars_from_grid(grid, 1, 1, 3))
      assert.same("AAA", get_chars_from_grid(grid, 2, 1, 3))
      assert.same("@AA", get_chars_from_grid(grid, 3, 1, 3))
      assert.same("AA ", get_chars_from_grid(grid, 4, 1, 3))

      vim.cmd("normal! zl")
      grid = l.load_base_grid(0, 0)
      assert.same("AAA", get_chars_from_grid(grid, 1, 1, 3))
      assert.same("AAA", get_chars_from_grid(grid, 2, 1, 3))
      assert.same("AA ", get_chars_from_grid(grid, 3, 1, 3))
      assert.same("A  ", get_chars_from_grid(grid, 4, 1, 3))
    end)
  end)

  describe("wrap support:", function()
    ---@param h integer
    ---@param w integer
    ---@param lines string[]
    ---@param win_options? string[]
    local viewport_for_wrap_testing = function(h, w, lines, win_options)
      win_options = win_options or {}
      win_options[#win_options + 1] = "wrap"
      setup_viewport(h, w, lines, 0, 0, win_options)
    end

    it("without wrapping", function()
      viewport_for_wrap_testing(3, 10, {
        "long sentence",
        "longenough",
      })
      vim.wo[0].wrap = false
      local grid = l.load_base_grid(0, 0)
      assert.same({
        get_chars_from_grid(grid, 1),
        get_chars_from_grid(grid, 2),
        get_chars_from_grid(grid, 3),
      }, {
        "long sente",
        "longenough",
        "          ",
      })
    end)

    it("simple wrapping", function()
      viewport_for_wrap_testing(3, 10, {
        "long sentence",
        "longenough",
      })
      local grid = l.load_base_grid(0, 0)
      assert.same({
        get_chars_from_grid(grid, 1),
        get_chars_from_grid(grid, 2),
        get_chars_from_grid(grid, 3),
      }, {
        "long sente",
        "nce       ",
        "longenough",
      })
    end)

    it("last line didn't fit, dy=lastline", function()
      viewport_for_wrap_testing(3, 10, {
        "long sentence",
        "now it's actually long",
      })
      vim.o.display = "lastline"
      local grid = l.load_base_grid(0, 0)
      assert.same({
        get_chars_from_grid(grid, 1),
        get_chars_from_grid(grid, 2),
        get_chars_from_grid(grid, 3),
      }, {
        "long sente",
        "nce       ",
        "now it'@@@",
      })
    end)

    it("last line didn't fit, dy=lastline (custom 'fcs')", function()
      viewport_for_wrap_testing(3, 10, {
        "long sentence",
        "now it's actually long",
      })
      vim.o.display = "lastline"
      vim.wo[0].fillchars = "lastline:&"
      local grid = l.load_base_grid(0, 0)
      assert.same({
        get_chars_from_grid(grid, 1),
        get_chars_from_grid(grid, 2),
        get_chars_from_grid(grid, 3),
      }, {
        "long sente",
        "nce       ",
        "now it'&&&",
      })
    end)

    it("last line didn't fit, dy=", function()
      viewport_for_wrap_testing(3, 10, {
        "long sentence",
        "now it's actually long",
      })
      vim.o.display = ""
      local grid = l.load_base_grid(0, 0)
      assert.same({
        get_chars_from_grid(grid, 1),
        get_chars_from_grid(grid, 2),
        get_chars_from_grid(grid, 3),
      }, {
        "long sente",
        "nce       ",
        "@         ",
      })
    end)

    it("last line didn't fit, dy= (custom 'fcs')", function()
      viewport_for_wrap_testing(3, 10, {
        "long sentence",
        "now it's actually long",
      })
      vim.o.display = ""
      vim.wo[0].fillchars = "lastline:&"
      local grid = l.load_base_grid(0, 0)
      assert.same({
        get_chars_from_grid(grid, 1),
        get_chars_from_grid(grid, 2),
        get_chars_from_grid(grid, 3),
      }, {
        "long sente",
        "nce       ",
        "&         ",
      })
    end)

    it("last line didn't fit, dy= (textoff=1)", function()
      viewport_for_wrap_testing(3, 11, {
        "long sentence",
        "now it's actually long",
      })
      vim.o.display = ""
      vim.wo[0].foldcolumn = "1"
      local grid = l.load_base_grid(0, 0)
      assert.same({
        get_chars_from_grid(grid, 1),
        get_chars_from_grid(grid, 2),
        get_chars_from_grid(grid, 3),
      }, {
        "long sente",
        "nce       ",
        "@         ",
      })
    end)

    it("last line didn't fit, dy=truncate", function()
      viewport_for_wrap_testing(3, 10, {
        "long sentence",
        "now it's actually long",
      })
      vim.o.display = "truncate"
      local grid = l.load_base_grid(0, 0)
      assert.same({
        get_chars_from_grid(grid, 1),
        get_chars_from_grid(grid, 2),
        get_chars_from_grid(grid, 3),
      }, {
        "long sente",
        "nce       ",
        "@@@       ",
      })
    end)

    it("last line didn't fit, dy=truncate (custom 'fcs')", function()
      viewport_for_wrap_testing(3, 10, {
        "long sentence",
        "now it's actually long",
      })
      vim.o.display = "truncate"
      vim.wo[0].fillchars = "lastline:&"
      local grid = l.load_base_grid(0, 0)
      assert.same({
        get_chars_from_grid(grid, 1),
        get_chars_from_grid(grid, 2),
        get_chars_from_grid(grid, 3),
      }, {
        "long sente",
        "nce       ",
        "&&&       ",
      })
    end)

    it("last line didn't fit, dy=truncate (textoff)", function()
      for i = 0, 4 do
        viewport_for_wrap_testing(3, 10 + i, {
          "long sentence",
          "now it's actually long",
        })
        vim.o.display = "truncate"
        vim.wo[0].foldcolumn = tostring(i)
        local grid = l.load_base_grid(0, 0)
        local expected_to_see = math.max(0, 3 - i)
        assert.same({
          get_chars_from_grid(grid, 1),
          get_chars_from_grid(grid, 2),
          get_chars_from_grid(grid, 3),
        }, {
          "long sente",
          "nce       ",
          string.rep("@", expected_to_see) .. string.rep(" ", 10 - expected_to_see),
        })
      end
    end)
  end)
end)
