local manager = require("cellular-automaton.manager")

local M = {}

---@type table<string, CellularAutomatonConfig>
M.animations = {}

---@param cfg CellularAutomatonConfig
M.register_animation = function(cfg)
  vim.validate("config", cfg, "table")
  vim.validate("config.fps", cfg.fps, "number")
  vim.validate("config.name", cfg.name, "string")
  vim.validate("config.init", cfg.init, "function", true)
  vim.validate("config.update", cfg.update, "function")

  M.animations[cfg.name] = cfg
end

---@param name string
local register_builtin_animation = function(name)
  local cfg = assert(require(string.format("cellular-automaton.animations.%s", name)))
  if not cfg.name or cfg.name == "" then
    cfg.name = name
  end
  M.register_animation(cfg)
end

register_builtin_animation("make_it_rain")
register_builtin_animation("game_of_life")
register_builtin_animation("scramble")

---@param name string
M.start_animation = function(name)
  -- Make sure animaiton exists
  if M.animations[name] == nil then
    error("Error while starting an animation. Unknown cellular-automaton animation: " .. name)
  end

  manager.execute_animation(M.animations[name])
end

return M
