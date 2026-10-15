-- Living Knox : affichage de la parole des PNJ (LK11-T04). Fiche : docs/conception/parole.md. Java 42.21.0 cité en
-- abrégé (J = zombie/...).
--
-- Client MP et solo. Reçoit les répliques choisies par l'autorité (server/LivingKnox/LK_Speech.lua) : en MP par la
-- commande serveur "speech" (module "LivingKnox", { u = réplique }), en solo par appel direct de View.receive.
-- Réplique : { id, npc, o = onlineId du corps chez le serveur, r = portée, b = attitude (couleur), k = clé et p =
-- paramètres | t = texte rédigé, n = auteur affiché (facultatif), chat = vrai si une ligne de chat est voulue }.
-- Une réplique déjà vue (même id) est ignorée : livraison répétée sans second affichage.
--
-- Bulle (LK11-T09) : dessinée par ce fichier à chaque image d'interface (OnPreUIDraw, J/ui/UIManager.java:303), au-dessus
-- de la tête de la copie locale du corps, pour chaque joueur local : position isoToScreenX/Y (J/Lua/LuaManager.java:
-- 3355-3370) au point des noms et bulles vanilla, z + 2/3 (IsoGameCharacter.getNameCoords, décalage 64 x tileScale
-- pour un étage de 96 x tileScale, IsoGameCharacter.java:6934-6935 ; IsoUtils.java:104-108), texte
-- getTextManager():DrawStringCentre en police Dialogue avec une ombre noire (même procédé que le Lua vanilla
-- client/erosion/debug/DebugDemoTime.lua:194-196). Durée en temps réel (SHOW_MS + MS_PER_CHAR par caractère, fondu
-- sur le dernier quart comme ChatElement.java:413) ; une bulle par corps. Le serveur a déjà
-- choisi les auditeurs : aucune règle d'audition refaite ici. L'ancienne bulle addLineChatElement (ChatElement du
-- zombie) n'a pas été vue en jeu le 2026-10-11 ; aucune cause trouvée dans le Java (fiche parole.md) : le dessin par le
-- mod ne dépend plus de cet état, et sa trace (stats.drawn, lastDraw) se lit depuis Lua.
-- View.show(corps, texte, couleur) sert aussi aux réponses du carnet (RS_LivingKnox.bubble).
-- Morceaux (E17-T13) : un texte de plus de PIECE caractères (réponse du carnet : jusqu'à 1600 octets) est découpé par
-- RS_TextCut.pieces (fin de phrase, sinon virgule, sinon entre deux mots, jamais dans un mot) et ses morceaux sont
-- affichés l'un après l'autre sur le même corps, chacun pendant sa durée de lecture. Un texte reçu pour un corps
-- dont la bulle n'a pas fini sa durée passe à la suite (MAX_PIECES morceaux en attente au plus) : une bulle n'est
-- jamais remplacée avant d'avoir eu le temps d'être lue ; sinon il la remplace.
-- Chat : client MP seulement (aucun chat en solo), ligne locale sans paquet ChatBase:createMessage puis showMessage sur
-- le canal « dire » (base ui-windows.md), auteur = nom fourni par le serveur ; le canal est découvert par OnAddMessage
-- (type 2). Tant qu'aucun message « dire » n'est passé, pas de ligne de chat (bulle seule).
-- Corps pas encore chargé chez ce client : bulle retentée WAIT_MS au plus, puis abandonnée.
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_ZombieGuard"
require "LivingKnox/LK_Anim"
require "LivingKnox/Data/Speech"
local TextCut = require "RadioSurvivor/RS_TextCut"

local View = LivingKnox.SpeechView or {}
LivingKnox.SpeechView = View

View.MODULE = "LivingKnox"
View.CMD = "speech"
View.SEEN_MAX = 128
View.WAIT_MS = 3000
View.RETRY_EVERY = 5      -- images entre deux essais de bulle en attente
View.SAY_CHAT = "say"     -- nom de ChatType.say (J/network/chat/ChatType.java:10) : énumération non exposée,
                          -- aucune méthode appelable (getValue lève une erreur), tostring = son nom
View.SHOW_MS = 5000       -- durée d'une bulle (ms réelles) ...
View.MS_PER_CHAR = 60     -- ... plus ceci par caractère ...
View.MAX_SHOW_MS = 15000  -- ... au plus
View.WRAP = 60            -- caractères par ligne de bulle au plus (vanilla : 75, ChatElement.java:51)
View.PIECE = 180          -- caractères d'un morceau de bulle au plus (trois lignes de WRAP environ)
View.MAX_PIECES = 16      -- morceaux en attente par corps au plus (au-delà : fin du texte reçu oubliée)
View.MAX_LOG = 32         -- morceaux affichés gardés dans View.pieceLog (suite en jeu)
View.MAX_BUBBLES = 16
View.HEAD_Z = 2 / 3       -- hauteur des noms et bulles vanilla, en étages (64 / 96)
View.COLOR = { 0.95, 0.92, 0.8 }

View.seen = View.seen or {}
View.order = View.order or {}
View.waiting = View.waiting or {}   -- liste { e, text, untilMs }
View.bubbles = View.bubbles or {}   -- liste { z, text, lines, r, g, b, born, untilMs, ms, npc, frames, rest }
View.state = View.state or { ticks = 0 }
View.stats = View.stats or { received = 0, duplicate = 0, shown = 0, chat = 0, missing = 0, lost = 0, bad = 0,
    drawn = 0, pieces = 0, dropped = 0 }
View.pieceLog = View.pieceLog or {} -- morceaux affichés, du plus ancien : { npc, text, at, ms } (suite en jeu)
View.last = View.last or nil        -- dernière réplique affichée { id, npc, text } (tests, suite en jeu)
View.lastDraw = View.lastDraw or nil -- dernière bulle dessinée { npc, text, x, y, player } (suite en jeu)

local function log() return LivingKnox.Log end
local function now() return getTimestampMs() end

local function count(name)
    View.stats[name] = (View.stats[name] or 0) + 1
end

-- Texte de la réplique dans la langue de ce client, ou nil (clé inconnue).
function View.textOf(e)
    if type(e.t) == "string" then return e.t end
    if type(e.k) ~= "string" then return nil end
    local p = type(e.p) == "table" and e.p or {}
    local n = #p
    local text
    if n == 0 then
        text = getTextOrNull(e.k)
    elseif n == 1 then
        text = getTextOrNull(e.k, p[1])
    elseif n == 2 then
        text = getTextOrNull(e.k, p[1], p[2])
    elseif n == 3 then
        text = getTextOrNull(e.k, p[1], p[2], p[3])
    else
        text = getTextOrNull(e.k, p[1], p[2], p[3], p[4])
    end
    return text
end

-- Copie locale du corps du PNJ : corps connu (autorité : registre ; client MP : copie confirmée par la liste du
-- serveur), sinon zombie réanimé de même onlineId (client MP).
function View.bodyOf(e)
    local A = LivingKnox.Anim
    local z = A ~= nil and A.knownBodies()[e.npc] or nil
    if z ~= nil then return z end
    if not isClient() or type(e.o) ~= "number" or getCell() == nil then return nil end
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        local c = list:get(i)
        if c ~= nil and c:getOnlineID() == e.o and not c:isDead() and c:isReanimatedPlayer() then return c end
    end
    return nil
end

-- Lignes d'une bulle : mots regroupés en lignes de View.WRAP caractères au plus (un mot plus long reste entier).
function View.wrap(text)
    local lines, cur = {}, ""
    for word in string.gmatch(text, "%S+") do
        if cur == "" then
            cur = word
        elseif string.len(cur) + 1 + string.len(word) <= View.WRAP then
            cur = cur .. " " .. word
        else
            lines[#lines + 1] = cur
            cur = word
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    return lines
end

-- Corps encore dans le monde de ce client (retiré : plus de case, J/iso/IsoMovingObject.java:732-741).
function View.alive(z)
    return z ~= nil and not z:isDead() and z:getCurrentSquare() ~= nil
end

-- Durée d'affichage d'un morceau (ms réelles).
function View.msOf(text)
    local ms = View.SHOW_MS + View.MS_PER_CHAR * string.len(text)
    if ms > View.MAX_SHOW_MS then ms = View.MAX_SHOW_MS end
    return ms
end

-- Morceau p ({ text, r, g, b, npc }) affiché maintenant dans la bulle b.
local function start(b, p, t)
    b.text, b.lines, b.r, b.g, b.b, b.npc = p.text, View.wrap(p.text), p.r, p.g, p.b, p.npc
    b.ms = View.msOf(p.text)
    b.born, b.untilMs, b.frames = t, t + b.ms, 0
    View.stats.pieces = (View.stats.pieces or 0) + 1
    local shown = View.pieceLog
    shown[#shown + 1] = { npc = p.npc, text = p.text, at = t, ms = b.ms }
    while #shown > View.MAX_LOG do table.remove(shown, 1) end
end

-- Bulle échue dont un morceau attend : morceau suivant affiché à partir de t (bulle sans file : posée avant un
-- rechargement du Lua).
local function advance(b, t)
    if b.rest == nil then b.rest = {} end
    while t >= b.untilMs and #b.rest > 0 do start(b, table.remove(b.rest, 1), t) end
end

-- Pose la bulle d'un corps, ou met le texte à la suite de sa bulle encore à lire. color = { r, g, b } (0..1),
-- View.COLOR par défaut ; npc facultatif. Rend vrai si le texte est affiché ou en attente.
function View.show(z, text, color, npc)
    if z == nil or type(text) ~= "string" then return false end
    local pieces = TextCut.pieces(text, View.PIECE)
    if #pieces == 0 then return false end
    local c = type(color) == "table" and color or View.COLOR
    local t = now()
    local queue = {}
    for i, piece in ipairs(pieces) do
        queue[i] = { text = piece, r = c[1], g = c[2], b = c[3], npc = npc }
    end
    View.lastPieces = { npc = npc, text = text, pieces = pieces }
    for _, b in ipairs(View.bubbles) do
        if b.z == z then
            advance(b, t)
            if t < b.untilMs then
                for _, p in ipairs(queue) do
                    if #b.rest >= View.MAX_PIECES then
                        View.stats.dropped = (View.stats.dropped or 0) + 1
                        break
                    end
                    b.rest[#b.rest + 1] = p
                end
                return true
            end
        end
    end
    local keep = {}
    for _, b in ipairs(View.bubbles) do
        if b.z ~= z then keep[#keep + 1] = b end
    end
    local bubble = { z = z, rest = queue }
    start(bubble, table.remove(queue, 1), t)
    keep[#keep + 1] = bubble
    while #keep > View.MAX_BUBBLES do table.remove(keep, 1) end
    View.bubbles = keep
    return true
end

function View.bubble(z, text, e)
    local D = LivingKnox.SpeechData
    local c = D.COLORS[e.b] or D.COLORS.neutral
    View.show(z, text, c, e.npc)
    count("shown")
    View.last = { id = e.id, npc = e.npc, text = text }
end

local function drawOne(tm, font, lh, pi, b, t)
    local z = b.z
    local x, y, h = z:getX(), z:getY(), z:getZ() + View.HEAD_Z
    local sx = isoToScreenX(pi, x, y, h)
    local sy = isoToScreenY(pi, x, y, h)
    local a = (b.untilMs - t) / (b.ms / 4)
    if a > 1 then a = 1 end
    for i = #b.lines, 1, -1 do
        sy = sy - lh
        local line = b.lines[i]
        tm:DrawStringCentre(font, sx - 1, sy - 1, line, 0, 0, 0, a)
        tm:DrawStringCentre(font, sx + 1, sy + 1, line, 0, 0, 0, a)
        tm:DrawStringCentre(font, sx, sy, line, b.r, b.g, b.b, a)
    end
    b.frames = b.frames + 1
    View.stats.drawn = View.stats.drawn + 1
    View.lastDraw = { npc = b.npc, text = b.text, x = sx, y = sy, player = pi }
end

-- Image d'interface : morceau suivant d'une bulle échue, bulles finies ou corps disparus oubliés, les autres
-- dessinées pour chaque joueur local.
function View.draw()
    if #View.bubbles == 0 then return end
    local t = now()
    local keep = {}
    for _, b in ipairs(View.bubbles) do
        advance(b, t)
        if t < b.untilMs and View.alive(b.z) then keep[#keep + 1] = b end
    end
    View.bubbles = keep
    if #keep == 0 then return end
    local tm = getTextManager()
    local font = UIFont.Dialogue
    local lh = tm:getFontHeight(font) + 1
    for pi = 0, getNumActivePlayers() - 1 do
        if getSpecificPlayer(pi) ~= nil then
            for _, b in ipairs(keep) do drawOne(tm, font, lh, pi, b, t) end
        end
    end
end

function View.chatLine(text, e)
    if e.chat ~= true or type(e.n) ~= "string" or not isClient() or View.chat == nil then return false end
    local ok, err = pcall(function()
        local message = View.chat:createMessage(text)
        message:setAuthor(e.n)
        message:setLocal(true)
        message:setOverHeadSpeech(false)
        message:setShouldAttractZombies(false)
        message:setShowInChat(true)
        View.chat:showMessage(message)   -- jamais sendToServer : ligne locale seulement
    end)
    if not ok then
        log().warn("speech %s: chat line failed: %s", tostring(e.id), tostring(err))
        return false
    end
    count("chat")
    return true
end

local function remember(id)
    View.seen[id] = true
    View.order[#View.order + 1] = id
    if #View.order > View.SEEN_MAX then View.seen[table.remove(View.order, 1)] = nil end
end

-- Réplique reçue. Rend vrai si elle est nouvelle (affichée ou en attente du corps).
function View.receive(e)
    if type(e) ~= "table" or type(e.id) ~= "string" or type(e.npc) ~= "string" then
        count("bad")
        return false
    end
    if View.seen[e.id] then
        count("duplicate")
        return false
    end
    remember(e.id)
    count("received")
    local text = View.textOf(e)
    if text == nil or text == "" then
        count("missing")
        log().warn("speech %s of %s: no text for key %s", e.id, e.npc, tostring(e.k))
        return false
    end
    View.chatLine(text, e)
    local z = View.bodyOf(e)
    if z ~= nil then
        View.bubble(z, text, e)
    else
        View.waiting[#View.waiting + 1] = { e = e, text = text, untilMs = now() + View.WAIT_MS }
    end
    return true
end

-- Bulles en attente d'un corps : affichées dès qu'il est là, oubliées après WAIT_MS.
function View.retry()
    if #View.waiting == 0 then return end
    local keep, t = {}, now()
    for _, w in ipairs(View.waiting) do
        local z = View.bodyOf(w.e)
        if z ~= nil then
            View.bubble(z, w.text, w.e)
        elseif t < w.untilMs then
            keep[#keep + 1] = w
        else
            count("lost")
            log().debug("speech %s of %s: body never loaded here, bubble dropped", w.e.id, w.e.npc)
        end
    end
    View.waiting = keep
end

function View.tick()
    local st = View.state
    st.ticks = st.ticks + 1
    if st.ticks < View.RETRY_EVERY then return end
    st.ticks = 0
    View.retry()
end

function View.onServerCommand(module, command, args)
    if module ~= View.MODULE or command ~= View.CMD or not isClient() then return end
    if type(args) ~= "table" then return end
    View.receive(args.u)
end

-- Canal « dire » de ce client, découvert sur un message affiché (y compris celui d'un autre joueur).
function View.observeMessage(message)
    local ok, chat = pcall(function() return message:getChat() end)
    if not ok or chat == nil then return end
    local okType, value = pcall(function() return tostring(chat:getType()) end)
    if okType and value == View.SAY_CHAT then View.chat = chat end
end

if not isServer() then
    local function onTick()
        LivingKnox.SpeechView.tick()
    end
    local function onServerCommand(module, command, args)
        LivingKnox.SpeechView.onServerCommand(module, command, args)
    end
    local function onAddMessage(message)
        LivingKnox.SpeechView.observeMessage(message)
    end
    -- Une erreur de dessin se répéterait à chaque image : bulles oubliées et une seule ligne au journal.
    local function onPreUIDraw()
        local V = LivingKnox.SpeechView
        local ok, err = pcall(V.draw)
        if not ok then
            V.bubbles = {}
            if not V.drawFailed then log().warn("speech bubbles: draw failed: %s", tostring(err)) end
            V.drawFailed = true
        end
    end
    LivingKnox.subscribe("OnPreUIDraw", "SpeechView.draw", onPreUIDraw)
    LivingKnox.subscribe("OnTick", "SpeechView.tick", onTick)
    LivingKnox.subscribe("OnServerCommand", "SpeechView.onServerCommand", onServerCommand)
    LivingKnox.subscribe("OnAddMessage", "SpeechView.observeMessage", onAddMessage)
end

return View
