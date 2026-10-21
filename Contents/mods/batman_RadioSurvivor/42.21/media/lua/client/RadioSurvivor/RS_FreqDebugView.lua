-- Radio Survivor : fenêtre de debug des fréquences de la partie (E05-T14). Doc :
-- docs/specifications-techniques/persona-format.md, section
-- « Panneau de debug des fréquences (E05-T14) ». M = media/lua vanilla 42.21.
--
-- Affiche ce que l'autorité répond (server/RadioSurvivor/RS_FreqDebug.lua, FreqDebug.view), sans rien décider, en
-- lecture seule : un tableau des voix (id, nom, état, fréquences de la partie, plages de tirage, radio requise, heures
-- d'écoute, rôle) et un tableau des autres fréquences du mod (bulletin du soir du chroniqueur). Tableaux de
-- LK_Table.lua (lu, jamais modifié : en-têtes cliquables pour trier, texte coupé, infobulle de la ligne).
-- Droits : FreqView.canUse (affichage du bouton seulement : solo = mode debug, client MP = rôle avec la capacité
-- PopmanManage) ; l'autorité revérifie à CHAQUE requête (RS_FreqDebug.isAllowed).
-- Requêtes : à l'ouverture et par le bouton « Actualiser », jamais fenêtre fermée (FreqView.send refuse sans
-- fenêtre ; réponse arrivée après la fermeture ignorée). Aucune relecture périodique : les fiches changent rarement.
-- Ouverture : bouton du panneau debug vanilla (ISDebugMenu, onglet MAIN : enveloppe de setupButtons qui ajoute le
-- bouton AVANT l'original, trié avec les autres, M/client/DebugUIs/DebugMenu/ISDebugMenu.lua:16-58, comme le bouton
-- « Living Knox - PNJ » de client/LivingKnox/LK_DebugView.lua), et console Lua : RS_FreqDebugView.open().
-- Transport : MP, "freqRequest" -> "freqReply" (module "RadioSurvivorDebug") ; solo, RS_FreqDebug.request appelé
-- directement, réponse rendue pendant l'appel (attente posée avant).
if isServer() then return end

local Const = require "RadioSurvivor/RadioSurvivor_Const"

local FreqView = RS_FreqDebugView or {}
RS_FreqDebugView = FreqView

-- Copies des constantes de RS_FreqDebug.lua (comparées par tests/test_rs_freqdebug.py).
FreqView.MODULE = "RadioSurvivorDebug"
FreqView.CMD_REQUEST = "freqRequest"
FreqView.CMD_REPLY = "freqReply"
FreqView.CAPABILITY = "PopmanManage"
FreqView.OP = "frequencies"

FreqView.state = FreqView.state or { n = 0, pending = nil, data = nil, status = nil, window = nil }
FreqView.stats = FreqView.stats or { sent = 0, received = 0, stale = 0, refused = 0 }

local function tr(key, ...)
    return getText("IGUI_RS_FreqDebug_" .. key, ...)
end

local function count(name)
    FreqView.stats[name] = (FreqView.stats[name] or 0) + 1
end

local function localPlayer()
    if getSpecificPlayer ~= nil then return getSpecificPlayer(0) end
    return nil
end

-- Vrai si le joueur peut ouvrir la fenêtre (affichage seulement : l'autorité décide).
function FreqView.canUse(player)
    if not isClient() then return isDebugEnabled ~= nil and isDebugEnabled() == true end
    player = player or localPlayer()
    if player == nil or Capability == nil or Capability[FreqView.CAPABILITY] == nil then return false end
    local role = player:getRole()
    return role ~= nil and role:hasCapability(Capability[FreqView.CAPABILITY]) == true
end

-- Requêtes -----------------------------------------------------------------------------------------------------------

-- Envoie la requête "frequencies", fenêtre ouverte seulement. Rend le numéro de requête, ou nil.
function FreqView.send()
    local st = FreqView.state
    local player = localPlayer()
    if st.window == nil or player == nil then return nil end
    st.n = st.n + 1
    local args = { op = FreqView.OP, n = st.n }
    st.pending = st.n                -- posé AVANT l'envoi : en solo, la réponse arrive pendant l'appel
    count("sent")
    if isClient() then
        sendClientCommand(player, FreqView.MODULE, FreqView.CMD_REQUEST, args)
    else
        local F = RS_FreqDebug
        if F == nil or F.request == nil then
            st.pending = nil
            st.status = tr("NotLoaded")
            FreqView.redraw()
            return nil
        end
        FreqView.receive(F.request(player, args))
    end
    return args.n
end

-- Réponse de l'autorité. Rend vrai si elle a été prise en compte.
function FreqView.receive(reply)
    if type(reply) ~= "table" or reply.op ~= FreqView.OP then return false end
    local st = FreqView.state
    if st.window == nil or st.pending ~= reply.n then
        count("stale")
        return false
    end
    st.pending = nil
    count("received")
    if not reply.ok then
        count("refused")
        st.data = nil
        if reply.err == "denied" then st.status = tr("Denied") else st.status = tr("Error", tostring(reply.err)) end
    else
        st.data = { enabled = reply.enabled == true, voices = type(reply.voices) == "table" and reply.voices or {},
            others = type(reply.others) == "table" and reply.others or {} }
        st.status = nil
        if not st.data.enabled then st.status = tr("Disabled") end
    end
    FreqView.redraw()
    return true
end

function FreqView.onServerCommand(module, command, args)
    if module ~= FreqView.MODULE or command ~= FreqView.CMD_REPLY then return end
    FreqView.receive(args)
end

-- Cellules ---------------------------------------------------------------------------------------------------------

local function mhz(khz)
    return Const.frequencyLabel(khz)
end

local function contains(list, value)
    for _, v in ipairs(type(list) == "table" and list or {}) do
        if v == value then return true end
    end
    return false
end

local function translated(key, fallback)
    local text = getTextOrNull ~= nil and getTextOrNull("IGUI_RS_FreqDebug_" .. key) or nil
    return text or tostring(fallback)
end

local function hhmm(minute)
    return string.format("%02d:%02d", math.floor(minute / 60), minute % 60)
end

-- Colonnes (clé, poids, largeur minimale) ; titre = traduction IGUI_RS_FreqDebug_Col_<clé>.
FreqView.VOICE_COLUMNS = {
    { key = "id", weight = 1, min = 80 }, { key = "name", weight = 2, min = 120 },
    { key = "state", weight = 1, min = 80 }, { key = "freqs", weight = 3, min = 140 },
    { key = "ranges", weight = 3, min = 140 }, { key = "radio", weight = 1, min = 100 },
    { key = "listen", weight = 2, min = 110 }, { key = "role", weight = 2, min = 110 } }
FreqView.OTHER_COLUMNS = {
    { key = "what", weight = 3, min = 160 }, { key = "voice", weight = 1, min = 80 },
    { key = "freq", weight = 1, min = 80 }, { key = "when", weight = 2, min = 120 } }

-- Cellules d'une voix v (vue de RS_FreqDebug.view). Fréquence non servie par une chaîne : marquée.
function FreqView.voiceCells(v)
    local freqs = {}
    for _, khz in ipairs(type(v.frequencies) == "table" and v.frequencies or {}) do
        if contains(v.served, khz) then
            freqs[#freqs + 1] = mhz(khz)
        else
            freqs[#freqs + 1] = tr("NotServed", mhz(khz))
        end
    end
    local ranges = {}
    for _, r in ipairs(type(v.ranges) == "table" and v.ranges or {}) do
        ranges[#ranges + 1] = mhz(r.low) .. "-" .. mhz(r.high)
    end
    local listen = {}
    for _, r in ipairs(type(v.listen) == "table" and v.listen or {}) do
        listen[#listen + 1] = hhmm(r.from) .. "-" .. hhmm(r.to)
    end
    return { id = tostring(v.id), name = tostring(v.name), state = translated("State_" .. tostring(v.state), v.state),
        freqs = #freqs > 0 and table.concat(freqs, ", ") or "-",
        ranges = #ranges > 0 and table.concat(ranges, ", ") or tr("Fixed"),
        radio = translated("Radio_" .. tostring(v.radio), v.radio),
        listen = #listen > 0 and table.concat(listen, ", ") or tr("Always"),
        role = v.chronicler and tr("Chronicler") or "-" }
end

-- Valeur de tri d'une voix : première fréquence (nombre) pour la colonne des fréquences.
function FreqView.voiceSort(v, key)
    if key == "freqs" and type(v.frequencies) == "table" then return v.frequencies[1] end
    if key == "ranges" and type(v.ranges) == "table" and v.ranges[1] ~= nil then return v.ranges[1].low end
    return nil
end

-- Cellules d'une autre fréquence o du mod.
function FreqView.otherCells(o)
    local freq = type(o.khz) == "number" and mhz(o.khz) or tr("OffAir")
    local when = type(o.hour) == "number" and tr("Daily", string.format("%02d:00", o.hour)) or "-"
    return { what = translated("Kind_" .. tostring(o.kind), o.kind), voice = tostring(o.voice), freq = freq, when = when }
end

-- Fenêtre ------------------------------------------------------------------------------------------------------------

function FreqView.redraw()
    local w = FreqView.state.window
    if w ~= nil and w.refreshView ~= nil then w:refreshView() end
end

-- Fenêtre fermée : plus aucune requête ; réponse en route ignorée.
function FreqView.closed(win)
    local st = FreqView.state
    if win ~= nil and st.window ~= win then return end
    st.window, st.pending, st.status, st.data = nil, nil, nil, nil
end

if ISCollapsableWindow ~= nil then
    require "LivingKnox/LK_Table"
    local Table = LivingKnox.Table
    local Window = ISCollapsableWindow:derive("RSFreqDebugWindow")
    FreqView.Window = Window

    local FONT = getTextManager():getFontHeight(UIFont.Small)
    local ROW = FONT + 6
    local BTN = FONT + 8
    local PAD = 10
    local VOICE_ROWS = 10
    local OTHER_ROWS = 3
    local W_MAX = 1300

    local function columns(list)
        local out = {}
        for i, c in ipairs(list) do out[i] = { key = c.key, weight = c.weight, min = c.min, title = tr("Col_" .. c.key) } end
        return out
    end

    function Window:createChildren()
        ISCollapsableWindow.createChildren(self)
        local w = self.width - 2 * PAD
        local y = self:titleBarHeight() + PAD
        local title = tr("Refresh")
        local bw = getTextManager():MeasureStringX(UIFont.Small, title) + 20
        self.refreshBtn = ISButton:new(PAD, y, bw, BTN, title, self, function() RS_FreqDebugView.send() end)
        self.refreshBtn:initialise()
        self.refreshBtn.font = UIFont.Small
        self:addChild(self.refreshBtn)
        self.statusX, self.statusY = self.refreshBtn:getRight() + 2 * PAD, y + math.floor((BTN - FONT) / 2)
        y = y + BTN + PAD
        local vh = ROW * (VOICE_ROWS + 1)
        self.voices = Table.new(self, PAD, y, w, vh, columns(FreqView.VOICE_COLUMNS),
            { cells = FreqView.voiceCells, sortValue = FreqView.voiceSort })
        y = y + vh + PAD
        self.othersY = y
        y = y + FONT + 6
        self.others = Table.new(self, PAD, y, w, self.height - PAD - y, columns(FreqView.OTHER_COLUMNS),
            { cells = FreqView.otherCells })
        self:refreshView()
    end

    function Window:refreshView()
        if self.voices == nil then return end
        local d = FreqView.state.data
        self.voices:setRows(d and d.voices or {}, function(v) return v.id end, nil)
        self.others:setRows(d and d.others or {}, nil, nil)
    end

    function Window:render()
        ISCollapsableWindow.render(self)
        local st = FreqView.state
        local line = st.status
        if line == nil and st.pending ~= nil then line = tr("Waiting") end
        if line == nil and st.data ~= nil then line = tr("Count", #st.data.voices) end
        if line ~= nil then self:drawText(tostring(line), self.statusX, self.statusY, 1, 1, 0.8, 1, UIFont.Small) end
        self:drawText(tr("Others"), PAD, self.othersY, 1, 1, 1, 1, UIFont.Small)
    end

    function Window:close()
        ISCollapsableWindow.close(self)
        self:removeFromUIManager()
        FreqView.closed(self)
    end

    -- Ouvre (ou ramène devant) la fenêtre et demande les fréquences. Rend la fenêtre, ou nil sans droit.
    function FreqView.open()
        if not FreqView.canUse() then
            Const.log("frequency debug view: not allowed for this player")
            return nil
        end
        local st = FreqView.state
        if st.window == nil then
            local core = getCore()
            local w = math.min(W_MAX, core:getScreenWidth() - 40)
            local h = math.min(BTN + ROW * (VOICE_ROWS + OTHER_ROWS + 2) + FONT + 6 + 5 * PAD + 30,
                core:getScreenHeight() - 60)
            local win = Window:new(40, 40, w, h)
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
        if st.pending == nil then FreqView.send() end
        return st.window
    end
end

-- Bouton du panneau debug vanilla ------------------------------------------------------------------------------------

if ISDebugMenu ~= nil then
    FreqView.baseSetupButtons = FreqView.baseSetupButtons or ISDebugMenu.setupButtons
    function ISDebugMenu:setupButtons(...)
        if RS_FreqDebugView.canUse() then   -- avant l'original : trié avec ses boutons, avant « Fermer »
            self:addButtonInfo(tr("Button"), function() RS_FreqDebugView.open() end, "MAIN")
        end
        return FreqView.baseSetupButtons(self, ...)
    end
end

-- Solo : réponses rendues directement par RS_FreqDebug.request. Une seule inscription si le fichier est relu.
if isClient() and Events ~= nil and Events.OnServerCommand ~= nil and not FreqView.subscribed then
    FreqView.subscribed = true
    Events.OnServerCommand.Add(function(module, command, args)
        RS_FreqDebugView.onServerCommand(module, command, args)
    end)
end

return FreqView
