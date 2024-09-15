local assert = require("luassert")

---@param lines string[]
---@param win_options? string[]
local function setup_viewport(lines, win_options)
  local options = win_options or {}
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(0, bufnr)
  if win_options then
    for _, option in ipairs(options) do
      vim.cmd.set(option)
    end
  end
end

describe("integration", function()
  before_each(function()
    local m = require("cellular-automaton.manager")
    for _, ctx in pairs(m._running_animations) do
      m.clean(ctx)
    end
  end)

  it("unhandled error doesn't break next animations", function()
    local test_animation = {
      name = "test",
      fps = 1,
      update = function()
        error("test error")
      end,
    }
    require("cellular-automaton").register_animation(test_animation)
    setup_viewport({ "aaaaa", "     " })
    assert.has.errors(function()
      vim.cmd.CellularAutomaton("test")
    end)
    vim.cmd("CellularAutomaton make_it_rain")
  end)

  it("quiting with :q doesn't break next animations", function()
    vim.cmd("CellularAutomaton make_it_rain")
    setup_viewport({ "aaaaa", "     " })
    vim.cmd("q")
    vim.cmd("CellularAutomaton make_it_rain")
  end)

  it("'list' window option is turned off to prevent marking trailing spaces", function()
    vim.cmd("set list")
    vim.cmd("CellularAutomaton make_it_rain")
    assert.is_false(vim.wo[0].list)
  end)
end)
