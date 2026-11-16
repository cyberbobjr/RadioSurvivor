-- Radio Survivor : échange sans contact au lieu du rendez-vous (E13-T04 ; E20-T07 : un passage par marchand, règle
-- hors de vue et délai de jeu d'E20-T05, ADR D06/D07 ; E23-T07 : tout ou rien sur ce qui a été déposé, ADR D02/D03 de
-- adr-troc-simple-et-cas-limites.md). Fiche : docs/annexes/conception/passeur-echange.md ; barème
-- docs/specifications-techniques/passeur-table.md, code shared/CoreAI/CA_TradeValues.lua.
-- Autorité seulement (serveur MP, jeu local en solo).
--
-- « Contenant » désigne ci-dessous ce que cherche le mode d'arrivée du marchand à DROP_RADIUS cases du lieu (champ
-- holds, RS_TradeHolds : sacs posés au sol par défaut, contenants des objets du lieu pour une planque ; un véhicule
-- n'est jamais lu). Sondage à chaque minute de jeu (EveryOneMinute), pour chaque marchand :
-- - passage attendu ou arrivé, contenu du lieu pas encore noté, lieu chargé : le contenu présent est noté
--   (RS_TradeDeposit.snapshot, gardé avec le passage par Trade.noteDeposit) ; seul ce qui est ajouté ensuite compte ;
-- - passage arrivé, reprise : un contenant du lieu qui contient déjà un objet marqué de la révision du passage prouve
--   que l'échange a été appliqué au monde sans que l'état soit écrit : passage clos « done » sans rien reposer ;
-- - le marchand ne passe que hors de vue de tout joueur (RS_OutOfSight : personne à moins de VIEW_TILES cases sur
--   chaque axe, ou case déchargée) depuis delay_hours heures de jeu (fiche, sinon DELAY_HOURS) ; un joueur revenu à
--   portée remet l'attente à zéro. Délai écoulé : l'échange est dû (Trade.watchLanding) et se fait au premier
--   sondage où la case est chargée (un joueur qui revient la charge avant de la voir) ;
-- - jamais tranquille WAIT_HOURS heures après son arrivée : le marchand repart (« watched »), sans rien toucher ni
--   pénaliser ;
-- - échange dû : objets ajoutés depuis la note, additionnés sur tous les contenants (premier niveau ; un objet marqué
--   par un mod, MOD_PREFIXES, n'est jamais pris). Tout ce qui est convenu est là (Ex.counts : état, filtre, sac vide,
--   papiers à un nom) : le marchand prend exactement la liste convenue (le reste reste en place), laisse sa marchandise
--   dans le contenant qui tenait le plus du paiement (le premier à égalité, ordre du chercheur), passage clos « done ».
--   Dépôt incomplet : promesse non tenue, il garde tout ce qui a été ajouté et ne laisse rien, passage clos
--   « cheated » (raison short, marge au plus haut) et fait de réputation trade.cheated. Rien d'ajouté : passage clos
--   « cancelled » (no_drop) et fait trade.nodrop (la moitié). Retraits DoRemoveItem + sendRemoveItemFromContainer ;
--   marchandise créée par instanceItem (journal du dehors de l'édition en cours par RS_OutsideNewsServer.create),
--   marque ModData MARK = révision, AddItem + sendAddItemToContainer ; état écrit aussitôt (RS_State.save), le tout
--   dans un seul appel Lua.
-- Chaque issue est dite à la radio sur la fréquence de la voix du passage (RS_TradeRun.say) et le son de départ du
-- mode d'arrivée est joué au lieu (RS_TradeRun.playSound).
-- Messages de journal en anglais ; aucune coordonnée diffusée. Code ASCII seulement.
if isClient() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local S = require "RadioSurvivor/RS_State"
local Trade = require "RadioSurvivor/RS_Trade"
local Run = require "RadioSurvivor/RS_TradeRun"
local TV = require "CoreAI/CA_TradeValues"
local News = require "RadioSurvivor/RS_OutsideNews"
local NewsServer = require "RadioSurvivor/RS_OutsideNewsServer"
local Rep = require "CoreAI/CA_Reputation"
local OutOfSight = require "RadioSurvivor/RS_OutOfSight"
local Arrivals = require "RadioSurvivor/RS_TradeArrivals"
local Holds = require "RadioSurvivor/RS_TradeHolds"
local Deposit = require "RadioSurvivor/RS_TradeDeposit"

local Ex = {}

Ex.DROP_RADIUS = 3             -- cases autour du lieu du rendez-vous où le paiement est cherché
Ex.HOLDS = "bags"              -- chercheur des contenants d'un mode sans champ holds (RS_TradeHolds)
Ex.DELAY_HOURS = 1             -- heures de jeu hors de vue avant l'échange, sauf delay_hours de la fiche
Ex.WAIT_HOURS = 12             -- jamais tranquille 12 heures de jeu après son arrivée : le marchand repart
Ex.MARK = "RS_TradeGiven"      -- ModData de la marchandise laissée : révision de l'accord
-- Clés de ModData posées par ce mod sur des objets (objets de quête, preuves, butin des PNJ) : objet jamais pris.
Ex.MOD_PREFIXES = { "RS_", "RadioSurvivor", "CA_", "LK" }
Ex.USES_MIN = { ["Base.GasmaskFilter"] = 0.5 }               -- filtre à moitié plein au moins (section 2.4)
Ex.EMPTY = { ["Base.Bag_ALICEpack_Army"] = true }             -- sac militaire pris vide seulement
Ex.WALLETS = { ["Base.Wallet"] = true, ["Base.Wallet_Male"] = true, ["Base.Wallet_Female"] = true }

local function log(msg) Const.log("trade exchange: " .. msg) end

local sight = OutOfSight.engine()

-- Composition : règle hors de vue (les bancs ou un autre moteur injectent la leur).
function Ex.useSight(watcher) sight = watcher end

-- ================================================================ joueurs

local function players()
    local out = {}
    if isServer() then
        local list = getOnlinePlayers and getOnlinePlayers()
        if list then
            for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
        end
    else
        local p = getPlayer and getPlayer()
        if p then out[1] = p end
    end
    return out
end

-- « Prénom Nom » des personnages des joueurs en ligne (papiers à leur nom refusés).
function Ex.playerNames()
    local out = {}
    for _, pl in ipairs(players()) do
        local d = pl and pl.getDescriptor and pl:getDescriptor() or nil
        if d then
            local name = tostring(d:getForename() or "") .. " " .. tostring(d:getSurname() or "")
            if string.len(name) > 2 then out[#out + 1] = name end
        end
    end
    return out
end

-- ================================================================ ce qui compte

local function modMarked(item)
    if not (item.hasModData and item:hasModData()) then return false end
    for k in pairs(item:getModData()) do
        if type(k) == "string" then
            for _, p in ipairs(Ex.MOD_PREFIXES) do
                if string.sub(k, 1, string.len(p)) == p then return true end
            end
        end
    end
    return false
end

-- Papier nominatif : nom affiché différent du nom du script (base api-42-21.md, « Pièces d'identité nominatives »)
-- et sans le nom du personnage d'un joueur en ligne.
local function nominative(item, names)
    local shown = item:getDisplayName()
    local script = item.getScriptItem and item:getScriptItem() or nil
    local base = script and script:getDisplayName() or nil
    if type(shown) ~= "string" or shown == "" or shown == base then return false end
    for _, n in ipairs(names or {}) do
        if string.find(shown, n, 1, true) then return false end
    end
    return true
end

-- Vrai si l'objet compte pour une ligne convenue : au barème (CA_TradeValues), sans marque d'un mod, dans l'état de la table
-- (état minimal, filtre à moitié plein, sac militaire vide, papiers à un nom qui n'est pas celui d'un joueur en ligne ;
-- portefeuille compté seul).
function Ex.counts(item, names)
    local t = item.getFullType and item:getFullType() or nil
    local e = TV.entry(t) or (type(t) == "string" and TV.SELL_ONLY[t]) or nil
    if e == nil or modMarked(item) then return false end
    if e.cond then
        local max = item:getConditionMax()
        if type(max) == "number" and max > 0 and item:getCondition() / max < e.cond - 1e-9 then return false end
    end
    if Ex.USES_MIN[t] and item:getCurrentUsesFloat() < Ex.USES_MIN[t] - 1e-9 then return false end
    if Ex.EMPTY[t] and not item:getInventory():isEmpty() then return false end
    if e.k == "papers" and not Ex.WALLETS[t] and not nominative(item, names) then return false end
    return true
end

-- ================================================================ monde

-- Contenants du lieu du passage run (DROP_RADIUS cases autour), cherchés par le chercheur du mode d'arrivée du
-- marchand id (champ holds, RS_TradeHolds ; sacs au sol par défaut) : liste { inv, id }, ou nil si la case du lieu
-- n'est pas chargée.
function Ex.holdsAt(id, run)
    local spec = Trade.specOf(id)
    local mode = spec and Arrivals.get(spec.arrival) or nil
    local finder = Holds.get(mode and mode.holds or Ex.HOLDS)
    local p = run.landing
    return finder(p.x, p.y, p.z, Ex.DROP_RADIUS)
end

-- Vrai si le contenant contient un objet de marchandise marqué de la révision rev.
function Ex.hasMark(inv, rev)
    for _, item in ipairs(Deposit.itemsOf(inv)) do
        if item.hasModData and item:hasModData() and item:getModData()[Ex.MARK] == rev then return true end
    end
    return false
end

-- Retire du monde les objets des entrées { item, hold } (hold : index dans holds). Rend leur nombre.
function Ex.remove(holds, entries)
    for _, e in ipairs(entries) do
        local inv = holds[e.hold].inv
        inv:DoRemoveItem(e.item)
        sendRemoveItemFromContainer(inv, e.item)
    end
    return #entries
end

-- Crée la marchandise de l'accord (lignes offer.lines) dans le contenant inv, marquée mark. Rend la liste des objets.
function Ex.give(inv, offer, mark)
    local given = {}
    for _, l in ipairs(offer.lines or {}) do
        for _ = 1, l.q do
            local item
            if l.t == News.FULL_TYPE then
                item = NewsServer.create(News.currentEdition())
            else
                item = instanceItem(l.t)
            end
            if item then
                item:getModData()[Ex.MARK] = mark
                inv:AddItem(item)
                sendAddItemToContainer(inv, item)
                given[#given + 1] = item
            else
                log("WARNING: instanceItem(" .. tostring(l.t) .. ") returned nil, one item not given")
            end
        end
    end
    return given
end

-- ================================================================ issue

local function save()
    if S.data and not S.blocked and type(S.save) == "function" then S.save() end
end

-- Faits de réputation par raison de fin d'un passage (action fermée de CA_Reputation).
Ex.REPUTATION = { short = "trade.cheated", no_drop = "trade.nodrop" }

-- Clôt le passage arrivé du marchand id (Trade.finishRun), note le fait de réputation de la raison, écrit l'état, dit
-- l'issue à la radio (say : nom du texte, facultatif) et joue le son de départ du mode d'arrivée (sauf reprise : le
-- marchand est déjà loin).
local function finish(id, outcome, reason, detail, say)
    local run = Trade.finishRun(id, outcome, reason, detail)
    if run == nil then return nil end
    local action = Ex.REPUTATION[reason]
    if action and type(S.data) == "table" then
        local who = run.cid or run.caller
        -- Rejeu impossible : finishRun ne rend le passage qu'une fois, et l'eventId est unique par révision.
        Rep.record(nil, "trade-" .. tostring(run.rev) .. "-" .. reason, who, action, nil,
            { run = run.passage, rev = run.rev })
    end
    save()
    if say then Run.say(run, say, "exchange") end
    if reason ~= "recovered" then Run.playSound(run, "leave") end
    return run
end

local function delayOf(id)
    local spec = Trade.specOf(id)
    return spec and spec.delayHours or Ex.DELAY_HOURS
end

-- Échange dû au lieu chargé : tout ou rien sur ce qui a été ajouté depuis la note. Rend l'issue.
local function exchange(id, run, holds)
    local offer = Trade.offerOf(id, run.caller, run.cid)
    if offer == nil or offer.rev ~= run.rev or offer.state ~= "open" then
        finish(id, "cancelled", "no_offer")
        return "no_offer"
    end
    local added = {}
    for _, e in ipairs(Deposit.added(holds, run.seen)) do
        if not modMarked(e.item) then added[#added + 1] = e end
    end
    if #added == 0 then
        log("run " .. tostring(run.passage) .. " of " .. tostring(id) .. ": nothing added at the landing")
        finish(id, "cancelled", "no_drop", nil, "Cancel_nodrop")
        return "no_drop"
    end
    local names = Ex.playerNames()
    local match = Deposit.match(added, offer.wants, function(item) return Ex.counts(item, names) end)
    if not match.complete then
        local kept = Ex.remove(holds, added)
        log("run " .. tostring(run.passage) .. " of " .. tostring(id) .. ": payment incomplete, kept the "
            .. kept .. " items added")
        finish(id, "cheated", "short", { kept = kept, missing = match.missing }, "Cheated")
        return "cheated"
    end
    local target = holds[match.hold] or holds[1]
    local took = Ex.remove(holds, match.take)
    local given = Ex.give(target.inv, offer, run.rev)
    log("run " .. tostring(run.passage) .. " of " .. tostring(id) .. ": took the " .. took .. " items agreed, gave "
        .. #given .. " items in hold " .. tostring(target.id))
    finish(id, "done", "done", { took = took, given = #given, bag = target.id }, "Done")
    return "done"
end

-- Note le contenu du lieu la première fois qu'il est vu chargé après la réservation. Rend le passage relu.
local function noteLanding(id, run, holds)
    if run.seen ~= nil or holds == nil then return run end
    Trade.noteDeposit(id, Deposit.snapshot(holds))
    return Trade.lastRun(id)
end

-- Sondage du passage du marchand id à l'heure du monde hours. Rend l'issue (done, cheated, no_drop, watched,
-- no_offer) ou nil (rien à faire, ou attente).
function Ex.updateTrader(id, hours)
    hours = hours or Trade.worldHours()
    local run = Trade.lastRun(id)
    if run == nil or (run.state ~= "booked" and run.state ~= "arrived") or type(run.landing) ~= "table" then
        return nil
    end
    if run.state == "booked" and run.seen ~= nil then return nil end
    local holds = Ex.holdsAt(id, run)
    run = noteLanding(id, run, holds)
    if run.state ~= "arrived" then return nil end
    for _, hold in ipairs(holds or {}) do
        if Ex.hasMark(hold.inv, run.rev) then
            log("run " .. tostring(run.passage) .. " of " .. tostring(id) .. ": goods of offer "
                .. tostring(run.rev) .. " already at the landing, exchange recovered")
            finish(id, "done", "recovered")
            return "done"
        end
    end
    if not Trade.watchLanding(id, sight, delayOf(id)) then
        if hours >= (run.arrivedAt or hours) + Ex.WAIT_HOURS then
            finish(id, "cancelled", "watched", nil, "Cancel_watched")
            return "watched"
        end
        return nil
    end
    if holds == nil then return nil end             -- dû, case déchargée : au retour d'un joueur
    return exchange(id, Trade.lastRun(id), holds)
end

-- Sondage de tous les marchands.
function Ex.update(hours)
    for _, id in ipairs(Trade.traderIds()) do Ex.updateTrader(id, hours) end
end

local function onEveryOneMinute()
    Ex.update()
end

local installed = false
function Ex.install()
    if installed then return end
    installed = true
    if Events.EveryOneMinute then Events.EveryOneMinute.Add(onEveryOneMinute) end
end

Ex.install()

return Ex
