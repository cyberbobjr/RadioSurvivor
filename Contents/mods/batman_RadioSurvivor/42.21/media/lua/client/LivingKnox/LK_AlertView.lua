-- Living Knox : cri d'alerte d'un PNJ joué par chaque joueur proche (LK05-T08). Fiche : docs/conception/alerte.md.
-- Java 42.21.0 cité en abrégé (J = zombie/...).
--
-- L'autorité (server/LivingKnox/LK_Alert.lua) décide de l'alerte et du cri ; ce fichier ne fait que JOUER la voix
-- reçue, localement, sans aucun paquet : aucune décision côté client.
--   - MP : commande serveur "alertCry" (module "LivingKnox"), { c = { id, gid, npc, o, x, y, z, s, k } }, envoyée aux
--     destinataires du relais des consignes (joueurs à 100 cases et propriétaire). Solo : appel direct de receive.
--   - Un identifiant déjà reçu est ignoré (livraison répétée) ; seules les voix de VOICES sont jouées.
--   - Voix jouée sur l'émetteur du corps du PNJ s'il est connu de cette machine (CharacterSoundEmitter.playSoundImpl
--     (String, IsoObject), seule surcharge à deux arguments : J/characters/CharacterSoundEmitter.java:190-201, aucun
--     paquet), sinon sur un émetteur libre posé à la position du cri (surcharge sans ambiguïté playSoundImpl(String,
--     boolean, IsoObject) : un nil en second argument choisirait (String, IsoGridSquare), base kahlua-lua.md).
--   - Le bruit qui attire les zombies est émis par l'autorité (addSound), pas ici.
if isServer() then return end

require "LivingKnox/LK_Core"
require "LivingKnox/LK_Log"

local View = LivingKnox.AlertView or {}
LivingKnox.AlertView = View

View.MODULE = "LivingKnox"
View.CMD = "alertCry"
View.VOICES = { VoiceMaleShoutHey = true, VoiceFemaleShoutHey = true }
View.MAX_SEEN = 64

View.seen = View.seen or {}
View.order = View.order or {}
View.stats = View.stats or { received = 0, played = 0, silent = 0, onBody = 0, free = 0, duplicate = 0, refused = 0 }
View.last = View.last or nil

local function log() return LivingKnox.Log end

local function finite(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end

local function count(name)
    View.stats[name] = (View.stats[name] or 0) + 1
end

local function remember(id)
    View.seen[id] = true
    View.order[#View.order + 1] = id
    if #View.order > View.MAX_SEEN then
        View.seen[table.remove(View.order, 1)] = nil
    end
end

-- Copie locale du corps du PNJ : même recherche que la bulle de parole (LivingKnox.SpeechView.bodyOf), sinon corps
-- connu des gestes (LivingKnox.Anim.knownBodies).
function View.bodyOf(e)
    local SV = LivingKnox.SpeechView
    if SV ~= nil and SV.bodyOf ~= nil then return SV.bodyOf(e) end
    local A = LivingKnox.Anim
    return A ~= nil and A.knownBodies ~= nil and A.knownBodies()[e.npc] or nil
end

-- Joue le cri e (table reçue). Rend vrai si une voix a été lancée.
function View.receive(e)
    if type(e) ~= "table" or type(e.id) ~= "string" or not View.VOICES[e.s] or not finite(e.x) or not finite(e.y)
        or not finite(e.z) then
        count("refused")
        return false
    end
    count("received")
    if View.seen[e.id] then
        count("duplicate")
        return false
    end
    remember(e.id)
    local z = View.bodyOf(e)
    local launched, handle = false, nil
    if z ~= nil and not z:isDead() then
        handle = z:getEmitter():playSoundImpl(e.s, nil)
        launched = true
        count("onBody")
    else
        local w = getWorld and getWorld() or nil
        local em = w ~= nil and w:getFreeEmitter(e.x + 0.5, e.y + 0.5, e.z) or nil
        if em ~= nil then
            handle = em:playSoundImpl(e.s, false, nil)
            launched = true
            count("free")
        end
    end
    View.last = { id = e.id, npc = e.npc, s = e.s, x = e.x, y = e.y, z = e.z, body = z ~= nil, handle = handle }
    -- "played" = voix lancée sur un émetteur. Le numéro rendu ne le prouve pas : son coupé (-nosound,
    -- Core.soundDisabled), getFreeEmitter rend un DummySoundEmitter dont playSoundImpl rend toujours 0
    -- (J/audio/DummySoundEmitter.java:133-145, J/iso/IsoWorld.java:493-498) ; "silent" compte ces numéros nuls.
    if launched then
        count("played")
        if handle == nil or handle == 0 then count("silent") end
    end
    log().debug("alert cry %s by %s (%s) at %d,%d,%d", e.id, tostring(e.npc), e.s, e.x, e.y, e.z)
    return true
end

function View.onServerCommand(module, command, args)
    if module ~= View.MODULE or command ~= View.CMD or type(args) ~= "table" then return end
    View.receive(args.c)
end

if isClient() then   -- solo : appel direct de receive par l'autorité, aucune commande
    local function onServerCommand(module, command, args)
        LivingKnox.AlertView.onServerCommand(module, command, args)
    end
    LivingKnox.subscribe("OnServerCommand", "AlertView.onServerCommand", onServerCommand)
end

return View
