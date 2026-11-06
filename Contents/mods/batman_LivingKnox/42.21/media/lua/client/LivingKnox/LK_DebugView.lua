-- Living Knox : panneau de debug des PNJ (LK13-T14). Fiche : docs/annexes/conception/administration.md, section « Panneau de
-- debug des PNJ ». M = media/lua vanilla 42.21.
--
-- Affiche ce que l'autorité répond à l'opération "activity" de LK_Admin.lua, sans rien décider : liste de tous les
-- groupes ; pour le groupe choisi, l'activité en direct de chaque PNJ (comportement, règle et raison, cible, routine,
-- geste, engagement, position, besoins, santé, incarné ou hors écran), le journal d'activité fin tenu en mémoire par
-- l'autorité (LK_Activity.lua, MAX lignes) et le journal sauvegardé du groupe ; ouverture de la fiche d'un membre
-- (LK13-T13, LivingKnox.NpcSheet.open).
-- LK13-T15 : quatre tableaux à colonnes (LK_Table.lua : en-têtes cliquables pour trier, texte coupé avec « ... »,
-- infobulle de la ligne entière) : groupes (id, nom, type, chef, vivants et présents, objectif, alerte et défense),
-- membres du groupe choisi, journal d'activité (plus récent d'abord) et journal sauvegardé ; fond opaque, police
-- UIFont.Small partout ; boutons « Ouvrir la fiche » et « Se téléporter » (op npcGoto par la fiche, NpcSheet.teleport).
-- LK13-T16 : colonne « Foyer » des groupes, position de chaque membre avec sa source (corps, dernière position connue,
-- foyer du groupe : LK_Admin.positionOf, DebugView.posText) ; « Se téléporter » vers un PNJ hors écran mène à sa
-- dernière position connue, sinon au foyer de son groupe (choix de l'autorité) ; bouton « Aller au foyer » du groupe
-- choisi (op homeGoto par la fiche, NpcSheet.teleportHome).
-- Droits : ceux de la fiche d'un PNJ (DebugView.canUse : solo = mode debug, client MP = rôle avec la capacité de
-- l'outil, affichage seulement) ; l'autorité revérifie à CHAQUE requête (LK_Admin.isAllowed, op dans DEBUG_OPS).
-- Rafraîchissement : une requête toutes les REFRESH_MS tant que le panneau est ouvert (DebugView.poll, appelé par
-- l'update de la fenêtre), jamais si une réponse est attendue ; rien panneau fermé. Envoi incrémental : le client
-- envoie le numéro de la dernière ligne d'activité reçue (after), l'autorité ne renvoie que les suivantes.
-- Ouverture : bouton du panneau debug vanilla (ISDebugMenu, onglet MAIN : enveloppe de setupButtons qui ajoute le
-- bouton AVANT l'original, trié avec les autres, M/client/DebugUIs/DebugMenu/ISDebugMenu.lua:16-58), bouton de la
-- fenêtre des groupes (LK_AdminView.lua) et console Lua : LivingKnox.DebugView.open().
-- Fenêtre d'administration (LK13-T01, LK_AdminView.lua) : bouton « Living Knox - Admin » posé par la même enveloppe du
-- panneau debug vanilla (une seule enveloppe pour les deux boutons : pas d'ordre de rechargement entre deux fichiers)
-- et bouton « Groupes (admin) » de ce panneau ; mêmes droits d'affichage (DebugView.canUse).
-- Transport : celui de LK_AdminView (MP : "adminRequest" -> "adminReply" ; solo : LivingKnox.Admin.request appelé
-- directement, réponse rendue pendant l'appel, attente posée avant).
if isServer() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Table"

local DebugView = LivingKnox.DebugView or {}
LivingKnox.DebugView = DebugView

-- Copies des constantes de LK_Admin.lua et LK_Activity.lua (comparées par tests/test_lk_debugview.py).
DebugView.MODULE = "LivingKnox"
DebugView.CMD_REQUEST = "adminRequest"
DebugView.CMD_REPLY = "adminReply"
DebugView.CAPABILITY = "PopmanManage"
DebugView.OP = "activity"
DebugView.MAX = 200          -- lignes d'activité gardées (celles de l'autorité)

DebugView.REFRESH_MS = 2000  -- relecture du panneau ouvert (décision du 2026-10-12)

DebugView.state = DebugView.state or { n = 0, pending = nil, groups = {}, hour = nil, enabled = true, selected = nil,
    data = nil, entries = {}, after = 0, member = nil, status = nil, window = nil, lastMs = nil }
DebugView.stats = DebugView.stats or { sent = 0, received = 0, stale = 0, refused = 0, polls = 0 }

local function log() return LivingKnox.Log end

local function tr(key, ...)
    return getText("IGUI_LK_Debug_" .. key, ...)
end

local function count(name)
    DebugView.stats[name] = (DebugView.stats[name] or 0) + 1
end

local function localPlayer()
    if getSpecificPlayer ~= nil then return getSpecificPlayer(0) end
    return nil
end

local function now() return getTimestampMs() end

-- Vrai si le joueur peut ouvrir le panneau (affichage seulement : l'autorité décide). Mêmes droits que la fiche.
function DebugView.canUse(player)
    if not isClient() then return isDebugEnabled ~= nil and isDebugEnabled() == true end
    player = player or localPlayer()
    if player == nil or Capability == nil or Capability[DebugView.CAPABILITY] == nil then return false end
    local role = player:getRole()
    return role ~= nil and role:hasCapability(Capability[DebugView.CAPABILITY]) == true
end

-- Requêtes -----------------------------------------------------------------------------------------------------------

-- Envoie la requête "activity" (liste des groupes, et activité du groupe choisi après la dernière ligne reçue). Rend
-- le numéro de requête, ou nil.
function DebugView.send()
    local st = DebugView.state
    local player = localPlayer()
    if player == nil then return nil end
    st.n = st.n + 1
    local args = { op = DebugView.OP, n = st.n }
    if st.selected ~= nil then
        args.gid = st.selected
        args.after = st.after
    end
    st.pending = st.n                -- posé AVANT l'envoi : en solo, la réponse arrive pendant l'appel
    st.lastMs = now()
    count("sent")
    if isClient() then
        sendClientCommand(player, DebugView.MODULE, DebugView.CMD_REQUEST, args)
    else
        local A = LivingKnox.Admin
        if A == nil or A.request == nil then
            st.pending = nil
            st.status = tr("NotLoaded")
            DebugView.redraw()
            return nil
        end
        DebugView.receive(A.request(player, args))
    end
    return args.n
end

-- Relecture périodique du panneau ouvert : au plus une requête par REFRESH_MS, aucune si une réponse est attendue,
-- aucune panneau fermé. Rend vrai si une requête est partie.
function DebugView.poll(ms)
    local st = DebugView.state
    if st.window == nil or st.pending ~= nil then return false end
    ms = ms or now()
    if st.lastMs ~= nil and ms - st.lastMs < DebugView.REFRESH_MS then return false end
    count("polls")
    return DebugView.send() ~= nil
end

-- Choix du groupe gid (nil : aucun) : activité et membre choisi oubliés, requête au prochain poll (aussitôt si aucune
-- réponse n'est attendue et que le panneau est ouvert).
function DebugView.select(gid)
    local st = DebugView.state
    if gid ~= st.selected then
        st.selected, st.data, st.entries, st.after, st.member = gid, nil, {}, 0, nil
    end
    st.lastMs = nil
    if st.window ~= nil and st.pending == nil then DebugView.send() end
    DebugView.redraw()
end

-- Lignes d'activité reçues (numéros croissants) ajoutées à celles déjà reçues, MAX gardées.
local function merge(st, list)
    for _, e in ipairs(type(list) == "table" and list or {}) do
        if type(e) == "table" and type(e.s) == "number" and e.s > st.after then
            st.entries[#st.entries + 1] = e
            st.after = e.s
        end
    end
    local extra = #st.entries - DebugView.MAX
    if extra > 0 then
        local kept = {}
        for i = extra + 1, #st.entries do kept[#kept + 1] = st.entries[i] end
        st.entries = kept
    end
end

-- Réponse de l'autorité. Rend vrai si elle a été prise en compte.
function DebugView.receive(reply)
    if type(reply) ~= "table" or reply.op ~= DebugView.OP then return false end
    local st = DebugView.state
    if st.pending ~= reply.n then
        count("stale")
        return false
    end
    st.pending = nil
    count("received")
    if not reply.ok then
        count("refused")
        if reply.err == "denied" then st.status = tr("Denied") else st.status = tr("Error", tostring(reply.err)) end
    else
        st.status = nil
        st.groups = type(reply.groups) == "table" and reply.groups or {}
        st.hour, st.enabled = reply.hour, reply.enabled == true
        if not st.enabled then st.status = tr("Disabled") end
        local g = reply.group
        if type(g) == "table" and g.id ~= nil and g.id == st.selected and reply.gid == st.selected then
            if type(g.seq) == "number" and g.seq < st.after then   -- autorité redémarrée : numéros repartis de zéro
                st.entries, st.after = {}, 0
                st.lastMs = nil
            end
            merge(st, g.activity)
            g.activity = nil
            st.data = g
        end
    end
    DebugView.redraw()
    return true
end

function DebugView.onServerCommand(module, command, args)
    if module ~= DebugView.MODULE or command ~= DebugView.CMD_REPLY then return end
    DebugView.receive(args)
end

-- Cellules des tableaux (LK13-T15) -----------------------------------------------------------------------------------

local function opt(v)
    if v == nil then return "-" end
    return tostring(v)
end

local function typeName(t)
    local name = getTextOrNull ~= nil and getTextOrNull("IGUI_LK_GroupType_" .. tostring(t)) or nil
    return name or tostring(t)
end

local function numberIn(id)
    return tonumber(string.match(tostring(id), "(%d+)$"))
end

-- Heure de jeu d'une minute d'âge du monde : jour (1 = premier, comme LK_Groups.today) et heure du jour (âge 0 à 7 h,
-- base api-42-21.md).
function DebugView.when(minute)
    if type(minute) ~= "number" then return "-" end
    local day = math.floor(minute / 1440) + 1
    local hod = (math.floor(minute / 60) + 7) % 24
    return tr("When", day, string.format("%02d:%02d", hod, minute % 60))
end

local function xyz(p)
    if type(p) ~= "table" or type(p.x) ~= "number" or type(p.y) ~= "number" or type(p.z) ~= "number" then
        return "-"
    end
    return math.floor(p.x) .. "," .. math.floor(p.y) .. "," .. math.floor(p.z)
end

-- Position d'un membre avec sa source (LK13-T16, LK_Admin.positionOf : "body" corps chargé, "last" dernière position
-- connue, "home" foyer du groupe ; vue sans src : last = dernière position connue). "-" sans position.
DebugView.POS_SOURCES = { body = true, last = true, home = true }
function DebugView.posText(p)
    local s = xyz(p)
    if s == "-" then return s end
    local src = p.src
    if not DebugView.POS_SOURCES[src] then src = p.last and "last" or "body" end
    return tr("Pos_" .. src, s)
end

-- Colonnes (clé, poids, largeur minimale) ; titre = traduction IGUI_LK_Debug_Col_<clé>.
DebugView.GROUP_COLUMNS = {
    { key = "gid", weight = 1, min = 60 }, { key = "gname", weight = 3, min = 120 },
    { key = "gtype", weight = 2, min = 90 }, { key = "leader", weight = 3, min = 130 },
    { key = "alive", weight = 2, min = 120 }, { key = "objective", weight = 2, min = 90 },
    { key = "alert", weight = 3, min = 130 }, { key = "home", weight = 2, min = 110 } }
DebugView.MEMBER_COLUMNS = {
    { key = "member", weight = 3, min = 150 }, { key = "npc", weight = 2, min = 110 },
    { key = "role", weight = 1, min = 70 }, { key = "duty", weight = 1, min = 70 },
    { key = "behaviour", weight = 3, min = 110 }, { key = "rule", weight = 4, min = 130 },
    { key = "target", weight = 3, min = 110 }, { key = "needs", weight = 1, min = 100 },
    { key = "health", weight = 1, min = 70 }, { key = "pos", weight = 3, min = 170 } }
DebugView.ACTIVITY_COLUMNS = {
    { key = "when", weight = 1, min = 100 }, { key = "who", weight = 1, min = 110 },
    { key = "kind", weight = 1, min = 80 }, { key = "text", weight = 8, min = 200 } }
DebugView.LOG_COLUMNS = {
    { key = "day", weight = 1, min = 60 }, { key = "lkind", weight = 1, min = 80 }, { key = "ltext", weight = 5, min = 150 } }

-- Cellules d'une ligne de groupe r (lignes de l'opération activity).
function DebugView.groupCells(r)
    local leader = "-"
    if r.leader ~= nil then
        leader = r.leaderName ~= nil and (tostring(r.leaderName) .. " (" .. tostring(r.leader) .. ")") or r.leader
    end
    local alert = {}
    if type(r.alert) == "table" then alert[#alert + 1] = tr("AlertCell", opt(r.alert.kind), opt(r.alert.level)) end
    if r.defense ~= nil then alert[#alert + 1] = tr("DefenseCell", tostring(r.defense)) end
    local objective = opt(r.objective)
    if type(r.gone) == "table" then objective = tr("Gone") end
    return { gid = opt(r.id), gname = opt(r.name), gtype = typeName(r.type), leader = leader,
        alive = tr("AliveCell", opt(r.alive), opt(r.total), opt(r.embodied or 0)), objective = objective,
        alert = #alert > 0 and table.concat(alert, ", ") or "-", home = xyz(r.home) }
end

-- Valeur de tri d'une ligne de groupe (nombres pour l'identifiant et les vivants).
function DebugView.groupSort(r, key)
    if key == "gid" then return numberIn(r.id) end
    if key == "alive" then return r.alive end
    if key == "alert" and type(r.alert) == "table" then return r.alert.level end
    return nil
end

-- Cellules d'un membre m (vue de LK_Activity.memberView, nom ajouté par LK_Admin.activity).
function DebugView.memberCells(m)
    local member = tostring(m.id)
    if m.name ~= nil then member = member .. " " .. tostring(m.name) end
    if m.leader then member = member .. " (" .. tr("Leader") .. ")" end
    local state
    if not m.alive then
        state = tr("Dead")
    elseif m.embodied then
        state = tr("Present")
    elseif m.away then
        state = tr("Away")
    else
        state = tr("Offscreen", opt(m.state))
    end
    local out = { member = member, npc = opt(m.npc) .. " - " .. state, role = opt(m.role), duty = opt(m.duty),
        behaviour = "-", rule = "-", target = "-", needs = "-", health = "-", pos = DebugView.posText(m.pos) }
    if not m.alive then return out end
    local b = { opt(m.b) }
    if type(m.combat) == "table" then b[#b + 1] = tr("Combat", opt(m.combat.k), opt(m.combat.u), opt(m.combat.phase)) end
    if type(m.routine) == "table" then b[#b + 1] = tr("Routine", opt(m.routine.key), opt(m.routine.phase)) end
    if m.gesture ~= nil then b[#b + 1] = tr("Gesture", m.gesture) end
    out.behaviour = table.concat(b, ", ")
    if m.rule ~= nil then out.rule = tostring(m.rule) .. ": " .. opt(m.why) end
    if m.key ~= nil then out.target = tostring(m.key) end
    if m.untilMin ~= nil then out.target = out.target .. " " .. tr("Until", DebugView.when(m.untilMin)) end
    local n = m.needs
    if type(n) == "table" then
        out.needs = opt(n.hunger) .. "/" .. opt(n.thirst) .. "/" .. opt(n.fatigue) .. "/" .. opt(n.fear)
    end
    if m.hp ~= nil then out.health = tostring(m.hp) .. " %" end
    if (m.wound or 0) > 0 then out.health = out.health .. " " .. tr("Wound", m.wound) end
    return out
end

function DebugView.memberSort(m, key)
    if key == "member" then return numberIn(m.id) end
    if key == "npc" then return numberIn(m.npc) end
    if key == "health" then return m.hp end
    return nil
end

-- Cellules d'une ligne du journal d'activité e.
function DebugView.entryCells(e)
    local who = e.mid or ""
    if e.npc ~= nil then who = who .. (who ~= "" and " " or "") .. e.npc end
    local kind = getTextOrNull ~= nil and getTextOrNull("IGUI_LK_Debug_Kind_" .. tostring(e.k)) or nil
    return { when = DebugView.when(e.m), who = who ~= "" and who or "-", kind = kind or tostring(e.k),
        text = tostring(e.t) }
end

function DebugView.entrySort(e, key)
    if key == "when" then return e.s end
    return nil
end

-- Cellules d'une entrée du journal sauvegardé du groupe.
function DebugView.logCells(e)
    return { day = tr("Day", opt(e.day)), lkind = tostring(e.kind), ltext = tostring(e.text) }
end

function DebugView.logSort(e, key)
    if key == "day" then return e.day end
    return nil
end

-- En-tête du groupe affiché (ligne au-dessus des journaux).
function DebugView.headerText(d)
    return tr("Header", d.id, tostring(d.name), typeName(d.type), opt(d.objective), opt(d.task),
        DebugView.when(d.minute))
end

-- Liste inversée (plus récente d'abord).
local function newestFirst(list)
    local out = {}
    for i = #list, 1, -1 do out[#out + 1] = list[i] end
    return out
end
DebugView.newestFirst = newestFirst

-- Membre choisi (vue) du groupe affiché, ou nil.
function DebugView.chosenMember()
    local st = DebugView.state
    if st.data == nil or st.member == nil then return nil end
    for _, m in ipairs(st.data.members or {}) do
        if m.id == st.member then return m end
    end
    return nil
end

-- Ouvre la fiche (LK13-T13) du membre mid du groupe affiché (membre choisi par défaut). Rend la fenêtre, ou nil.
function DebugView.openSheet(mid)
    local st = DebugView.state
    if mid ~= nil then st.member = mid end
    local m = DebugView.chosenMember()
    local S = LivingKnox.NpcSheet
    if m == nil or m.npc == nil or S == nil or S.open == nil then return nil end
    return S.open(m.npc)
end

-- Téléportation près du membre choisi (LK13-T15, requête npcGoto par la fiche : LivingKnox.NpcSheet.teleport). Rend
-- le numéro de requête, ou nil.
function DebugView.teleport(mid)
    local st = DebugView.state
    if mid ~= nil then st.member = mid end
    local m = DebugView.chosenMember()
    local S = LivingKnox.NpcSheet
    if m == nil or m.npc == nil or not m.alive or S == nil or S.teleport == nil then return nil end
    return S.teleport(m.npc)
end

-- Ligne (liste des groupes) du groupe gid, ou nil.
function DebugView.groupRow(gid)
    for _, r in ipairs(DebugView.state.groups or {}) do
        if type(r) == "table" and r.id == gid then return r end
    end
    return nil
end

-- Téléportation au foyer du groupe gid (groupe choisi par défaut ; LK13-T16, requête homeGoto par la fiche :
-- LivingKnox.NpcSheet.teleportHome). Rend le numéro de requête, ou nil (aucun groupe, foyer inconnu).
function DebugView.teleportHome(gid)
    gid = gid or DebugView.state.selected
    local r = DebugView.groupRow(gid)
    local S = LivingKnox.NpcSheet
    if r == nil or type(r.home) ~= "table" or S == nil or S.teleportHome == nil then return nil end
    return S.teleportHome(gid)
end

-- Message d'une action faite ailleurs (fiche : téléportation demandée depuis ce panneau).
function DebugView.notify(text)
    DebugView.state.status = text
    DebugView.redraw()
end

-- Fenêtre ------------------------------------------------------------------------------------------------------------

function DebugView.redraw()
    local w = DebugView.state.window
    if w ~= nil and w.refreshView ~= nil then w:refreshView() end
end

if ISCollapsableWindow ~= nil then
    local Table = LivingKnox.Table
    local Window = ISCollapsableWindow:derive("LKDebugViewWindow")
    DebugView.Window = Window

    local FONT = getTextManager():getFontHeight(UIFont.Small)
    local ROW = FONT + 6
    local BTN = FONT + 8
    local PAD = 10
    local GROUP_ROWS = 6
    local MEMBER_ROWS = 7
    local W_MAX, H_MAX = 1760, 980

    local function titled(columns)
        for _, c in ipairs(columns) do c.title = tr("Col_" .. c.key) end
        return columns
    end

    local function copyColumns(list)
        local out = {}
        for i, c in ipairs(list) do out[i] = { key = c.key, weight = c.weight, min = c.min } end
        return titled(out)
    end

    local function button(win, x, y, title, fn)
        local bw = getTextManager():MeasureStringX(UIFont.Small, title) + 20
        local b = ISButton:new(x, y, bw, BTN, title, win, fn)
        b:initialise()
        b.font = UIFont.Small
        win:addChild(b)
        return b
    end

    function Window:createChildren()
        ISCollapsableWindow.createChildren(self)
        local w = self.width - 2 * PAD
        local y = self:titleBarHeight() + PAD
        local gh = ROW * (GROUP_ROWS + 1)
        self.groups = Table.new(self, PAD, y, w, gh, copyColumns(DebugView.GROUP_COLUMNS), {
            cells = DebugView.groupCells, sortValue = DebugView.groupSort,
            onSelect = function(r) if type(r) == "table" and type(r.id) == "string" then DebugView.select(r.id) end end })
        y = y + gh + PAD
        local mh = ROW * (MEMBER_ROWS + 1)
        self.members = Table.new(self, PAD, y, w, mh, copyColumns(DebugView.MEMBER_COLUMNS), {
            cells = DebugView.memberCells, sortValue = DebugView.memberSort,
            onSelect = function(m)
                if type(m) == "table" and type(m.id) == "string" then
                    DebugView.state.member = m.id
                    DebugView.redraw()
                end
            end,
            onDouble = function(m) if type(m) == "table" then DebugView.openSheet(m.id) end end })
        y = y + mh + PAD
        self.sheetBtn = button(self, PAD, y, tr("Sheet"), function() LivingKnox.DebugView.openSheet() end)
        self.gotoBtn = button(self, self.sheetBtn:getRight() + PAD, y, tr("Teleport"),
            function() LivingKnox.DebugView.teleport() end)
        self.homeBtn = button(self, self.gotoBtn:getRight() + PAD, y, tr("TeleportHome"),
            function() LivingKnox.DebugView.teleportHome() end)
        self.adminBtn = button(self, self.homeBtn:getRight() + 2 * PAD, y, tr("Admin"),
            function() LivingKnox.DebugView.openAdmin() end)
        self.statusX, self.statusY = self.adminBtn:getRight() + 2 * PAD, y + math.floor((BTN - FONT) / 2)
        y = y + BTN + PAD
        self.headerY = y
        y = y + FONT + 6
        local bottom = self.height - PAD
        local aw = math.floor(w * 0.64)
        self.activity = Table.new(self, PAD, y, aw, bottom - y, copyColumns(DebugView.ACTIVITY_COLUMNS), {
            cells = DebugView.entryCells, sortValue = DebugView.entrySort })
        self.log = Table.new(self, PAD + aw + PAD, y, w - aw - PAD, bottom - y, copyColumns(DebugView.LOG_COLUMNS), {
            cells = DebugView.logCells, sortValue = DebugView.logSort })
        self:refreshView()
    end

    function Window:refreshView()
        if self.groups == nil then return end
        local st = DebugView.state
        local function id(r) return r.id end
        self.groups:setRows(st.groups or {}, id, st.selected)
        local d = st.data
        local shown = d ~= nil and d.id == st.selected
        self.members:setRows(shown and d.members or {}, id, st.member)
        self.activity:setRows(shown and newestFirst(st.entries) or {}, function(e) return e.s end, nil)
        self.log:setRows(shown and newestFirst(d.log or {}) or {}, nil, nil)
        local m = DebugView.chosenMember()
        local ok = m ~= nil and m.npc ~= nil and m.alive == true
        self.sheetBtn:setEnable(ok)
        self.gotoBtn:setEnable(ok)
        local r = DebugView.groupRow(st.selected)
        self.homeBtn:setEnable(r ~= nil and type(r.home) == "table")
    end

    function Window:update()
        ISCollapsableWindow.update(self)
        DebugView.poll(now())
    end

    function Window:render()
        ISCollapsableWindow.render(self)
        local st = DebugView.state
        local line = st.status
        if line == nil and st.pending ~= nil and #(st.groups or {}) == 0 then line = tr("Waiting") end
        if line == nil and st.hour ~= nil then line = tr("Refresh", math.floor(DebugView.REFRESH_MS / 1000)) end
        if line ~= nil then
            self:drawText(tostring(line), self.statusX, self.statusY, 1, 1, 0.8, 1, UIFont.Small)
        end
        local d = st.data
        local head = tr("Select")
        if d ~= nil and d.id == st.selected then
            head = DebugView.headerText(d) .. "   " .. tr("Activity", #st.entries)
        end
        self:drawText(head, PAD, self.headerY, 1, 1, 1, 1, UIFont.Small)
    end

    function Window:close()
        ISCollapsableWindow.close(self)
        self:removeFromUIManager()
        DebugView.closed(self)
    end

    -- Ouvre (ou ramène devant) le panneau, sur le groupe gid s'il est donné. Rend la fenêtre, ou nil sans droit.
    -- Taille fixée à l'ouverture d'après l'écran (au plus W_MAX x H_MAX) : non redimensionnable (LK_Table.lua).
    function DebugView.open(gid)
        if not DebugView.canUse() then
            log().warn("npc debug view: not allowed for this player")
            return nil
        end
        local st = DebugView.state
        if st.window == nil then
            local core = getCore()
            local w = math.min(W_MAX, core:getScreenWidth() - 40)
            local h = math.min(H_MAX, core:getScreenHeight() - 60)
            local win = Window:new(20, 30, w, h)
            win.title = tr("Title")
            win.backgroundColor = { r = 0.08, g = 0.08, b = 0.08, a = 1 }
            win:setResizable(false)
            win:initialise()
            win:addToUIManager()
            st.window = win
        else
            st.window:setVisible(true)
            st.window:bringToTop()
        end
        st.status = nil
        if gid ~= nil then
            DebugView.select(gid)
        else
            st.lastMs = nil
            DebugView.poll(now())
        end
        return st.window
    end
end

-- Fenêtre d'administration des groupes (LK13-T01), sur le groupe choisi ici. Rend la fenêtre, ou nil.
function DebugView.openAdmin()
    local V = LivingKnox.AdminView
    if V == nil or V.open == nil or not DebugView.canUse() then return nil end
    local win = V.open()
    local gid = DebugView.state.selected
    if win ~= nil and gid ~= nil and V.select ~= nil then V.select(gid) end
    return win
end

-- Panneau fermé : plus aucune requête (DebugView.poll ne part qu'avec un panneau ouvert) ; réponse en route ignorée.
function DebugView.closed(win)
    local st = DebugView.state
    if win ~= nil and st.window ~= win then return end
    st.window, st.pending, st.lastMs, st.status = nil, nil, nil, nil
end

-- Bouton du panneau debug vanilla ------------------------------------------------------------------------------------

if ISDebugMenu ~= nil then
    DebugView.baseSetupButtons = DebugView.baseSetupButtons or ISDebugMenu.setupButtons
    function ISDebugMenu:setupButtons(...)
        if LivingKnox.DebugView.canUse() then   -- avant l'original : trié avec ses boutons, avant « Fermer »
            self:addButtonInfo(tr("Button"), function() LivingKnox.DebugView.open() end, "MAIN")
            if LivingKnox.AdminView ~= nil then   -- LK13-T01 : fenêtre d'administration (solo en mode debug compris)
                self:addButtonInfo(getText("IGUI_LK_Admin_DebugButton"), function() LivingKnox.DebugView.openAdmin() end,
                    "MAIN")
            end
        end
        return DebugView.baseSetupButtons(self, ...)
    end
end

if isClient() then   -- solo : réponses rendues directement par LivingKnox.Admin.request
    local function onServerCommand(module, command, args)
        LivingKnox.DebugView.onServerCommand(module, command, args)
    end
    LivingKnox.subscribe("OnServerCommand", "DebugView.onServerCommand", onServerCommand)
end

return DebugView
