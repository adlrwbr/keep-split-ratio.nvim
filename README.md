# 🪟 keep-split-ratio.nvim

Preserve split percentages on UI resize. If you have 70/30 or 50/50 vertical splits, resizing your terminal/editor resizes the splits proportionally.

- Lightweight. Does nothing until `VimResized` fires.
- Per-tab state.
- Respects `winfixwidth` columns (they keep their width).

## Install

### Lazy.nvim
```lua
{ "adlrwbr/keep-split-ratio.nvim", opts = {} }
```

## Demo

As we resize the window,

| Default | with `keep-split-ratio.nvim` |
| --- | --- |
| only the right side grows and shrinks | both splits grow and shrink

![demo](./demo.gif)
