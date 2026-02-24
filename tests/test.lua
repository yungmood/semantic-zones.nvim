-- Run with: nvim --headless -u NONE -l tests/test.lua

local pass, fail = 0, 0

local function ok(desc, cond)
  if cond then
    pass = pass + 1
    io.write("  [PASS] " .. desc .. "\n")
  else
    fail = fail + 1
    io.write("  [FAIL] " .. desc .. "\n")
  end
end

local function section(name)
  io.write("\n" .. name .. "\n" .. string.rep("-", #name) .. "\n")
end

vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h"))
local sz = require("semantic-zones")

-- ── helpers ───────────────────────────────────────────────────────────────────

local function make_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "terminal", { buf = buf })
  return buf
end

-- Seed internal state so tests run headlessly without a real terminal.
-- zone_seq is a list of zone type strings, one per row, e.g. {"A","B","C","D"}.
local function inject_zones(buf, zone_seq)
  local ext_ns = vim.api.nvim_create_namespace("semantic_zones")
  -- Ensure the buffer has enough lines for the extmarks.
  local needed = #zone_seq
  local current = vim.api.nvim_buf_line_count(buf)
  if current < needed then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn["repeat"]({ "" }, needed))
  end
  for row, zone_type in ipairs(zone_seq) do
    local id = vim.api.nvim_buf_set_extmark(buf, ext_ns, row - 1, 0, { right_gravity = false })
    sz._inject(buf, zone_type, id)
  end
end

-- ── plugin setup ──────────────────────────────────────────────────────────────

section("setup")
local setup_ok, setup_err = pcall(function() sz.setup({}) end)
ok("setup() completes without error", setup_ok)

-- ── OSC 133 parser ────────────────────────────────────────────────────────────

section("OSC 133 parse")
local p = sz._parse_osc133
ok("parses A",       p("\x1b]133;A") == "A")
ok("parses B",       p("\x1b]133;B") == "B")
ok("parses C",       p("\x1b]133;C") == "C")
ok("parses D",       p("\x1b]133;D") == "D")
ok("parses D;0",     p("\x1b]133;D;0") == "D")
ok("nil input",      p(nil) == nil)
ok("empty string",   p("") == nil)
ok("garbage input",  p("not an escape") == nil)

-- ── cells() on fresh buffer ───────────────────────────────────────────────────

section("cells() on fresh buffer")
local empty_buf = make_buf()
local empty_cells = sz.cells(empty_buf)
ok("returns a table",         type(empty_cells) == "table")
ok("returns empty table",     #empty_cells == 0)

-- ── single complete A-B-C-D cell ─────────────────────────────────────────────

section("single complete cell (A B C D)")
local buf1 = make_buf()
inject_zones(buf1, { "A", "B", "C", "D" })
local cells1 = sz.cells(buf1)
ok("exactly one cell",        #cells1 == 1)
ok("cell.a is present",       cells1[1] and cells1[1].a ~= nil)
ok("cell.b is present",       cells1[1] and cells1[1].b ~= nil)
ok("cell.c is present",       cells1[1] and cells1[1].c ~= nil)
ok("cell.d is present",       cells1[1] and cells1[1].d ~= nil)
ok("zones in row order",      cells1[1].a.row < cells1[1].b.row
                               and cells1[1].b.row < cells1[1].c.row
                               and cells1[1].c.row < cells1[1].d.row)

-- ── multiple complete cells ───────────────────────────────────────────────────

section("multiple complete cells")
local buf2 = make_buf()
inject_zones(buf2, { "A", "B", "C", "D", "A", "B", "C", "D" })
local cells2 = sz.cells(buf2)
ok("two cells from two A-D sequences", #cells2 == 2)
ok("second cell starts after first",   cells2[2].a.row > cells2[1].a.row)

-- ── partial cell (no D) ───────────────────────────────────────────────────────

section("partial cell (A B, no C or D)")
local buf3 = make_buf()
inject_zones(buf3, { "A", "B" })
local cells3 = sz.cells(buf3)
ok("partial cell still appears",   #cells3 == 1)
ok("partial cell has .a",          cells3[1].a ~= nil)
ok("partial cell has .b",          cells3[1].b ~= nil)
ok("partial cell has no .d",       cells3[1].d == nil)

-- ── orphan B/C/D before first A are ignored ──────────────────────────────────

section("orphan zones before first A")
local buf4 = make_buf()
inject_zones(buf4, { "B", "C", "D", "A", "B", "C", "D" })
local cells4 = sz.cells(buf4)
ok("orphan B/C/D before A ignored",  #cells4 == 1)
ok("cell starts at the A row",        cells4[1].a.row == 3)  -- 0-indexed row 3

-- ── consecutive A's (prior cell flushed) ─────────────────────────────────────

section("consecutive A zones flush previous cell")
local buf5 = make_buf()
inject_zones(buf5, { "A", "B", "A", "B", "C", "D" })
local cells5 = sz.cells(buf5)
ok("two cells when A follows A",      #cells5 == 2)
ok("first cell has no .d",            cells5[1].d == nil)
ok("second cell is complete",         cells5[2].d ~= nil)

-- ── cell_at_row ───────────────────────────────────────────────────────────────

section("cell_at_row")
local at = sz._cell_at_row
ok("row before any cell → nil",        at(cells2, -1) == nil)
ok("row 0 → first cell",               at(cells2, 0) == cells2[1])
ok("row inside first cell → cell 1",   at(cells2, 2) == cells2[1])
ok("row at second cell's A → cell 2",  at(cells2, cells2[2].a.row) == cells2[2])
ok("row past last cell → last cell",   at(cells2, 999) == cells2[2])

-- ── clear() ───────────────────────────────────────────────────────────────────

section("clear()")
sz.clear(buf1)
ok("cells() empty after clear",         #sz.cells(buf1) == 0)
sz.clear(empty_buf)
ok("clear() on already-empty buf is ok", #sz.cells(empty_buf) == 0)

-- ── keymap registration ───────────────────────────────────────────────────────

section("keymap registration (default)")
sz.setup({})
local term_buf = make_buf()
vim.api.nvim_exec_autocmds("TermOpen", { buffer = term_buf })

local function has_map(maps, lhs)
  for _, m in ipairs(maps) do
    if m.lhs == lhs then return true end
  end
  return false
end

local function has_leader_map(maps)
  for _, m in ipairs(maps) do
    if m.lhs:match("^<leader>") then return true end
  end
  return false
end

local nmaps = vim.api.nvim_buf_get_keymap(term_buf, "n")
local xmaps = vim.api.nvim_buf_get_keymap(term_buf, "x")
local omaps = vim.api.nvim_buf_get_keymap(term_buf, "o")

ok("]c mapped (n)",             has_map(nmaps, "]c"))
ok("[c mapped (n)",             has_map(nmaps, "[c"))
ok("; mapped (n)",              has_map(nmaps, ";"))
ok(", mapped (n)",              has_map(nmaps, ","))
ok("ic mapped (x)",             has_map(xmaps, "ic"))
ok("oc mapped (x)",             has_map(xmaps, "oc"))
ok("ac mapped (x)",             has_map(xmaps, "ac"))
ok("ic mapped (o)",             has_map(omaps, "ic"))
ok("oc mapped (o)",             has_map(omaps, "oc"))
ok("ac mapped (o)",             has_map(omaps, "ac"))
ok("no <leader> maps (n)",      not has_leader_map(nmaps))
ok("no <leader> maps (x)",      not has_leader_map(xmaps))

section("keymap registration (custom / disabled)")
local buf_custom = make_buf()
sz.setup({ keymaps = { next_cell = "gj", prev_cell = "gk", repeat_fwd = false, repeat_back = false } })
vim.api.nvim_exec_autocmds("TermOpen", { buffer = buf_custom })
local nm_custom = vim.api.nvim_buf_get_keymap(buf_custom, "n")
ok("custom next_cell gj mapped",   has_map(nm_custom, "gj"))
ok("custom prev_cell gk mapped",   has_map(nm_custom, "gk"))
ok("disabled repeat_fwd not mapped", not has_map(nm_custom, ";"))
ok("disabled repeat_back not mapped", not has_map(nm_custom, ","))

-- ── summary ───────────────────────────────────────────────────────────────────

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
if fail > 0 then os.exit(1) end
