-- Living Knox : mesure de charge du moteur sur la machine qui le fait tourner (LK13-T02).
-- Fiche : docs/annexes/conception/charge.md ; résultats et protocole : docs/annexes/tests/validation/charge-*.md.
--
-- Mesure, jamais d'effet sur le jeu. Sur l'autorité (serveur MP, solo), démarrée par un administrateur
-- (LK_Admin.lua, requête { op = "load", action = "start" | "report" | "stop" }) ; sur un client MP, depuis la console
-- Lua du mode debug pour la machine locale seulement (Load.start / Load.print / Load.stop), ou Load.ask(action) qui
-- envoie la requête d'administration au serveur et imprime la réponse.
--
-- Ce qui est mesuré pendant une session (Load.active) :
--   - coût de chaque abonné du moteur (LivingKnox.handlers["<événement>/<Module>.<nom>"], inscrits par
--     LivingKnox.subscribe) : appels, temps total, plus long appel ; regroupé par module (<Module>) et par image :
--     temps de l'image (somme des abonnés mesurés entre deux passages du compteur OnTick), moyenne et maximum ;
--   - fenêtre glissante de CFG.WINDOW_MS (temps réel) : la dernière fenêtre close est gardée (moyennes, maximum,
--     messages par seconde) ; ligne de journal à chaque fenêtre close si la session le demande (log = true) ;
--   - commandes réseau du module "LivingKnox" envoyées (enveloppe de sendServerCommand sur l'autorité, de
--     sendClientCommand sur un client MP) par commande : nombre, taille approchée (Load.size), envois à un joueur ou
--     à tous ; commandes reçues (abonné OnClientCommand / OnServerCommand de ce module) ;
--   - écritures des registres (autorité) : enveloppe de LivingKnox.Store.writeSlotFile (registres des PNJ LKREG1, des
--     groupes LKGRP1, des attitudes LKATT1) : nombre, temps total et plus longue écriture (encodage, fichier, relecture
--     de vérification quand elle est faite), retirée à l'arrêt si elle est encore en place ;
--   - taille de l'état sauvegardé (autorité, au rapport) : octets RSV2 des registres des PNJ, des groupes (et par
--     champ de groupe : log, journal, stock, members, fort...) et des attitudes, x 2 (hex des fichiers, LK_Store).
-- Enveloppes : posées UNE fois par abonné, puis gardées (transparentes hors session : un test de Load.active et
-- l'appel direct). Pose différée : les abonnés de tous les événements sauf OnTickEvenPaused au premier
-- OnTickEvenPaused qui suit le départ (Load.install), ceux d'OnTickEvenPaused au premier OnTick (Load.counter) :
-- Remove/Add d'un abonné pendant le déclenchement de son propre événement l'appellerait deux fois dans l'image (un
-- abonné ajouté pendant un déclenchement est appelé aussitôt, base kahlua-lua.md). Même fonction, mêmes arguments,
-- mêmes valeurs rendues, aucun pcall (une erreur atteint le moteur comme avant ; l'appel n'est alors pas compté).
-- Ordre (LK13-T12) : les enveloppes passent en fin de liste de leur événement avec les abonnés du moteur qui les
-- suivaient, dans l'ordre réel d'inscription (LivingKnox.handlerSeq, remises en fin de liste de LivingKnox.requeue
-- comprises) : même ordre relatif des abonnés du moteur avec ou sans mesure, mêmes registres et mêmes écritures
-- (banc tools/load_bench.py run_compare). Seuls les abonnés posés hors de LivingKnox.subscribe (autres mods, vanilla)
-- peuvent passer avant eux. Un module rechargé
-- (LivingKnox.subscribe) remplace l'enveloppe : il n'est plus mesuré jusqu'au départ suivant.
-- Horloge : Load.clock() (getTimestampMs par défaut, pas de 1 ms : la moyenne sur beaucoup d'appels est
-- l'estimation, le maximum une borne à la milliseconde près ; base kahlua-lua.md). Le banc hors jeu y met une
-- horloge fine (tools/load_bench.py). Les fenêtres suivent getTimestampMs (Load.now).
-- Messages du journal en anglais (préfixe [LivingKnox]).
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Log"

local Load = LivingKnox.Load or {}
LivingKnox.Load = Load

Load.MODULE = "LivingKnox"
Load.CMD_REQUEST = "adminRequest"   -- = LK_Admin (requête op = "load")
Load.CMD_REPLY = "adminReply"

Load.CFG = Load.CFG or {
    WINDOW_MS = 60000,        -- fenêtre glissante (temps réel)
    WINDOW_MIN = 1000,
    WINDOW_MAX = 600000,
    TOP_MODULES = 12,         -- modules détaillés dans le rapport (les autres en une ligne)
    TOP_COMMANDS = 8,         -- commandes réseau détaillées par sens
    MAX_LINE = 300,           -- longueur d'une ligne du rapport
}

-- Budgets proposés (docs/annexes/tests/validation/charge-hors-jeu-2026-10-12.md, à confirmer par la mesure en jeu). Moyennes par
-- image ; serveur dédié à 10 images par seconde (100 ms par image, base multiplayer.md), client à 30-60.
Load.BUDGET = Load.BUDGET or {
    authority = { tickMs = 2.0, tickMaxMs = 25, moduleMs = 0.5, sentPerSec = 40, sentBytesPerSec = 8192,
        stateBytes = 1048576 },
    client = { tickMs = 1.0, tickMaxMs = 8, moduleMs = 0.5, sentPerSec = 5, sentBytesPerSec = 1024 },
}

Load.wrapped = Load.wrapped or {}   -- slot -> { slot, event, key, module, fn, wrapper }
Load.active = Load.active or nil
Load.last = Load.last or nil        -- résumé de la dernière session arrêtée

local function sideName()
    if isServer() then return "server" end
    if isClient() then return "client" end
    return "solo"
end

function Load.now()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return 0
end

Load.clock = Load.clock or Load.now

local function fixed(v, decimals)
    local m = 10 ^ (decimals or 3)
    return tostring(math.floor((v or 0) * m + 0.5) / m)
end
Load.fixed = fixed

-- Taille approchée d'arguments réseau : longueur des chaînes, 8 par nombre, 1 par booléen, 2 par table (clés
-- comprises). Ordre de grandeur seulement (le Java sérialise autrement, TableNetworkUtils).
function Load.size(v, depth)
    local t = type(v)
    if t == "string" then return string.len(v) end
    if t == "number" then return 8 end
    if t == "boolean" then return 1 end
    if t ~= "table" then return 0 end
    depth = depth or 0
    if depth > 8 then return 0 end
    local n = 2
    for k, x in pairs(v) do n = n + Load.size(k, depth + 1) + Load.size(x, depth + 1) end
    return n
end

-- Module d'un abonné : "<événement>/<Module>.<nom>" -> "<Module>" ; nil pour les abonnés de ce module.
local function parseSlot(slot)
    local event, key = string.match(slot, "^([^/]+)/(.+)$")
    if event == nil then return nil end
    local module = string.match(key, "^([^%.]+)") or key
    if module == "Load" then return nil end
    return event, key, module
end

-- Comptage -------------------------------------------------------------------------------------------------------

local function newCounter() return { calls = 0, ms = 0, max = 0 } end
local function newNet() return { count = 0, bytes = 0, toOne = 0, toAll = 0, byCmd = {} } end

local function newWindow(t)
    return { startMs = t, ticks = 0, ms = 0, max = 0, slots = {}, sent = newNet(), recv = newNet() }
end

local function bump(map, key)
    local c = map[key]
    if c == nil then
        c = newCounter()
        map[key] = c
    end
    return c
end

local function add(c, dt)
    c.calls = c.calls + 1
    c.ms = c.ms + dt
    if dt > c.max then c.max = dt end
end

local function record(s, entry, dt)
    add(bump(s.slots, entry.slot), dt)
    add(bump(s.window.slots, entry.slot), dt)
    s.frame.ms = s.frame.ms + dt
    s.frame.modules[entry.module] = (s.frame.modules[entry.module] or 0) + dt
end

local function finish(entry, s, t0, ...)
    if Load.active == s and s.measuring then record(s, entry, Load.clock() - t0) end
    return ...
end

local function makeWrapper(entry)
    local fn = entry.fn
    return function(...)
        local s = Load.active
        if s == nil or not s.measuring then return fn(...) end
        return finish(entry, s, Load.clock(), fn(...))
    end
end

local function netCount(net, command, args, toAll)
    local c = net.byCmd[command]
    if c == nil then
        c = { count = 0, bytes = 0 }
        net.byCmd[command] = c
    end
    local bytes = Load.size(args)
    c.count = c.count + 1
    c.bytes = c.bytes + bytes
    net.count = net.count + 1
    net.bytes = net.bytes + bytes
    if toAll then net.toAll = net.toAll + 1 else net.toOne = net.toOne + 1 end
end

-- Envoi : (module, command, args) ou (player, module, command, args). sendServerCommand sans joueur = à tous.
local function countSent(s, ...)
    local a, b, c, d = ...
    local command, args, toAll
    if type(a) == "string" then
        if a ~= Load.MODULE then return end
        command, args, toAll = b, c, true
    else
        if b ~= Load.MODULE then return end
        command, args, toAll = c, d, false
    end
    if s.netName == "sendClientCommand" then toAll = false end
    netCount(s.sent, tostring(command), args, toAll)
    netCount(s.window.sent, tostring(command), args, toAll)
end

-- Enveloppes des abonnés -----------------------------------------------------------------------------------------

-- Enveloppe les abonnés du moteur pas encore enveloppés ; evenPaused = true : ceux d'OnTickEvenPaused seulement,
-- false : tous les autres. Rend le nombre d'abonnés nouvellement enveloppés.
-- LK13-T12 : ordre gardé. Par événement, les abonnés du moteur sont pris dans l'ordre réel de la liste
-- (LivingKnox.handlerSeq : rang du dernier Add, LivingKnox.subscribe ou LivingKnox.requeue) ; à partir du premier à
-- envelopper, chacun est retiré puis rajouté en fin de liste dans cet ordre (enveloppe neuve, enveloppe déjà posée
-- ou abonné Load.* tel quel) : l'ordre relatif de tous les abonnés du moteur reste celui d'avant la pose. Seuls les
-- abonnés inscrits hors de LivingKnox.subscribe (autres mods, vanilla) peuvent se retrouver avant eux.
local function slotEvent(slot)
    return string.match(slot, "^([^/]+)/")
end

local function wrapSlots(evenPaused)
    local handlers = LivingKnox.handlers or {}
    local seq = LivingKnox.handlerSeq or {}
    local byEvent, events = {}, {}
    for slot, fn in pairs(handlers) do
        local event = slotEvent(slot)
        if event ~= nil and type(fn) == "function" and (event == "OnTickEvenPaused") == evenPaused
                and Events[event] ~= nil then
            local list = byEvent[event]
            if list == nil then
                list = {}
                byEvent[event] = list
                events[#events + 1] = event
            end
            list[#list + 1] = slot
        end
    end
    table.sort(events)
    local count = 0
    for _, event in ipairs(events) do
        local list = byEvent[event]
        -- Rang absent (abonné posé sans subscribe) : en tête, par clé ; rangs uniques sinon.
        table.sort(list, function(a, b)
            local ra, rb = seq[a] or 0, seq[b] or 0
            if ra ~= rb then return ra < rb end
            return a < b
        end)
        local first = nil
        for i, slot in ipairs(list) do
            local entry = Load.wrapped[slot]
            if parseSlot(slot) ~= nil and (entry == nil or entry.wrapper ~= handlers[slot]) then
                first = i
                break
            end
        end
        if first ~= nil then
            local ev = Events[event]
            for i = first, #list do
                local slot = list[i]
                local cur = handlers[slot]
                local entry = Load.wrapped[slot]
                local _, key, module = parseSlot(slot)
                local fn = cur
                if module ~= nil and (entry == nil or entry.wrapper ~= cur) then
                    entry = { slot = slot, event = event, key = key, module = module, fn = cur }
                    entry.wrapper = makeWrapper(entry)
                    Load.wrapped[slot] = entry
                    handlers[slot] = entry.wrapper
                    fn = entry.wrapper
                    count = count + 1
                end
                ev.Remove(cur)
                ev.Add(fn)
                if LivingKnox.markAdded ~= nil then LivingKnox.markAdded(slot) end
            end
        end
    end
    return count
end

-- Abonnés mesurés pendant la session : enveloppe en place.
local function measuredSlots()
    local out = {}
    for slot, fn in pairs(LivingKnox.handlers or {}) do
        local entry = Load.wrapped[slot]
        if entry ~= nil and entry.wrapper == fn then out[#out + 1] = slot end
    end
    table.sort(out)
    return out
end

-- Enveloppe réseau : posée au départ, retirée à l'arrêt si elle est encore en place (un autre mod a pu envelopper
-- par-dessus : la nôtre reste alors, transparente). Arguments transmis tels quels (surcharges Java selon le nombre
-- d'arguments : jamais de nil ajouté, base kahlua-lua.md).
local function wrapNet(s)
    local name = isClient() and "sendClientCommand" or "sendServerCommand"
    local original = _G[name]
    if type(original) ~= "function" then return end
    local wrapper = function(...)
        local cur = Load.active
        if cur == s and s.measuring then countSent(s, ...) end
        return original(...)
    end
    _G[name] = wrapper
    s.netName, s.netOriginal, s.netWrapper = name, original, wrapper
end

local function unwrapNet(s)
    if s.netName ~= nil and _G[s.netName] == s.netWrapper then _G[s.netName] = s.netOriginal end
end

-- Écritures des registres (autorité) : même fonction, mêmes arguments, mêmes valeurs rendues.
local function wrapSaves(s)
    local Store = LivingKnox.Store
    if isClient() or type(Store) ~= "table" or type(Store.writeSlotFile) ~= "function" then return end
    local original = Store.writeSlotFile
    local function done(header, t0, ...)
        if Load.active == s and s.measuring then add(bump(s.saves, tostring(header)), Load.clock() - t0) end
        return ...
    end
    local wrapper = function(path, header, seq, data, noVerify)   -- noVerify : LK13-T06 (registre des groupes)
        return done(header, Load.clock(), original(path, header, seq, data, noVerify))
    end
    Store.writeSlotFile = wrapper
    s.saveOriginal, s.saveWrapper = original, wrapper
end

local function unwrapSaves(s)
    local Store = LivingKnox.Store
    if s.saveWrapper ~= nil and Store ~= nil and Store.writeSlotFile == s.saveWrapper then
        Store.writeSlotFile = s.saveOriginal
    end
end

-- Session -------------------------------------------------------------------------------------------------------

-- Démarre une session sur cette machine. opts = { windowMs, log }. Rend la session, ou nil et la raison.
function Load.start(opts)
    if Load.active ~= nil then return nil, "a measure is already running" end
    opts = type(opts) == "table" and opts or {}
    local w = tonumber(opts.windowMs) or Load.CFG.WINDOW_MS
    if w ~= w or w < Load.CFG.WINDOW_MIN then w = Load.CFG.WINDOW_MIN end
    if w > Load.CFG.WINDOW_MAX then w = Load.CFG.WINDOW_MAX end
    local t = Load.now()
    local s = { side = sideName(), windowMs = math.floor(w), log = opts.log == true, startMs = t, measuring = false,
        installed = false, evenPausedPending = true, ticks = 0, tickMs = 0, tickMax = 0, busyTicks = 0,
        modTickMax = {}, frame = { ms = 0, modules = {} }, slots = {}, saves = {}, sent = newNet(), recv = newNet(),
        window = newWindow(t), lastWindow = nil, peakSentPerSec = 0, windows = 0 }
    Load.active = s
    return s
end

-- Premier OnTickEvenPaused après le départ : abonnés (hors OnTickEvenPaused) et réseau enveloppés, mesure ouverte.
function Load.install()
    local s = Load.active
    if s == nil or s.installed then return end
    s.installed = true
    s.wrappedNow = wrapSlots(false)
    wrapNet(s)
    wrapSaves(s)
    local t = Load.now()
    s.startMs = t
    s.window = newWindow(t)
    s.measuring = true
end

local function closeWindow(s, t)
    local w = s.window
    local secs = (t - w.startMs) / 1000
    w.endMs = t
    w.secs = secs
    if secs > 0 then
        local rate = w.sent.count / secs
        if rate > s.peakSentPerSec then s.peakSentPerSec = rate end
    end
    s.lastWindow = w
    s.windows = s.windows + 1
    s.window = newWindow(t)
    if s.log then
        for _, line in ipairs(Load.windowLines(s, w)) do LivingKnox.Log.info("load: %s", line) end
    end
end

-- Compteur d'images (OnTick) : clôt l'image (somme des abonnés mesurés depuis le passage précédent), enveloppe les
-- abonnés d'OnTickEvenPaused au premier passage, clôt la fenêtre échue.
function Load.counter()
    local s = Load.active
    if s == nil or not s.measuring then return end
    if s.evenPausedPending then
        s.evenPausedPending = false
        s.wrappedNow = (s.wrappedNow or 0) + wrapSlots(true)
    end
    local f = s.frame
    s.ticks = s.ticks + 1
    s.tickMs = s.tickMs + f.ms
    if f.ms > s.tickMax then s.tickMax = f.ms end
    if f.ms >= 1 then s.busyTicks = s.busyTicks + 1 end
    for m, ms in pairs(f.modules) do
        if ms > (s.modTickMax[m] or 0) then s.modTickMax[m] = ms end
    end
    local w = s.window
    w.ticks = w.ticks + 1
    w.ms = w.ms + f.ms
    if f.ms > w.max then w.max = f.ms end
    s.frame = { ms = 0, modules = {} }
    local t = Load.now()
    if t - w.startMs >= s.windowMs then closeWindow(s, t) end
end

-- Commande reçue (OnClientCommand sur l'autorité, OnServerCommand sur un client).
function Load.received(module, command, args)
    local s = Load.active
    if s == nil or not s.measuring or module ~= Load.MODULE then return end
    netCount(s.recv, tostring(command), args, false)
    netCount(s.window.recv, tostring(command), args, false)
end

-- Taille de l'état sauvegardé (autorité). Rend { registry, groups, attitudes, sections, groupCount, members,
-- logEntries, journalEntries, stockItems } en octets de fichier (hex = 2 x RSV2), ou nil et la raison.
function Load.stateSize()
    if isClient() then return nil, "not the authority" end
    local ok, Codec = pcall(require, "RadioSurvivor/RS_Codec")
    if not ok or type(Codec) ~= "table" or type(Codec.encodeBytes) ~= "function" then return nil, "no codec" end
    local function bytes(v)
        if v == nil then return 0 end
        local done, body = pcall(Codec.encodeBytes, v)
        if not done then return -1 end
        return string.len(body) * 2
    end
    local LK = LivingKnox
    local out = { sections = {}, groupCount = 0,
        members = 0, logEntries = 0, journalEntries = 0, stockItems = 0 }
    out.registry = bytes(LK.Store and LK.Store.state and LK.Store.state.data)
    out.attitudes = bytes(LK.Hostility and LK.Hostility.state and LK.Hostility.state.data)
    local data = LK.Groups and LK.Groups.state and LK.Groups.state.data
    out.groups = bytes(data)
    if type(data) == "table" and type(data.groups) == "table" then
        local sec = out.sections
        for _, g in pairs(data.groups) do
            out.groupCount = out.groupCount + 1
            for k, v in pairs(g) do
                local key = tostring(k)
                sec[key] = (sec[key] or 0) + bytes({ v })
            end
            if type(g.members) == "table" then
                for _ in pairs(g.members) do out.members = out.members + 1 end
            end
            if type(g.log) == "table" then out.logEntries = out.logEntries + #g.log end
            if type(g.journal) == "table" and type(g.journal.e) == "table" then
                out.journalEntries = out.journalEntries + #g.journal.e
            end
            if type(g.stock) == "table" and type(g.stock.items) == "table" then
                out.stockItems = out.stockItems + #g.stock.items
            end
        end
    end
    return out
end

local function moduleTable(slots, durationTicks, tickMax)
    local mods = {}
    for slot, c in pairs(slots) do
        local entry = Load.wrapped[slot]
        local m = entry and entry.module or "?"
        local mc = mods[m]
        if mc == nil then
            mc = { module = m, calls = 0, ms = 0, max = 0, slots = {} }
            mods[m] = mc
        end
        mc.calls = mc.calls + c.calls
        mc.ms = mc.ms + c.ms
        if c.max > mc.max then mc.max = c.max end
        mc.slots[#mc.slots + 1] = { key = entry and entry.key or slot, event = entry and entry.event or "?",
            calls = c.calls, ms = c.ms, max = c.max }
    end
    local list = {}
    for _, mc in pairs(mods) do
        mc.perTick = durationTicks > 0 and mc.ms / durationTicks or 0
        mc.tickMax = tickMax and tickMax[mc.module] or nil
        table.sort(mc.slots, function(a, b)
            if a.ms ~= b.ms then return a.ms > b.ms end
            return a.key < b.key
        end)
        list[#list + 1] = mc
    end
    table.sort(list, function(a, b)
        if a.ms ~= b.ms then return a.ms > b.ms end
        return a.module < b.module
    end)
    return list
end

local function netCopy(net)
    local cmds = {}
    for name, c in pairs(net.byCmd) do cmds[#cmds + 1] = { command = name, count = c.count, bytes = c.bytes } end
    table.sort(cmds, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.command < b.command
    end)
    return { count = net.count, bytes = net.bytes, toOne = net.toOne, toAll = net.toAll, commands = cmds }
end

-- Résumé de la session s (en cours ou arrêtée) : tables simples, sans objet du moteur.
function Load.summary(s)
    s = s or Load.active
    if s == nil then return nil, "no measure running" end
    local t = s.stopMs or Load.now()
    local secs = (t - s.startMs) / 1000
    local sum = { side = s.side, running = Load.active == s, installed = s.installed, secs = secs, ticks = s.ticks,
        engineMs = s.tickMs, perTickMs = s.ticks > 0 and s.tickMs / s.ticks or 0, tickMaxMs = s.tickMax,
        busyTicks = s.busyTicks, windowMs = s.windowMs, windows = s.windows, measured = #measuredSlots(),
        modules = moduleTable(s.slots, s.ticks, s.modTickMax), sent = netCopy(s.sent), recv = netCopy(s.recv),
        peakSentPerSec = s.peakSentPerSec }
    sum.saves = {}
    for header, c in pairs(s.saves) do
        sum.saves[#sum.saves + 1] = { header = header, calls = c.calls, ms = c.ms, max = c.max }
    end
    table.sort(sum.saves, function(a, b) return a.header < b.header end)
    sum.sentPerSec = secs > 0 and s.sent.count / secs or 0
    sum.sentBytesPerSec = secs > 0 and s.sent.bytes / secs or 0
    sum.recvPerSec = secs > 0 and s.recv.count / secs or 0
    if s.lastWindow ~= nil then
        local w = s.lastWindow
        sum.window = { secs = w.secs, ticks = w.ticks, perTickMs = w.ticks > 0 and w.ms / w.ticks or 0, maxMs = w.max,
            sentPerSec = w.secs > 0 and w.sent.count / w.secs or 0, recvPerSec = w.secs > 0 and w.recv.count / w.secs
            or 0, modules = moduleTable(w.slots, w.ticks) }
    end
    if s.side ~= "client" then sum.state = Load.stateSize() end
    sum.over = Load.check(sum)
    return sum
end

-- Dépassements des budgets proposés (liste de textes anglais, vide si tout est dans le budget).
function Load.check(sum)
    local b = Load.BUDGET[sum.side == "client" and "client" or "authority"]
    local over = {}
    if b == nil or sum.ticks == 0 then return over end
    if sum.perTickMs > b.tickMs then
        over[#over + 1] = "engine " .. fixed(sum.perTickMs) .. " > " .. b.tickMs .. " ms/tick"
    end
    if sum.tickMaxMs > b.tickMaxMs then
        over[#over + 1] = "max tick " .. fixed(sum.tickMaxMs, 1) .. " > " .. b.tickMaxMs .. " ms"
    end
    for _, m in ipairs(sum.modules) do
        if m.perTick > b.moduleMs then
            over[#over + 1] = "module " .. m.module .. " " .. fixed(m.perTick) .. " > " .. b.moduleMs .. " ms/tick"
        end
    end
    if sum.sentPerSec > b.sentPerSec then
        over[#over + 1] = "sent " .. fixed(sum.sentPerSec, 1) .. " > " .. b.sentPerSec .. " msg/s"
    end
    if sum.sentBytesPerSec > b.sentBytesPerSec then
        over[#over + 1] = "sent " .. fixed(sum.sentBytesPerSec, 0) .. " > " .. b.sentBytesPerSec .. " B/s"
    end
    local st = sum.state
    if b.stateBytes ~= nil and type(st) == "table" then
        for _, name in ipairs({ "registry", "groups", "attitudes" }) do
            if (st[name] or 0) > b.stateBytes then
                over[#over + 1] = "state " .. name .. " " .. st[name] .. " > " .. b.stateBytes .. " B"
            end
        end
    end
    return over
end

-- Arrête la session : enveloppe réseau retirée (si encore en place), enveloppes des abonnés gardées (transparentes).
-- Rend le résumé (aussi gardé dans Load.last).
function Load.stop()
    local s = Load.active
    if s == nil then return nil, "no measure running" end
    s.stopMs = Load.now()
    s.measuring = false
    unwrapNet(s)
    unwrapSaves(s)
    Load.active = nil
    local sum = Load.summary(s)
    Load.last = sum
    return sum
end

-- Texte ----------------------------------------------------------------------------------------------------------

local function cut(line)
    local max = Load.CFG.MAX_LINE
    if string.len(line) > max then return string.sub(line, 1, max - 3) .. "..." end
    return line
end

local function netText(net, secs)
    local parts = {}
    for i, c in ipairs(net.commands) do
        if i > Load.CFG.TOP_COMMANDS then
            parts[#parts + 1] = "+" .. (#net.commands - Load.CFG.TOP_COMMANDS) .. " more"
            break
        end
        parts[#parts + 1] = c.command .. " " .. c.count .. " (" .. fixed(secs > 0 and c.count / secs or 0, 2)
            .. "/s, " .. c.bytes .. " B)"
    end
    return net.count .. " msg (" .. fixed(secs > 0 and net.count / secs or 0, 2) .. "/s), " .. net.bytes .. " B ("
        .. fixed(secs > 0 and net.bytes / secs or 0, 0) .. " B/s), to one " .. net.toOne .. ", to all " .. net.toAll
        .. (#parts > 0 and ("; " .. table.concat(parts, ", ")) or "")
end

local function moduleLine(m)
    local parts = {}
    for i, h in ipairs(m.slots) do
        if i > 3 then break end
        parts[#parts + 1] = h.key .. " " .. fixed(h.calls > 0 and h.ms / h.calls or 0) .. " ms/call x" .. h.calls
            .. " max " .. fixed(h.max, 1)
    end
    return "module " .. m.module .. ": " .. fixed(m.perTick) .. " ms/tick, max " .. fixed(m.tickMax, 1)
        .. " ms in one tick, " .. m.calls .. " calls (" .. table.concat(parts, "; ") .. ")"
end

-- Lignes du rapport (anglais, une information par ligne).
function Load.lines(sum)
    local out = {}
    if sum == nil then return { "no measure" } end
    out[#out + 1] = "load on " .. sum.side .. (sum.running and " (running)" or "") .. ": " .. fixed(sum.secs, 1)
        .. " s, " .. sum.ticks .. " ticks, engine " .. fixed(sum.perTickMs) .. " ms/tick (max " .. fixed(sum.tickMaxMs, 1)
        .. " ms in one tick, " .. sum.busyTicks .. " ticks >= 1 ms), " .. sum.measured .. " subscribers measured"
    if not sum.installed then out[#out + 1] = "not installed yet (waits for the next tick)" end
    local top = Load.CFG.TOP_MODULES
    local restMs, restN = 0, 0
    for i, m in ipairs(sum.modules) do
        if i <= top then
            out[#out + 1] = moduleLine(m)
        else
            restMs = restMs + m.ms
            restN = restN + 1
        end
    end
    if restN > 0 then
        out[#out + 1] = "modules: " .. restN .. " more, " .. fixed(sum.ticks > 0 and restMs / sum.ticks or 0)
            .. " ms/tick together"
    end
    out[#out + 1] = "net sent: " .. netText(sum.sent, sum.secs)
    out[#out + 1] = "net received: " .. netText(sum.recv, sum.secs)
    if sum.window ~= nil then
        local w = sum.window
        local names = {}
        for i, m in ipairs(w.modules) do
            if i > 5 then break end
            names[#names + 1] = m.module .. " " .. fixed(m.perTick)
        end
        out[#out + 1] = "last window (" .. fixed(w.secs, 1) .. " s, " .. w.ticks .. " ticks): engine "
            .. fixed(w.perTickMs) .. " ms/tick, max " .. fixed(w.maxMs, 1) .. " ms, sent " .. fixed(w.sentPerSec, 2)
            .. " msg/s (peak window " .. fixed(sum.peakSentPerSec, 2) .. "), top " .. table.concat(names, ", ")
    end
    if #sum.saves > 0 then
        local parts = {}
        for _, c in ipairs(sum.saves) do
            parts[#parts + 1] = c.header .. " " .. c.calls .. " (" .. fixed(sum.secs > 0 and c.calls * 60 / sum.secs or 0, 2)
                .. "/min, " .. fixed(c.calls > 0 and c.ms / c.calls or 0, 2) .. " ms each, max " .. fixed(c.max, 1) .. ")"
        end
        out[#out + 1] = "saves: " .. table.concat(parts, ", ")
    end
    local st = sum.state
    if type(st) == "table" then
        local keys = {}
        for k in pairs(st.sections) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            if st.sections[a] ~= st.sections[b] then return st.sections[a] > st.sections[b] end
            return a < b
        end)
        local parts = {}
        for i = 1, math.min(#keys, 6) do parts[i] = keys[i] .. " " .. st.sections[keys[i]] end
        out[#out + 1] = "state: registry " .. st.registry .. " B, groups " .. st.groups .. " B (largest fields: "
            .. table.concat(parts, ", ") .. "), attitudes " .. st.attitudes .. " B; " .. st.groupCount .. " groups, "
            .. st.members
            .. " members, " .. st.logEntries .. " log, " .. st.journalEntries .. " journal, " .. st.stockItems
            .. " stock entries"
    end
    out[#out + 1] = #sum.over > 0 and ("budget: OVER " .. table.concat(sum.over, "; ")) or "budget: ok"
    for i, line in ipairs(out) do out[i] = cut(line) end
    return out
end

-- Lignes d'une fenêtre close (journal périodique facultatif).
function Load.windowLines(s, w)
    local names = {}
    local mods = moduleTable(w.slots, w.ticks)
    for i, m in ipairs(mods) do
        if i > 5 then break end
        names[#names + 1] = m.module .. " " .. fixed(m.perTick)
    end
    return { cut("window " .. fixed(w.secs, 1) .. " s on " .. s.side .. ": " .. w.ticks .. " ticks, engine "
        .. fixed(w.ticks > 0 and w.ms / w.ticks or 0) .. " ms/tick, max " .. fixed(w.max, 1) .. " ms; sent "
        .. w.sent.count .. " msg / " .. w.sent.bytes .. " B, received " .. w.recv.count .. " msg; top "
        .. table.concat(names, ", ")) }
end

-- Console (debug) : imprime le rapport de la session en cours ou de la dernière.
function Load.print()
    local sum = Load.active and Load.summary() or Load.last
    for _, line in ipairs(Load.lines(sum)) do LivingKnox.Log.info("load: %s", line) end
    return sum ~= nil
end

-- Client MP : requête d'administration au serveur (le serveur vérifie le droit) ; la réponse est imprimée.
Load.askN = Load.askN or 0
function Load.ask(action, opts)
    if not isClient() then return false end
    Load.askN = Load.askN + 1
    local args = { op = "load", action = action, n = Load.askN }
    if type(opts) == "table" then
        args.windowMs = opts.windowMs
        args.log = opts.log == true
    end
    sendClientCommand(Load.MODULE, Load.CMD_REQUEST, args)
    return true
end

function Load.onReply(module, command, args)
    if module ~= Load.MODULE or command ~= Load.CMD_REPLY or type(args) ~= "table" or args.op ~= "load" then return end
    if args.ok ~= true then
        LivingKnox.Log.info("load: server refused the load request: %s", tostring(args.err))
        return
    end
    local lines = type(args.lines) == "table" and args.lines or {}
    for _, line in ipairs(lines) do LivingKnox.Log.info("load: server %s", tostring(line)) end
end

-- Abonnés permanents (transparents hors session ; clé "Load." : jamais enveloppés).
if Events ~= nil then
    local function onInstall() LivingKnox.Load.install() end
    local function onCounter() LivingKnox.Load.counter() end
    LivingKnox.subscribe("OnTickEvenPaused", "Load.install", onInstall)
    LivingKnox.subscribe("OnTick", "Load.counter", onCounter)
    if isClient() then
        local function onServerCommand(module, command, args)
            LivingKnox.Load.received(module, command, args)
            LivingKnox.Load.onReply(module, command, args)
        end
        LivingKnox.subscribe("OnServerCommand", "Load.received", onServerCommand)
    else
        local function onClientCommand(module, command, player, args)
            LivingKnox.Load.received(module, command, args)
        end
        LivingKnox.subscribe("OnClientCommand", "Load.received", onClientCommand)
    end
end

return Load
