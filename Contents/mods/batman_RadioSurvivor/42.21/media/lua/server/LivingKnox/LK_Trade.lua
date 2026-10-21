-- Living Knox : troc direct d'un joueur avec un groupe ami (LK11-T08). Fiche : docs/annexes/conception/troc.md.
-- Java 42.21.0 cité en abrégé (J = zombie/...) ; M = media/lua vanilla.
-- Autorité seulement (serveur dédié ou hébergé, solo) : un client MP charge aussi media/lua/server, il s'arrête ici.
--
-- Le joueur ouvre la fenêtre de troc (client/LivingKnox/LK_TradeView.lua, menu contextuel « Troquer » sur un PNJ),
-- reçoit l'offre du groupe (Trade.offer : ses objets que le groupe prendrait, avec leur valeur ; les objets du stock
-- réel que le groupe cède, avec leur valeur ; le coefficient de prix), coche des objets des deux côtés et propose.
-- Le serveur réévalue tout au moment de la proposition (Trade.evaluate, lecture seule) puis l'applique (Trade.apply)
-- dans le même appel Lua, sans rien attendre : aucun paquet ni aucun autre code du jeu ne passe entre la vérification
-- de présence des objets et leur déplacement.
-- Barème commun avec le passeur de l'Ohio : shared/RadioSurvivor/RS_TradeValues.lua
-- (docs/specifications-techniques/passeur-table.md, section 5).
--   - marge du groupe selon l'attitude envers le joueur (LivingKnox.Hostility.get) : CFG.MARGIN ; autres niveaux :
--     refus "attitude" ;
--   - ce que le joueur donne vaut V x multiplicateur de besoin (Trade.buyFactor, réserves de LK_Stock relues
--     maintenant), arrondi au point inférieur sur le total ; argent, bijoux, images et papiers : refus "unwanted" ;
--   - ce que le groupe cède coûte ceil(V x quantité x (1 + marge)) par type ; refus "price" si le joueur donne moins ;
--   - le groupe ne cède pas ce qui lui manque : après l'échange, chaque catégorie de stock d'où il cède garde sa
--     réserve visée (have - cédés + reçus >= want, seuils de LK08-T07), sinon refus "short".
-- Ordre d'écriture (Trade.apply ; aucun objet créé, aucun objet en double, aucun perdu) :
--   1. une écriture du registre des groupes : objets cédés ôtés de la référence du stock, entrée « trade » au journal
--      du groupe ; échec : rien n'a bougé (refus "away") ;
--   2. objets du joueur, un par un : retirés de son inventaire (DoRemoveItem, sendRemoveItemFromContainer : paquet au
--      joueur seul, J/network/GameServer.java:2269-2277), puis rangés dans un conteneur du foyer (AddItem,
--      sendAddItemToContainer) ;
--   3. objets du groupe, un par un : retirés de leur meuble puis remis au joueur comme le vanilla remet un objet
--      (M/shared/ActionManager.lua:4-24 : inventaire, ou au sol à ses pieds s'il est trop chargé) ;
--   4. relecture du stock (Stock.check) : les objets reçus entrent dans la référence comme des dépôts.
-- Un seul objet est en transit à la fois ; un déplacement qui échoue remet l'objet dans son conteneur d'origine. Un
-- arrêt après l'étape 1 laisse au pire un objet cédé dans son meuble (relu comme un ajout) : jamais un vol compté.
-- Déconnexion : la proposition est traitée à sa réception, joueur présent ; un joueur parti avant n'a rien envoyé.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Groups"
require "LivingKnox/LK_Hostility"
require "LivingKnox/LK_Stock"
local TV = require "RadioSurvivor/RS_TradeValues"

local Trade = LivingKnox.Trade or {}
LivingKnox.Trade = Trade

Trade.MODULE = "LivingKnox"
Trade.CMD_REQUEST = "tradeRequest"
Trade.CMD_REPLY = "tradeReply"
Trade.OPS = { open = true, propose = true }
Trade.REASONS = { "attitude", "away", "empty", "unwanted", "worn", "short", "gone", "price", "stranger" }
Trade.Values = TV
-- Réglages (valeurs de départ, à recalibrer en jeu ; fiche troc.md).
Trade.CFG = Trade.CFG or {
    RANGE = 4,                                                    -- distance joueur-PNJ au plus (cases)
    MARGIN = { trusting = 0.10, favorable = 0.10, cautious = 0.30 }, -- marge par attitude ; autre : pas de troc
    GROUP_REFUSES = { valuables = true, images = true, papers = true }, -- classes sans débouché pour un groupe
    -- Multiplicateur de besoin de ce que le groupe reçoit, sur l'échelle de réserve du barème (0..100, réserve visée
    -- = TARGET_LEVEL) : niveau = TARGET_LEVEL x have / want.
    TARGET_LEVEL = 60,
    BUY = { { below = 25, factor = 1.5 }, { below = 60, factor = 1.0 }, { below = 100, factor = 0.5 } },
    MAX_LINES = 24,     -- objets au plus de chaque côté d'une proposition
    OFFER_MAX = 40,     -- objets au plus de chaque liste d'une offre
}
Trade.stats = Trade.stats or { offers = 0, proposals = 0, done = 0, refused = 0, moved = 0, failed = 0 }

local function log() return LivingKnox.Log end
local function Groups() return LivingKnox.Groups end
local function Stock() return LivingKnox.Stock end
local function Hostility() return LivingKnox.Hostility end
local function cfg() return Trade.CFG end

local function isInt(v) return type(v) == "number" and v == v and math.floor(v) == v and v > -2147483649
    and v < 2147483648 end

-- ================================================================ valeurs

-- Marge du groupe pour le niveau d'attitude level, ou nil (pas de troc).
function Trade.margin(level)
    return cfg().MARGIN[level]
end

-- Multiplicateur de besoin d'un objet reçu par le groupe dans la catégorie de stock cat, d'après l'évaluation a
-- (Stock.needs). Objet hors des catégories du stock (piles, alcool, matériel militaire) : 1. 0 = réserve pleine.
function Trade.buyFactor(cat, a)
    if cat == nil or a == nil or a.have == nil or a.have[cat] == nil then return 1 end
    local have, want = a.have[cat], a.want[cat] or 0
    local level = want > 0 and cfg().TARGET_LEVEL * have / want or 100
    for _, step in ipairs(cfg().BUY) do
        if level < step.below then return step.factor end
    end
    return 0
end

local function conditionOk(item, need)
    if need == nil then return true end
    local max = item:getConditionMax()
    if max == nil or max <= 0 then return true end
    return item:getCondition() / max >= need
end

-- Catégorie de stock et valeur V d'un objet pour un groupe (classes refusées et objets non conformes : 0, raison).
local function baseValue(item)
    local S = Stock()
    local t = item:getFullType()
    if not TV.isBase(t) then return 0, nil, "unwanted" end
    local cat = S.categoryOf(item)
    local v, class = TV.value(t, cat)
    if v <= 0 or (class ~= nil and cfg().GROUP_REFUSES[class]) then return 0, cat, "unwanted" end
    local e = TV.entry(t)
    if e ~= nil and not conditionOk(item, e.cond) then return 0, cat, "unwanted" end
    if (cat == "food" or cat == "water") and not S.consumable(item, cat) then return 0, cat, "unwanted" end
    return v, cat
end
Trade.baseValue = baseValue

-- Vrai si l'objet de l'inventaire du joueur est porté, tenu, accroché ou marqué favori (jamais pris).
local function inUse(player, item)
    if player:isEquipped(item) or player:isAttachedItem(item) then return true end
    return item:isFavorite() == true
end

-- Valeur pour le groupe d'un objet du joueur : V x multiplicateur (> 0), ou 0 et la raison ("worn", "unwanted"),
-- et la catégorie de stock.
function Trade.playerValue(player, item, a)
    if inUse(player, item) then return 0, "worn" end
    if instanceof(item, "InventoryContainer") and not item:getInventory():isEmpty() then return 0, "unwanted" end
    local v, cat, why = baseValue(item)
    if v <= 0 then return 0, why, cat end
    local f = Trade.buyFactor(cat, a)
    if f <= 0 then return 0, "unwanted", cat end
    return v * f, nil, cat
end

-- ================================================================ lectures

-- Objets de premier niveau de l'inventaire principal du joueur, par identifiant.
local function playerItems(player)
    local out, order = {}, {}
    local items = player:getInventory():getItems()
    for j = 0, items:size() - 1 do
        local it = items:get(j)
        if it ~= nil then
            out[it:getID()] = it
            order[#order + 1] = it
        end
    end
    return out, order
end

-- Objets que le groupe peut céder, relus maintenant dans les conteneurs du foyer : objets des catégories du stock
-- (valeur > 0, consommables pour la nourriture et l'eau) et, dans les conteneurs posés pour le groupe (caisse,
-- tentes), objets du barème hors catégories (ce qu'un joueur y a laissé). Rend { { i, t, v, c, item, container, key,
-- owned } } dans l'ordre des conteneurs.
local function candidates(containers)
    local out = {}
    for _, ct in ipairs(containers) do
        local items = ct.container:getItems()
        for j = 0, items:size() - 1 do
            local it = items:get(j)
            if it ~= nil then
                local v, cat = baseValue(it)
                if v > 0 and (cat ~= nil or ct.owned) then
                    out[#out + 1] = { i = it:getID(), t = it:getFullType(), v = v, c = cat, item = it,
                                      container = ct.container, key = ct.key }
                end
            end
        end
    end
    return out
end

-- Conteneur où ranger ce que le groupe reçoit : premier conteneur posé pour le groupe, sinon le premier du foyer.
local function destination(containers)
    for _, ct in ipairs(containers) do
        if ct.owned then return ct end
    end
    return containers[1]
end

-- Contexte commun : attitude, marge, évaluation du stock, conteneurs. Rend ctx, ou nil, raison, détail.
local function context(gid, key)
    local H = Hostility()
    local att, why = H.get(gid, key)
    if att == nil then return nil, "away", tostring(why) end
    local m = Trade.margin(att.level)
    if m == nil then return nil, "attitude", att.level end
    local S = Stock()
    local a, sw = S.needs(gid)
    if a == nil then return nil, "away", tostring(sw) end
    local containers, cw = S.homeContainers(gid)
    if containers == nil or #containers == 0 then return nil, "away", tostring(cw or "no container") end
    a = S.needs(gid) or a   -- écarts hors écran appliqués par homeContainers
    return { level = att.level, margin = m, k = 1 + m, a = a, containers = containers }
end

-- Offre du groupe gid au joueur de clé key : { k, give = { { i, t, v } } (objets du joueur que le groupe prendrait),
-- take = { { i, t, v } } (objets cédés, au plus le surplus de chaque catégorie au-dessus de la réserve visée) }, ou
-- nil, raison, détail.
function Trade.offer(gid, key, player)
    local ctx, why, detail = context(gid, key)
    if ctx == nil then return nil, why, detail end
    local out = { k = ctx.k, give = {}, take = {} }
    local _, order = playerItems(player)
    for _, it in ipairs(order) do
        if #out.give >= cfg().OFFER_MAX then break end
        local v = Trade.playerValue(player, it, ctx.a)
        if v > 0 then out.give[#out.give + 1] = { i = it:getID(), t = it:getFullType(), v = v } end
    end
    local left = {}
    for c, have in pairs(ctx.a.have) do left[c] = have - (ctx.a.want[c] or 0) end
    for _, e in ipairs(candidates(ctx.containers)) do
        if #out.take >= cfg().OFFER_MAX then break end
        if e.c == nil or left[e.c] == nil or left[e.c] > 0 then
            if e.c ~= nil and left[e.c] ~= nil then left[e.c] = left[e.c] - 1 end
            out.take[#out.take + 1] = { i = e.i, t = e.t, v = e.v }
        end
    end
    return out
end

local function idList(list)
    if type(list) ~= "table" then return nil end
    local out, seen = {}, {}
    for _, id in ipairs(list) do
        if not isInt(id) or seen[id] then return nil end
        seen[id] = true
        out[#out + 1] = id
    end
    if #out > cfg().MAX_LINES then return nil end
    return out
end
Trade.idList = idList

-- Évalue (lecture seule) l'échange : le joueur donne les objets d'identifiants give (son inventaire principal),
-- demande ceux d'identifiants take (conteneurs du foyer). Rend { ok, reason, detail, item (type en cause), k,
-- given, asked, gives = { { item, t, i, v, c } }, takes = { { item, container, key, t, i, v, c } }, dest } ; ok
-- vrai si l'échange est acceptable.
function Trade.evaluate(gid, key, player, give, take)
    local ev = { ok = false }
    give, take = idList(give), idList(take)
    if give == nil or take == nil then
        ev.reason, ev.detail = "empty", "bad item list"
        return ev
    end
    if #give == 0 or #take == 0 then
        ev.reason = "empty"
        return ev
    end
    local ctx, why, detail = context(gid, key)
    if ctx == nil then
        ev.reason, ev.detail = why, detail
        return ev
    end
    ev.k, ev.level = ctx.k, ctx.level
    local mine = playerItems(player)
    local gives, values, bought = {}, {}, {}
    for _, id in ipairs(give) do
        local it = mine[id]
        if it == nil then
            ev.reason, ev.detail = "gone", "player item " .. tostring(id)
            return ev
        end
        local v, vwhy, cat = Trade.playerValue(player, it, ctx.a)
        if v <= 0 then
            ev.reason, ev.detail, ev.item = vwhy, it:getFullType(), it:getFullType()
            return ev
        end
        gives[#gives + 1] = { item = it, t = it:getFullType(), i = id, v = v, c = cat }
        values[#values + 1] = v
        if cat ~= nil then bought[cat] = (bought[cat] or 0) + 1 end
    end
    local byId = {}
    for _, e in ipairs(candidates(ctx.containers)) do byId[e.i] = e end
    local takes, lines, sold = {}, {}, {}
    for _, id in ipairs(take) do
        local e = byId[id]
        if e == nil then
            ev.reason, ev.detail = "gone", "group item " .. tostring(id)
            return ev
        end
        takes[#takes + 1] = e
        lines[#lines + 1] = { t = e.t, v = e.v }
        if e.c ~= nil then sold[e.c] = (sold[e.c] or 0) + 1 end
    end
    for _, c in ipairs(Stock().CATEGORIES) do
        if (sold[c] or 0) > 0 then
            local have, want = ctx.a.have[c] or 0, ctx.a.want[c] or 0
            local after = have - sold[c] + (bought[c] or 0)
            if after < want then
                ev.reason, ev.detail = "short", string.format("%s: have %d, keep %d, after %d", c, have, want, after)
                return ev
            end
        end
    end
    ev.given = TV.giveTotal(values)
    ev.asked = TV.askTotal(lines, ctx.k)
    ev.gives, ev.takes, ev.dest = gives, takes, destination(ctx.containers)
    if ev.given < ev.asked then
        ev.reason, ev.detail = "price", string.format("give %d, ask %d", ev.given, ev.asked)
        return ev
    end
    ev.ok, ev.reason = true, "done"
    return ev
end

-- ================================================================ application

-- Déplace un objet de from vers to (retrait puis ajout, envoyés aux clients sur un serveur). En cas d'erreur, l'objet
-- est remis dans from. Rend vrai si l'objet est arrivé.
local function transfer(item, from, to)
    local removed = false
    local ok, err = pcall(function()
        from:DoRemoveItem(item)
        removed = true
        if isServer() then sendRemoveItemFromContainer(from, item) end
        to:AddItem(item)
        if isServer() then sendAddItemToContainer(to, item) end
    end)
    if ok then return true end
    log().error("trade: moving %s (%s) failed: %s", tostring(item:getFullType()), tostring(item:getID()), tostring(err))
    if removed and not to:getItems():contains(item) then
        from:AddItem(item)
        if isServer() then sendAddItemToContainer(from, item) end
    end
    return false
end

-- Remet au joueur un objet retiré d'un meuble : inventaire, ou au sol à ses pieds s'il est trop chargé (comme
-- Actions.addOrDropItem). Rend "inventory", "ground" ou nil.
local function deliver(item, from, player)
    if not transfer(item, from, player:getInventory()) then return nil end
    local inv = player:getInventory()
    if inv:getCapacityWeight() <= inv:getEffectiveCapacity(player) then return "inventory" end
    inv:DoRemoveItem(item)
    if isServer() then sendRemoveItemFromContainer(inv, item) end
    local sq = player:getCurrentSquare()
    if sq == nil then
        inv:AddItem(item)
        if isServer() then sendAddItemToContainer(inv, item) end
        return "inventory"
    end
    sq:AddWorldInventoryItem(item, 0.5, 0.5, 0, true)
    return "ground"
end

local function typesText(list)
    local parts = {}
    for _, e in ipairs(list) do parts[#parts + 1] = e.t end
    return table.concat(parts, ", ")
end

-- Applique un échange évalué acceptable (ev de Trade.evaluate, même appel Lua). Rend vrai et le détail { ground =
-- objets posés au sol, failed = déplacements échoués }, ou nil et une raison (registre non écrit : rien n'a bougé).
function Trade.apply(gid, key, player, ev)
    local G, S = Groups(), Stock()
    local soldIds = {}
    for _, e in ipairs(ev.takes) do soldIds[e.i] = true end
    local text = string.format("trade with %s: got %s; gave %s (%d for %d)", key, typesText(ev.gives),
        typesText(ev.takes), ev.given, ev.asked)
    local written = G.update(function(data)
        local live = data.groups[gid]
        if live == nil or type(live.home) ~= "table" or not S.validRef(live.stock, live.home) then
            return false, false
        end
        local kept = {}
        for _, e in ipairs(live.stock.items) do
            if not soldIds[e.i] then kept[#kept + 1] = e end
        end
        live.stock.items = kept
        G.appendLog(live, "trade", string.sub(text, 1, G.TEXT_MAX), G.today())
        return true, true
    end)
    if not written or not G.flush() then return nil, "registry not written" end   -- LK13-T06 : écrit avant le monde
    local out = { ground = 0, failed = 0 }
    local inv = player:getInventory()
    for _, e in ipairs(ev.gives) do
        if transfer(e.item, inv, ev.dest.container) then
            Trade.stats.moved = Trade.stats.moved + 1
        else
            out.failed = out.failed + 1
        end
    end
    for _, e in ipairs(ev.takes) do
        local where = deliver(e.item, e.container, player)
        if where == nil then
            out.failed = out.failed + 1
        else
            Trade.stats.moved = Trade.stats.moved + 1
            if where == "ground" then out.ground = out.ground + 1 end
        end
    end
    Trade.stats.failed = Trade.stats.failed + out.failed
    local r, why = S.check(gid, { force = true })
    if r == nil then log().warn("trade: group %s stock not read again after the trade: %s", gid, tostring(why)) end
    return true, out
end

-- ================================================================ réplique, demandes

local function reply(npc, lineKey, player, band)
    local Sp = LivingKnox.Speech
    if npc == nil or Sp == nil or Sp.say == nil then return false end
    local ok, out = pcall(Sp.say, npc, { key = lineKey }, { player = player, band = band, chat = false })
    if not ok then
        log().warn("trade: reply %s of %s failed: %s", lineKey, tostring(npc), tostring(out))
        return false
    end
    return out ~= nil
end

local function bandOf(level)
    local Sp = LivingKnox.Speech
    if Sp ~= nil and Sp.bandOf ~= nil and level ~= nil then return Sp.bandOf(level) end
    return nil
end

-- Proposition du joueur de clé key au groupe gid (logique de Trade.request, sans contrôle de distance). opts =
-- { npc = membre qui répond (facultatif) }. Rend { ok, reason, detail, item, given, asked, ground, line, said }.
function Trade.propose(gid, key, player, give, take, opts)
    opts = type(opts) == "table" and opts or {}
    Trade.stats.proposals = Trade.stats.proposals + 1
    local ev = Trade.evaluate(gid, key, player, give, take)
    local out = { ok = false, reason = ev.reason, detail = ev.detail, item = ev.item, given = ev.given,
                  asked = ev.asked }
    if ev.ok then
        local done, res = Trade.apply(gid, key, player, ev)
        if done then
            out.ok, out.ground, out.failed = true, res.ground, res.failed
            Trade.stats.done = Trade.stats.done + 1
            LivingKnox.publish("tradeDone", { group = gid, player = key, got = typesText(ev.gives),
                gave = typesText(ev.takes), given = ev.given, asked = ev.asked, npc = opts.npc,
                day = Groups().today() })
            log().info("trade: group %s traded with %s: got %s; gave %s (%d for %d)%s", gid, key,
                typesText(ev.gives), typesText(ev.takes), ev.given, ev.asked,
                res.failed > 0 and (", " .. res.failed .. " move(s) failed") or "")
        else
            out.reason, out.detail = "away", tostring(res)
        end
    end
    if out.ok then
        out.line = "IGUI_LK_Trade_Done"
    else
        Trade.stats.refused = Trade.stats.refused + 1
        out.line = "IGUI_LK_Trade_Refuse_" .. tostring(out.reason)
        log().info("trade: group %s refused a trade with %s: %s%s", gid, key, tostring(out.reason),
            out.detail and (" (" .. out.detail .. ")") or "")
    end
    out.said = reply(opts.npc, out.line, player, out.ok and "friendly" or bandOf(ev.level))
    return out
end

-- PNJ npc d'un groupe, corps présent à CFG.RANGE cases au plus du joueur, même niveau. Rend gid, ou nil et raison.
local function near(player, npc)
    if type(npc) ~= "string" then return nil, "bad request" end
    local gid = Groups().findNpc(npc)
    if gid == nil then return nil, "npc not in a group" end
    local B = LivingKnox.Bodies
    local body = B ~= nil and B.find ~= nil and B.find(npc) or nil
    if body == nil then return nil, "npc not embodied" end
    local dx, dy = body:getX() - player:getX(), body:getY() - player:getY()
    local r = cfg().RANGE
    if math.floor(body:getZ()) ~= math.floor(player:getZ()) or dx * dx + dy * dy > r * r then
        return nil, "too far"
    end
    return gid
end

-- Demande venue de la fenêtre d'un joueur (commande "tradeRequest" en MP, appel direct en solo) : args = { op =
-- "open" | "propose", n = numéro de requête, npc = "lk-<n>", give = { id }, take = { id } }. Rend la réponse
-- { op, n, npc, ok, reason, detail, item, line, offer (offre à jour), given, asked, ground }, ou nil et une raison
-- (requête invalide, PNJ absent ou trop loin : rien n'est dit).
function Trade.request(player, args)
    if type(args) ~= "table" or player == nil or player:isDead() then return nil, "bad request" end
    if not LivingKnox.isAuthority() then return nil, "not the authority" end
    if not Trade.OPS[args.op] or not isInt(args.n) then return nil, "bad request" end
    local gid, why = near(player, args.npc)
    if gid == nil then return nil, why end
    local out = { op = args.op, n = args.n, npc = args.npc, ok = false }
    local key = Hostility().keyOf(player)
    if key == nil then
        out.reason, out.line = "stranger", "IGUI_LK_Trade_Refuse_stranger"
        reply(args.npc, out.line, player, nil)
        Trade.stats.refused = Trade.stats.refused + 1
        return out
    end
    if args.op == "propose" then
        local res = Trade.propose(gid, key, player, args.give, args.take, { npc = args.npc })
        for k, v in pairs(res) do out[k] = v end
        out.op, out.n = "propose", args.n
    end
    Trade.stats.offers = Trade.stats.offers + 1
    local offer, ow, od = Trade.offer(gid, key, player)
    if offer ~= nil then
        out.offer = offer
        if args.op == "open" then out.ok = true end
    elseif args.op == "open" then
        out.reason, out.detail = ow, od
        out.line = "IGUI_LK_Trade_Refuse_" .. tostring(ow)
        Trade.stats.refused = Trade.stats.refused + 1
        local att = Hostility().get(gid, key)
        reply(args.npc, out.line, player, bandOf(att and att.level))
        log().info("trade: group %s will not trade with %s: %s (%s)", gid, key, tostring(ow), tostring(od))
    end
    return out
end

function Trade.onClientCommand(module, command, player, args)
    if module ~= Trade.MODULE or command ~= Trade.CMD_REQUEST or not isServer() or player == nil then return end
    local out, why = Trade.request(player, args)
    if out == nil then
        log().info("trade: request of %s refused: %s", tostring(player:getUsername()), tostring(why))
        out = { op = type(args) == "table" and args.op or nil, n = type(args) == "table" and args.n or nil,
                ok = false, err = tostring(why) }
    end
    sendServerCommand(player, Trade.MODULE, Trade.CMD_REPLY, out)
end

if Events ~= nil and isServer() then
    local function onClientCommand(module, command, player, args)
        LivingKnox.Trade.onClientCommand(module, command, player, args)
    end
    LivingKnox.subscribe("OnClientCommand", "Trade.onClientCommand", onClientCommand)
end

return Trade
