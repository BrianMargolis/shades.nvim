# shades.nvim

`shades.nvim` is a Neovim client for [`shades`](https://github.com/BrianMargolis/shades).

Installation example with `lazy.nvim`:
```lua
{
    "brianmargolis/shades.nvim",
    name = "shades",
    lazy = false,
    event = "VimEnter",
    config = function()
      require("shades").setup({
        set_color = function(color)
          vim.opt.background = color
        end,
      })
    end,
  }
```

`socket_path` is optional and defaults to `/tmp/theme-change.sock`.

`binary` is optional and defaults to `shades`, looked up on `$PATH`.

If the daemon isn't running, or the connection drops, the plugin retries with
backoff (1s doubling up to 30s) and reapplies the current theme once it
reconnects.

## Commands

- `:Shades toggle` switches to the default theme on the other side (light or
  dark) of the current one, like `shades toggle`.
- `:Shades random` switches to a random theme that is dark if the current one
  is dark, light if it is light.

Both run the `shades` CLI, so the change reaches every client, not just Neovim.
The plugin sets no keybinds; map the Lua functions yourself, e.g. with
`lazy.nvim`'s `keys`:

```lua
keys = {
  { "<leader>tt", function() require("shades").toggle() end, desc = "Toggle light/dark theme" },
  { "<leader>tr", function() require("shades").random() end, desc = "Random theme, same shade" },
},
```

## The palette

`set_color` receives a second argument: the colors of the theme being applied,
keyed by the names shades uses (`BG0` through `BG5`, `BGDIM`, `RED`, `ORANGE`,
`YELLOW`, `GREEN`, `BLUE`, `AQUA`, `PURPLE`, `FG`, `GRAY1` through `GRAY3`).
The daemon resolves it from `shades.yaml` and sends it over the socket, so a
config never has to keep its own copy of a theme's hex values.

```lua
set_color = function(color, palette)
  vim.api.nvim_set_hl(0, "MyStatusline", { fg = palette.FG, bg = palette.BG1 })
end,
```

It is `nil` against a daemon old enough to predate the `palette` message, so
guard before indexing it. The same value is available outside the callback as
`require("shades").palette()`, and `require("shades").get(callback)` passes
`(theme, palette)`.
