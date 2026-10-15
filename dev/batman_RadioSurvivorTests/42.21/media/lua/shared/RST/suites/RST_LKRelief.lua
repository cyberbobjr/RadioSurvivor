--[[
lk.relief - decimation and relief of Living Knox groups (LK09-T04, server/LivingKnox/LK_Population.lua, mark "gone"
of LK_Groups.lua): a group without any living member is marked gone (cause "wiped"), kept in the registry with its
home, furnishing and stock (traces), and gets no new member; after the delay drawn between the options
LivingKnox.ReliefDaysMin and ReliefDaysMax, ONE new group is installed by the population path (type weights,
planGroup, LivingKnox.Sites.pick on the real metagrid) far from the old home (Sites.CONFIG.GROUP_DISTANCE) and from
every other home.
Tags "world" and "server": the authority only, on a save named rstest*, with a target player (t.ctx.player). Solo:
RST.run({ suite = "lk.relief", tags = "world" }). Dedicated server: RST.server({ suite = "lk.relief", tags = "world" })
from an admin client.
The days are not waited for: the due hour written in the mark is checked against the options, then set to the
current hour (registry update) so that the next relief step installs the relief. The relief step also handles the
real groups of the save (a real group already wiped out may be marked gone or relieved during the test).
Cleanup (t:defer): the test group and its relief group are removed from the registry.
Not checked here: persistence of the mark and of the due hour across a restart (reload the save and read the
console lines "group grp-<n> gone" / "relief: grp-<m> ... replaces grp-<n>"), dispersal of a lone survivor.
Outside the game: tests/test_lk_relief.py.
]]

require "RST/RST"

local function LK() return LivingKnox end

local function module(t)
    if type(isClient) == "function" and isClient() then
        t:skip("LK_Population is not loaded on an MP client (authority only)")
    end
    local E = LK()
    if E == nil or type(E.Population) ~= "table" or type(E.Population.reliefStep) ~= "function"
        or type(E.Groups) ~= "table" or type(E.Sites) ~= "table" then
        t:skip("LivingKnox.Population relief (LK09-T04) is not loaded here")
    end
    if not E.Config.isEnabled() then t:skip("Living Knox is disabled (sandbox option LivingKnox.Enabled)") end
    t:ok(E.Groups.ensure(), "group registry not ready")
    return E
end

local function dist(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

RST.suite("lk.relief", { tags = { "world", "server" }, testTimeoutMs = 60000 }, function(s)
    s.test("module exports", function(t)
        local E = module(t)
        for _, name in ipairs({ "reliefStep", "markGone", "dueReliefs", "planRelief", "reliefDelay", "insert" }) do
            t:eq("function", type(E.Population[name]), "LivingKnox.Population." .. name)
        end
        for _, name in ipairs({ "applyGone", "isGone", "livingCount" }) do
            t:eq("function", type(E.Groups[name]), "LivingKnox.Groups." .. name)
        end
    end)

    s.test("a wiped-out group is marked gone, then relieved once far from its home", function(t)
        local E = module(t)
        local G, P = E.Groups, E.Population
        local p = t.ctx and t.ctx.player
        t:ok(p ~= nil, "no target player (t.ctx.player)")
        local home = { x = math.floor(p:getX()), y = math.floor(p:getY()), z = math.floor(p:getZ()) }
        local g = assert(G.create({ type = "settlers", name = "RST relief", day = G.today(), home = home }))
        local gid, relief = g.id, nil
        local mids = {}
        for _, role in ipairs({ "worker", "fighter", "medic", "scout" }) do
            mids[#mids + 1] = assert(G.addMember(gid, { role = role, day = G.today() }))
        end
        t:defer(function()
            G.remove(gid)
            if relief then G.remove(relief) end
        end, "remove the test group and its relief group")

        for _, mid in ipairs(mids) do assert(G.markDead(gid, mid)) end
        local now = P.currentHour()
        t:ok(now ~= nil, "no game clock")
        local made = P.reliefStep(now)
        t:eq(0, #(made or {}), "relief installed at once")
        local gone = G.get(gid).gone
        t:ok(gone ~= nil, "group not marked gone")
        t:eq("wiped", gone.cause, "cause")
        t:eq(now, gone.hour, "hour of the mark")
        local settings = E.Config.population()
        t:ok(gone.due >= now + settings.reliefMin * 24 and gone.due <= now + settings.reliefMax * 24,
            "due hour " .. tostring(gone.due) .. " outside " .. settings.reliefMin .. ".." .. settings.reliefMax
            .. " day(s)")
        t:ok(G.get(gid).home ~= nil, "home of the gone group erased")
        local r, why = G.addMember(gid, { role = "worker" })
        t:eq(nil, r, "a member was added to a gone group")
        t:note("gone at hour " .. now .. ", relief due at hour " .. gone.due .. " (" .. (gone.due - now) / 24
            .. " day(s)); addMember refused: " .. tostring(why))

        -- The days are not waited for: due hour moved to now.
        t:ok(G.update(function(d)
            d.groups[gid].gone.due = now
            return true, true
        end), "registry not written")
        made = P.reliefStep(now) or {}
        t:ok(#made >= 1, "no relief installed (see the WARN relief line of console.txt)")
        local old = G.get(gid)
        relief = old.gone.relief
        t:ok(relief ~= nil, "gone.relief not set")
        local ng = relief and G.get(relief)
        t:ok(ng ~= nil and ng.home ~= nil, "relief group without home")
        if ng and ng.home then
            local d = dist(ng.home, home)
            t:ok(d >= E.Sites.CONFIG.GROUP_DISTANCE, "relief home " .. math.floor(d) .. " squares from the old home")
            for _, other in ipairs(G.list()) do
                local og = G.get(other)
                if other ~= relief and og and og.home then
                    t:ok(dist(ng.home, og.home) >= E.Sites.CONFIG.GROUP_DISTANCE,
                        relief .. " too close to the home of " .. other)
                end
            end
            t:ok(G.livingCount(ng) >= 1, "relief group without living member")
            t:note("relief " .. relief .. " (" .. ng.type .. ", " .. G.livingCount(ng) .. " member(s)) at "
                .. ng.home.x .. "," .. ng.home.y .. "," .. ng.home.z .. ", " .. math.floor(d)
                .. " squares from the old home")
        end
        -- Only once.
        local again = P.reliefStep(now + 1) or {}
        for _, id in ipairs(again) do
            t:ok(id ~= relief, "second relief")
        end
        t:eq(relief, G.get(gid).gone.relief, "relief changed by a second step")
    end)
end)
