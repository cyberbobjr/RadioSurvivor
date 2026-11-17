-- Living Knox : file d'attente étalée sur les images, une seule implémentation pour le moteur (LK20-T05, ADR
-- docs/architecture/decisions/adr-simplification-livingknox.md, D05). Chargé par LK_Core ; ne requiert pas LK_Core
-- (l'espace de noms est créé ici s'il manque). Servent : la relecture du stock de la minute (LK_Stock), le relevé de
-- fortification de la minute (LK_Fortify), la notation de l'heure (LK_Decisions).
--
-- LivingKnox.FrameQueue.new(opts, state) rend une file :
--   opts.hold   : clé de retenue d'écriture du registre des groupes (LivingKnox.Groups.hold), lu à l'exécution
--   opts.frames : images de retenue par entrée en file (1 par défaut)
--   opts.margin : images de retenue en plus (0 par défaut)
--   opts.step   : fonction de travail du module, step(q, all) -> spent, result : une étape (le budget d'une image)
--                 à partir de q.list[q.head], q.head avancé par elle ; all : vidage immédiat (finish), étape complète.
--                 spent faux : rien n'a été fait (entrées déjà traitées ailleurs), la fin peut se faire dans l'image.
--                 result : rendu par frame, compté par finish quand il est vrai.
--   state       : facultatif, table existante reprise telle quelle (module rechargé : même identité, mêmes champs)
-- Champs publics (lus par les modules et les bancs) : list, head (première entrée à traiter), queued ([clé] =
-- entrée, tenu par le module qui retire la clé quand l'entrée est finie), fresh (enfilée dans cette image : rien
-- avant l'image suivante), write (écriture du registre à faire dans une image à elle, à la fin de la file).
LivingKnox = LivingKnox or {}

local FrameQueue = LivingKnox.FrameQueue or {}
LivingKnox.FrameQueue = FrameQueue

local Methods = {}
Methods.__index = Methods

-- Vrai si une entrée attend encore.
function Methods:pending()
    return self.head <= #self.list
end

-- Nombre d'entrées en attente.
function Methods:count()
    return #self.list - self.head + 1
end

-- Ajoute item en fin de file ; key : contrôle de doublon (q.queued[key] = item) ; rend faux si key est déjà en file.
-- Une file entièrement traitée repart d'une liste neuve.
function Methods:push(item, key)
    if key ~= nil and self.queued[key] ~= nil then return false end
    if self.head > #self.list then self.list, self.head, self.queued = {}, 1, {} end
    if key ~= nil then self.queued[key] = item end
    self.list[#self.list + 1] = item
    return true
end

-- Retient l'écriture du registre des groupes le temps des entrées en attente (frames par entrée, plus margin).
function Methods:hold()
    LivingKnox.Groups.hold(self.spec.hold, (self.spec.frames or 1) * self:count() + (self.spec.margin or 0))
end

-- Départ de la file remplie dans cette image : première étape à l'image suivante, écriture retenue jusqu'à la fin.
function Methods:start()
    if not self:pending() then return end
    self.fresh, self.write = true, true
    self:hold()
end

-- Début d'image (OnTickEvenPaused) : les entrées enfilées à l'image précédente peuvent partir.
function Methods:frameStart()
    self.fresh = false
end

-- Fin de file : liste vidée, retenue levée ; flush : écrit le registre s'il a changé et qu'aucune autre retenue ne
-- reste (une autre retenue écrira à sa fin).
function Methods:close(flush)
    self.list, self.head, self.queued, self.write = {}, 1, {}, false
    local G = LivingKnox.Groups
    if G == nil or G.release == nil then return end
    G.release(self.spec.hold)
    if flush and G.isDirty() and not G.isHeld() then G.flush() end
end

-- Une image (OnTick) : une étape de travail ; la file vide, une image pour l'écriture seule. Rend le résultat de
-- l'étape, ou faux.
function Methods:frame()
    if self.fresh then return false end
    if self:pending() then
        local spent, result = self.spec.step(self, false)
        if spent then return result end
    end
    if self.write then self:close(true) end
    return false
end

-- File vidée tout de suite (bancs, OnSave, heure nouvelle) ; retenue levée sans écriture. Rend le nombre d'étapes
-- au résultat vrai.
function Methods:finish()
    self.fresh = false
    local n = 0
    while self:pending() do
        local spent, result = self.spec.step(self, true)
        if result then n = n + 1 end
        if not spent then break end
    end
    self:close(false)
    return n
end

-- Oublie la file (réinitialisation du module).
function Methods:clear()
    self.fresh = false
    self:close(false)
end

function FrameQueue.new(opts, state)
    local self = state or {}
    self.list, self.head, self.queued = self.list or {}, self.head or 1, self.queued or {}
    self.fresh, self.write = self.fresh == true, self.write == true
    self.spec = opts
    return setmetatable(self, Methods)
end

return FrameQueue
