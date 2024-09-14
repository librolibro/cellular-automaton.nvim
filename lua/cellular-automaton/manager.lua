local M = {}

local ui = require("cellular-automaton.ui")
local common = require("cellular-automaton.common")

---@type string?
local current_animation_name = nil

---@type integer?
local animation_start_time_ms = nil

---@return integer
local monotonic_ms = function()
  ---@diagnostic disable-next-line: undefined-field
  return vim.uv.now()
end

---@return boolean
local animation_in_progress = function()
  return current_animation_name ~= nil and animation_start_time_ms ~= nil
end

---@type integer
local augroup = nil
local reset_augroup = function()
  augroup = vim.api.nvim_create_augroup("CellularAutomaton", { clear = true })
end
reset_augroup()

--- Processing another frame
---@param grid CellularAutomatonGrid
---@param animation_config CellularAutomatonConfig
---@param win_id? integer
local function process_frame(grid, animation_config, win_id)
  -- quit if animation already interrupted
  if win_id == nil or not vim.api.nvim_win_is_valid(win_id) then
    return
  end
  -- proccess frame
  ui.render_frame(grid)
  local render_at = common.time()
  local state_changed = animation_config.update(grid)

  -- schedule next frame
  local fps = animation_config.fps or 50
  local time_since_render = common.time() - render_at
  local timeout = math.max(0, 1000 / fps - time_since_render)
  if state_changed then
    vim.defer_fn(function()
      process_frame(grid, animation_config, win_id)
    end, timeout)
  end
end

---@param events string|string[]
---@param opts? {pattern?: string}
local clean_on_events = function(events, opts)
  ---@type table
  opts = opts or {}
  opts.group = augroup
  opts.callback = M.clean
  vim.api.nvim_create_autocmd(events, opts)
end

---@param win_id integer
---@param buffers Buffers
local function setup_cleaning(win_id, buffers)
  local exit_keys = { "q", "Q", "<ESC>", "<CR>" }
  for _, key in ipairs(exit_keys) do
    for _, buffer_id in ipairs(buffers) do
      for _, mode in ipairs({ "n", "i" }) do
        -- TODO: use new 'vim.keymap.set' API
        vim.api.nvim_buf_set_keymap(
          buffer_id,
          mode,
          key,
          "<Cmd>lua require('cellular-automaton.manager').clean()<CR>",
          { silent = true }
        )
      end
    end
  end
  -- NOTE(libro): VimResized with pattern (like
  --   WinClosed lower) doesn't work (should it?)
  clean_on_events("VimResized")
  clean_on_events("WinClosed", { pattern = tostring(win_id) })
  clean_on_events("TabClosed", { pattern = tostring(vim.api.nvim_get_current_tabpage()) })
  clean_on_events("TabLeave")
end

---@param animation_config CellularAutomatonConfig
local function _execute_animation(animation_config)
  if animation_in_progress() then
    error("Nested animations are forbidden")
  end
  current_animation_name = assert(animation_config.name)
  local host_win_id = vim.api.nvim_get_current_win()
  local host_bufnr = vim.api.nvim_get_current_buf()
  local grid = require("cellular-automaton.load").load_base_grid(host_win_id, host_bufnr)
  if animation_config.init ~= nil then
    animation_config.init(grid)
  end
  local win_id, buffers = ui.open_window(host_win_id)
  animation_start_time_ms = monotonic_ms()
  process_frame(grid, animation_config, win_id)
  setup_cleaning(win_id, buffers)
end

---@param animation_config CellularAutomatonConfig
M.execute_animation = function(animation_config)
  local ok, err = pcall(_execute_animation, animation_config)
  if not ok then
    M.clean(false)
    error(err)
  end
end

--- NOTE: *event_data* is a table with ':h event-args' if called
--- from autocommand's callback, and 'false' if error was occured
---@param event_data table|false|nil
M.clean = function(event_data)
  if not animation_in_progress() then
    return
  end

  -- notify about animation end (if not in headless mode) ...
  if #vim.api.nvim_list_uis() > 0 then
    local chunks = {
      { assert(current_animation_name) .. "(", "Normal" },
      { string.format("%.3f ms", (monotonic_ms() - assert(animation_start_time_ms)) / 1000), "DiagnosticInfo" },
      { "): animation stopped", "Normal" },
    }
    if event_data == false then
      chunks[#chunks + 1] = { " error occured!", "ErrorMsg" }
    elseif event_data then
      chunks[#chunks + 1] = { string.format(" [%s]", assert(event_data.event)), "Comment" }
    end
    vim.api.nvim_echo(chunks, true, {})
  end

  -- ... and then clean things up
  animation_start_time_ms = nil
  current_animation_name = nil
  reset_augroup()
  ui.clean()
end

return M
