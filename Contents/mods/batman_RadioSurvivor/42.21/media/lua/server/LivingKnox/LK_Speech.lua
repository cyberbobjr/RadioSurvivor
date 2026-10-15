-- Living Knox : parole de proximité des PNJ (LK11-T04). Fiche : docs/conception/parole.md. Java 42.21.0 cité en
-- abrégé (J = zombie/...).
--
-- Autorité seulement (serveur MP ou solo) ; un client MP charge aussi media/lua/server et s'arrête à la première ligne.
-- Affichage : client/LivingKnox/LK_SpeechView.lua (bulle au-dessus du corps, ligne facultative du chat « dire »).
--
-- Points d'entrée :
--   Speech.say(npcId, quoi, opts) -> { id, heard = { joueur, ... }, names = { compte, ... } } | nil, raison
--       quoi : texte déjà rédigé (dialogue LLM du carnet, E08-T03), 1..MAX_TEXT octets sans caractère de contrôle ;
--              ou { key = "IGUI_...", params = { 4 au plus } } traduit par chaque client dans sa langue.
--       opts : id (identifiant de réplique fourni par l'appelant, [%w_.:-] 1..64 ; sinon "sp-<départ>-<n>"),
--              range (cases, 1..MAX_RANGE ; défaut RANGE), name (auteur affiché dans le chat, 1..48 octets),
--              chat (faux : bulle seule ; défaut vrai), band (couleur : friendly, neutral, hostile ; défaut neutral).
--   Speech.bark(npcId, situation, opts) -> résultat de say + champ line (id de la réplique) | nil, raison
--       réplique courte du catalogue (shared/LivingKnox/Data/Speech.lua) choisie selon le type du groupe, le rôle du
--       membre et l'attitude du groupe envers opts.player (joueur visé, facultatif) ; délai GAP_MS entre deux
--       répliques du même PNJ, SAME_MS avant de redire la même situation au même joueur (I9.5). opts : player,
--       band (force l'attitude), range, chat (défaut faux : bulle seule), roll (tirage de test : function(n) -> 1..n).
-- Auditeurs : joueurs qui entendent le PNJ à cet instant, depuis la position de SON corps (Speech.hears, règle de la
-- bulle vanilla ChatElement.getScrambleValue, J/chat/ChatElement.java:204-237, sans texte brouillé : seulement les
-- joueurs qui liraient la phrase en entier). Candidats : destinataires du relais des consignes (Directives.targets,
-- joueurs à 100 cases et propriétaire) en MP, joueurs locaux en solo. Personne n'entend : rien n'est envoyé (raison
-- "nobody hears"), le délai n'est pas consommé.
-- Livraison MP : une commande serveur "speech" (module "LivingKnox") par auditeur, { u = réplique } ; le client ignore
-- un identifiant déjà vu (livraison répétée). Solo : appel direct de LivingKnox.SpeechView.receive, une fois.
-- Aucun bruit pour les zombies (effet distinct, à la charge de l'appelant, ADR B17) ; aucun secret dans une réplique.
if isClient() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Config"
require "LivingKnox/LK_Log"
require "LivingKnox/Data/Speech"

local Speech = LivingKnox.Speech or {}
LivingKnox.Speech = Speech

Speech.MODULE = "LivingKnox"
Speech.CMD = "speech"
Speech.RANGE = 25          -- cases : lecture complète à 15 cases dehors (0,6 x portée), comme la bulle vanilla
Speech.MAX_RANGE = 60
Speech.GAP_MS = 6000       -- entre deux répliques du même PNJ (bark)
Speech.SAME_MS = 90000     -- avant de redire la même situation au même joueur (bark)
Speech.MAX_TEXT = 200      -- octets d'un texte rédigé
Speech.MAX_NAME = 48
Speech.MAX_PARAMS = 4
Speech.MAX_PARAM = 64
Speech.MAX_RECENT = 256    -- entrées (PNJ, situation, joueur) gardées au plus

Speech.state = Speech.state or { n = 0, start = nil }
Speech.last = Speech.last or {}       -- npcId -> { ms, line } dernière réplique (bark)
Speech.recent = Speech.recent or {}   -- "npc|situation|compte" -> ms
Speech.recentCount = Speech.recentCount or 0
Speech.stats = Speech.stats or { said = 0, barks = 0, sent = 0, refused = 0, silent = 0 }

local function Data() return LivingKnox.SpeechData end
local function log() return LivingKnox.Log end
local function now() return getTimestampMs() end

local function count(name)
    Speech.stats[name] = (Speech.stats[name] or 0) + 1
end

local function contains(list, v)
    if list == nil then return true end
    for _, x in ipairs(list) do
        if x == v then return true end
    end
    return false
end

local function nameOf(player)
    local D = LivingKnox.Directives
    if D ~= nil and D.senderName ~= nil then return D.senderName(player) end
    local ok, name = pcall(function() return player:getUsername() end)
    if ok and name ~= nil then return tostring(name) end
    return "?"
end

-- ---------------------------------------------------------------- catalogue

function Speech.isSituation(s)
    return type(s) == "string" and contains(Data().SITUATIONS, s)
end

-- Attitude (bande) d'un niveau de LK_Hostility ; "neutral" pour un niveau inconnu.
function Speech.bandOf(level)
    return Data().BAND_OF_LEVEL[level] or "neutral"
end

-- Répliques d'une situation admises par le contexte { type, role, band }, avec leur poids : { { line, w }, ... }.
function Speech.candidates(situation, ctx)
    local D = Data()
    local out = {}
    ctx = ctx or {}
    for _, line in ipairs(D.lines) do
        if line.situation == situation and contains(line.bands, ctx.band or "neutral")
            and (line.types == nil or contains(line.types, ctx.type))
            and (line.roles == nil or contains(line.roles, ctx.role)) then
            local w = D.WEIGHT_BASE
            if line.types ~= nil then w = w + D.WEIGHT_TYPE end
            if line.roles ~= nil then w = w + D.WEIGHT_ROLE end
            out[#out + 1] = { line = line, w = w }
        end
    end
    return out
end

local function defaultRoll(n)
    return ZombRand(n) + 1
end

-- Réplique tirée (pondérée) parmi les candidats ; avoid : id à éviter si un autre convient. roll(n) -> 1..n.
function Speech.pick(situation, ctx, roll, avoid)
    local list = Speech.candidates(situation, ctx)
    if #list > 1 and avoid ~= nil then
        local kept = {}
        for _, c in ipairs(list) do
            if c.line.id ~= avoid then kept[#kept + 1] = c end
        end
        list = kept
    end
    if #list == 0 then return nil end
    local total = 0
    for _, c in ipairs(list) do total = total + c.w end
    local r = math.floor((roll or defaultRoll)(total))
    if r < 1 then r = 1 end
    if r > total then r = total end
    for _, c in ipairs(list) do
        r = r - c.w
        if r <= 0 then return c.line end
    end
    return list[#list].line
end

-- Contrôle du catalogue : identifiants uniques et propres, situations et bandes connues, au moins une réplique sans
-- type ni rôle par situation et par bande. Rend la liste des problèmes (vide = bon).
function Speech.checkData()
    local D = Data()
    local problems, seen = {}, {}
    for i, line in ipairs(D.lines) do
        local where = "line " .. i
        if type(line.id) ~= "string" or not string.match(line.id, "^[%w_]+$") then
            problems[#problems + 1] = where .. ": bad id"
        elseif seen[line.id] then
            problems[#problems + 1] = where .. ": duplicate id " .. line.id
        else
            seen[line.id] = true
        end
        if not Speech.isSituation(line.situation) then
            problems[#problems + 1] = where .. ": unknown situation " .. tostring(line.situation)
        end
        for _, b in ipairs(line.bands or {}) do
            if not contains(D.BANDS, b) then problems[#problems + 1] = where .. ": unknown band " .. tostring(b) end
        end
    end
    for _, s in ipairs(D.SITUATIONS) do
        for _, b in ipairs(D.BANDS) do
            local generic = false
            for _, line in ipairs(D.lines) do
                if line.situation == s and contains(line.bands, b) and line.types == nil and line.roles == nil then
                    generic = true
                end
            end
            if not generic then problems[#problems + 1] = "no generic line for " .. s .. "/" .. b end
        end
    end
    return problems
end

-- Contexte du PNJ envers le joueur visé : { type, role, band }. Sans groupe : neutre ; sans joueur ou sans identité de
-- personnage liée : attitude de départ du type (LK_Hostility).
function Speech.context(npcId, player)
    local ctx = { band = "neutral" }
    local G, H = LivingKnox.Groups, LivingKnox.Hostility
    if G == nil or not G.ensure() then return ctx end
    local gid, mid = G.findNpc(npcId)
    local g = gid and G.state.data.groups[gid] or nil
    local m = g and g.members[mid] or nil
    if m == nil then return ctx end
    ctx.type, ctx.group = g.type, gid
    ctx.role = (g.leader == mid) and "leader" or m.role
    if H == nil then return ctx end
    local level
    local key = player ~= nil and H.keyOf(player) or nil
    if key ~= nil then
        local a = H.get(gid, key)
        level = a and a.level or nil
    end
    if level == nil then level = H.levelOf(H.startFor(g.type)) end
    ctx.band = Speech.bandOf(level)
    return ctx
end

-- ---------------------------------------------------------------- audition

-- Vrai si le joueur p lirait EN ENTIER une phrase dite par le corps src de portée range : même règle que la bulle
-- vanilla (J/chat/ChatElement.java:204-237 : même pièce = portée x 2 et affichage forcé ; même bâtiment et même étage
-- = portée x 2 ; un seul des deux dans un bâtiment = portée / 2 et brouillé ; 25 % de portée en moins par étage
-- d'écart et brouillé ; distance euclidienne en x, y ; lecture complète sous 0,6 x portée hors brouillage forcé).
-- Mort ou endormi : rien. Sourd : comme la bulle vanilla d'un personnage, il lit (J/chat/ChatElement.java:183).
function Speech.hears(src, p, range)
    if src == nil or p == nil or p:isDead() then return false end
    if p.isAsleep ~= nil and p:isAsleep() then return false end
    local sq, dq = src:getSquare(), p:getSquare()
    if sq == nil or dq == nil then return false end
    local mod, forceScramble, forceDisplay = 1, false, false
    local sb, pb = sq:getBuilding(), dq:getBuilding()
    local dz = math.abs(p:getZ() - src:getZ())
    if pb ~= nil and sb ~= nil and pb == sb then
        if dq:getRoom() == sq:getRoom() then
            mod, forceDisplay = 2, true
        elseif dz < 1 then
            mod = 2
        end
    elseif pb ~= nil or sb ~= nil then
        mod, forceScramble = 0.5, true
    end
    if dz >= 1 then
        mod = mod - mod * dz * 0.25
        forceScramble = true
    end
    if mod <= 0 then return false end
    local r = range * mod
    local dx, dy = p:getX() - src:getX(), p:getY() - src:getY()
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist >= r then return false end
    return forceDisplay or (not forceScramble and dist < r * 0.6)
end

-- Joueurs candidats autour du corps z : { [compte] = joueur }.
local function candidatesAround(z)
    local out = {}
    if isServer() then
        local D = LivingKnox.Directives
        if D ~= nil and D.targets ~= nil then
            out = D.targets(z)
        else
            local list = getOnlinePlayers()
            for i = 0, (list and list:size() or 0) - 1 do
                local p = list:get(i)
                if p ~= nil then out[nameOf(p)] = p end
            end
        end
        return out
    end
    local n = getNumActivePlayers and getNumActivePlayers() or 1
    for i = 0, math.max(n, 1) - 1 do
        local p = getSpecificPlayer and getSpecificPlayer(i) or (i == 0 and getPlayer() or nil)
        if p ~= nil then out[nameOf(p) .. "#" .. i] = p end
    end
    return out
end

-- Auditeurs du corps z : liste triée { { name, player }, ... }.
function Speech.listeners(z, range)
    local out = {}
    for name, p in pairs(candidatesAround(z)) do
        if Speech.hears(z, p, range) then out[#out + 1] = { name = name, player = p } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- ---------------------------------------------------------------- parole

local function clean(text, max)
    if type(text) ~= "string" then return nil end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" or string.len(text) > max or string.find(text, "%c") then return nil end
    return text
end

-- Contenu à envoyer : { t = texte } ou { k = clé, p = paramètres }, ou nil et une raison.
local function content(what)
    if type(what) == "string" then
        local t = clean(what, Speech.MAX_TEXT)
        if t == nil then return nil, "bad text" end
        return { t = t }
    end
    if type(what) ~= "table" or type(what.key) ~= "string" or not string.match(what.key, "^IGUI_[%w_]+$")
        or string.len(what.key) > 96 then
        return nil, "bad key"
    end
    local out = { k = what.key }
    if what.params ~= nil then
        if type(what.params) ~= "table" or #what.params > Speech.MAX_PARAMS then return nil, "bad params" end
        local p = {}
        for i, v in ipairs(what.params) do
            if type(v) == "number" then v = tostring(v) end
            v = clean(v, Speech.MAX_PARAM)
            if v == nil then return nil, "bad param " .. i end
            p[i] = v
        end
        if #p > 0 then out.p = p end
    end
    return out
end

local function nextId()
    local st = Speech.state
    if st.start == nil then st.start = now() end
    st.n = st.n + 1
    return "sp-" .. string.format("%.0f", st.start) .. "-" .. st.n
end

local function deliver(entry, heard)
    if isServer() then
        for _, h in ipairs(heard) do
            sendServerCommand(h.player, Speech.MODULE, Speech.CMD, { u = entry })
            count("sent")
        end
        return
    end
    local View = LivingKnox.SpeechView
    if View ~= nil and View.receive ~= nil then View.receive(entry) end
end

function Speech.say(npcId, what, opts)
    opts = opts or {}
    if not LivingKnox.isAuthority() then return nil, "not the authority" end
    local c, why = content(what)
    if c == nil then
        count("refused")
        return nil, why
    end
    local B = LivingKnox.Bodies
    if B == nil then return nil, "bodies not loaded" end
    local z, where = B.find(npcId)
    if z == nil then
        count("refused")
        return nil, "npc not embodied (" .. tostring(where) .. ")"
    end
    local range = tonumber(opts.range) or Speech.RANGE
    if range < 1 then range = 1 end
    if range > Speech.MAX_RANGE then range = Speech.MAX_RANGE end
    local id = opts.id
    if id ~= nil and (type(id) ~= "string" or not string.match(id, "^[%w_.:%-]+$") or string.len(id) > 64) then
        count("refused")
        return nil, "bad id"
    end
    local heard = Speech.listeners(z, range)
    if #heard == 0 then
        count("silent")
        return nil, "nobody hears"
    end
    local band = opts.band
    if not contains(Data().BANDS, band) then band = "neutral" end
    local entry = { id = id or nextId(), npc = npcId, o = z:getOnlineID(), r = range, b = band, k = c.k, p = c.p,
        t = c.t, chat = opts.chat ~= false }
    local name = clean(opts.name, Speech.MAX_NAME)
    if name ~= nil then entry.n = name end
    deliver(entry, heard)
    count("said")
    local out = { id = entry.id, heard = {}, names = {} }
    for i, h in ipairs(heard) do
        out.heard[i], out.names[i] = h.player, h.name
    end
    log().debug("speech %s by %s heard by %d player(s): %s", entry.id, npcId, #heard, table.concat(out.names, ", "))
    return out
end

local function remember(key, t)
    if Speech.recent[key] == nil then Speech.recentCount = Speech.recentCount + 1 end
    Speech.recent[key] = t
    if Speech.recentCount <= Speech.MAX_RECENT then return end
    local keep, n = {}, 0   -- entrées échues oubliées ; hors de pairs (table modifiée)
    for k, ms in pairs(Speech.recent) do
        if t - ms < Speech.SAME_MS then
            keep[k] = ms
            n = n + 1
        end
    end
    Speech.recent, Speech.recentCount = keep, n
end

function Speech.bark(npcId, situation, opts)
    opts = opts or {}
    if not LivingKnox.isAuthority() then return nil, "not the authority" end
    if not Speech.isSituation(situation) then return nil, "unknown situation " .. tostring(situation) end
    local t = now()
    local last = Speech.last[npcId]
    if last ~= nil and t - last.ms < Speech.GAP_MS then return nil, "cooldown" end
    local who = opts.player ~= nil and nameOf(opts.player) or ""
    local key = tostring(npcId) .. "|" .. situation .. "|" .. who
    local said = Speech.recent[key]
    if said ~= nil and t - said < Speech.SAME_MS then return nil, "said recently" end
    local ctx = Speech.context(npcId, opts.player)
    if opts.band ~= nil then
        if not contains(Data().BANDS, opts.band) then return nil, "unknown band " .. tostring(opts.band) end
        ctx.band = opts.band
    end
    local line = Speech.pick(situation, ctx, opts.roll, last and last.line or nil)
    if line == nil then return nil, "no line for " .. situation .. "/" .. tostring(ctx.band) end
    local out, why = Speech.say(npcId, { key = Data().KEY_PREFIX .. line.id },
        { range = opts.range, chat = opts.chat == true, band = ctx.band, name = opts.name })
    if out == nil then return nil, why end
    Speech.last[npcId] = { ms = t, line = line.id }
    remember(key, t)
    count("barks")
    out.line = line.id
    return out
end

-- PNJ oublié ou mort : délais effacés (appelé par le consommateur au besoin ; sans effet sinon).
function Speech.forget(npcId)
    Speech.last[npcId] = nil
end

return Speech
