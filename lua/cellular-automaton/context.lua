local time = require("cellular-automaton.common").time

--- Current animation context
---
---@class CellularAutomatonContext
---
--- true if animation was
--- interrupted (e.g. via event)
---@field interrupted boolean
---
--- Current animation name
---@field name string
---
--- Time when the animation started
--- (see *monotonic_ms* function)
---@field private started_ms integer
---
--- Floating window ID used for animation
---@field winid integer
---
--- Buffers used for animation (they're
--- swapping each frame to avoid flickering)
---@field buffers integer[]
---
--- Function to retrieve next buffer ID
---@field next_bufnr fun():integer
---
--- Namespace ID used for buffers highlighting
---@field hl_ns_id integer
---
--- Autocmd group identifier. If you're creating any
--- autocmds for animation window, use this one
---@field augroup integer
local ctx = {}
ctx.__index = ctx

setmetatable(ctx, {
  __call = function(cls, ...)
    return cls.new(...)
  end,
})

---@param name string
---@param winid integer
---@param buffers integer[]
---@return CellularAutomatonContext
function ctx.new(name, winid, buffers)
  vim.validate({
    name = { name, "string" },
    winid = { winid, "number" },
    bufnrs = { buffers, "table" },
  })
  assert(#buffers > 0, "No buffers specified")

  local self = setmetatable({}, ctx)
  self.started_ms = time()
  self.interrupted = false
  self.buffers = buffers
  self.winid = winid
  self.name = name

  local group_name = "cellular-automaton-" .. tostring(winid)
  self.augroup = vim.api.nvim_create_augroup(group_name, { clear = true })
  self.hl_ns_id = vim.api.nvim_create_namespace(group_name)
  self.next_bufnr = self:bufnr_iterator()

  return self
end

---@return fun():integer
function ctx:bufnr_iterator()
  local count = 0
  local bufnrs = assert(self.buffers)
  local nbufnrs = #bufnrs

  ---@return integer
  return function()
    count = count + 1
    if count >= nbufnrs then
      count = 1
    end
    return bufnrs[count]
  end
end

---@return integer
function ctx:elapsed_ms()
  local dt = time() - self.started_ms
  return math.max(0, dt)
end

return ctx
