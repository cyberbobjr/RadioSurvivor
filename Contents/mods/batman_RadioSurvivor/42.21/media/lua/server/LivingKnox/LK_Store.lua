-- Living Knox : persistance du registre des PNJ dans un fichier de la machine qui fait autorité (serveur ou solo).
-- Jamais de ModData globale (lisible par tous les clients). Fiche : docs/annexes/conception/corps-registre.md.
--
-- Fichiers : Zomboid/Lua/batman_RadioSurvivor/livingknox/registry-<partie>-<0|1>.txt (getFileWriter), <partie> =
-- hex du « mode/nom » de la partie. Deux emplacements écrits en alternance ; chaque fichier :
--     LKREG1=<numéro d'écriture>
--     <octets RSV2 en hex (RS_Codec, couche octets)>
--     <somme de contrôle>
--     end
-- Relecture : le fichier valide de plus grand numéro ; un registre d'un schéma antérieur est migré
-- (Identity.upgrade) puis réécrit. Schéma inconnu (autre version du mod), structure fausse ou
-- deux fichiers illisibles : registre BLOQUÉ (aucune écriture, fichiers conservés pour une récupération) ; tant
-- qu'il est bloqué, rien ne se crée et aucun corps n'est retiré.
-- Monde neuf (OnInitGlobalModData(isNewGame = true)) : registre vide, même si un ancien fichier porte ce nom
-- (monde effacé puis recréé sous le même nom).
-- Écriture regroupée (LK13-T10, même règle que le registre des groupes LK13-T06 ; fiche corps-registre.md
-- « Persistance ») : un changement d'identité ou d'état (création, retrait, arme) marque le registre « à écrire »
-- (Store.markChanged : state.queued) ; une seule écriture par image, à la fin de l'image (abonné OnTick placé en fin
-- de liste), ou à l'OnTickEvenPaused suivant si aucun OnTick n'a écrit (pause, PauseEmpty) ; à OnSave (solo) ; avant
-- une relecture (init). Écriture immédiate gardée pour la mort d'un corps (Store.flush, mort unique LK07-T04).
-- Changement mineur (positions vues, santé de référence : Store.markDirty) : écrit à OnSave ou avec l'écriture
-- suivante, comme avant. Relecture de contrôle : à la première écriture de la session et sur demande
-- (Store.flush({ verify = true }), Store.verifyFile()), plus à chaque écriture.
require "LivingKnox/LK_Core"
require "LivingKnox/LK_Log"
require "LivingKnox/LK_Identity"
local Codec = require "RadioSurvivor/RS_Codec"

local Store = LivingKnox.Store or {}
LivingKnox.Store = Store

Store.DIR = "batman_RadioSurvivor/livingknox/"
Store.HEADER = "LKREG1"

Store.state = Store.state or { data = nil, seq = 0, blocked = false, reason = nil, dirty = false, path = nil }
-- LK13-T10 : queued = changements à écrire à la fin de l'image ; age = OnTickEvenPaused passés depuis, sans
-- écriture ; verified = une écriture de la session relue. dirty = changements mineurs (OnSave).
Store.stats = Store.stats or { marks = 0, writes = 0, verified = 0 }

local function log() return LivingKnox.Log end

function Store.worldKey()
    local w = getWorld()
    return tostring(w:getGameMode()) .. "/" .. tostring(w:getWorld())
end

function Store.slotPath(slot)
    return Store.state.path .. "-" .. slot .. ".txt"
end

-- Fichiers à deux emplacements (registre des PNJ, registre des groupes LK_Groups) : chaque fichier =
-- "<entête>=<numéro>", octets RSV2 en hex, somme de contrôle, "end".
-- Lit un emplacement : rend { seq, data } (data non validée), puis exists (le fichier existe).
function Store.readSlotFile(path, header)
    local r = getFileReader(path, false)
    if not r then return nil, false end
    local head, raw, checksum, finish = r:readLine(), r:readLine(), r:readLine(), r:readLine()
    r:close()
    if head == nil and raw == nil then return nil, false end -- fichier vide : jamais écrit
    if not head or not raw or finish ~= "end" then return nil, true end
    local seq = tonumber(string.match(head, "^" .. header .. "=(%d+)$") or "")
    local body = Store.unhexOfBytes(raw)   -- LK13-T06 : mêmes octets et même somme que Codec, plus rapides
    if not seq or not body or Store.checksumOfBytes(body) ~= checksum then return nil, true end
    local data = Codec.decodeBytes(body)
    if type(data) ~= "table" then return nil, true end
    return { seq = seq, data = data }, true
end

-- Hex d'une chaîne d'octets (codes 0-255, sortie d'encodeBytes) : mêmes chiffres que Codec.hexBytes, par une table de
-- remplacement de gsub (lue par rawget, aucun appel de fonction par octet ; LK13-T06 : environ 9 fois plus rapide
-- sous Lua 5.1).
local HEX = {}
for i = 0, 255 do HEX[string.char(i)] = string.format("%02x", i) end
local function hexOfBytes(s)
    return (string.gsub(s, ".", HEX))
end
Store.hexOfBytes = hexOfBytes

-- Inverse : mêmes refus et mêmes octets que Codec.unhexBytes (chaîne de longueur paire, chiffres 0-9a-f seulement),
-- par une table de remplacement de gsub au lieu d'un appel de fonction par octet (LK13-T06, relecture).
local UNHEX = {}
for i = 0, 255 do UNHEX[string.format("%02x", i)] = string.char(i) end
function Store.unhexOfBytes(s)
    if type(s) ~= "string" or #s > Codec.MAX_BYTES * 2 or #s % 2 ~= 0 or s:find("[^0-9a-f]") then return nil end
    return (string.gsub(s, "..", UNHEX))
end

-- Somme de contrôle d'une chaîne d'octets : même valeur que Codec.checksumBytes (Adler-32 en décimal), le modulo pris
-- tous les BLOCK octets au lieu de deux fois par octet (LK13-T06 : environ deux fois plus rapide sous Kahlua). Entiers
-- exacts en flottants : a < 65521 + 255 x BLOCK, b < 65521 + BLOCK x a, soit moins de 5e9 pour BLOCK = 4000.
-- LK13-T06 (suite) : seize octets lus par un seul appel string.byte(s, k, k + 15) ; pour ces seize octets
-- c1..c16, a gagne leur somme et b gagne 16 x a + 16 c1 + 15 c2 + ... + c16 (mêmes entiers que seize pas d'un octet ;
-- environ 1,7 fois plus rapide dans la VM Kahlua).
local BLOCK = 4000
local function checksumOfBytes(s)
    local a, b, n, i = 1, 0, #s, 1
    local byte = string.byte
    while i <= n do
        local j = i + BLOCK - 1
        if j > n then j = n end
        local k = i
        while k + 15 <= j do
            local c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16 = byte(s, k, k + 15)
            b = b + 16 * a + 16 * c1 + 15 * c2 + 14 * c3 + 13 * c4 + 12 * c5 + 11 * c6 + 10 * c7 + 9 * c8 + 8 * c9
                + 7 * c10 + 6 * c11 + 5 * c12 + 4 * c13 + 3 * c14 + 2 * c15 + c16
            a = a + c1 + c2 + c3 + c4 + c5 + c6 + c7 + c8 + c9 + c10 + c11 + c12 + c13 + c14 + c15 + c16
            k = k + 16
        end
        for q = k, j do
            a = a + byte(s, q)
            b = b + a
        end
        a, b = a % 65521, b % 65521
        i = j + 1
    end
    return string.format("%.0f", b * 65536 + a)
end
Store.checksumOfBytes = checksumOfBytes

-- Écrit data sous le numéro seq dans path, puis relit le fichier pour le vérifier (sauf noVerify : LK13-T06, registre
-- des groupes écrit souvent, contrôlé à sa première écriture de la session et sur demande). Rend vrai, ou faux et une
-- raison ("exceeds serialization bounds", "cannot open <path> for writing", "write verification failed (<path>)").
function Store.writeSlotFile(path, header, seq, data, noVerify)
    local ok, body = pcall(Codec.encodeBytes, data)
    if not ok then return false, "exceeds serialization bounds" end
    local w = getFileWriter(path, true, false)
    if not w then return false, "cannot open " .. path .. " for writing" end
    w:write(header .. "=" .. seq .. "\n" .. hexOfBytes(body) .. "\n" .. checksumOfBytes(body) .. "\nend\n")
    w:close()
    if noVerify == true then return true end
    local check = Store.readSlotFile(path, header)
    if not check or check.seq ~= seq then return false, "write verification failed (" .. path .. ")" end
    return true
end

-- Base des noms de fichier d'un registre pour la partie courante : <DIR><nom>-<hex du mode/nom de partie>.
function Store.worldFileBase(name)
    return Store.DIR .. name .. "-" .. Codec.hexBytes(Store.worldKey())
end

local function readSlot(path)
    return Store.readSlotFile(path, Store.HEADER)
end

local function block(reason)
    Store.state.blocked = true
    Store.state.reason = reason
    log().error("registry BLOCKED: %s; files kept for recovery (%s-0.txt, -1.txt)", reason,
        tostring(Store.state.path))
    return false
end

-- Charge (ou crée) le registre de la partie courante. newWorld = vrai : registre vide. Rend vrai si prêt.
-- Des changements pas encore écrits (state.queued) sont d'abord écrits dans les fichiers qu'ils concernent : une
-- relecture ne perd jamais une écriture différée.
function Store.init(newWorld)
    local st = Store.state
    if st.queued and st.data ~= nil and not st.blocked and st.path ~= nil then Store.flush() end
    st.data, st.seq, st.blocked, st.reason, st.dirty = nil, 0, false, nil, false
    st.queued, st.age, st.verified = false, 0, false
    st.path = Store.worldFileBase("registry")
    local a, existsA = readSlot(Store.slotPath(0))
    local b, existsB = readSlot(Store.slotPath(1))
    local best = a
    if b and (not a or b.seq > a.seq) then best = b end
    local lastSeq = 0
    if a then lastSeq = a.seq end
    if b and b.seq > lastSeq then lastSeq = b.seq end
    if newWorld then
        st.data, st.seq = LivingKnox.Identity.newRegistry(), lastSeq
        log().info("registry: new world, empty registry")
        return Store.save()
    end
    if not best then
        if existsA or existsB then return block("both registry files are unreadable") end
        st.data, st.seq = LivingKnox.Identity.newRegistry(), 0
        log().info("registry: no file yet, empty registry")
        return true
    end
    local from = LivingKnox.Identity.upgrade(best.data)
    local data, why, kind = LivingKnox.Identity.validate(best.data)
    if not data then
        if kind == "schema" then return block(why) end
        return block("registry file #" .. best.seq .. " is invalid: " .. why)
    end
    st.data, st.seq = data, best.seq
    local count = 0
    for _ in pairs(data.npcs) do count = count + 1 end
    log().info("registry loaded: %s npc(s), file #%s", tostring(count), tostring(best.seq))
    if from then
        log().info("registry migrated from schema %s to %s", tostring(from), tostring(LivingKnox.Identity.SCHEMA))
        return Store.save()
    end
    return true
end

-- Charge le registre s'il ne l'est pas encore (rechargement Lua, événement manqué). Rend vrai si prêt.
function Store.ensure()
    if Store.state.data or Store.state.blocked then return Store.isReady() end
    return Store.init(false)
end

function Store.isReady()
    return Store.state.data ~= nil and not Store.state.blocked
end

function Store.isBlocked()
    return Store.state.blocked == true, Store.state.reason
end

-- Registre courant (nil s'il n'est pas prêt).
function Store.data()
    if not Store.isReady() then return nil end
    return Store.state.data
end

-- Écrit le registre dans l'emplacement suivant, tout de suite (changements en attente et mineurs compris). Relu pour
-- vérification si verify, ou si aucune écriture de la session ne l'a encore été. Rend vrai si écrit.
function Store.save(verify)
    local st = Store.state
    if st.blocked or not st.data then return false end
    verify = verify == true or not st.verified
    local seq = st.seq + 1
    local ok, why = Store.writeSlotFile(Store.slotPath(seq % 2), Store.HEADER, seq, st.data, not verify)
    if not ok then
        if string.sub(why, 1, 6) == "cannot" then return block(why) end
        return block("registry " .. why)
    end
    st.seq, st.dirty, st.queued, st.age = seq, false, false, 0
    Store.stats.writes = Store.stats.writes + 1
    if verify then
        st.verified = true
        Store.stats.verified = Store.stats.verified + 1
    end
    return true
end

-- Changement d'identité ou d'état fait : écriture différée à la fin de l'image (voir l'en-tête). Rend vrai si noté,
-- faux si le registre n'est pas prêt.
function Store.markChanged()
    local st = Store.state
    if st.data == nil or st.blocked then return false end
    st.queued, st.age = true, 0
    Store.stats.marks = Store.stats.marks + 1
    return true
end

function Store.isQueued()
    return Store.state.queued == true
end

-- Écrit maintenant les changements en attente (pas les seuls changements mineurs). opts.verify : relecture de
-- contrôle. Rend vrai si le registre est à jour dans les fichiers (rien en attente, ou écrit), faux si non prêt,
-- bloqué ou écriture refusée (registre bloqué).
function Store.flush(opts)
    local st = Store.state
    if st.blocked then return false end
    if not st.queued then return st.data ~= nil end
    return Store.save(type(opts) == "table" and opts.verify == true)
end

-- Relecture de contrôle sur demande : l'emplacement de la dernière écriture doit porter son numéro et se décoder.
-- Rend vrai, ou faux et une raison (fichier différent : registre bloqué, comme une écriture qui échoue à la relecture).
function Store.verifyFile()
    local st = Store.state
    if st.blocked or not st.data then return false, "registry not ready" end
    if st.seq == 0 then return true end   -- rien écrit encore (aucun fichier attendu)
    local check = readSlot(Store.slotPath(st.seq % 2))
    if not check or check.seq ~= st.seq then
        block("registry write verification failed (" .. Store.slotPath(st.seq % 2) .. ")")
        return false, "write verification failed"
    end
    Store.stats.verified = Store.stats.verified + 1
    return true
end

-- Changement mineur (positions vues, santé de référence) : écrit plus tard (OnSave, ou avec l'écriture suivante).
function Store.markDirty()
    Store.state.dirty = true
end

-- OnSave (abonné de LK_Server) : changements mineurs ou en attente écrits.
function Store.saveIfDirty()
    if Store.state.dirty or Store.state.queued then return Store.save() end
    return false
end

-- Fin de l'image (OnTick, placé en fin de liste) : une seule écriture pour tous les changements de l'image.
function Store.onTick()
    if Store.state.queued then Store.flush() end
end

local function onTickHandler() LivingKnox.Store.onTick() end

-- Début de l'image (OnTickEvenPaused) : changements restés sans écriture une image entière (aucun OnTick : pause,
-- PauseEmpty) écrits ici ; sinon l'OnTick de cette image les écrit. Au premier passage, l'abonné OnTick (inscrit au
-- chargement) passe en fin de liste, comme celui du registre des groupes (base kahlua-lua.md : même fonction retirée
-- puis rajoutée depuis un autre événement de l'image, aucun double appel) ; enveloppe de mesure LK_Load déplacée
-- de même (LK13-T12), un abonné remplacé par un rechargement laissé en place. LK_Groups charge LK_Store avant de
-- s'inscrire : l'abonné du registre des PNJ passe
-- en fin de liste le premier, ce registre est donc écrit avant celui des groupes dans la même fin d'image.
function Store.onTickEvenPaused()
    local st = Store.state
    if not st.tickHooked then
        st.tickHooked = true
        LivingKnox.requeue("OnTick", "Store.flush", onTickHandler)   -- LK13-T12 : enveloppe de mesure comprise
    end
    if not st.queued then return end
    if (st.age or 0) >= 1 then
        Store.flush()
    else
        st.age = (st.age or 0) + 1
    end
end

-- Écriture regroupée (LK13-T10) : début et fin de l'image ; OnSave reste l'abonné Store.saveIfDirty de LK_Server.
-- Autorité seulement : un client MP charge aussi media/lua/server et n'a jamais de registre.
if Events ~= nil and not isClient() then   -- Events absent seulement hors du jeu (banc Kahlua sans événements)
    LivingKnox.subscribe("OnTick", "Store.flush", onTickHandler)
    LivingKnox.subscribe("OnTickEvenPaused", "Store.flushPaused", function() LivingKnox.Store.onTickEvenPaused() end)
end

return Store
