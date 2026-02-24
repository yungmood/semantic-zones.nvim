# semantic-zones.nvim

Tracks [OSC 133](https://gitlab.freedesktop.org/Per_Bothner/specifications/blob/master/proposals/semantic-prompts.md) semantic-prompt zones in Neovim terminal buffers and exposes them as navigable cells and text objects.

## Requirements

- Neovim ≥ 0.10
- A shell with OSC 133 support (see [Shell integration](#shell-integration) below, or use WezTerm/Kitty built-in integration)

## Installation

**Neovim 0.12+ native**
```lua
vim.pack.add("yungmood/semantic-zones.nvim")
```

**lazy.nvim**
```lua
{ "yungmood/semantic-zones.nvim", config = true }
```

Call `require("semantic-zones").setup()` unless your plugin manager does it for you (e.g. `config = true`).

## Usage

All keymaps are local to terminal buffers.

| Key   | Action                     |
|-------|----------------------------|
| `]c`  | Next cell                  |
| `[c`  | Previous cell              |
| `;`   | Repeat last jump           |
| `,`   | Repeat last jump (reverse) |
| `ic`  | Text object: input zone    |
| `oc`  | Text object: output zone   |
| `ac`  | Text object: entire cell   |

Text objects work with any operator — `yic`, `dic`, `vac`, etc.

## Configuration

```lua
require("semantic-zones").setup({
  keymaps = {
    next_cell   = "]c",
    prev_cell   = "[c",
    repeat_fwd  = ";",
    repeat_back = ",",
  },
})
```

Set any value to `false` to disable that mapping.

## Shell integration

```bash
_semantic_precmd()  { printf '\e]133;D\e\\\e]133;A\e\\'; }
_semantic_prompt()  { printf '\e]133;B\e\\'; }
_semantic_preexec() { printf '\e]133;C\e\\'; }
```

### zsh 
```zsh
add-zsh-hook precmd  _semantic_precmd
add-zsh-hook precmd  _semantic_prompt
add-zsh-hook preexec _semantic_preexec
```

### bash
```bash
PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_semantic_precmd;_semantic_prompt"
trap '_semantic_preexec' DEBUG
```

## API

```lua
local sz = require("semantic-zones")

sz.cells(buf)  -- SemanticCell[] — all cells in buf (defaults to current buffer)
sz.clear(buf)  -- clear all recorded zones for buf
```

A `SemanticCell` is `{ a, b?, c?, d? }` where each field is a `SemanticZone` with `.row`, `.col`, `.type`, and `.id`.

