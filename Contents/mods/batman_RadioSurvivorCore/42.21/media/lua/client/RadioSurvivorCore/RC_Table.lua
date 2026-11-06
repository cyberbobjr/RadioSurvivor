--[[
RadioSurvivorCore: column table of the debug tools (LK13-T15; moved from Living Knox by E18-T09 so that RadioSurvivor's
frequency debug view works without Living Knox). Living Knox keeps the name LivingKnox.Table (LK_Table).
Design: docs/annexes/conception/administration.md, section "Panneau de debug des PNJ". M = vanilla 42.21 media/lua.

Pure functions (tested outside the game): Table.layout (column widths: minimum plus a share of the rest by weight),
Table.clip (text cut with "..." to a width in pixels, measure given by the caller), Table.sorted (stable sort by
column, numbers then texts, empty values last).
Element: Table.new(parent, x, y, w, h, columns, opts): a row of ISButton headers (click: sort by the column, second
click: reverse order, like ISUsersList, M/client/ISUI/AdminPanel/ISUsersList.lua:139-150) above an
ISScrollingListBox whose doDrawItem draws aligned cells (cut text); the row tooltip (tooltip field of the item,
ISScrollingListBox.lua:391-437) gives the whole text of each column. Font: UIFont.Small everywhere.
columns = { { key, title, weight, min } } ; opts = { cells = function(row) -> { [key] = text },
sortValue = function(row, key) -> number or text (default: text of the cell), onSelect(row), onDouble(row) }.
No size changes after creation (vanilla scroll bar fixed at creation): the window holding the table is not
resizable.
]]
if isServer() then return end

RadioSurvivorCore = RadioSurvivorCore or {}
local Table = RadioSurvivorCore.Table or {}
RadioSurvivorCore.Table = Table

Table.ELLIPSIS = "..."
Table.PAD = 6          -- inner margin of a cell
Table.SCROLL_W = 16    -- width kept for the vanilla scroll bar (ISScrollBar)
Table.MIN = 40         -- minimum width of a column without min

-- Widths: each column gets its min, then the rest of width by weight (the last one keeps the rounding). Sets c.x and
-- c.w on each column (table modified and returned).
function Table.layout(columns, width)
    local fixed, weights = 0, 0
    for _, c in ipairs(columns) do
        fixed = fixed + (c.min or Table.MIN)
        weights = weights + (c.weight or 1)
    end
    local extra = math.max(0, width - fixed)
    local x = 0
    for i, c in ipairs(columns) do
        local w = (c.min or Table.MIN) + math.floor(extra * (c.weight or 1) / math.max(1, weights))
        if i == #columns then w = math.max(c.min or Table.MIN, width - x) end
        c.x, c.w = x, w
        x = x + w
    end
    return columns
end

-- Text cut to fit in width pixels (measure(text) -> pixels). Returns the text (whole, or cut and followed by "...")
-- and true when it was cut.
function Table.clip(text, width, measure)
    text = tostring(text or "")
    if measure(text) <= width then return text, false end
    local ell = Table.ELLIPSIS
    local room = width - measure(ell)
    if room <= 0 then return "", true end
    local lo, hi = 0, #text
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if measure(string.sub(text, 1, mid)) <= room then lo = mid else hi = mid - 1 end
    end
    return string.sub(text, 1, lo) .. ell, true
end

local function rank(v)
    if type(v) == "number" then return 1 end
    if v == nil or v == "" or v == "-" then return 3 end
    return 2
end

-- Rows sorted by key (copy of the list; stable sort: on a tie, original order). valueOf(row, key) -> number or text;
-- desc = descending order (empty values stay last).
function Table.sorted(rows, key, desc, valueOf)
    local items = {}
    for i, r in ipairs(rows) do
        local v = valueOf(r, key)
        if type(v) == "string" then v = string.lower(v) end
        items[i] = { r = r, v = v, i = i }
    end
    table.sort(items, function(a, b)
        local ra, rb = rank(a.v), rank(b.v)
        if ra ~= rb then return ra < rb end
        if ra ~= 3 and a.v ~= b.v then
            if desc then return a.v > b.v end
            return a.v < b.v
        end
        return a.i < b.i
    end)
    local out = {}
    for i, it in ipairs(items) do out[i] = it.r end
    return out
end

-- Rich text of the tooltip of a row: "title: text" per column ("<" replaced: the text is never interpreted).
function Table.tooltip(columns, cells)
    local L = {}
    for _, c in ipairs(columns) do
        local v = cells[c.key]
        if v ~= nil and v ~= "" then
            L[#L + 1] = string.gsub(tostring(c.title) .. ": " .. tostring(v), "<", "(")
        end
    end
    return table.concat(L, " <LINE> ")
end

-- Element -------------------------------------------------------------------------------------------------------------

local Widget = {}
Widget.__index = Widget
Table.Widget = Widget

function Widget:valueOf(row, key)
    if self.opts.sortValue ~= nil then
        local v = self.opts.sortValue(row, key)
        if v ~= nil then return v end
    end
    local cells = self.opts.cells(row)
    return cells[key]
end

function Widget:titleOf(c)
    if self.sortKey == c.key then return c.title .. (self.desc and " v" or " ^") end
    return c.title
end

function Widget:onHeader(key)
    if self.sortKey == key then self.desc = not self.desc else self.sortKey, self.desc = key, false end
    for _, c in ipairs(self.columns) do
        if c.button ~= nil then c.button:setTitle(self:titleOf(c)) end
    end
    self:setRows(self.rows, self.keyOf, self.selectedKey)
end

-- Fills the table (rows = data rows, keyOf(row) = stable key, selectedKey = chosen row), keeping the scroll and the
-- chosen sort.
function Widget:setRows(rows, keyOf, selectedKey)
    self.rows, self.keyOf, self.selectedKey = rows or {}, keyOf, selectedKey
    local list = self.list
    local shown = self.rows
    if self.sortKey ~= nil then
        local w = self
        shown = Table.sorted(self.rows, self.sortKey, self.desc, function(r, k) return w:valueOf(r, k) end)
    end
    local top = list:getYScroll()
    local index = nil
    list:clear()
    for _, r in ipairs(shown) do
        local cells = self.opts.cells(r)
        local item = list:addItem("", r)
        item.cells = cells
        item.tooltip = Table.tooltip(self.columns, cells)
        if selectedKey ~= nil and keyOf ~= nil and keyOf(r) == selectedKey then index = #list.items end
    end
    list.selected = index or 0
    list:setYScroll(top)
end

local function drawRow(list, y, item, alt)
    local self = list.lkTable
    local h = list.itemheight
    if y + list:getYScroll() + h < 0 or y + list:getYScroll() >= list.height then return y + h end
    if list.selected == item.index then
        list:drawRect(0, y, list:getWidth(), h - 1, 0.3, 0.7, 0.35, 0.15)
    elseif list.mouseoverselected == item.index and list:isMouseOver() then
        list:drawRect(0, y, list:getWidth(), h - 1, 0.1, 1, 1, 1)
    elseif alt then
        list:drawRect(0, y, list:getWidth(), h - 1, 0.06, 1, 1, 1)
    end
    local tm = getTextManager()
    local function measure(s) return tm:MeasureStringX(UIFont.Small, s) end
    local ty = y + math.floor((h - self.fontH) / 2)
    for _, c in ipairs(self.columns) do
        local text = Table.clip(item.cells[c.key], c.w - 2 * Table.PAD, measure)
        list:drawText(text, c.x + Table.PAD, ty, 0.9, 0.9, 0.9, 1, UIFont.Small)
        if c.x > 0 then list:drawRect(c.x, y, 1, h, 0.25, 0.6, 0.6, 0.6) end
    end
    return y + h
end

-- Creates the table in parent (headers at y, rows below). Returns the object (fields list, columns; setRows).
function Table.new(parent, x, y, w, h, columns, opts)
    local self = setmetatable({ parent = parent, opts = opts or {}, columns = columns, rows = {}, sortKey = nil,
        desc = false }, Widget)
    local tm = getTextManager()
    self.fontH = tm:getFontHeight(UIFont.Small)
    local headH = self.fontH + 6
    Table.layout(columns, w - Table.SCROLL_W)
    for _, c in ipairs(columns) do
        local key = c.key
        local b = ISButton:new(x + c.x, y, c.w, headH, c.title, self, function(tbl) tbl:onHeader(key) end)
        b:initialise()
        b.font = UIFont.Small
        b.titleLeft = true
        b.backgroundColor = { r = 0.25, g = 0.25, b = 0.25, a = 1 }
        b.borderColor = { r = 0.45, g = 0.45, b = 0.45, a = 1 }
        parent:addChild(b)
        c.button = b
    end
    local list = ISScrollingListBox:new(x, y + headH, w, h - headH)
    list:initialise()
    list:instantiate()
    list.font = UIFont.Small
    list.itemheight = self.fontH + 6
    list.drawBorder = true
    list.backgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 1 }
    list.lkTable = self
    list.doDrawItem = drawRow
    parent:addChild(list)
    self.list = list
    list:setOnMouseDownFunction(self, function(tbl, row)
        if tbl.keyOf ~= nil then tbl.selectedKey = tbl.keyOf(row) end
        if tbl.opts.onSelect ~= nil then tbl.opts.onSelect(row) end
    end)
    list:setOnMouseDoubleClick(self, function(tbl, row)
        if tbl.opts.onDouble ~= nil then tbl.opts.onDouble(row) end
    end)
    return self
end

return Table
