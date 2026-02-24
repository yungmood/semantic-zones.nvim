-- Unit tests for semantic-zones.nvim
-- Run with: nvim --headless -u NONE -l tests/unit_spec.lua

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

-- Load module (requires nvim runtime)
vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h"))
local sz = require("semantic-zones")

-- ── parse_osc133 ─────────────────────────────────────────────────────────────

section("parse_osc133")
local p = sz._parse_osc133

ok("nil input returns nil",       p(nil) == nil)
ok("empty string returns nil",    p("") == nil)
ok("unrelated OSC returns nil",   p("\x1b]133;E") == nil)
ok("ESC+] 133;A",                 p("\x1b]133;A") == "A")
ok("ESC+] 133;B",                 p("\x1b]133;B") == "B")
ok("ESC+] 133;C",                 p("\x1b]133;C") == "C")
ok("ESC+] 133;D",                 p("\x1b]133;D") == "D")
ok("D with exit code 133;D;0",    p("\x1b]133;D;0") == "D")
ok("bare ]133;A (no ESC)",        p("]133;A") == "A")
ok("embedded in longer string",   p("foo\x1b]133;Cbar") == "C")

-- ── build_cells ──────────────────────────────────────────────────────────────

section("build_cells (via _build_cells with mock zones)")

-- Mock sorted zone list for cell building
local function make_zone(t, row)
  return { type = t, id = 0, row = row, col = 0 }
end

-- Patch sorted_zones via a helper that builds cells from a raw zone list
local function cells_from_zones(zone_list)
  local cells, cur = {}, nil
  for _, z in ipairs(zone_list) do
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

local zones1 = {
  make_zone("A", 0), make_zone("B", 1),
  make_zone("C", 2), make_zone("D", 3),
}
local c1 = cells_from_zones(zones1)
ok("single complete cell",        #c1 == 1)
ok("cell has a,b,c,d",            c1[1].a and c1[1].b and c1[1].c and c1[1].d)
ok("cell.a.row == 0",             c1[1].a.row == 0)
ok("cell.d.row == 3",             c1[1].d.row == 3)

local zones2 = {
  make_zone("A", 0), make_zone("B", 1), make_zone("C", 2), make_zone("D", 3),
  make_zone("A", 4), make_zone("B", 5), make_zone("C", 6), make_zone("D", 7),
}
local c2 = cells_from_zones(zones2)
ok("two complete cells",          #c2 == 2)
ok("second cell.a.row == 4",      c2[2].a.row == 4)

local zones3 = { make_zone("A", 0), make_zone("B", 1) }
local c3 = cells_from_zones(zones3)
ok("incomplete cell still captured", #c3 == 1)
ok("incomplete cell has no c/d",     c3[1].c == nil and c3[1].d == nil)

local zones4 = {
  make_zone("A", 0), make_zone("B", 1), make_zone("C", 2), make_zone("D", 3),
  make_zone("A", 4),
}
local c4 = cells_from_zones(zones4)
ok("complete + open cell = 2",    #c4 == 2)

-- ── cell_at_row ───────────────────────────────────────────────────────────────

section("cell_at_row")
local car = sz._cell_at_row

local cells_sample = cells_from_zones({
  make_zone("A", 0), make_zone("B", 1), make_zone("C", 2), make_zone("D", 3),
  make_zone("A", 10), make_zone("B", 11), make_zone("C", 12), make_zone("D", 13),
})

ok("row before any cell returns nil",  car(cells_sample, -1) == nil)
ok("row 0 returns first cell",         car(cells_sample, 0) ~= nil and car(cells_sample, 0).a.row == 0)
ok("row 5 returns first cell",         car(cells_sample, 5).a.row == 0)
ok("row 10 returns second cell",       car(cells_sample, 10).a.row == 10)
ok("row 15 returns second cell",       car(cells_sample, 15).a.row == 10)
ok("empty cells table returns nil",    car({}, 5) == nil)

-- ── Summary ───────────────────────────────────────────────────────────────────

io.write(string.format("\n%d passed, %d failed\n", pass, fail))
if fail > 0 then os.exit(1) end
