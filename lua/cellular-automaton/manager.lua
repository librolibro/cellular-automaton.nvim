local M = {}

local ui = require("cellular-automaton.ui")
local common = require("cellular-automaton.common")
local animation_context_class = require("cellular-automaton.context")

---@type table<integer, CellularAutomatonContext>
M._running_animations = {}

--- Processing another frame
---@param grid CellularAutomatonCell[][]
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
  local state_changed = cfg:update(grid)

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
  ---@type vim.api.keyset.create_autocmd
  opts = opts or {}
  opts.group = assert(ctx).augroup
  if opts.callback == nil then
    opts.callback = function(event_data)
      require("cellular-automaton.manager").clean(ctx, event_data)
    end
  end
  opts.once = true
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
  clean_on_events(ctx, "VimResized", {
    callback = function(event_data)
      -- after VimResized event fired the last line always
      -- clears so make a little pause before notifying
      require("cellular-automaton.manager").clean(ctx, event_data, 250)
    end,
  })
  clean_on_events(ctx, "WinResized", {
    callback = function(event_data)
      for _, winid in
        ipairs(assert(vim.v.event.windows) --[=[@as integer[]]=])
      do
        -- If any of the non-floating windows changed its size (or
        -- this exact floating window itself) then stop the animation
        if
          not common.is_floating(winid)
          or winid == ctx.host_winid
          or winid == ctx.winid
        then
          require("cellular-automaton.manager").clean(ctx, event_data)
          return
        end
      end
    end,
  })
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
    cfg:init(grid)
  end
  setup_cleaning(ctx)
  process_frame(grid, cfg, ctx)
end

---@param cfg CellularAutomatonConfig
---@param host_winid integer
M.execute_animation = function(cfg, host_winid)
  -- ensure that choosen window is
  -- visible (on the current tagpage)
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
  -- only one animation per window supported
  if
    M._running_animations[host_winid]
    and not M._running_animations[host_winid].interrupted
  then
    error(
      "There is already running animation for winid=" .. tostring(host_winid)
    )
  end
  -- animations for animation windows are also not supported
  -- TODO: maybe transform them (possibly to
  --   another animation but saving the state)?
  for k, ctx in pairs(M._running_animations) do
    -- also cleaning up previous (interrupted) sessions
    if ctx.interrupted then
      M._running_animations[k] = nil
    elseif ctx.winid == host_winid then
      error(
        string.format(
          "You want to run an animation for winid=%d"
            .. " which is already an animation window",
          host_winid
        )
      )
    end
  end
  -- creating and preparing floating window
  -- and buffers for the future animation
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

---@param ctx CellularAutomatonContext
---@param event_data table|false|nil
local notify_about_animation_end = function(ctx, event_data)
  local chunks = {
    { ctx.name .. "(", "Normal" },
    { string.format("%.3f s", ctx:elapsed_ms() / 1000), "DiagnosticInfo" },
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

--- NOTE: *event_data* is a table with ':h event-args' if called
--- from autocommand's callback, and 'false' if error was occured
---@param ctx CellularAutomatonContext
---@param event_data table|false|nil
---@param msg_delay_ms? integer
M.clean = function(ctx, event_data, msg_delay_ms)
  if ctx.interrupted then
    return
  end
  ctx.interrupted = true

  -- notify about animation end (if not in headless mode) ...
  if #vim.api.nvim_list_uis() > 0 then
    if msg_delay_ms and msg_delay_ms > 0 then
      vim.defer_fn(function()
        notify_about_animation_end(ctx, event_data)
      end, msg_delay_ms)
    else
      notify_about_animation_end(ctx, event_data)
    end
  end

  -- ... and then clean things up
  vim.api.nvim_del_augroup_by_id(ctx.augroup)
  ui.clean(ctx.winid, ctx.buffers)
end

return M
