--[[
Hooks of the generic launcher pz-autotest (.claude/tools/pz-autotest) for the RST test engine of RadioSurvivor.
Configuration: RadioSurvivor/autotest.json. Loaded by batman_PZAutoTestDriver with loadstring (global environment,
RST already loaded by batman_RadioSurvivorTests). Parameters (ctx.params, all text, "-P name=value"):
    suite=a,b       RST suite names or dot prefixes (client: RST.run, server: RST.Server.runSuites)
    campaign=name   client only: RST.campaign(name) (exclusive with suite)
    tags=a,b        explicit RST filter tags (e.g. world); replaces the default exclusion
    exclude=a,b     explicit RST exclusion ("" = none)
Client side (solo, or client 1 in mp with --client-run): same calls as RST_AutoClient.lua. Server side (dedicated
server, or mp server after "go"): RST.Server.runSuites with the first online player as t.ctx.player (none in mode
server: world suites SKIP there).
]]

local H = { client = {}, server = {} }

local function filter(ctx)
    local P, Z = ctx.params, ctx.Z
    local f = { suite = Z.split(P.suite) }
    if P.tags ~= nil then f.tags = Z.split(P.tags) end
    if P.exclude ~= nil then f.exclude = Z.split(P.exclude) end
    return f
end

local function summaryOf(report, file)
    local s = RST.summaryLine(report)
    if file then s = s .. " report=" .. file end
    return s
end

function H.client.start(ctx)
    local P = ctx.params
    if P.campaign and P.suite then return false, "campaign= and suite= exclude each other" end
    if P.campaign then return RST.campaign(P.campaign) end
    if not P.suite or P.suite == "" then return false, "parameter suite= or campaign= is needed" end
    return RST.run(filter(ctx))
end

function H.client.done()
    return not RST.running()
end

function H.client.result()
    local report = RST._last
    if not report then return false, "no RST report" end
    local client = RST.Client or {}
    local lines = (client.lastReport == report and client.lastLines) or RST.formatReport(report)
    return { ok = report.ok and report.total > 0, summary = summaryOf(report, client.lastFile), lines = lines }
end

function H.server.start(ctx)
    if ctx.params.campaign then return false, "campaign= is client side only (RST_Campaign.lua): use suite=" end
    if not ctx.params.suite or ctx.params.suite == "" then return false, "parameter suite= is needed" end
    if not RST.Server then return false, "RST.Server missing (server Lua of batman_RadioSurvivorTests not loaded)" end
    H.server.res = nil
    local player = ctx.players()[1]
    return RST.Server.runSuites(filter(ctx), function(res) H.server.res = res end,
        { requester = "pz-autotest", player = player })
end

function H.server.done()
    return H.server.res ~= nil
end

function H.server.result()
    local res = H.server.res
    local report = res.report
    return { ok = report.ok and report.total > 0, summary = summaryOf(report, res.written and res.file or nil),
        lines = res.lines }
end

return H
