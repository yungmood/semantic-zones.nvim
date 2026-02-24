--- semantic-zones.nvim
--- Tracks OSC 133 semantic-prompt zones in Neovim terminal buffers and
--- provides unimpaired-style cell navigation plus yank helpers.
---
--- OSC 133 zone markers (Per Bothner / freedesktop semantic-prompts spec):
---   ESC ] 133 ; A ST  – prompt start
---   ESC ] 133 ; B ST  – prompt end / command-input start
---   ESC ] 133 ; C ST  – command-input end / output start
---   ESC ] 133 ; D ST  – output end  (may carry exit code: 133;D;0)
---
--- A "cell" is the group A → B → C → D for one shell command cycle.

local M = {}

-- Namespace for extmarks
local ns = vim.api.nvim_create_namespace("semantic_zones")

--- Per-buffer state table.
--- state[bufnr] = { zones = { {type, id} ... }, last_dir = 1 | -1 | nil }
local state = {}

local function buf_state(buf)
  if not state[buf] then
    state[buf] = { zones = {}, last_dir = nil }
  end
  return state[buf]
end

-- ── Zone recording ────────────────────────────────────────────────────────────

--- Return the 0-indexed row of the terminal cursor for *buf*.
--- Falls back to the last line of the buffer when no window is found.
local function term_cursor_row(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local ok, pos = pcall(vim.api.nvim_win_get_cursor, win)
    if ok then
      return pos[1] - 1 -- nvim cursor is 1-indexed; extmarks are 0-indexed
    end
  end
  return math.max(0, vim.api.nvim_buf_line_count(buf) - 1)
end

--- Place an extmark at the current terminal cursor row and remember the zone.
local function record_zone(buf, zone_type)
  local row = term_cursor_row(buf)
  local id = vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
    right_gravity = false,
  })
  local s = buf_state(buf)
  table.insert(s.zones, { type = zone_type, id = id })
end

--- Parse an OSC 133 zone letter (A/B/C/D) from a raw terminal sequence.
--- Handles both ESC ] … BEL and ESC ] … ST terminators.
local function parse_osc133(data)
  -- ESC ] 133 ; X  (where X is A, B, C, or D, possibly followed by ; params)
  return (data or ""):match("\x1b%]133;([ABCD])")
    or (data or ""):match("^%]133;([ABCD])") -- without leading ESC (rare)
end

-- ── Cell building ─────────────────────────────────────────────────────────────

--- Return all zones with their current positions, sorted by (row, col).
local function sorted_zones(buf)
  local s = buf_state(buf)
  local result = {}
  for _, z in ipairs(s.zones) do
    local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, z.id, {})
    if pos and #pos >= 2 then
      result[#result + 1] = { type = z.type, id = z.id, row = pos[1], col = pos[2] }
    end
  end
  table.sort(result, function(a, b)
    return a.row < b.row or (a.row == b.row and a.col < b.col)
  end)
  return result
end

--- Group zones into cells.  Each cell is a table with optional fields
--- a, b, c, d (each a zone entry with .row, .col, .id).
local function build_cells(buf)
  local zones = sorted_zones(buf)
  local cells, cur = {}, nil
  for _, z in ipairs(zones) do
    if z.type == "A" then
      if cur then cells[#cells + 1] = cur end
      cur = { a = z }
    elseif z.type == "B" and cur then
      cur.b = z
    elseif z.type == "C" and cur then
      cur.c = z
    elseif z.type == "D" and cur then
      cur.d = z
      cells[#cells + 1] = cur
      cur = nil
    end
  end
  if cur then cells[#cells + 1] = cur end
  return cells
end

--- Return the most-recent cell whose prompt starts at or before *row*.
local function cell_at_row(cells, row)
  local result
  for _, cell in ipairs(cells) do
    if cell.a.row <= row then
      result = cell
    end
  end
  return result
end

-- ── Navigation ────────────────────────────────────────────────────────────────

--- Jump to the next (direction=1) or previous (direction=-1) cell start.
--- Records the direction so `;` / `,` can repeat it.
local function nav_cell(direction)
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "terminal" then return end

  local win = vim.api.nvim_get_current_win()
  local cells = build_cells(buf)
  if #cells == 0 then return end

  local cur_row = vim.api.nvim_win_get_cursor(win)[1] - 1 -- 0-indexed
  local target

  if direction > 0 then
    for _, cell in ipairs(cells) do
      if cell.a.row > cur_row then
        target = cell
        break
      end
    end
  else
    for i = #cells, 1, -1 do
      if cells[i].a.row < cur_row then
        target = cells[i]
        break
      end
    end
  end

  if target then
    vim.api.nvim_win_set_cursor(win, { target.a.row + 1, 0 })
  end

  buf_state(buf).last_dir = direction
end

--- Repeat the last cell navigation.  *reverse* flips the stored direction.
local function repeat_nav(reverse)
  local buf = vim.api.nvim_get_current_buf()
  local s = buf_state(buf)
  if not s.last_dir then return end
  nav_cell(reverse and -s.last_dir or s.last_dir)
end

-- ── Yank / select helpers ────────────────────────────────────────────────────

--- Yank lines [start_row, end_row) (0-indexed, end exclusive) into the
--- unnamed register as a linewise yank.
local function yank_lines(buf, start_row, end_row)
  if start_row >= end_row then return end
  local lines = vim.api.nvim_buf_get_lines(buf, start_row, end_row, false)
  if #lines == 0 then return end
  vim.fn.setreg('"', table.concat(lines, "\n") .. "\n", "l")
  vim.notify(string.format("[semantic-zones] yanked %d line(s)", #lines))
end

--- Visually select lines [start_row, end_row) (0-indexed, end exclusive).
local function select_lines(win, start_row, end_row)
  if start_row >= end_row then return end
  vim.api.nvim_win_set_cursor(win, { start_row + 1, 0 })
  vim.cmd("normal! V")
  vim.api.nvim_win_set_cursor(win, { end_row, 0 }) -- end_row is exclusive → last line = end_row-1+1
end

--- Yank or visually select a zone relative to the cursor.
--- *op*   = "yank" | "select"
--- *zone* = "input" | "output" | "cell"
local function zone_op(op, zone)
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "terminal" then return end

  local win = vim.api.nvim_get_current_win()
  local cells = build_cells(buf)
  local cur_row = vim.api.nvim_win_get_cursor(win)[1] - 1
  local cell = cell_at_row(cells, cur_row)

  if not cell then
    vim.notify("[semantic-zones] no cell at cursor", vim.log.levels.WARN)
    return
  end

  local start_row, end_row

  if zone == "input" then
    -- Input: from B (or A when B is absent) up to (not including) C or D
    local s = cell.b or cell.a
    local e = cell.c or cell.d
    if s and e then
      start_row, end_row = s.row, e.row
    end
  elseif zone == "output" then
    -- Output: from C up to (not including) D
    if cell.c and cell.d then
      start_row, end_row = cell.c.row, cell.d.row
    else
      vim.notify("[semantic-zones] no output zone found", vim.log.levels.WARN)
      return
    end
  elseif zone == "cell" then
    -- Whole cell: from A up to and including D (or the last available marker)
    local e = cell.d or cell.c or cell.b
    if e then
      start_row, end_row = cell.a.row, e.row + 1
    else
      start_row, end_row = cell.a.row, cell.a.row + 1
    end
  end

  if not start_row then
    vim.notify("[semantic-zones] zone boundaries not available", vim.log.levels.WARN)
    return
  end

  if op == "yank" then
    yank_lines(buf, start_row, end_row)
  elseif op == "select" then
    select_lines(win, start_row, end_row)
  end
end

-- ── Buffer-local keymaps ──────────────────────────────────────────────────────

local function setup_keymaps(buf, km)
  local function map(lhs, fn)
    if lhs and lhs ~= "" then
      vim.keymap.set("n", lhs, fn, { buffer = buf, silent = true, noremap = true })
    end
  end

  map(km.next_cell,    function() nav_cell(1) end)
  map(km.prev_cell,    function() nav_cell(-1) end)
  map(km.repeat_fwd,   function() repeat_nav(false) end)
  map(km.repeat_back,  function() repeat_nav(true) end)

  map(km.yank_input,   function() zone_op("yank",   "input") end)
  map(km.yank_output,  function() zone_op("yank",   "output") end)
  map(km.yank_cell,    function() zone_op("yank",   "cell") end)

  map(km.select_input,  function() zone_op("select", "input") end)
  map(km.select_output, function() zone_op("select", "output") end)
  map(km.select_cell,   function() zone_op("select", "cell") end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Default configuration.
M.defaults = {
  keymaps = {
    next_cell    = "]c",
    prev_cell    = "[c",
    repeat_fwd   = ";",
    repeat_back  = ",",
    yank_input   = "<leader>yi",
    yank_output  = "<leader>yo",
    yank_cell    = "<leader>yc",
    select_input  = "<leader>si",
    select_output = "<leader>so",
    select_cell   = "<leader>sc",
  },
}

--- Set up the plugin.
---@param opts? table Optional configuration (merged with M.defaults).
function M.setup(opts)
  if vim.fn.has("nvim-0.10") == 0 then
    vim.notify("[semantic-zones] requires Neovim >= 0.10", vim.log.levels.ERROR)
    return
  end

  local cfg = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})

  local group = vim.api.nvim_create_augroup("SemanticZones", { clear = true })

  vim.api.nvim_create_autocmd("TermOpen", {
    group = group,
    callback = function(ev)
      local buf = ev.buf
      buf_state(buf) -- initialise

      -- Intercept OSC 133 sequences emitted by the shell
      vim.api.nvim_create_autocmd("TermRequest", {
        group = group,
        buffer = buf,
        callback = function(req_ev)
          local data = (req_ev.data ~= nil and req_ev.data ~= "") and req_ev.data
            or vim.v.termrequest
          local zone_type = parse_osc133(data)
          if zone_type then
            record_zone(buf, zone_type)
          end
        end,
      })

      setup_keymaps(buf, cfg.keymaps)

      -- Release state when the buffer is wiped
      vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
        group = group,
        buffer = buf,
        once = true,
        callback = function()
          state[buf] = nil
        end,
      })
    end,
  })
end

--- Return cell data for *buf* (defaults to current buffer).
--- Useful for debugging: `:lua vim.print(require('semantic-zones').cells())`
function M.cells(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  return build_cells(buf)
end

--- Clear all recorded zones for *buf* (defaults to current buffer).
function M.clear(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  state[buf] = nil
end

return M
