-- Radio Survivor: what the booking team left at the landing (E23-T07, ADR D02/D03 of adr-troc-simple-et-cas-limites.md).
-- Pure rules on the holds a finder of RS_TradeHolds returns (list { inv, id }), first level of each hold only:
--   Deposit.snapshot(holds) -> seen        ids (text) of the items present the first time the server sees the landing
--                                          loaded after the booking (kept with the run: RS_Trade.noteDeposit)
--   Deposit.added(holds, seen) -> entries  items not in seen, in finder order: { item, hold = index in holds }
--   Deposit.match(entries, wants, counts)  all or nothing: exactly the quantity of each line of wants (full type t,
--                                          quantity q) among the entries that counts(item) accepts; returns
--                                          { complete, take = entries, hold = index of the hold that held most of the
--                                          payment (the first one on a tie), missing = { t = quantity } }
-- Item ids are drawn at creation and saved with the item (base world-placement.md: getID kept by a save and by an MP
-- transaction), so a restart keeps the note valid. Several holds add up; an item already there (a bag left before,
-- the loot of a dumpster, the stash of another player) never counts. A vehicle is never a hold (RS_TradeHolds).
-- Authority only. ASCII only (Kahlua lexer).
if isClient() then return end

local Deposit = {}

Deposit.MAX_SEEN = 1000      -- item ids noted at most (a full dumpster and a few bags are far below)

-- Items of the first level of a hold (Lua list, copy: items can be removed while it is read).
function Deposit.itemsOf(inv)
    local out = {}
    local list = inv and inv:getItems()
    if list == nil then return out end
    for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
    return out
end

local function idOf(item)
    return tostring(item:getID())
end

function Deposit.snapshot(holds)
    local seen, count = {}, 0
    for _, hold in ipairs(holds or {}) do
        for _, item in ipairs(Deposit.itemsOf(hold.inv)) do
            if count >= Deposit.MAX_SEEN then return seen end
            seen[idOf(item)] = true
            count = count + 1
        end
    end
    return seen
end

function Deposit.added(holds, seen)
    local out = {}
    seen = seen or {}
    for index, hold in ipairs(holds or {}) do
        for _, item in ipairs(Deposit.itemsOf(hold.inv)) do
            if not seen[idOf(item)] then out[#out + 1] = { item = item, hold = index } end
        end
    end
    return out
end

function Deposit.match(entries, wants, counts)
    local res = { complete = true, take = {}, missing = {}, hold = nil }
    local used, byHold = {}, {}
    for _, line in ipairs(wants or {}) do
        local need = line.q
        for i, e in ipairs(entries or {}) do
            if need <= 0 then break end
            if not used[i] and e.item:getFullType() == line.t and (counts == nil or counts(e.item)) then
                used[i] = true
                need = need - 1
                res.take[#res.take + 1] = e
                byHold[e.hold] = (byHold[e.hold] or 0) + 1
            end
        end
        if need > 0 then
            res.complete = false
            res.missing[line.t] = need
        end
    end
    local best = 0
    for index, n in pairs(byHold) do
        if n > best or (n == best and index < res.hold) then res.hold, best = index, n end
    end
    return res
end

return Deposit
