-- Radio Survivor : échange sans contact sur la berge (E13-T04). Fiche : docs/conception/passeur-echange.md ; barème
-- docs/passeur-table.md (sections 1 et 2), code shared/RadioSurvivor/RS_TradeValues.lua. Autorité seulement (serveur
-- MP, jeu local en solo).
--
-- Après le signal (RS_TradeRun : state arrived), le joueur dépose un sac au ponton (DROP_RADIUS cases autour de
-- Trade.PIER) et s'éloigne. Sondage à chaque minute de jeu (EveryOneMinute) tant que la barque attend :
-- - personne (aucun joueur vivant, quelle que soit son équipe) à moins de AWAY_RADIUS cases du ponton, case du ponton
--   chargée, au moins un sac (InventoryContainer posé au sol) dans la zone : le passeur passe. Il évalue le contenu de
--   chaque sac (premier niveau ; un portefeuille avec son contenu) au barème, avec les conditions et les plafonds de
--   la table, et prend dans l'ordre du sac ce qui couvre le prix de l'offre figée du passage (Trade.offerOf) ;
-- - assez : les objets pris sont retirés du sac (DoRemoveItem + sendRemoveItemFromContainer), la contrepartie de
--   l'offre est créée dans le même sac (instanceItem, journal du dehors par RS_OutsideNewsServer.create, marque
--   ModData MARK = révision de l'offre, AddItem + sendAddItemToContainer), puis le passage est clos « done »
--   (Trade.finishRun) et l'état privé écrit aussitôt (RS_State.save). Tout se fait dans un seul appel Lua : un joueur
--   qui revient ne peut rien interrompre, et le passage clos n'est plus sondé (contrepartie posée une seule fois) ;
-- - pas assez (sac de valeur positive mais inférieure au prix) : tricherie, rien n'est pris ni donné, passage clos
--   « cheated » (marge du passeur au plus haut, RS_Trade) et fait de réputation trade.cheated appliqué une fois au
--   personnage du carnet de l'appelant (RS_Reputation.record, réputation interne E04-T08 ; un appelant sans
--   personnage du carnet : fait noté sans effet) ;
-- - sac sans rien que le passeur prenne : ignoré (pas de tricherie) ;
-- - rien d'utile au bout de EXCHANGE_HOURS heures de jeu après l'arrivée : le passeur repart, passage annulé
--   (« no_drop »).
-- Reprise : un sac de la zone qui contient déjà un objet marqué de la révision du passage prouve que l'échange a été
-- appliqué au monde sans que l'état soit écrit : passage clos « done » sans rien reposer.
-- Chaque issue est dite à la radio sur la fréquence de la voix du passage (RS_TradeRun.say, texte traduit).
-- Messages de journal en anglais ; aucune coordonnée diffusée. Code ASCII seulement.
if isClient() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"
local Config = require "RadioSurvivor/RS_Config"
local S = require "RadioSurvivor/RS_State"
local Trade = require "RadioSurvivor/RS_Trade"
local Run = require "RadioSurvivor/RS_TradeRun"
local TV = require "RadioSurvivor/RS_TradeValues"
local News = require "RadioSurvivor/RS_OutsideNews"
local NewsServer = require "RadioSurvivor/RS_OutsideNewsServer"
local Rep = require "RadioSurvivor/RS_Reputation"

local Ex = {}

Ex.DROP_RADIUS = 3             -- cases autour de Trade.PIER où le sac est cherché (le ponton fait 2 x 6 cases)
Ex.AWAY_RADIUS = 20            -- personne à moins de 20 cases : le passeur accoste
Ex.EXCHANGE_HOURS = 2          -- heures de jeu d'attente après l'arrivée de la barque
Ex.CAP_POINTS = 120            -- points pris au plus par passage (section 1)
Ex.CAP_KG = 20                 -- poids pris au plus (place dans la barque, section 1)
Ex.MARK = "RS_TradeGiven"      -- ModData de la contrepartie : révision de l'offre
-- Clés de ModData posées par ce mod sur des objets (objets de quête, preuves, butin des PNJ) : objet refusé.
Ex.MOD_PREFIXES = { "RS_", "RadioSurvivor", "LK" }
Ex.USES_MIN = { ["Base.GasmaskFilter"] = 0.5 }               -- filtre à moitié plein au moins (section 2.4)
Ex.EMPTY = { ["Base.Bag_ALICEpack_Army"] = true }             -- sac militaire pris vide seulement
Ex.WALLETS = { ["Base.Wallet"] = true, ["Base.Wallet_Male"] = true, ["Base.Wallet_Female"] = true }

local function log(msg) Const.log("trade exchange: " .. msg) end

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

-- Un joueur vivant à moins de AWAY_RADIUS cases du ponton ?
function Ex.anyoneNear()
    local p = Trade.PIER
    local r2 = Ex.AWAY_RADIUS * Ex.AWAY_RADIUS
    for _, pl in ipairs(players()) do
        if pl and not (pl.isDead and pl:isDead()) then
            local dx, dy = pl:getX() - p.x, pl:getY() - p.y
            if dx * dx + dy * dy <= r2 then return true end
        end
    end
    return false
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

-- ================================================================ évaluation

-- Objets d'un conteneur (liste Lua, copie : on peut retirer en la parcourant).
function Ex.itemsOf(container)
    local out = {}
    local inv = container and container.getInventory and container:getInventory() or container
    local list = inv and inv:getItems()
    if list == nil then return out end
    for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
    return out
end

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

local function weightOf(item)
    local w = item.getUnequippedWeight and item:getUnequippedWeight() or 0
    return tonumber(w) or 0
end

-- Entrée du barème d'un objet que le passeur prend (classe de Trade.TAKES, conditions remplies), ou nil.
local function accepted(item, names, caps)
    local t = item.getFullType and item:getFullType() or nil
    if not TV.isBase(t) then return nil end
    local e = TV.entry(t)
    if e == nil or caps[e.k] == nil or modMarked(item) then return nil end
    if e.cond then
        local max = item:getConditionMax()
        if type(max) == "number" and max > 0 and item:getCondition() / max < e.cond - 1e-9 then return nil end
    end
    if Ex.USES_MIN[t] and item:getCurrentUsesFloat() < Ex.USES_MIN[t] - 1e-9 then return nil end
    if Ex.EMPTY[t] and not item:getInventory():isEmpty() then return nil end
    if e.k == "papers" and not Ex.WALLETS[t] and not nominative(item, names) then return nil end
    return e, t
end

-- Unités prises ou laissées d'un bloc : { items = objets retirés ensemble, parts = { { t, k, v, n } }, w = kg }.
-- Billets par lots entiers de e.lot ; portefeuille au premier niveau avec son contenu (parties en plus, objets non
-- pris emportés avec lui).
local function unitsOf(items, names, caps, depth)
    local units, money = {}, nil
    for _, item in ipairs(items) do
        local e, t = accepted(item, names, caps)
        if e and e.lot then
            money = money or { items = {}, t = t, e = e }
            money.items[#money.items + 1] = item
        elseif e then
            local parts = { { t = t, k = e.k, v = e.v, n = 1 } }
            if depth == 1 and Ex.WALLETS[t] and instanceof(item, "InventoryContainer") then
                for _, u in ipairs(unitsOf(Ex.itemsOf(item), names, caps, 2)) do
                    for _, p in ipairs(u.parts) do parts[#parts + 1] = p end
                end
            end
            units[#units + 1] = { items = { item }, parts = parts, w = weightOf(item) }
        end
    end
    if money then
        local lot = money.e.lot
        for i = 1, math.floor(#money.items / lot) do
            local its, w = {}, 0
            for j = (i - 1) * lot + 1, i * lot do
                its[#its + 1] = money.items[j]
                w = w + weightOf(money.items[j])
            end
            units[#units + 1] = { items = its, parts = { { t = money.t, k = money.e.k, v = money.e.v, n = lot } }, w = w }
        end
    end
    return units
end

-- Évalue le contenu d'un sac (liste d'objets du premier niveau) : prend dans l'ordre les unités qui tiennent dans
-- les plafonds (classe, pièces de papiers, nombre par type, CAP_POINTS, CAP_KG) jusqu'à couvrir need (facultatif :
-- sans need, tout ce qui tient). Rend { value, kg, taken = objets à retirer, lines = { t = nombre }, byClass,
-- pieces, left = unités laissées par les plafonds }.
function Ex.appraise(items, names, need)
    local caps = {}
    for _, c in ipairs(Trade.TAKES) do caps[c.k] = c end
    local res = { value = 0, kg = 0, taken = {}, lines = {}, byClass = {}, pieces = 0, left = 0 }
    for _, u in ipairs(unitsOf(items or {}, names, caps, 1)) do
        if need ~= nil and res.value >= need then break end
        local addClass, addCount, addPieces, addValue = {}, {}, 0, 0
        for _, p in ipairs(u.parts) do
            addClass[p.k] = (addClass[p.k] or 0) + p.v
            addCount[p.t] = (addCount[p.t] or 0) + p.n
            if p.k == "papers" then addPieces = addPieces + 1 end
            addValue = addValue + p.v
        end
        local ok = res.kg + u.w <= Ex.CAP_KG + 1e-9 and res.value + addValue <= Ex.CAP_POINTS
        for k, v in pairs(addClass) do
            if (res.byClass[k] or 0) + v > caps[k].cap then ok = false end
        end
        for t, n in pairs(addCount) do
            local cap = TV.entry(t).cap
            if cap and (res.lines[t] or 0) + n > cap then ok = false end
        end
        if caps.papers and caps.papers.pieces and res.pieces + addPieces > caps.papers.pieces then ok = false end
        if ok then
            for k, v in pairs(addClass) do res.byClass[k] = (res.byClass[k] or 0) + v end
            for t, n in pairs(addCount) do res.lines[t] = (res.lines[t] or 0) + n end
            res.pieces = res.pieces + addPieces
            res.value = res.value + addValue
            res.kg = res.kg + u.w
            for _, item in ipairs(u.items) do res.taken[#res.taken + 1] = item end
        else
            res.left = res.left + 1
        end
    end
    return res
end

-- ================================================================ monde

-- Sacs posés au sol dans le carré de côté 2r + 1 centré sur (cx, cy, z) ; nil si la case centrale n'est pas chargée.
function Ex.bagsIn(cx, cy, z, r)
    local cell = getCell and getCell() or nil
    if cell == nil or cell:getGridSquare(cx, cy, z) == nil then return nil end
    local out = {}
    for x = cx - r, cx + r do
        for y = cy - r, cy + r do
            local sq = cell:getGridSquare(x, y, z)
            local wos = sq and sq:getWorldObjects() or nil
            if wos then
                for i = 0, wos:size() - 1 do
                    local wo = wos:get(i)
                    local item = wo and wo:getItem() or nil
                    if item and instanceof(item, "InventoryContainer") then out[#out + 1] = item end
                end
            end
        end
    end
    return out
end

-- Vrai si le sac contient un objet de contrepartie marqué de la révision rev.
function Ex.hasMark(bag, rev)
    for _, item in ipairs(Ex.itemsOf(bag)) do
        if item.hasModData and item:hasModData() and item:getModData()[Ex.MARK] == rev then return true end
    end
    return false
end

-- Applique l'échange au sac : retire les objets pris, crée la contrepartie de l'offre (marquée mark). Rend la liste
-- des objets donnés.
function Ex.apply(bag, taken, offer, mark)
    local inv = bag:getInventory()
    for _, item in ipairs(taken) do
        inv:DoRemoveItem(item)
        sendRemoveItemFromContainer(inv, item)
    end
    local given = {}
    for _, l in ipairs(offer.lines or {}) do
        for _ = 1, l.q do
            local item
            if l.t == News.FULL_TYPE then item = NewsServer.create(offer.passage) else item = instanceItem(l.t) end
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

-- Clôt le passage arrivé (Trade.finishRun), écrit l'état, dit l'issue à la radio (say : nom du texte, facultatif).
local function finish(outcome, reason, detail, say)
    local run = Trade.finishRun(outcome, reason, detail)
    if run == nil then return nil end
    if outcome == "cheated" and type(S.data) == "table" and type(S.data.outcomes) == "table" then
        local who = run.cid or run.caller
        Rep.record(S.data, "trade-" .. tostring(run.rev) .. "-cheated", who, "trade.cheated",
            Config.Reputation and Config.Reputation.failure or -5,
            { run = run.passage, rev = run.rev, value = detail and detail.value, price = detail and detail.price })
        -- Rejeu impossible : finishRun ne rend le passage qu'une fois, et l'eventId « trade-<rév>-cheated » est unique.
    end
    save()
    if say then Run.say(run, say, "exchange") end
    return run
end

-- Sondage du passage dont la barque attend, à l'heure du monde hours. Rend l'issue (done, cheated, no_drop,
-- no_offer) ou nil (rien à faire, ou attente).
function Ex.update(hours)
    hours = hours or Trade.worldHours()
    local run = Trade.lastRun()
    if run == nil or run.state ~= "arrived" then return nil end
    local p = Trade.PIER
    local bags = Ex.bagsIn(p.x, p.y, p.z, Ex.DROP_RADIUS)
    for _, bag in ipairs(bags or {}) do
        if Ex.hasMark(bag, run.rev) then
            log("run " .. tostring(run.passage) .. ": counterpart of offer " .. tostring(run.rev)
                .. " already in a bag, exchange recovered")
            finish("done", "recovered")
            return "done"
        end
    end
    if hours >= (run.arrivedAt or hours) + Ex.EXCHANGE_HOURS then
        finish("cancelled", "no_drop", nil, "Cancel_nodrop")
        return "no_drop"
    end
    if bags == nil or #bags == 0 or Ex.anyoneNear() then return nil end
    local offer = Trade.offerOf(run.caller, run.cid)
    if offer == nil or offer.rev ~= run.rev or offer.state ~= "open" then
        finish("cancelled", "no_offer")
        return "no_offer"
    end
    local names = Ex.playerNames()
    local best, bestRes = nil, nil
    for _, bag in ipairs(bags) do
        local res = Ex.appraise(Ex.itemsOf(bag), names, offer.price)
        if bestRes == nil or res.value > bestRes.value then best, bestRes = bag, res end
    end
    if bestRes.value <= 0 then return nil end      -- rien que le passeur prenne : pas un échange
    local detail = { value = bestRes.value, price = offer.price, took = #bestRes.taken, bag = best:getID() }
    if bestRes.value < offer.price then
        log("run " .. tostring(run.passage) .. ": bag " .. tostring(detail.bag) .. " worth " .. bestRes.value
            .. " points for a price of " .. offer.price .. ", refused")
        finish("cheated", "cheated", detail, "Cheated")
        return "cheated"
    end
    local given = Ex.apply(best, bestRes.taken, offer, run.rev)
    detail.given = #given
    log("run " .. tostring(run.passage) .. ": took " .. #bestRes.taken .. " items worth " .. bestRes.value
        .. " points from bag " .. tostring(detail.bag) .. ", gave " .. #given .. " items for " .. offer.price)
    finish("done", "done", detail, "Done")
    return "done"
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
