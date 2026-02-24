# semantic-zones.nvim

Tracks [OSC 133](https://gitlab.freedesktop.org/Per_Bothner/specifications/blob/master/proposals/semantic-prompts.md) semantic-prompt zones in Neovim terminal buffers and exposes them as text objects and navigable regions.

## Requirements

- Neovim ≥ 0.10
- Shell with OSC 133 support (zsh, bash, fish — see shell snippets below — or WezTerm/Kitty built-in integration)

## Installation

**Neovim 0.12+ native**
```lua
vim.pack.add("yungmood/semantic-zones.nvim")
```

**lazy.nvim**
```lua
{ "yungmood/semantic-zones.nvim", config = true }
```

Then call `require("semantic-zones").setup()` unless using `config = true`.

## Keymaps (terminal buffers only)

| Key   | Action                          |
|-------|---------------------------------|
| `]c`  | Next cell                       |
| `[c`  | Previous cell                   |
| `;`   | Repeat last jump                |
| `,`   | Repeat last jump (reverse)      |
| `vic` | Select input (text object)      |
| `voc` | Select output (text object)     |
| `vac` | Select entire cell (text object)|

Text objects `ic`, `oc`, `ac` work with any operator: `y`, `d`, `c`, `v`, etc.

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

Set any key to `""` or `false` to disable it.

## Integration with editable-term.nvim

[editable-term.nvim](https://github.com/xb-bx/editable-term.nvim) provides insert-mode editing of the terminal prompt; semantic-zones.nvim provides text objects and navigation for command output. Load both independently — they do not conflict:

```lua
{ "xb-bx/editable-term.nvim",      config = true },
{ "yungmood/semantic-zones.nvim",   config = true },
```

## API

```lua
local sz = require("semantic-zones")
sz.cells(buf)  -- returns { {a, b?, c?, d?} ... }
sz.clear(buf)  -- clears recorded zones
```

## Shell integration

### zsh
```zsh
precmd()  { print -Pn '\e]133;D\a\e]133;A\a' }
preexec() { print -Pn '\e]133;C\a' }
PS1='%n@%m:%~%# $(print -Pn "\e]133;B\a")'
```

### bash
```bash
PROMPT_COMMAND='printf "\e]133;D\a\e]133;A\a"'
PS1='\u@\h:\w\$ $(printf "\e]133;B\a")'
trap 'printf "\e]133;C\a"' DEBUG
```

### fish
```fish
function __semantic_precmd --on-event fish_prompt
    printf '\e]133;D\a\e]133;A\a'
end
function __semantic_preexec --on-event fish_preexec
    printf '\e]133;C\a'
end
```

## License

MIT
