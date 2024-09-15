local M = {}

local ui = require("cellular-automaton.ui")
local common = require("cellular-automaton.common")
local animation_context_class = require("cellular-automaton.context")

---@type table<integer, CellularAutomatonContext>
M._running_animations = {}

--- Processing another frame
---@param grid CellularAutomatonGrid
---@param cfg CellularAutomatonConfig
---@param ctx CellularAutomatonContext
local function process_frame(grid, cfg, ctx)
  -- quit if animation already interrupted
  if ctx.interrupted or not vim.api.nvim_win_is_valid(ctx.winid) then
    return
  end
  -- proccess frame
  ui.render_frame(grid, ctx)
  local render_at = common.time()
  local state_changed = cfg.update(grid)

  -- schedule next frame
  local fps = cfg.fps
  local time_since_render = common.time() - render_at
  local timeout = math.max(0, 1000 / fps - time_since_render)
  if state_changed then
    vim.defer_fn(function()
      process_frame(grid, cfg, ctx)
    end, timeout)
  end
end

---@param ctx CellularAutomatonContext
---@param events string|string[]
---@param opts? {pattern?: string}
local clean_on_events = function(ctx, events, opts)
  ---@type table
  opts = opts or {}
  opts.group = assert(ctx).augroup
  opts.callback = function(event_data)
    M.clean(ctx, event_data)
  end
  vim.api.nvim_create_autocmd(events, opts)
end

---@param ctx CellularAutomatonContext
local function setup_cleaning(ctx)
  local clean = function()
    require("cellular-automaton.manager").clean(ctx)
  end

  local exit_keys = { "q", "Q", "<ESC>", "<CR>" }
  for _, lhs in ipairs(exit_keys) do
    for _, bufnr in ipairs(ctx.buffers) do
      vim.keymap.set({ "n", "i" }, lhs, clean, {
        silent = true,
        buffer = bufnr,
      })
    end
  end
  -- TODO: WinResized
  clean_on_events(ctx, "VimResized")
  clean_on_events(ctx, "WinClosed", { pattern = tostring(ctx.winid) })
  clean_on_events(ctx, "TabClosed", {
    pattern = tostring(vim.api.nvim_get_current_tabpage()),
  })
  clean_on_events(ctx, "TabLeave")
end

---@param cfg CellularAutomatonConfig
---@param host_winid integer
---@param host_bufnr integer
---@param ctx CellularAutomatonContext
local function _execute_animation(cfg, host_winid, host_bufnr, ctx)
  local l = require("cellular-automaton.load")
  local grid = l.load_base_grid(host_winid, host_bufnr)
  if cfg.init ~= nil then
    cfg.init(grid)
  end
  setup_cleaning(ctx)
  process_frame(grid, cfg, ctx)
end

---@param cfg CellularAutomatonConfig
---@param host_winid integer
M.execute_animation = function(cfg, host_winid)
  local host_winid_visible = false
  for _, tabpage_winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if tabpage_winid == host_winid then
      host_winid_visible = true
      break
    end
  end
  if not host_winid_visible then
    error(string.format("winid=%d is not on the current tabpage", host_winid))
  end
  if M._running_animations[host_winid] and not M._running_animations[host_winid].interrupted then
    error("There is already running animation for winid=" .. tostring(host_winid))
  end
  for k, ctx in pairs(M._running_animations) do
    if ctx.interrupted then
      M._running_animations[k] = nil
    elseif ctx.winid == host_winid then
      error(string.format("You want to run an animation for winid=%d which is already an animation window", host_winid))
    end
  end
  local host_bufnr = vim.api.nvim_win_get_buf(host_winid)
  local winid, buffers = ui.prepare_window_and_buffers(host_winid)
  -- creating animation context
  local ctx = animation_context_class.new(cfg.name, host_winid, winid, buffers)
  M._running_animations[host_winid] = ctx
  local ok, err = pcall(_execute_animation, cfg, host_winid, host_bufnr, ctx)
  if not ok then
    M.clean(ctx, false)
    error(err)
  end
end

--- NOTE: *event_data* is a table with ':h event-args' if called
--- from autocommand's callback, and 'false' if error was occured
---@param ctx CellularAutomatonContext
---@param event_data table|false|nil
M.clean = function(ctx, event_data)
  if ctx.interrupted then
    return
  end
  ctx.interrupted = true

  -- notify about animation end (if not in headless mode) ...
  if #vim.api.nvim_list_uis() > 0 then
    local chunks = {
      { ctx.name .. "(", "Normal" },
      { string.format("%.3f ms", ctx:elapsed_ms() / 1000), "DiagnosticInfo" },
      { "): animation stopped", "Normal" },
    }
    if event_data == false then
      chunks[#chunks + 1] = { " error occured!", "ErrorMsg" }
    elseif event_data then
      local evt = assert(event_data.event)
      chunks[#chunks + 1] = { string.format(" [%s]", evt), "Comment" }
    end
    vim.api.nvim_echo(chunks, true, {})
  end

  -- ... and then clean things up
  vim.api.nvim_del_augroup_by_id(ctx.augroup)
  ui.clean(ctx.winid, ctx.buffers)
end

return M
