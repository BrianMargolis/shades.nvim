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
        socket_path = "/tmp/theme-change.sock",
      })
    end,
  }
```
