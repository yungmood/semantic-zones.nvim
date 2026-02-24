-- Integration tests for semantic-zones.nvim
-- Run with: nvim --headless -u NONE -l tests/integration_spec.lua

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
  io.write("\n" .. name .. "\n")
end

vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h"))
local sz = require("semantic-zones")

-- ── setup / teardown helpers ─────────────────────────────────────────────────

local function make_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "terminal", { buf = buf })
  return buf
end

local function inject_zones(buf, zone_seq)
  -- Manually seed internal state the same way record_zone does,
  -- so integration tests can run headlessly without a real terminal.
  local ns = vim.api.nvim_create_namespace("semantic_zones")
  for row, zone_type in ipairs(zone_seq) do
    local id = vim.api.nvim_buf_set_extmark(buf, ns, row - 1, 0, { right_gravity = false })
    sz._inject(buf, zone_type, id)
  end
end

-- ── Plugin setup ──────────────────────────────────────────────────────────────

section("setup")
local ok_setup, err = pcall(function() sz.setup({}) end)
ok("setup() completes without error", ok_setup)

-- ── cells() API ───────────────────────────────────────────────────────────────

section("cells() API")
local buf = make_buf()
local initial_cells = sz.cells(buf)
ok("fresh buffer returns empty cells", type(initial_cells) == "table" and #initial_cells == 0)

-- ── clear() API ───────────────────────────────────────────────────────────────

section("clear() API")
local buf2 = make_buf()
sz.clear(buf2)
ok("clear() on empty buffer does not error", true)
local after_clear = sz.cells(buf2)
ok("cells() after clear() returns empty table", #after_clear == 0)

-- ── Keymap registration ───────────────────────────────────────────────────────

section("keymap registration")
sz.setup({})
local term_buf = make_buf()
-- Fire TermOpen manually to trigger keymap setup
vim.api.nvim_exec_autocmds("TermOpen", { buffer = term_buf })

local keymaps = vim.api.nvim_buf_get_keymap(term_buf, "n")
local function has_map(maps, lhs)
  for _, m in ipairs(maps) do
    if m.lhs == lhs then return true end
  end
  return false
end
ok("]c mapped in terminal buffer",  has_map(keymaps, "]c"))
ok("[c mapped in terminal buffer",  has_map(keymaps, "[c"))
ok("; mapped in terminal buffer",   has_map(keymaps, ";"))
ok(", mapped in terminal buffer",   has_map(keymaps, ","))

local xmaps = vim.api.nvim_buf_get_keymap(term_buf, "x")
ok("ic text object in visual mode", has_map(xmaps, "ic"))
ok("oc text object in visual mode", has_map(xmaps, "oc"))
ok("ac text object in visual mode", has_map(xmaps, "ac"))

local omaps = vim.api.nvim_buf_get_keymap(term_buf, "o")
ok("ic text object in op-pending mode", has_map(omaps, "ic"))
ok("oc text object in op-pending mode", has_map(omaps, "oc"))
ok("ac text object in op-pending mode", has_map(omaps, "ac"))

-- ── No leader maps ────────────────────────────────────────────────────────────

section("no leader maps")
local function has_leader_map(maps)
  for _, m in ipairs(maps) do
    if m.lhs:match("^<leader>") then return true end
  end
  return false
end
ok("no <leader> maps in normal mode", not has_leader_map(keymaps))
ok("no <leader> maps in visual mode", not has_leader_map(xmaps))

-- ── Custom keymap override ────────────────────────────────────────────────────

section("custom keymap override")
local buf3 = make_buf()
sz.setup({ keymaps = { next_cell = "gj", prev_cell = "gk", repeat_fwd = false, repeat_back = false } })
vim.api.nvim_exec_autocmds("TermOpen", { buffer = buf3 })
local km3 = vim.api.nvim_buf_get_keymap(buf3, "n")
ok("custom next_cell gj is mapped",     has_map(km3, "gj"))
ok("custom prev_cell gk is mapped",     has_map(km3, "gk"))
ok("disabled repeat_fwd not mapped",    not has_map(km3, ";"))

-- ── OSC 133 parse round-trip ──────────────────────────────────────────────────

section("OSC 133 parse round-trip")
local p = sz._parse_osc133
ok("A round-trip",  p("\x1b]133;A") == "A")
ok("B round-trip",  p("\x1b]133;B") == "B")
ok("C round-trip",  p("\x1b]133;C") == "C")
ok("D round-trip",  p("\x1b]133;D") == "D")
ok("D;0 round-trip", p("\x1b]133;D;0") == "D")

-- ── Summary ───────────────────────────────────────────────────────────────────

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
if fail > 0 then os.exit(1) end
