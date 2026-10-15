-- Living Knox : fenêtre de troc avec un groupe (LK11-T08), côté joueur local (client MP, solo).
-- Fiche : docs/conception/troc.md. M = media/lua vanilla.
--
-- Menu contextuel « Troquer » sur un PNJ (OnFillWorldObjectContextMenu, même repérage du corps que « Demander de
-- l'aide » : LivingKnox.RelationsView.bodyNear) : ouvre la fenêtre et demande l'offre du groupe. Le client ne connaît
-- ni l'attitude ni le stock : l'option est offerte sur tout PNJ, le serveur répond par une offre ou un refus motivé
-- (réplique du PNJ). La fenêtre n'affiche que ce que le serveur a répondu : à gauche les objets du joueur que le groupe
-- prendrait (valeur pour lui), à droite les objets cédés (valeur V) ; un clic coche ou décoche. Totaux calculés avec le
-- barème partagé (shared/RadioSurvivor/RS_TradeValues.lua, coefficient k de l'offre) ; le serveur recalcule tout.
-- Transport : MP, sendClientCommand "tradeRequest" { op = "open" | "propose", n, npc, give, take } -> OnServerCommand
-- "tradeReply" ; solo, LivingKnox.Trade.request appelé directement (réponse rendue pendant l'appel : l'attente est
-- posée avant, base multiplayer.md). Aucun texte du joueur n'est lu.
if isServer() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_RelationsView"
local TV = require "RadioSurvivor/RS_TradeValues"

local View = LivingKnox.TradeView or {}
LivingKnox.TradeView = View

-- Copies des constantes de LK_Trade.lua (comparées par tests/test_lk_trade.py).
View.MODULE = "LivingKnox"
View.CMD_REQUEST = "tradeRequest"
View.CMD_REPLY = "tradeReply"

View.state = View.state or { n = 0, pending = nil, npc = nil, offer = nil, give = {}, take = {}, status = nil,
    window = nil }
View.stats = View.stats or { offered = 0, sent = 0, received = 0, stale = 0 }

local function tr(key, ...)
    return getText("IGUI_LK_Trade_" .. key, ...)
end

local function localPlayer()
    if getSpecificPlayer ~= nil then return getSpecificPlayer(0) end
    return nil
end

local function itemName(t)
    local name = getItemNameFromFullType ~= nil and getItemNameFromFullType(t) or nil
    if type(name) ~= "string" or name == "" then return tostring(t) end
    return name
end

local function points(v)
    if math.floor(v) == v then return tostring(v) end
    return string.format("%.1f", v)
end

-- Envoie une requête op ("open", "propose") pour le PNJ courant. Rend le numéro de requête, ou nil.
function View.send(op, fields)
    local st = View.state
    local player = localPlayer()
    if player == nil or st.npc == nil then return nil end
    st.n = st.n + 1
    local args = { op = op, n = st.n, npc = st.npc }
    for k, v in pairs(fields or {}) do args[k] = v end
    st.pending = st.n               -- posé AVANT l'envoi : en solo, la réponse arrive pendant l'appel
    st.status = tr("Waiting")
    View.stats.sent = View.stats.sent + 1
    if LivingKnox.isAuthority() then
        local T = LivingKnox.Trade
        if T == nil or T.request == nil then
            st.pending = nil
            st.status = tr("Unavailable")
            View.redraw()
            return nil
        end
        local out, why = T.request(player, args)
        if out == nil then out = { op = op, n = args.n, ok = false, err = tostring(why) } end
        View.receive(out)
    else
        sendClientCommand(player, View.MODULE, View.CMD_REQUEST, args)
    end
    return args.n
end

local function selected(set, list)
    local out = {}
    for _, e in ipairs(list or {}) do
        if set[e.i] then out[#out + 1] = e end
    end
    return out
end

-- Totaux de la sélection : valeur donnée, prix demandé (barème partagé).
function View.totals()
    local st = View.state
    local o = st.offer
    if o == nil then return 0, 0 end
    local values, lines = {}, {}
    for _, e in ipairs(selected(st.give, o.give)) do values[#values + 1] = e.v end
    for _, e in ipairs(selected(st.take, o.take)) do lines[#lines + 1] = { t = e.t, v = e.v } end
    return TV.giveTotal(values), (TV.askTotal(lines, o.k))
end

-- Réponse de l'autorité. Rend vrai si elle a été prise en compte.
function View.receive(reply)
    if type(reply) ~= "table" then return false end
    local st = View.state
    if st.pending == nil or reply.n ~= st.pending then
        View.stats.stale = View.stats.stale + 1
        return false
    end
    st.pending = nil
    View.stats.received = View.stats.received + 1
    if type(reply.offer) == "table" then
        st.offer = reply.offer
        st.give, st.take = {}, {}
    elseif reply.op == "open" then
        st.offer = nil
    end
    if reply.line ~= nil then
        local text = getText(reply.line)
        if reply.item ~= nil then text = text .. " (" .. itemName(reply.item) .. ")" end
        st.status = text
    elseif reply.err ~= nil then
        st.status = tr("Unavailable")
    else
        st.status = nil
    end
    View.redraw()
    return true
end

function View.onServerCommand(module, command, args)
    if module ~= View.MODULE or command ~= View.CMD_REPLY then return end
    View.receive(args)
end

function View.toggle(side, id)
    local set = View.state[side]
    if set == nil then return end
    if set[id] then set[id] = nil else set[id] = true end
    View.redraw()
end

-- Propose l'échange coché. Rend le numéro de requête, ou nil (rien de coché d'un côté).
function View.propose()
    local st = View.state
    if st.offer == nil then return nil end
    local give, take = {}, {}
    for _, e in ipairs(selected(st.give, st.offer.give)) do give[#give + 1] = e.i end
    for _, e in ipairs(selected(st.take, st.offer.take)) do take[#take + 1] = e.i end
    if #give == 0 or #take == 0 then
        st.status = getText("IGUI_LK_Trade_Refuse_empty")
        View.redraw()
        return nil
    end
    return View.send("propose", { give = give, take = take })
end

-- Texte d'une ligne de liste.
function View.rowText(e, checked)
    return (checked and "[x] " or "[ ] ") .. itemName(e.t) .. "  " .. tr("Points", points(e.v))
end

function View.redraw()
    local w = View.state.window
    if w ~= nil and w.refreshView ~= nil then w:refreshView() end
end

-- Ouvre la fenêtre pour le PNJ npc et demande l'offre.
function View.open(npc)
    local st = View.state
    if st.npc ~= npc then
        st.offer, st.give, st.take = nil, {}, {}
    end
    st.npc = npc
    if View.Window ~= nil then
        if st.window == nil then
            local win = View.Window:new(120, 120, 640, 420)
            win.title = tr("Title")
            win:setResizable(false)
            win:initialise()
            win:addToUIManager()
            st.window = win
        else
            st.window:setVisible(true)
            st.window:bringToTop()
        end
    end
    View.send("open")
    return st.window
end

function View.fill(playerNum, context, worldObjects, test)
    if not LivingKnox.Config.isEnabled() then return end
    local player = getSpecificPlayer(playerNum)
    if player == nil or player:isDead() then return end
    local R = LivingKnox.RelationsView
    local npc = R ~= nil and R.bodyNear ~= nil and R.bodyNear(player, worldObjects) or nil
    if npc == nil then return end
    if test then return ISWorldObjectContextMenu.setTest() end
    context:addOption(tr("Menu"), npc, View.open)
    View.stats.offered = View.stats.offered + 1
end

-- Fenêtre -----------------------------------------------------------------------------------------------------------

if ISCollapsableWindow ~= nil then
    local Window = ISCollapsableWindow:derive("LKTradeWindow")
    View.Window = Window

    local FONT = getTextManager():getFontHeight(UIFont.Small)
    local BTN = FONT + 8
    local PAD = 10
    local LIST_H = 260

    local function button(parent, x, y, title, fn)
        local w = getTextManager():MeasureStringX(UIFont.Small, title) + 20
        local b = ISButton:new(x, y, w, BTN, title, parent, fn)
        b:initialise()
        parent:addChild(b)
        return b
    end

    local function list(parent, x, y, w, side)
        local l = ISScrollingListBox:new(x, y, w, LIST_H)
        l:initialise()
        parent:addChild(l)
        l.itemheight = FONT + 6
        l.font = UIFont.Small
        l:setOnMouseDownFunction(parent, function(_, item)
            if type(item) == "table" and item.i ~= nil then LivingKnox.TradeView.toggle(side, item.i) end
        end)
        return l
    end

    function Window:createChildren()
        ISCollapsableWindow.createChildren(self)
        local th = self:titleBarHeight()
        local w = math.floor((self.width - 3 * PAD) / 2)
        self.labelY = th + PAD
        local y = self.labelY + FONT + 4
        self.giveList = list(self, PAD, y, w, "give")
        self.takeList = list(self, 2 * PAD + w, y, w, "take")
        self.takeX = 2 * PAD + w
        y = y + LIST_H + PAD
        self.totalY = y
        y = y + FONT + PAD
        self.proposeBtn = button(self, PAD, y, tr("Propose"), function() LivingKnox.TradeView.propose() end)
        self.refreshBtn = button(self, self.proposeBtn:getRight() + PAD, y, tr("Refresh"),
            function() LivingKnox.TradeView.send("open") end)
        self.statusY = y + BTN + PAD
        self:refreshView()
    end

    function Window:render()
        ISCollapsableWindow.render(self)
        self:drawText(tr("Yours"), PAD, self.labelY, 1, 1, 1, 1, UIFont.Small)
        self:drawText(tr("Theirs"), self.takeX, self.labelY, 1, 1, 1, 1, UIFont.Small)
        local give, ask = View.totals()
        local ok = give >= ask and ask > 0
        self:drawText(tr("Totals", tostring(give), tostring(ask)), PAD, self.totalY, ok and 0.6 or 1, 1,
            ok and 0.6 or 0.8, 1, UIFont.Small)
        local line = View.state.status
        if line ~= nil then
            self:drawText(tostring(line), PAD, self.statusY, 1, 1, 0.8, 1, UIFont.Small)
        end
    end

    function Window:close()
        ISCollapsableWindow.close(self)
        self:removeFromUIManager()
        if View.state.window == self then View.state.window = nil end
    end

    local function fillList(l, entries, set)
        l:clear()
        if #entries == 0 then
            l:addItem(tr("Nothing"), nil)
            return
        end
        for _, e in ipairs(entries) do l:addItem(View.rowText(e, set[e.i] == true), e) end
    end

    function Window:refreshView()
        if self.giveList == nil then return end
        local st = View.state
        local o = st.offer or { give = {}, take = {} }
        fillList(self.giveList, o.give or {}, st.give)
        fillList(self.takeList, o.take or {}, st.take)
        self.proposeBtn:setEnable(st.offer ~= nil and st.pending == nil)
    end
end

if Events ~= nil then
    local function onFill(playerNum, context, worldObjects, test)
        return LivingKnox.TradeView.fill(playerNum, context, worldObjects, test)
    end
    LivingKnox.subscribe("OnFillWorldObjectContextMenu", "TradeView.fill", onFill)
    if isClient() then   -- solo : réponses rendues directement par LivingKnox.Trade.request
        local function onServerCommand(module, command, args)
            LivingKnox.TradeView.onServerCommand(module, command, args)
        end
        LivingKnox.subscribe("OnServerCommand", "TradeView.onServerCommand", onServerCommand)
    end
end

return View
