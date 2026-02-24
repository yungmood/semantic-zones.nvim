---@class SemanticZone
---@field type string
---@field id integer
---@field row integer
---@field col integer

---@class SemanticCell
---@field a SemanticZone
---@field b? SemanticZone
---@field c? SemanticZone
---@field d? SemanticZone

---@class SemanticZonesKeymaps
---@field next_cell string|false
---@field prev_cell string|false
---@field repeat_fwd string|false
---@field repeat_back string|false

---@class SemanticZonesConfig
---@field keymaps SemanticZonesKeymaps

local M = {}

local ns = vim.api.nvim_create_namespace("semantic_zones")

---@type table<integer, {zones: {type: string, id: integer}[], last_dir: integer?}>
local state = {}

---@param buf integer
---@return {zones: {type: string, id: integer}[], last_dir: integer?}
local function buf_state(buf)
  if not state[buf] then
    state[buf] = { zones = {}, last_dir = nil }
  end
  return state[buf]
end

---@param buf integer
---@return integer
local function term_cursor_row(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local ok, pos = pcall(vim.api.nvim_win_get_cursor, win)
    if ok then return pos[1] - 1 end
  end
  return math.max(0, vim.api.nvim_buf_line_count(buf) - 1)
end

---@param buf integer
---@param zone_type string
local function record_zone(buf, zone_type)
  local row = term_cursor_row(buf)
  local id = vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { right_gravity = false })
  table.insert(buf_state(buf).zones, { type = zone_type, id = id })
end

---@param data? string
---@return string?
local function parse_osc133(data)
  return (data or ""):match("\x1b%]133;([ABCD])")
    or (data or ""):match("^%]133;([ABCD])")
end

---@param buf integer
---@return SemanticZone[]
local function sorted_zones(buf)
  local result = {}
  for _, z in ipairs(buf_state(buf).zones) do
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

---@param buf integer
---@return SemanticCell[]
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

---@param cells SemanticCell[]
---@param row integer
---@return SemanticCell?
local function cell_at_row(cells, row)
  local result
  for _, cell in ipairs(cells) do
    if cell.a.row <= row then result = cell end
  end
  return result
end

---@param direction integer
local function nav_cell(direction)
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "terminal" then return end
  local win = vim.api.nvim_get_current_win()
  local cells = build_cells(buf)
  if #cells == 0 then return end
  local cur_row = vim.api.nvim_win_get_cursor(win)[1] - 1
  local target
  if direction > 0 then
    for _, cell in ipairs(cells) do
      if cell.a.row > cur_row then target = cell; break end
    end
  else
    for i = #cells, 1, -1 do
      if cells[i].a.row < cur_row then target = cells[i]; break end
    end
  end
  if target then vim.api.nvim_win_set_cursor(win, { target.a.row + 1, 0 }) end
  buf_state(buf).last_dir = direction
end

---@param reverse boolean
local function repeat_nav(reverse)
  local buf = vim.api.nvim_get_current_buf()
  local s = buf_state(buf)
  if not s.last_dir then return end
  nav_cell(reverse and -s.last_dir or s.last_dir)
end

---@param start_row integer
---@param end_row integer
local function select_region(start_row, end_row)
  if start_row >= end_row then return end
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(win, { start_row + 1, 0 })
  vim.cmd("normal! V")
  vim.api.nvim_win_set_cursor(win, { end_row, 0 })
end

---@param zone "input"|"output"|"cell"
local function zone_textobj(zone)
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
    local s = cell.b or cell.a
    local e = cell.c or cell.d
    if s and e then start_row, end_row = s.row, e.row end
  elseif zone == "output" then
    if cell.c and cell.d then
      start_row, end_row = cell.c.row, cell.d.row
    else
      vim.notify("[semantic-zones] no output zone", vim.log.levels.WARN)
      return
    end
  elseif zone == "cell" then
    local e = cell.d or cell.c or cell.b
    start_row = cell.a.row
    end_row = e and (e.row + 1) or (cell.a.row + 1)
  end
  if not start_row then
    vim.notify("[semantic-zones] zone boundaries not available", vim.log.levels.WARN)
    return
  end
  select_region(start_row, end_row)
end

---@param buf integer
---@param km SemanticZonesKeymaps
local function setup_keymaps(buf, km)
  ---@param mode string|string[]
  ---@param lhs string|false
  ---@param fn function
  local function map(mode, lhs, fn)
    if lhs and lhs ~= "" then
      vim.keymap.set(mode, lhs, fn, { buffer = buf, silent = true, noremap = true })
    end
  end
  map("n", km.next_cell,   function() nav_cell(1) end)
  map("n", km.prev_cell,   function() nav_cell(-1) end)
  map("n", km.repeat_fwd,  function() repeat_nav(false) end)
  map("n", km.repeat_back, function() repeat_nav(true) end)
  map({ "x", "o" }, "ic", function() zone_textobj("input") end)
  map({ "x", "o" }, "oc", function() zone_textobj("output") end)
  map({ "x", "o" }, "ac", function() zone_textobj("cell") end)
end

---@type SemanticZonesConfig
M.defaults = {
  keymaps = {
    next_cell   = "]c",
    prev_cell   = "[c",
    repeat_fwd  = ";",
    repeat_back = ",",
  },
}

---@param opts? SemanticZonesConfig
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
      buf_state(buf)
      vim.api.nvim_create_autocmd("TermRequest", {
        group = group,
        buffer = buf,
        callback = function(req_ev)
          local data = (req_ev.data ~= nil and req_ev.data ~= "") and req_ev.data
            or vim.v.termrequest
          local zone_type = parse_osc133(data)
          if zone_type then record_zone(buf, zone_type) end
        end,
      })
      setup_keymaps(buf, cfg.keymaps)
      vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
        group = group,
        buffer = buf,
        once = true,
        callback = function() state[buf] = nil end,
      })
    end,
  })
end

---@param buf? integer
---@return SemanticCell[]
function M.cells(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  return build_cells(buf)
end

---@param buf? integer
function M.clear(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  state[buf] = nil
end

M._parse_osc133 = parse_osc133
M._build_cells = build_cells
M._cell_at_row = cell_at_row

---@param buf integer
---@param zone_type string
---@param id integer
function M._inject(buf, zone_type, id)
  table.insert(buf_state(buf).zones, { type = zone_type, id = id })
end

return M
