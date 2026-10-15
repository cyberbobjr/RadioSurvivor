-- Living Knox : fenêtre d'administration des groupes (LK13-T01). Fiche : docs/conception/administration.md.
-- M = media/lua vanilla 42.21.
--
-- Affiche ce que l'autorité (server/LivingKnox/LK_Admin.lua) répond, sans rien décider : liste des groupes (état,
-- foyer exact = « carte » en coordonnées), détail et journal d'un groupe, relève forcée, foyer déplacé vers une case
-- saisie (ou la position du joueur). Le serveur revérifie les droits à chaque requête : la garde d'ici ne sert qu'à
-- l'affichage.
-- Ouverture :
--   - MP : bouton « Living Knox » du panneau d'admin vanilla (ISAdminPanelUI, panneau MP seulement : M/client/ISUI/
--     AdminPanel/ISAdminPanelUI.lua:23-24, 157-182 ; bouton ajouté avant le tri des enfants par title), actif si le
--     rôle du joueur a la capacité du serveur (getRole():hasCapability, affichage seulement) ;
--   - solo (mode debug) : bouton « Living Knox - Admin » du panneau debug vanilla (ISDebugMenu, posé par l'enveloppe de
--     setupButtons de LK_DebugView.lua, mêmes droits que le panneau de debug des PNJ : DebugView.canUse), bouton
--     « Groupes (admin) » du panneau de debug des PNJ, console Lua LivingKnox.AdminView.open().
-- Mesure de charge (LK13-T02, op "load" de LK_Admin.lua) : boutons Démarrer / Rapport / Arrêter ; le rapport (coût par
-- image et par module, réseau, écritures, taille de l'état, verdict des budgets) remplace le détail du groupe jusqu'au
-- choix d'un groupe (View.loadSend, état View.state.load).
-- Transport : MP, sendClientCommand "adminRequest" -> OnServerCommand "adminReply" ; solo, LivingKnox.Admin.request
-- appelé directement (réponse rendue pendant l'appel : l'attente est posée avant, base multiplayer.md).
if isServer() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Log"

local View = LivingKnox.AdminView or {}
LivingKnox.AdminView = View

-- Copies des constantes de LK_Admin.lua (comparées par tests/test_lk_admin.py).
View.MODULE = "LivingKnox"
View.CMD_REQUEST = "adminRequest"
View.CMD_REPLY = "adminReply"
View.CAPABILITY = "PopmanManage"
-- Réponses lues par LK_NpcSheet.lua (npc, npcSet) et LK_DebugView.lua (activity, LK13-T14), même commande de réponse.
View.SHEET_OPS = { npc = true, npcSet = true, activity = true }

View.state = View.state or { n = 0, pending = {}, groups = {}, hour = nil, enabled = true, selected = nil,
    detail = nil, status = nil, window = nil, load = nil, showLoad = false }
View.stats = View.stats or { sent = 0, received = 0, stale = 0, refused = 0 }

local function log() return LivingKnox.Log end

local function tr(key, ...)
    return getText("IGUI_LK_Admin_" .. key, ...)
end

local function count(name)
    View.stats[name] = (View.stats[name] or 0) + 1
end

local function localPlayer()
    if getSpecificPlayer ~= nil then return getSpecificPlayer(0) end
    return nil
end

-- Vrai si le joueur peut ouvrir l'outil (affichage seulement : le serveur décide). Solo : toujours.
function View.canUse(player)
    if not isClient() then return true end
    player = player or localPlayer()
    if player == nil or Capability == nil or Capability[View.CAPABILITY] == nil then return false end
    local role = player:getRole()
    return role ~= nil and role:hasCapability(Capability[View.CAPABILITY]) == true
end

-- Envoie une requête op (list, group, relief, home) avec les champs fields. Rend le numéro de requête, ou nil.
function View.send(op, fields)
    local st = View.state
    local player = localPlayer()
    if player == nil then return nil end
    st.n = st.n + 1
    local args = { op = op, n = st.n }
    for k, v in pairs(fields or {}) do args[k] = v end
    st.pending[op] = st.n            -- posé AVANT l'envoi : en solo, la réponse arrive pendant l'appel
    count("sent")
    if isClient() then
        sendClientCommand(player, View.MODULE, View.CMD_REQUEST, args)
    else
        local A = LivingKnox.Admin
        if A == nil or A.request == nil then
            st.pending[op] = nil
            st.status = tr("NotLoaded")
            View.redraw()
            return nil
        end
        View.receive(A.request(player, args))
    end
    return args.n
end

function View.refresh()
    View.send("list")
    if View.state.selected ~= nil then View.send("group", { gid = View.state.selected }) end
end

function View.select(gid)
    View.state.selected = gid
    View.state.showLoad = false
    View.state.detail = nil
    View.send("group", { gid = gid })
    View.redraw()
end

-- Réponse de l'autorité. Rend vrai si elle a été prise en compte.
function View.receive(reply)
    if type(reply) ~= "table" or type(reply.op) ~= "string" then return false end
    if View.SHEET_OPS[reply.op] then return false end   -- LK13-T13/T14 : fiche d'un PNJ, panneau de debug des PNJ
    local st = View.state
    if st.pending[reply.op] ~= reply.n then
        count("stale")
        return false
    end
    st.pending[reply.op] = nil
    count("received")
    if not reply.ok then
        count("refused")
        if reply.err == "denied" then st.status = tr("Denied") else st.status = tr("Error", tostring(reply.err)) end
    elseif reply.op == "list" then
        st.groups = type(reply.groups) == "table" and reply.groups or {}
        st.hour, st.enabled = reply.hour, reply.enabled == true
        if not st.enabled then st.status = tr("Disabled") end
    elseif reply.op == "group" then
        if type(reply.group) == "table" and reply.group.id == st.selected then st.detail = reply.group end
    elseif reply.op == "relief" then
        st.status = tr("ReliefDone", tostring(reply.gid), tostring(reply.relief))
        View.refresh()
    elseif reply.op == "load" then
        st.load = { action = reply.action, running = reply.running == true,
            lines = type(reply.lines) == "table" and reply.lines or {} }
        st.showLoad = true
        st.status = tr(st.load.running and "LoadRunning" or "LoadStopped")
    elseif reply.op == "home" then
        local h = type(reply.home) == "table" and reply.home or {}
        st.status = tr("HomeDone", tostring(reply.gid), tostring(h.x) .. "," .. tostring(h.y) .. "," .. tostring(h.z))
        View.refresh()
    end
    View.redraw()
    return true
end

function View.onServerCommand(module, command, args)
    if module ~= View.MODULE or command ~= View.CMD_REPLY then return end
    View.receive(args)
end

-- Mesure de charge de l'autorité (LK13-T02) : action "start", "report" ou "stop". Rend le numéro de requête, ou nil.
View.LOAD_ACTIONS = { start = true, report = true, stop = true }
function View.loadSend(action)
    if not View.LOAD_ACTIONS[action] then return nil end
    return View.send("load", { action = action })
end

-- Texte riche du rapport de mesure (lignes rendues par l'autorité, LK_Load.lines).
function View.loadText(load)
    local L = { " <H2> " .. tr("LoadTitle") .. " <TEXT> " }
    L[#L + 1] = tr(load.running and "LoadRunning" or "LoadStopped")
    for _, line in ipairs(load.lines or {}) do L[#L + 1] = (string.gsub(tostring(line), "<", "(")) end
    return table.concat(L, " <LINE> ")
end

-- Textes ----------------------------------------------------------------------------------------------------------

local function safe(s)
    return (string.gsub(tostring(s), "<", "("))
end

local function typeName(t)
    local name = getTextOrNull and getTextOrNull("IGUI_LK_GroupType_" .. tostring(t)) or nil
    return name or tostring(t)
end

local function coords(h)
    if type(h) ~= "table" then return tr("NoHome") end
    return tr("Home", h.x .. "," .. h.y .. "," .. h.z)
end

local function goneText(r)
    local g = r.gone
    if type(g) ~= "table" then return nil end
    if g.relief ~= nil then return tr("Relieved", tostring(g.cause), tostring(g.relief)) end
    if type(g.dueIn) == "number" and g.dueIn > 0 then return tr("Gone", tostring(g.cause), tostring(g.dueIn)) end
    return tr("GoneDue", tostring(g.cause))
end

-- Entrée du journal de récit (vue de LK_Journal.entryView, LK10-T02) : date « jour, heure » et texte composé dans la
-- langue du client (arguments à clé : rôle, lieu, résolus d'abord, repli sur leur texte ; même règle que
-- LK_Journal.compose côté serveur).
function View.journalWhen(e)
    if type(e.hour) == "number" then return tr("JournalWhen", e.day, string.format("%02d", e.hour)) end
    return tr("Day", e.day)
end

function View.journalText(e)
    local args = {}
    for i, a in ipairs(type(e.args) == "table" and e.args or {}) do
        local text = a.key ~= nil and getTextOrNull ~= nil and getTextOrNull(a.key) or nil
        args[i] = safe(text or a.text)
    end
    return getText(tostring(e.key), args[1], args[2], args[3], args[4])
end

-- Ligne de la liste pour un groupe r (réponse list).
function View.rowText(r)
    local parts = { r.id, typeName(r.type), safe(r.name), tr("Alive", r.alive, r.total) }
    if (r.embodied or 0) > 0 then parts[#parts + 1] = tr("Embodied", r.embodied) end
    if r.objective ~= nil then parts[#parts + 1] = tr("Objective", r.objective) end
    parts[#parts + 1] = coords(r.home)
    local gone = goneText(r)
    if gone then parts[#parts + 1] = gone end
    return table.concat(parts, "  |  ")
end

-- Vrai si la relève forcée peut être demandée pour le détail d : groupe disparu sans relève, ou sans aucun vivant pas
-- encore constaté disparu (l'autorité pose alors la marque, LK_Admin.forceRelief).
function View.canRelieve(d)
    if type(d) ~= "table" then return false end
    if type(d.gone) == "table" then return d.gone.relief == nil end
    return (d.alive or 0) == 0 and (d.total or 0) > 0
end

-- Texte riche du détail d'un groupe d (réponse group).
function View.detailText(d)
    local L = {}
    local function line(s) L[#L + 1] = safe(s) end
    line(View.rowText(d))
    line(tr("Needs", d.needs.food, d.needs.medical, d.needs.ammo, d.morale))
    if d.task ~= nil then line(tr("Task", d.task)) end
    if type(d.expedition) == "table" then
        line(tr("Expedition", tostring(d.expedition.place), d.expedition.team, tostring(d.expedition.returns)))
    end
    if d.replaces ~= nil then line(tr("Replaces", d.replaces)) end
    if type(d.story) == "string" and d.story ~= "" then line(d.story) end
    local out = table.concat(L, " <LINE> ") .. " <LINE> <LINE> <H2> " .. tr("Members") .. " <TEXT> <LINE> "
    L = {}
    for _, m in ipairs(d.members or {}) do
        local s = m.id .. "  " .. tostring(m.role) .. (m.id == d.leader and (" (" .. tr("Leader") .. ")") or "")
            .. "  " .. (m.alive and tr("IsAlive") or tr("IsDead"))
        if m.npc ~= nil then s = s .. "  " .. m.npc end
        if m.duty ~= nil then s = s .. "  " .. tr("Duty", m.duty) end
        if (m.wound or 0) > 0 then s = s .. "  " .. tr("Wound", m.wound) end
        if m.embodied then s = s .. "  " .. tr("Present") end
        line(s)
    end
    out = out .. table.concat(L, " <LINE> ") .. " <LINE> <LINE> <H2> " .. tr("Journal") .. " <TEXT> <LINE> "
    L = {}
    local story = d.journal or {}
    for i = #story, 1, -1 do   -- journal de récit (LK10-T02), plus récente d'abord
        local e = story[i]
        line(View.journalWhen(e) .. "  " .. View.journalText(e))
    end
    out = out .. table.concat(L, " <LINE> ") .. " <LINE> <LINE> <H2> " .. tr("Log") .. " <TEXT> <LINE> "
    L = {}
    local entries = d.log or {}
    for i = #entries, 1, -1 do   -- plus récente d'abord
        local e = entries[i]
        line(tr("Day", e.day) .. "  " .. tostring(e.kind) .. "  " .. tostring(e.text))
    end
    return out .. table.concat(L, " <LINE> ")
end

-- Fenêtre -----------------------------------------------------------------------------------------------------------

function View.redraw()
    local w = View.state.window
    if w ~= nil and w.refreshView ~= nil then w:refreshView() end
end

if ISCollapsableWindow ~= nil then
    local Window = ISCollapsableWindow:derive("LKAdminWindow")
    View.Window = Window

    local FONT = getTextManager():getFontHeight(UIFont.Small)
    local BTN = FONT + 8
    local PAD = 10

    local function button(parent, x, y, title, fn)
        local w = getTextManager():MeasureStringX(UIFont.Small, title) + 20
        local b = ISButton:new(x, y, w, BTN, title, parent, fn)
        b:initialise()
        parent:addChild(b)
        return b
    end

    local function entry(parent, x, y, w)
        local e = ISTextEntryBox:new("", x, y, w, BTN)
        e:initialise()
        parent:addChild(e)       -- instantiate : réglages Java seulement après (base ui-windows.md)
        e:setOnlyNumbers(true)
        e:setMaxTextLength(6)
        return e
    end

    function Window:createChildren()
        ISCollapsableWindow.createChildren(self)
        local th = self:titleBarHeight()
        local w = self.width - 2 * PAD
        local y = th + PAD
        self.list = ISScrollingListBox:new(PAD, y, w, 180)
        self.list:initialise()
        self:addChild(self.list)
        self.list.itemheight = FONT + 6
        self.list.font = UIFont.Small
        self.list:setOnMouseDownFunction(self, function(_, item)
            if type(item) == "table" and type(item.id) == "string" then LivingKnox.AdminView.select(item.id) end
        end)
        y = y + 180 + PAD
        self.detail = ISRichTextPanel:new(PAD, y, w, 220)
        self.detail:initialise()
        self:addChild(self.detail)
        self.detail:addScrollBars()
        self.detail.clip = true
        self.detail.autosetheight = false
        self.detail.background = true
        self.detail.backgroundColor = { r = 0, g = 0, b = 0, a = 0.5 }
        self.detail.marginRight = self.detail.marginLeft
        y = y + 220 + PAD
        local x = PAD
        self.refreshBtn = button(self, x, y, tr("Refresh"), function() LivingKnox.AdminView.refresh() end)
        x = self.refreshBtn:getRight() + PAD
        self.reliefBtn = button(self, x, y, tr("Relief"), function(win) win:onRelief() end)
        x = self.reliefBtn:getRight() + 2 * PAD
        self.xEntry = entry(self, x, y, 60)
        self.yEntry = entry(self, self.xEntry:getRight() + 4, y, 60)
        self.zEntry = entry(self, self.yEntry:getRight() + 4, y, 36)
        x = self.zEntry:getRight() + PAD
        self.hereBtn = button(self, x, y, tr("Here"), function(win) win:fillHere() end)
        x = self.hereBtn:getRight() + PAD
        self.homeBtn = button(self, x, y, tr("MoveHome"), function(win) win:onMoveHome() end)
        x = self.homeBtn:getRight() + 2 * PAD
        -- LK13-T14 : panneau de debug des PNJ (mêmes droits que la fiche d'un PNJ : debug en solo).
        self.debugBtn = button(self, x, y, tr("DebugView"), function() LivingKnox.AdminView.openDebugView() end)
        -- LK13-T02 : mesure de charge de l'autorité.
        y = y + BTN + PAD
        self.loadStartBtn = button(self, PAD, y, tr("LoadStart"), function() LivingKnox.AdminView.loadSend("start") end)
        self.loadReportBtn = button(self, self.loadStartBtn:getRight() + PAD, y, tr("LoadReport"),
            function() LivingKnox.AdminView.loadSend("report") end)
        self.loadStopBtn = button(self, self.loadReportBtn:getRight() + PAD, y, tr("LoadStop"),
            function() LivingKnox.AdminView.loadSend("stop") end)
        self.statusY = y + BTN + PAD
        self:fillHere()
        self:refreshView()
    end

    function Window:fillHere()
        local p = localPlayer()
        if p == nil then return end
        self.xEntry:setText(tostring(math.floor(p:getX())))
        self.yEntry:setText(tostring(math.floor(p:getY())))
        self.zEntry:setText(tostring(math.floor(p:getZ())))
    end

    local function unfocus(e)
        if e ~= nil and e.isFocused ~= nil and e:isFocused() then e:unfocus() end
    end

    function Window:unfocusEntries()
        unfocus(self.xEntry)
        unfocus(self.yEntry)
        unfocus(self.zEntry)
    end

    function Window:onRelief()
        self:unfocusEntries()
        local gid = View.state.selected
        if gid == nil then
            View.state.status = tr("Select")
            return self:refreshView()
        end
        View.send("relief", { gid = gid })
    end

    function Window:onMoveHome()
        self:unfocusEntries()
        local gid = View.state.selected
        local x, y = tonumber(self.xEntry:getText()), tonumber(self.yEntry:getText())
        local z = tonumber(self.zEntry:getText())
        if gid == nil or x == nil or y == nil or z == nil then
            View.state.status = tr(gid == nil and "Select" or "BadSquare")
            return self:refreshView()
        end
        View.send("home", { gid = gid, x = math.floor(x), y = math.floor(y), z = math.floor(z) })
    end

    function Window:refreshView()
        if self.list == nil then return end
        local st = View.state
        local selectedIndex = nil
        self.list:clear()
        for _, r in ipairs(st.groups or {}) do
            self.list:addItem(View.rowText(r), r)
            if r.id == st.selected then selectedIndex = #self.list.items end
        end
        if selectedIndex ~= nil then self.list.selected = selectedIndex end
        local text = tr("Select")
        if st.showLoad and st.load ~= nil then
            text = View.loadText(st.load)
        elseif st.detail ~= nil and st.detail.id == st.selected then
            text = View.detailText(st.detail)
        end
        self.detail:setText(text)
        self.detail:paginate()
        self.reliefBtn:setEnable(View.canRelieve(st.detail))
        self.homeBtn:setEnable(st.selected ~= nil)
        local D = LivingKnox.DebugView
        self.debugBtn:setEnable(D ~= nil and D.canUse ~= nil and D.canUse() == true)
        local running = st.load ~= nil and st.load.running == true
        self.loadStartBtn:setEnable(not running)   -- arrêt et rapport toujours offerts (mesure lancée ailleurs)
    end

    function Window:render()
        ISCollapsableWindow.render(self)
        local st = View.state
        local line = st.status
        if line == nil then
            for _, n in pairs(st.pending) do
                if n ~= nil then line = tr("Waiting") end
            end
        end
        if line == nil and st.hour ~= nil then line = tr("Hour", st.hour) end
        if line ~= nil then self:drawText(safe(line), PAD, self.statusY, 1, 1, 0.8, 1, UIFont.Small) end
    end

    function Window:close()
        self:unfocusEntries()
        ISCollapsableWindow.close(self)
        self:removeFromUIManager()
        if View.state.window == self then View.state.window = nil end
    end

    -- Ouvre (ou ramène devant) la fenêtre et demande la liste. Rend la fenêtre, ou nil si le joueur n'y a pas droit.
    function View.open()
        if not View.canUse() then
            log().warn("admin window: not allowed for this player (capability %s)", View.CAPABILITY)
            return nil
        end
        local st = View.state
        if st.window == nil then
            local w = math.min(860, getCore():getScreenWidth() - 40)
            local h = 180 + 220 + 3 * BTN + 7 * PAD + 30
            local win = Window:new(80, 80, w, h)
            win.title = tr("Title")
            win.backgroundColor = { r = 0.08, g = 0.08, b = 0.08, a = 1 }   -- opaque : lisible sur le jeu (essai solo)
            win:setResizable(false)
            win:initialise()
            win:addToUIManager()
            st.window = win
        else
            st.window:setVisible(true)
            st.window:bringToTop()
        end
        st.status = nil
        View.refresh()
        return st.window
    end
end

-- Panneau de debug des PNJ (LK13-T14, LK_DebugView.lua), ouvert sur le groupe choisi ici.
function View.openDebugView()
    local D = LivingKnox.DebugView
    if D == nil or D.open == nil then return nil end
    return D.open(View.state.selected)
end

-- Bouton du panneau d'admin (MP) -----------------------------------------------------------------------------------

if ISAdminPanelUI ~= nil and isClient() then
    View.baseCreate = View.baseCreate or ISAdminPanelUI.create
    View.baseUpdate = View.baseUpdate or ISAdminPanelUI.updateButtons
    function ISAdminPanelUI:create(...)
        local fh = getTextManager():getFontHeight(UIFont.Small)
        local b = ISButton:new(0, 0, 200, fh + 6, tr("Button"), self, function() LivingKnox.AdminView.open() end)
        b:initialise()
        b:instantiate()
        b.borderColor = self.buttonBorderColor
        b.tooltip = tr("ButtonTooltip")
        self:addChild(b)          -- avant le tri par title de l'original (base ui-windows.md)
        self.lkAdminBtn = b
        return View.baseCreate(self, ...)
    end
    function ISAdminPanelUI:updateButtons(...)
        local result = View.baseUpdate(self, ...)
        if self.lkAdminBtn ~= nil then self.lkAdminBtn.enable = View.canUse() end
        return result
    end
end

if isClient() then   -- solo : réponses rendues directement par LivingKnox.Admin.request
    local function onServerCommand(module, command, args)
        LivingKnox.AdminView.onServerCommand(module, command, args)
    end
    LivingKnox.subscribe("OnServerCommand", "AdminView.onServerCommand", onServerCommand)
end

return View
