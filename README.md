# semantic-zones.nvim

A tiny Neovim plugin that tracks **OSC 133 semantic-prompt zones** in terminal
buffers and turns them into navigable, yankable regions — replicating WezTerm's
"semantic zones" feature entirely inside Neovim.

---

## What are semantic zones?

Shells that support the
[semantic-prompts spec](https://gitlab.freedesktop.org/Per_Bothner/specifications/blob/master/proposals/semantic-prompts.md)
emit OSC 133 escape sequences to annotate the terminal output stream:

| Sequence              | Meaning                                           |
|-----------------------|---------------------------------------------------|
| `ESC ] 133 ; A ST`    | **Prompt start** – shell about to print prompt    |
| `ESC ] 133 ; B ST`    | **Input start** – user starts typing command      |
| `ESC ] 133 ; C ST`    | **Output start** – command running, output begins |
| `ESC ] 133 ; D ST`    | **Output end** – command finished (may include exit code: `D;0`) |

One complete **cell** is the A → B → C → D cycle for a single shell command.

---

## Requirements

- **Neovim ≥ 0.10** (uses the `TermRequest` autocmd event)
- A shell / terminal with OSC 133 integration enabled (see [Shell integration](#shell-integration))

---

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "yungmood/semantic-zones.nvim",
  config = function()
    require("semantic-zones").setup()
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "yungmood/semantic-zones.nvim",
  config = function()
    require("semantic-zones").setup()
  end,
}
```

### Manual (vim-plug, etc.)

```vim
Plug 'yungmood/semantic-zones.nvim'
```

Then in your Lua config:

```lua
require("semantic-zones").setup()
```

---

## Configuration

`setup()` accepts an optional table.  All keys are optional and fall back to
the defaults shown below.

```lua
require("semantic-zones").setup({
  keymaps = {
    -- unimpaired-style cell navigation
    next_cell    = "]c",
    prev_cell    = "[c",
    -- repeat last cell jump (like ; / , for f/F/t/T)
    repeat_fwd   = ";",
    repeat_back  = ",",
    -- yank into the unnamed register
    yank_input   = "<leader>yi",   -- yank the command that was typed
    yank_output  = "<leader>yo",   -- yank the command's output
    yank_cell    = "<leader>yc",   -- yank input + output together
    -- enter visual-line mode covering the region
    select_input  = "<leader>si",
    select_output = "<leader>so",
    select_cell   = "<leader>sc",
  },
})
```

Set any keymap to `""` or `false` to disable it.

All keymaps are **buffer-local** and only active in `terminal` buffers.

---

## Default keymaps (terminal normal mode)

| Key             | Action                                       |
|-----------------|----------------------------------------------|
| `]c`            | Jump to the **next** cell (prompt)           |
| `[c`            | Jump to the **previous** cell (prompt)       |
| `;`             | Repeat last cell jump (same direction)       |
| `,`             | Repeat last cell jump (opposite direction)   |
| `<leader>yi`    | Yank command **i**nput                       |
| `<leader>yo`    | Yank command **o**utput                      |
| `<leader>yc`    | Yank whole **c**ell (input + output)         |
| `<leader>si`    | Visually **s**elect command **i**nput        |
| `<leader>so`    | Visually **s**elect command **o**utput       |
| `<leader>sc`    | Visually **s**elect whole **c**ell           |

---

## Shell integration

Your shell must emit OSC 133 sequences.  Many shells already do this when
running inside WezTerm or with their built-in terminal integration scripts.

### bash

Add to `~/.bashrc` (or `~/.bash_profile`):

```bash
# Semantic-prompt OSC 133 markers
__semantic_prompt_cmd() {
  # D (output end / command end)
  printf '\e]133;D\a'
}
__semantic_prompt_start() {
  # A (prompt start)
  printf '\e]133;A\a'
}
__semantic_prompt_end() {
  # B (input start – end of prompt text)
  printf '\e]133;B\a'
}
__semantic_output_start() {
  # C (output start – user pressed Enter)
  printf '\e]133;C\a'
}

trap '__semantic_output_start' DEBUG
PROMPT_COMMAND='__semantic_prompt_cmd; __semantic_prompt_start'
PS1='\u@\h:\w\$ $(__semantic_prompt_end)'
```

### zsh

Add to `~/.zshrc`:

```zsh
# Semantic-prompt OSC 133 markers
precmd()  { print -Pn '\e]133;D\a\e]133;A\a' }
preexec() { print -Pn '\e]133;C\a' }
PS1='%n@%m:%~%# $(print -Pn "\e]133;B\a")'
```

### fish

Add to `~/.config/fish/config.fish`:

```fish
function __semantic_precmd --on-event fish_prompt
    printf '\e]133;D\a\e]133;A\a'
end
function __semantic_preexec --on-event fish_preexec
    printf '\e]133;C\a'
end
# Append to your existing prompt function:
# printf '\e]133;B\a'
```

### WezTerm / Kitty / iTerm2

These terminals automatically inject OSC 133 markers when their built-in shell
integration is enabled — no extra configuration needed.

---

## API

```lua
local sz = require("semantic-zones")

-- Return a list of cells for a buffer (default: current)
-- Useful for debugging or building custom features
local cells = sz.cells(buf)
-- cells[i] = { a={row,col,id}, b=..., c=..., d=... }

-- Clear all recorded zones for a buffer
sz.clear(buf)
```

---

## How it works

1. On `TermOpen`, the plugin attaches a `TermRequest` autocmd to the terminal buffer.
2. Whenever the shell emits an OSC 133 sequence, Neovim fires `TermRequest`
   and the plugin records the **current terminal cursor row** as an extmark.
3. Extmarks follow text as the terminal scrolls, keeping zone positions accurate.
4. Navigation and yank helpers query the extmarks on demand.

---

## License

MIT
