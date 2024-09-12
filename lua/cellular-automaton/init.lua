local manager = require("cellular-automaton.manager")

local M = {}

---@type table<string, CellularAutomatonConfig>
M.animations = {}

---@param config CellularAutomatonConfig
M.register_animation = function(config)
  vim.validate("config", config, "table")
  vim.validate("config.fps", config.fps, "number")
  vim.validate("config.name", config.name, "string")
  vim.validate("config.init", config.init, "function", true)
  vim.validate("config.update", config.update, "function")

  M.animations[config.name] = config
end

---@param name string
local register_builtin_animation = function(name)
  local config = assert(require(string.format("cellular-automaton.animations.%s", name)))
  if not config.name or config.name == "" then
    config.name = name
  end
  M.register_animation(config)
end

register_builtin_animation("make_it_rain")
register_builtin_animation("game_of_life")
register_builtin_animation("scramble")

---@param animation_name string
M.start_animation = function(animation_name)
  -- Make sure animaiton exists
  if M.animations[animation_name] == nil then
    error("Error while starting an animation. Unknown cellular-automaton animation: " .. animation_name)
  end

  manager.execute_animation(M.animations[animation_name])
end

return M
