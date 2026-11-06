-- Living Knox : fiche d'un PNJ par clic droit (LK13-T13). Fiche : docs/annexes/conception/administration.md, section
-- « Fiche d'un PNJ ». M = media/lua vanilla 42.21.
--
-- Option « Détails (Living Knox) » du menu contextuel du monde (OnFillWorldObjectContextMenu,
-- M/client/ISUI/ISWorldObjectContextMenu.lua:213) sur un corps de PNJ connu ici (LivingKnox.Anim.knownBodies : corps
-- relié en solo, roster de la garde des zombies sur un client MP) à CLICK case au plus d'une case cliquée, au niveau
-- du joueur. L'option n'apparaît que si Sheet.canUse() : solo = mode debug (isDebugEnabled), client MP = rôle avec la
-- capacité de l'outil d'administration (getRole():hasCapability, affichage seulement). L'autorité revérifie le droit
-- à CHAQUE requête et CHAQUE réglage (LK_Admin.isAllowed) : la garde d'ici ne décide rien.
-- Fenêtre : tout l'état que l'autorité répond (op "npc" de LK_Admin), relu toutes les REFRESH_MS tant qu'elle est
-- ouverte (Sheet.poll, appelé par l'update de la fenêtre : rien n'est envoyé fenêtre fermée) ; une ligne de réglage par
-- champ de FIELDS (op "npcSet", valeur bornée et notée au journal du groupe par l'autorité).
-- LK13-T15 : fiche en sections étiquetées (identité, besoins, santé, comportement, perception, équipement ; nombres
-- arrondis, santé en %), champs de réglage préremplis avec la valeur actuelle (tant que l'administrateur n'y a pas
-- touché), actions : rôle (liste fermée des rôles du type, op "npcRole"), prénom et nom (op "npcName", texte nettoyé
-- par LivingKnox.Admin.cleanNamePart et revérifié par l'autorité), téléportation près du PNJ (op "npcGoto" : solo,
-- déplacé par l'autorité ; client MP, « /teleportto x,y,z » envoyé ici avec la destination choisie par l'autorité,
-- capacité TeleportToCoordinates revérifiée par le serveur, base multiplayer.md).
-- LK13-T16 : position affichée avec sa source (corps, dernière position connue, foyer du groupe : Sheet.posText) ;
-- téléportation vers un PNJ hors écran menée par l'autorité à sa dernière position connue, sinon au foyer de son groupe ;
-- téléportation au foyer d'un groupe (op "homeGoto", Sheet.teleportHome, bouton du panneau de debug).
-- Transport : celui de LK_AdminView (MP : "adminRequest" -> "adminReply" ; solo : LivingKnox.Admin.request appelé
-- directement, réponse rendue pendant l'appel, attente posée avant).
if isServer() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Anim"
require "LivingKnox/LK_Table"

local Sheet = LivingKnox.NpcSheet or {}
LivingKnox.NpcSheet = Sheet

-- Copies des constantes de LK_Admin.lua (comparées par tests/test_lk_npcsheet.py).
Sheet.MODULE = "LivingKnox"
Sheet.CMD_REQUEST = "adminRequest"
Sheet.CMD_REPLY = "adminReply"
Sheet.CAPABILITY = "PopmanManage"
Sheet.FIELDS = { "hunger", "thirst", "fatigue", "fear", "health", "bleed", "wound" }
Sheet.OPS = { npc = true, npcSet = true, npcRole = true, npcName = true, npcGoto = true, homeGoto = true }
Sheet.GOTO_OPS = { npcGoto = true, homeGoto = true }   -- téléportations (LK13-T15, foyer d'un groupe : LK13-T16)
Sheet.TELEPORT_CAPABILITY = "TeleportToCoordinates"   -- capacité exigée par /teleportto (TeleportToCommand.java:24)

Sheet.REFRESH_MS = 2000   -- relecture de la fiche ouverte (décision du 2026-10-12)
Sheet.CLICK = 1.5         -- distance au plus entre le corps et une case cliquée

Sheet.state = Sheet.state or { n = 0, pending = {}, npc = nil, data = nil, status = nil, window = nil, lastMs = nil }
Sheet.stats = Sheet.stats or { offered = 0, sent = 0, received = 0, stale = 0, refused = 0, polls = 0, teleports = 0 }

local function log() return LivingKnox.Log end

local function tr(key, ...)
    return getText("IGUI_LK_Sheet_" .. key, ...)
end

local function count(name)
    Sheet.stats[name] = (Sheet.stats[name] or 0) + 1
end

local function localPlayer()
    if getSpecificPlayer ~= nil then return getSpecificPlayer(0) end
    return nil
end

local function now() return getTimestampMs() end

-- Vrai si le joueur peut voir l'option et ouvrir la fiche (affichage seulement : l'autorité décide).
function Sheet.canUse(player)
    if not isClient() then return isDebugEnabled ~= nil and isDebugEnabled() == true end
    player = player or localPlayer()
    if player == nil or Capability == nil or Capability[Sheet.CAPABILITY] == nil then return false end
    local role = player:getRole()
    return role ~= nil and role:hasCapability(Capability[Sheet.CAPABILITY]) == true
end

local function dist2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

-- Identifiant du PNJ dont le corps est le plus près d'une case cliquée (CLICK cases au plus, niveau du joueur), ou nil.
function Sheet.bodyNear(player, worldObjects)
    local A = LivingKnox.Anim
    if A == nil or A.knownBodies == nil or type(worldObjects) ~= "table" then return nil end
    local pz = math.floor(player:getZ())
    local best, bestD
    for _, o in ipairs(worldObjects) do
        local sq = o ~= nil and o.getSquare ~= nil and o:getSquare() or nil
        if sq ~= nil and sq:getZ() == pz then
            for id, z in pairs(A.knownBodies()) do
                if math.floor(z:getZ()) == pz then
                    local d = dist2(z:getX(), z:getY(), sq:getX() + 0.5, sq:getY() + 0.5)
                    if d <= Sheet.CLICK * Sheet.CLICK and (bestD == nil or d < bestD) then best, bestD = id, d end
                end
            end
        end
    end
    return best
end

-- Requêtes -----------------------------------------------------------------------------------------------------------

-- Envoie une requête op ("npc" ou "npcSet") avec les champs fields. Rend le numéro de requête, ou nil.
function Sheet.send(op, fields)
    local st = Sheet.state
    local player = localPlayer()
    if player == nil or not Sheet.OPS[op] then return nil end
    st.n = st.n + 1
    local args = { op = op, n = st.n }
    for k, v in pairs(fields or {}) do args[k] = v end
    st.pending[op] = st.n            -- posé AVANT l'envoi : en solo, la réponse arrive pendant l'appel
    count("sent")
    if isClient() then
        sendClientCommand(player, Sheet.MODULE, Sheet.CMD_REQUEST, args)
    else
        local A = LivingKnox.Admin
        if A == nil or A.request == nil then
            st.pending[op] = nil
            st.status = tr("NotLoaded")
            Sheet.redraw()
            return nil
        end
        Sheet.receive(A.request(player, args))
    end
    return args.n
end

function Sheet.refresh()
    local st = Sheet.state
    if st.npc == nil then return nil end
    st.lastMs = now()
    return Sheet.send("npc", { npc = st.npc })
end

-- Relecture périodique de la fiche ouverte (update de la fenêtre) : au plus une requête par REFRESH_MS, aucune si une
-- relecture attend encore sa réponse, aucune fiche fermée. Rend vrai si une requête est partie.
function Sheet.poll(ms)
    local st = Sheet.state
    if st.window == nil or st.npc == nil or st.pending.npc ~= nil then return false end
    ms = ms or now()
    if st.lastMs ~= nil and ms - st.lastMs < Sheet.REFRESH_MS then return false end
    count("polls")
    return Sheet.refresh() ~= nil
end

-- Réglage d'un champ (texte saisi converti par l'appelant). Rend le numéro de requête, ou nil.
function Sheet.set(field, value)
    local st = Sheet.state
    if st.npc == nil or type(value) ~= "number" then return nil end
    return Sheet.send("npcSet", { npc = st.npc, field = field, value = value })
end

-- Changement de rôle du PNJ de la fiche (un rôle de la liste rendue par l'autorité). Rend le numéro de requête, ou nil.
function Sheet.setRole(role)
    local st = Sheet.state
    if st.npc == nil or type(role) ~= "string" then return nil end
    return Sheet.send("npcRole", { npc = st.npc, role = role })
end

-- Prénom et nom du PNJ de la fiche (textes saisis : contrôlés ici pour le message, revérifiés par l'autorité). Rend
-- le numéro de requête, ou nil.
function Sheet.rename(first, last)
    local st = Sheet.state
    if st.npc == nil then return nil end
    local A = LivingKnox.Admin
    if A ~= nil and A.cleanNamePart ~= nil and (A.cleanNamePart(first) == nil or A.cleanNamePart(last) == nil) then
        st.status = tr("BadName")
        Sheet.redraw()
        return nil
    end
    return Sheet.send("npcName", { npc = st.npc, first = first, last = last })
end

-- Vrai si le joueur peut se faire téléporter par /teleportto (client MP : capacité de son rôle ; solo : toujours).
function Sheet.canTeleport(player)
    if not isClient() then return true end
    player = player or localPlayer()
    local cap = Capability ~= nil and Capability[Sheet.TELEPORT_CAPABILITY] or nil
    local role = player ~= nil and player:getRole() or nil
    return cap ~= nil and role ~= nil and role:hasCapability(cap) == true
end

-- Message d'état de la fiche, recopié dans le panneau de debug (action lancée depuis lui).
function Sheet.notify(text)
    Sheet.state.status = text
    local V = LivingKnox.DebugView
    if V ~= nil and V.notify ~= nil and V.state ~= nil and V.state.window ~= nil then V.notify(text) end
end

-- Téléportation près du PNJ npc (fiche par défaut). Rend le numéro de requête, ou nil.
function Sheet.teleport(npc)
    npc = npc or Sheet.state.npc
    if type(npc) ~= "string" then return nil end
    if not Sheet.canTeleport() then
        Sheet.notify(tr("GotoNoRight"))
        Sheet.redraw()
        return nil
    end
    return Sheet.send("npcGoto", { npc = npc })
end

-- Téléportation au foyer du groupe gid (LK13-T16, bouton du panneau de debug). Rend le numéro de requête, ou nil.
function Sheet.teleportHome(gid)
    if type(gid) ~= "string" then return nil end
    if not Sheet.canTeleport() then
        Sheet.notify(tr("GotoNoRight"))
        Sheet.redraw()
        return nil
    end
    return Sheet.send("homeGoto", { gid = gid })
end

-- Destination rendue par l'autorité : solo, joueur déjà déplacé (moved) ; client MP, « /teleportto x,y,z »
-- (ISAdminMessage.lua:81-85). Message selon la source (dest.src : corps, dernière position connue, foyer du groupe).
-- Rend le message d'état.
function Sheet.goTo(dest, moved)
    if type(dest) ~= "table" or type(dest.x) ~= "number" or type(dest.y) ~= "number" or type(dest.z) ~= "number" then
        return tr("Error", "bad destination")
    end
    local x, y, z = math.floor(dest.x), math.floor(dest.y), math.floor(dest.z)
    local where = x .. "," .. y .. "," .. z
    if not moved then
        if not isClient() then return tr("Error", "not moved") end
        SendCommandToServer("/teleportto " .. where)
    end
    count("teleports")
    if dest.src == "home" then return tr("GotoHome", where) end
    if dest.last then return tr("GotoLast", where) end
    return tr("GotoDone", where)
end

-- Réponse de l'autorité. Rend vrai si elle a été prise en compte.
function Sheet.receive(reply)
    if type(reply) ~= "table" or not Sheet.OPS[reply.op] then return false end
    local st = Sheet.state
    if st.pending[reply.op] ~= reply.n then
        count("stale")
        return false
    end
    st.pending[reply.op] = nil
    count("received")
    if not reply.ok then
        count("refused")
        local text = reply.err == "denied" and tr("Denied") or tr("Error", tostring(reply.err))
        if Sheet.GOTO_OPS[reply.op] then Sheet.notify(text) else st.status = text end
    elseif Sheet.GOTO_OPS[reply.op] then
        Sheet.notify(Sheet.goTo(reply.dest, reply.moved == true))
    elseif type(reply.npc) == "table" and reply.npc.id == st.npc then
        st.data = reply.npc
        if reply.op ~= "npc" then
            st.status = tr("SetDone", Sheet.fieldName(reply.field), tostring(reply.old), tostring(reply.value))
            st.refill = true   -- champs repris sur les valeurs retenues
        end
    end
    Sheet.redraw()
    return true
end

function Sheet.onServerCommand(module, command, args)
    if module ~= Sheet.MODULE or command ~= Sheet.CMD_REPLY then return end
    Sheet.receive(args)
end

-- Textes -------------------------------------------------------------------------------------------------------------

function Sheet.fieldName(field)
    return tr("Field_" .. tostring(field))
end

local function opt(v)
    if v == nil then return "-" end
    return tostring(v)
end

-- Nombre arrondi au dixième (texte), "-" sans nombre.
local function num(v)
    if type(v) ~= "number" or v ~= v then return opt(v) end
    return tostring(math.floor(v * 10 + 0.5) / 10)
end
Sheet.num = num

local function xyz(p)
    if type(p) ~= "table" then return "-" end
    return math.floor(p.x) .. "," .. math.floor(p.y) .. "," .. math.floor(p.z)
end

-- Position et sa source (LK13-T16 : src "body", "last" ou "home" de LK_Admin.positionOf ; ancienne vue sans src :
-- last = dernière position connue). "-" sans position.
Sheet.POS_SOURCES = { body = true, last = true, home = true }
function Sheet.posText(p)
    if type(p) ~= "table" then return "-" end
    local src = p.src
    if not Sheet.POS_SOURCES[src] then src = p.last and "last" or "body" end
    return tr("Pos_" .. src, xyz(p))
end

local function when(minute)
    if type(minute) ~= "number" then return "-" end
    local day = math.floor(minute / 1440) + 1
    local hod = (math.floor(minute / 60) + 7) % 24
    return tr("When", day, string.format("%02d:%02d", hod, minute % 60))
end

-- Sections étiquetées de la fiche d (réponse npc) : { { title, rows = { { libellé, valeur } } } } (textes traduits,
-- nombres arrondis, santé en %). Les trois premières à gauche, les autres à droite (Sheet.LEFT).
Sheet.LEFT = 3
function Sheet.sections(d)
    local typeName = getTextOrNull ~= nil and getTextOrNull("IGUI_LK_GroupType_" .. tostring(d.type)) or nil
    local pos = Sheet.posText(d.pos)
    local identity = { title = tr("Sec_Identity"), rows = {
        { tr("L_Name"), opt(d.name) },
        { tr("L_Npc"), opt(d.id) .. " (" .. opt(d.mid) .. ")" },
        { tr("L_Group"), opt(d.group) .. " (" .. opt(d.gid) .. ", " .. (typeName or opt(d.type)) .. ")" },
        { tr("L_Role"), opt(d.role) .. " / " .. opt(d.profile) },
        { tr("L_Leader"), d.leader and tr("Leader") or opt(d.leaderId) },
        { tr("L_State"), opt(d.state) .. ", " .. (d.embodied and tr("Present") or tr("Absent")) },
        { tr("L_Position"), pos },
        { tr("L_Home"), xyz(d.home) } } }
    local n, e = d.needs or {}, d.envy or {}
    local needs = { title = tr("Sec_Needs"), rows = {
        { Sheet.fieldName("hunger"), tr("NeedCell", num(n.hunger), num(e.hunger)) },
        { Sheet.fieldName("thirst"), tr("NeedCell", num(n.thirst), num(e.thirst)) },
        { Sheet.fieldName("fatigue"), tr("NeedCell", num(n.fatigue), num(e.fatigue)) },
        { Sheet.fieldName("fear"), tr("NeedCell", num(n.fear), num(e.fear)) } } }
    local h = type(d.health) == "table" and d.health or {}
    local last = type(h.last) == "table" and tr("LastWound", opt(h.last.p), num(h.last.d)) or ""
    local health = { title = tr("Sec_Health"), rows = {
        { tr("L_Health"), h.pct ~= nil and (num(h.pct) .. " %") or "-" },
        { tr("L_Bleed"), h.bleedPct ~= nil and (num(h.bleedPct) .. " % / h") or "-" },
        { tr("L_Wounds"), opt(h.wounds) .. (last ~= "" and (", " .. last) or "") },
        { tr("L_Offscreen"), num(d.wound) .. " / " .. num(d.woundMax) } } }
    local de = type(d.decision) == "table" and d.decision or nil
    local rows = {}
    if de ~= nil then
        rows[#rows + 1] = { tr("L_Behaviour"), opt(de.b) }
        rows[#rows + 1] = { tr("L_Rule"), opt(de.rule) .. ": " .. opt(de.why) }
        rows[#rows + 1] = { tr("L_Until"), when(de.untilMin) .. " (" .. tr("Now", when(d.minute)) .. ")" }
    else
        rows[#rows + 1] = { tr("L_Behaviour"), tr("NoDecision") }
    end
    rows[#rows + 1] = { tr("L_Task"), tr("TaskCell", opt(d.objective), opt(d.duty), opt(d.task)) }
    if type(d.routine) == "table" then
        rows[#rows + 1] = { tr("L_Routine"), opt(d.routine.key) .. " (" .. opt(d.routine.phase) .. ")" }
    end
    if type(d.combat) == "table" then
        rows[#rows + 1] = { tr("L_Combat"), opt(d.combat.k) .. " -> " .. opt(d.combat.u) .. " (" .. opt(d.combat.phase) .. ")" }
    end
    rows[#rows + 1] = { tr("L_Gesture"), opt(d.gesture) .. " / " .. opt(d.vigilance) }
    local behaviour = { title = tr("Sec_Behaviour"), rows = rows }
    local s = d.senses
    local perception
    if type(s) == "table" then
        local who = {}
        for _, p in ipairs(s.players or {}) do
            local how = (p.s and (" (" .. tr("Seen") .. ")") or "") .. (p.h and (" (" .. tr("Heard") .. ")") or "")
            who[#who + 1] = tostring(p.u) .. how
        end
        perception = { title = tr("Sec_Perception"), rows = {
            { tr("L_Senses"), tr("SensesCell", opt(s.seen), opt(s.heard), opt(s.zombies))
                .. (s.stale and (" " .. tr("Stale")) or "") },
            { tr("L_Players"), #who > 0 and table.concat(who, ", ") or "-" } } }
    else
        perception = { title = tr("Sec_Perception"), rows = { { tr("L_Senses"), tr("NoSenses") } } }
    end
    local w = d.weapon
    local weapon = tr("Unarmed")
    if type(w) == "table" then
        weapon = opt(w.t)
        if w.max ~= nil then weapon = tr("Firearm", opt(w.t), opt(w.loaded), opt(w.max), opt(w.loose), opt(w.inMags)) end
    end
    local equipment = { title = tr("Sec_Equipment"), rows = { { tr("L_Weapon"), weapon } } }
    return { identity, needs, health, behaviour, perception, equipment }
end

-- Valeur actuelle d'un champ de réglage (préremplissage), texte ou "".
function Sheet.fieldValue(d, field)
    if type(d) ~= "table" then return "" end
    local v
    if field == "health" then
        v = type(d.health) == "table" and d.health.pct or nil
    elseif field == "bleed" then
        v = type(d.health) == "table" and d.health.bleedPct or nil
    elseif field == "wound" then
        v = d.wound
    else
        v = type(d.needs) == "table" and d.needs[field] or nil
    end
    if type(v) ~= "number" then return "" end
    return num(v)
end

-- Fenêtre ------------------------------------------------------------------------------------------------------------

function Sheet.redraw()
    local w = Sheet.state.window
    if w ~= nil and w.refreshView ~= nil then w:refreshView() end
end

if ISCollapsableWindow ~= nil then
    local Window = ISCollapsableWindow:derive("LKNpcSheetWindow")
    Sheet.Window = Window

    local FONT = getTextManager():getFontHeight(UIFont.Small)
    local LINE = FONT + 4
    local ROW = FONT + 8
    local PAD = 10
    local LABEL_W = 150
    local SECTION_ROWS = 20   -- lignes réservées par colonne de sections (titres compris)

    local function measure(s) return getTextManager():MeasureStringX(UIFont.Small, s) end

    local function button(win, x, y, title, fn)
        local b = ISButton:new(x, y, measure(title) + 20, ROW, title, win, fn)
        b:initialise()
        b.font = UIFont.Small
        win:addChild(b)
        return b
    end

    local function entry(win, x, y, w, maxLen)
        local e = ISTextEntryBox:new("", x, y, w, ROW)
        e.font = UIFont.Small
        e:initialise()
        win:addChild(e)       -- réglages Java seulement après addChild (base ui-windows.md)
        e:setMaxTextLength(maxLen)
        return e
    end

    function Window:createChildren()
        ISCollapsableWindow.createChildren(self)
        local w = self.width - 2 * PAD
        self.sectionsY = self:titleBarHeight() + PAD
        local line, cols = self.lineH or LINE, self.cols or 2
        local y = self.sectionsY + SECTION_ROWS * line + PAD
        self.setY = y
        self.rows = {}
        local setTitle = tr("Set")
        local bw = measure(setTitle) + 20
        for i, field in ipairs(Sheet.FIELDS) do
            local col = (i - 1) % cols
            local ry = y + math.floor((i - 1) / cols) * (ROW + 4)
            local x = PAD + col * math.floor(w / cols)
            local e = ISTextEntryBox:new("", x + LABEL_W, ry, 70, ROW)
            e.font = UIFont.Small
            e:initialise()
            self:addChild(e)
            e:setOnlyNumbers(true)
            e:setMaxTextLength(5)
            local b = ISButton:new(e:getRight() + 4, ry, bw, ROW, setTitle, self, function(win) win:onSet(field) end)
            b:initialise()
            b.font = UIFont.Small
            self:addChild(b)
            self.rows[field] = { entry = e, button = b, x = x, y = ry, shown = nil }
        end
        y = y + math.ceil(#Sheet.FIELDS / cols) * (ROW + 4) + PAD
        -- Actions (LK13-T15) : rôle, prénom et nom, téléportation.
        self.actionY = y
        self.roleCombo = ISComboBox:new(PAD + LABEL_W, y, 160, ROW, self, nil)
        self.roleCombo:initialise()
        self:addChild(self.roleCombo)
        self.roleBtn = button(self, self.roleCombo:getRight() + 4, y, tr("RoleSet"), function(win) win:onRole() end)
        self.gotoBtn = button(self, self.roleBtn:getRight() + 3 * PAD, y, tr("Teleport"),
            function() LivingKnox.NpcSheet.teleport() end)
        y = y + ROW + 4
        self.nameY = y
        local A = LivingKnox.Admin
        local maxLen = A ~= nil and A.NAME_PART_MAX or 24
        self.firstEntry = entry(self, PAD + LABEL_W, y, 160, maxLen)
        self.lastEntry = entry(self, self.firstEntry:getRight() + 4, y, 160, maxLen)
        self.nameBtn = button(self, self.lastEntry:getRight() + 4, y, tr("Rename"), function(win) win:onRename() end)
        y = y + ROW + PAD
        self.statusY = y
        self:refreshView()
    end

    function Window:unfocusEntries()
        local list = { self.firstEntry, self.lastEntry }
        for _, r in pairs(self.rows or {}) do list[#list + 1] = r.entry end
        for _, e in ipairs(list) do
            if e ~= nil and e.isFocused ~= nil and e:isFocused() then e:unfocus() end
        end
    end

    function Window:onSet(field)
        self:unfocusEntries()
        local r = self.rows[field]
        local v = r and tonumber(r.entry:getText()) or nil
        if v == nil then
            Sheet.state.status = tr("BadValue")
            return self:refreshView()
        end
        Sheet.set(field, v)
    end

    function Window:onRole()
        self:unfocusEntries()
        local role = self.roleCombo:getOptionData(self.roleCombo.selected)
        if role ~= nil then Sheet.setRole(role) end
    end

    function Window:onRename()
        self:unfocusEntries()
        Sheet.rename(self.firstEntry:getText(), self.lastEntry:getText())
    end

    -- Champ prérempli avec la valeur actuelle, sauf s'il a le focus ou si l'administrateur a changé son texte.
    local function prefill(e, value, shown, force)
        local focused = e.isFocused ~= nil and e:isFocused()
        if focused then return shown end
        local text = e:getText()
        if force or text == "" or text == shown then
            if text ~= value then e:setText(value) end
            return value
        end
        return shown
    end

    function Window:refreshView()
        if self.rows == nil then return end
        local st = Sheet.state
        local d = st.data
        if d ~= nil and d.id ~= st.npc then d = nil end
        local force = st.refill == true or self.shownNpc ~= st.npc
        st.refill, self.shownNpc = nil, st.npc
        local alive = d ~= nil and d.alive == true
        for field, r in pairs(self.rows) do
            if d ~= nil then r.shown = prefill(r.entry, Sheet.fieldValue(d, field), r.shown, force) end
            local enable = alive
            if field == "health" or field == "bleed" then enable = enable and d.embodied == true end
            r.button:setEnable(enable)
        end
        if d ~= nil then
            self.firstShown = prefill(self.firstEntry, opt(d.firstName ~= nil and d.firstName or ""), self.firstShown, force)
            self.lastShown = prefill(self.lastEntry, opt(d.lastName ~= nil and d.lastName or ""), self.lastShown, force)
            local key = table.concat(d.roles or {}, ",") .. "|" .. tostring(d.role)
            if key ~= self.rolesKey then
                self.rolesKey = key
                self.roleCombo:clear()
                self.roleCombo.selected = 0
                for i, role in ipairs(d.roles or {}) do
                    self.roleCombo:addOptionWithData(role, role)
                    if role == d.role then self.roleCombo.selected = i end
                end
            end
        end
        self.roleBtn:setEnable(alive)
        self.nameBtn:setEnable(alive)
        self.gotoBtn:setEnable(alive)
    end

    function Window:update()
        ISCollapsableWindow.update(self)
        Sheet.poll(now())
    end

    local function drawSection(win, sec, x, y, w)
        win:drawText(sec.title, x, y, 1, 0.8, 0.4, 1, UIFont.Small)
        y = y + (win.lineH or LINE)
        for _, row in ipairs(sec.rows) do
            local label = LivingKnox.Table.clip(row[1], LABEL_W - 8, measure)
            win:drawText(label, x + 8, y, 0.7, 0.7, 0.7, 1, UIFont.Small)
            local value = LivingKnox.Table.clip(row[2], w - LABEL_W - 8, measure)
            win:drawText(value, x + LABEL_W, y, 1, 1, 1, 1, UIFont.Small)
            y = y + (win.lineH or LINE)
        end
        return y + 4
    end

    function Window:render()
        ISCollapsableWindow.render(self)
        local st = Sheet.state
        local d = st.data
        local half = math.floor((self.width - 2 * PAD) / 2)
        if d ~= nil and d.id == st.npc then
            local secs = Sheet.sections(d)
            local yl, yr = self.sectionsY, self.sectionsY
            for i, sec in ipairs(secs) do
                if i <= Sheet.LEFT then
                    yl = drawSection(self, sec, PAD, yl, half - PAD)
                else
                    yr = drawSection(self, sec, PAD + half, yr, half - PAD)
                end
            end
        end
        for _, field in ipairs(Sheet.FIELDS) do
            local r = self.rows and self.rows[field]
            if r ~= nil then   -- libellé coupé avant son champ (« Saignement par heure (0-100) » en français)
                local label = LivingKnox.Table.clip(Sheet.fieldName(field), LABEL_W - 8, measure)
                self:drawText(label, r.x, r.y + 4, 1, 1, 1, 1, UIFont.Small)
            end
        end
        if self.actionY ~= nil then
            self:drawText(tr("L_Role"), PAD, self.actionY + 4, 1, 1, 1, 1, UIFont.Small)
            self:drawText(tr("L_FirstLast"), PAD, self.nameY + 4, 1, 1, 1, 1, UIFont.Small)
        end
        local line = st.status
        if line == nil and st.pending.npc ~= nil and st.data == nil then line = tr("Waiting") end
        if line ~= nil then self:drawText(tostring(line), PAD, self.statusY, 1, 1, 0.8, 1, UIFont.Small) end
    end

    function Window:close()
        self:unfocusEntries()
        ISCollapsableWindow.close(self)
        self:removeFromUIManager()
        Sheet.closed(self)
    end

    -- Ouvre la fiche du PNJ npc (une seule fenêtre : elle passe au nouveau PNJ). Rend la fenêtre, ou nil sans droit.
    function Sheet.open(npc)
        if not Sheet.canUse() then
            log().warn("npc sheet: not allowed for this player")
            return nil
        end
        local st = Sheet.state
        if st.npc ~= npc then st.data = nil end
        st.npc, st.status, st.lastMs = npc, nil, nil
        if st.window == nil then
            local core = getCore()
            local w = math.min(1000, core:getScreenWidth() - 40)
            local function height(line, cols)
                return 30 + SECTION_ROWS * line + math.ceil(#Sheet.FIELDS / cols) * (ROW + 4) + 2 * (ROW + 4) + 5 * PAD
                    + FONT
            end
            -- Écran bas (1280 x 720 : fenêtre coupée, essai solo 2026-10-15) : lignes serrées, réglages sur 3 colonnes.
            local line, cols = LINE, 2
            if height(line, cols) > core:getScreenHeight() - 20 then line, cols = FONT + 2, 3 end
            local h = math.min(height(line, cols), core:getScreenHeight() - 20)
            -- Haut gardé à l'écran sur un petit écran (1280 x 720 : fenêtre coupée en bas à y = 60, essai solo 2026-10-15).
            local top = math.max(0, math.min(60, core:getScreenHeight() - h - 20))
            local win = Window:new(math.max(0, core:getScreenWidth() - w - 40), top, w, h)
            win.lineH, win.cols = line, cols
            win.backgroundColor = { r = 0.08, g = 0.08, b = 0.08, a = 1 }
            win:setResizable(false)
            win:initialise()
            win:addToUIManager()
            st.window = win
        else
            st.window:setVisible(true)
            st.window:bringToTop()
        end
        st.window.title = tr("Title", npc)
        st.window:refreshView()
        Sheet.refresh()
        return st.window
    end
end

-- Fenêtre fermée : plus aucune relecture (Sheet.poll ne part qu'avec une fenêtre ouverte).
function Sheet.closed(win)
    local st = Sheet.state
    if win ~= nil and st.window ~= win then return end
    st.window, st.npc, st.data, st.status, st.lastMs = nil, nil, nil, nil, nil
    st.pending = {}
end

-- Menu contextuel ----------------------------------------------------------------------------------------------------

function Sheet.onChoose(_, npc)
    if Sheet.open ~= nil then Sheet.open(npc) end
end

function Sheet.fill(playerNum, context, worldObjects, test)
    local player = getSpecificPlayer(playerNum)
    if player == nil or not Sheet.canUse(player) then return end
    local npc = Sheet.bodyNear(player, worldObjects)
    if npc == nil then return end
    if test then return ISWorldObjectContextMenu.setTest() end
    context:addOption(tr("Menu"), player, Sheet.onChoose, npc)
    count("offered")
end

if Events ~= nil then
    local function onFill(playerNum, context, worldObjects, test)
        return LivingKnox.NpcSheet.fill(playerNum, context, worldObjects, test)
    end
    LivingKnox.subscribe("OnFillWorldObjectContextMenu", "NpcSheet.fill", onFill)
end

if isClient() then   -- solo : réponses rendues directement par LivingKnox.Admin.request
    local function onServerCommand(module, command, args)
        LivingKnox.NpcSheet.onServerCommand(module, command, args)
    end
    LivingKnox.subscribe("OnServerCommand", "NpcSheet.onServerCommand", onServerCommand)
end

return Sheet
