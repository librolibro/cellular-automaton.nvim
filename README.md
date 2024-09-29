# cellular-automaton.nvim

A useless plugin that might help you cope with stubbornly broken tests
or overall lack of sense in life. It lets you execute aesthetically pleasing,
cellular automaton animations based on the content of neovim buffer.

https://user-images.githubusercontent.com/37074839/204104990-6ebd7767-92e9-43b9-878a-3493a08a3308.mov


## What is cellular automata

From the [Wiki](https://en.wikipedia.org/wiki/Cellular_automaton):

> A cellular automaton is a model used in computer science and mathematics.
> The idea is to model a dynamic system by using a number of cells. Each cell
> has one of several possible states. With each "turn" or iteration
> the state of the current cell is determined by two things: its
> current state, and the states of the neighbouring cells.

## But.. why?

There is no pragmatic use case whatsoever. However,
there are some pseudo-scientifically proven "use-cases":

- Urgent deadline approaches? Don't worry. With
    this plugin you can procrastinate even more!
- Are you stuck and don't know how to proceed? You can
    use this plugin as a visual stimulant for epic ideas!
- Those nasty colleagues keep peeking over your
    shoulder and stealing your code? Now you can
    obfuscate your editor! Good luck stealing that.
- Working with legacy code? Just create a
    `<leader>fml` mapping and see it melt.

## Requirements

- neovim >= 0.9

## Installation

```
use 'eandrju/cellular-automaton.nvim' 
```

## Usage

You can trigger it using simple command:

```
:CellularAutomaton make_it_rain
```

or

```
:CellularAutomaton game_of_life
```

Or just create a mapping:

```lua
vim.keymap.set("n", "<leader>fml", "<cmd>CellularAutomaton make_it_rain<CR>")

-- Same but using Lua API
vim.keymap.set("n", "<leader>fml", function()
  require("cellular-automaton").start_animation("make_it_rain")
  -- Or this:
  -- require("cellular-automaton").start_animation("make_it_rain", 0)
end)
```

To start the animation for not current buffer:

```lua
-- winid is the 'window-ID' of the window you want animation to start in
require("cellular-automaton").start_animation("make_it_rain", winid)
```

You can close animation window with one of: `q`/`Q`/`<Esc>`/`<CR>`.
Also the animation will end if you'll close/resize animation
window, or if you'll close/leave the tabpage.

### Change animation FPS

That's how you can dynamically change animation FPS:

```lua
local map_automaton = function(lhs, automaton_name, default_fps)
  -- Setting default FPS at the beginning
  assert(require("cellular-automaton").animations[automaton_name]).fps = default_fps
  vim.keymap.set(
    "n",
    lhs,
    function()
      -- Retrieving out automaton configuration
      local ca = require("cellular-automaton")
      local automaton = assert(ca.animations[automaton_name])

      -- Some FPS boundaries (you might
      -- set your own or skip that part)
      local fps_min = 1; local fps_max = 50
      local fps = vim.v.count ~= 0 and vim.v.count or assert(automaton.fps)

      if fps < fps_min or fps > fps_max then
        vim.api.nvim_echo({
          { automaton_name, "ErrorMsg" },
          {
            string.format(
              ": FPS in range [%d, %d] expected but"
                .. " %d given (use ':h count' to change FPS)",
              fps_min,
              fps_max,
              fps
            ),
            "Normal",
          },
        }, true, {})
        return
      end

      -- Setting new FPS before animation starts
      automaton.fps = fps
      ca.start_animation(automaton_name)
    end,
    { desc = string.format('Execute "%s" automaton', automaton_name) }
  )
end

map_automaton("<leader>fml", "make_it_rain", 25)
```

- `<leader>fml` will start animation at 25 FPS (since it's the default value),
- Using `15<leader>fml` will start animation at 15 FPS - next
    `<leader>fml` will also use 15 FPS since it's the
    last value used and you didn't overwrite it.
    - (see `:h count` or `:h [count]` for more info
        about count before the command works)

## Fork goals

- [x] Proper UTF-8 and tab support
- [x] Using `vim.inspect_pos()` for better and more accurate
    highlighting (support for old-style and extmark-based
    highlighting including LSP semantic tokens and any
    other custom extmark, e.g. the ones
    nvim-colorizer applies)
- [x] `getwininfo()` usage
    - [x] get rid of monstrous VimL function - just use *textoff* field
    - [x] reproduce *textoff* for created window
- [x] support splits (create window on top of the host window
    at the same place, relative to it but not to the editor)
- [x] `strtrans()` support
- [ ] support MORE extmarks (e.g. diagnostics)
- [x] more flexible **make_it_rain** configuration
- [x] support for nested animations (if they're on the same tabpage)
    - didn't test it properly but looks like it's working
- [x] ability to start animation for not current window
- [x] disable `colorcolumn`/`cursorline` for animation window
- [ ] `listchars` support?
- [ ] wrap support
    - [x] minimal support added (only respecting 'wrap', 'display' and
        'fillchars' but not 'linebreak', 'showbreak', 'breatat' and 'wrapmargin')
        - code is messy and ugly as hell ... need to refactor
            this because the more I write the less I understand :)
- [ ] fold support
- [ ] conceal support (both old-style and extmark-based)
- [ ] ability to also fall down numbers, folds and signs?
- [ ] better performance
    - the more things I made in this project the bigger startuptime is
        (I mean *load_base_grid* execution time): more difficult virtual
        column iteration, there's whole extmark stack for highlighting
        (not just one highlight group) etc. It is possible
        to make some performance improvements?

## Supported animations

### Make it Rain

https://user-images.githubusercontent.com/37074839/204104990-6ebd7767-92e9-43b9-878a-3493a08a3308.mov

### Game of Life

https://user-images.githubusercontent.com/37074839/204162517-35b429ad-4cef-45b1-b680-bc7a69a4e8c7.mov

## Implementing your own cellular automaton logic
Using a simple interface you can implement your own cellular automaton
animation. You need to provide a configuration table with an `update` method,
which takes a 2D grid of cells and modifies it in place \(base types described
in [types.lua](./lua/cellular-automaton/types.lua) file\).

Example sliding animation:

```lua
local config = {
    fps = 50,
    name = 'slide',
}

-- init method is invoked only once at the start
-- function config:init(grid) end

-- update method
function config:update(grid)
    for i = 1, #grid do
        local prev = grid[i][#(grid[i])]
        for j = 1, #(grid[i]) do
            grid[i][j], prev = prev, grid[i][j]
        end
    end
    return true
end

require("cellular-automaton").register_animation(config)
```

Result:

https://user-images.githubusercontent.com/37074839/204161376-3b10aadd-90e1-4059-b701-ce318085622c.mov

## Inspiration and references
- https://www.youtube.com/watch?v=5Ka3tbbT-9E
- https://www.youtube.com/watch?v=prXuyMCgbTc
