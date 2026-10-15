"""Actual carnet Lua + existing Python bridge, offline, isolated temporary exchange folders.

These are simulated Java/network APIs, NOT a dedicated-server or in-game validation.
python RadioSurvivor/tests/test_carnet.py
"""
from __future__ import annotations

import importlib.util
import json
import math
import os
import re
import sys
import tempfile
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
sys.path.append(str(Path(__file__).resolve().parents[1] / 'tools'))
import pz_paths  # noqa: E402  (vanilla folders: PZ_STEAM_LIBRARY, PZ_MEDIA or Steam detection)
from unittest import mock
from unittest.mock import patch

from test_protocol import Game, Clock, LUA, ROOT, start_bridge, pump, lua_list

sys.path.insert(0, str(ROOT / 'bridge'))
import radio_bridge as bridge_module
import npc_protocol as protocol

STUBS = r'''
HaloTextHelper.addGoodText = HaloTextHelper.addBadText
local radioInstanceof = instanceof
instanceof = function(o, c)
    if c == 'IsoPlayer' then return type(o) == 'table' and o.isPlayer == true end
    return radioInstanceof(o, c)
end
CharacterTrait = {DEAF = 'Deaf'}
Capability = {IgnoreChatSlowMode = 'IgnoreChatSlowMode', EmptyLinesInChat = 'EmptyLinesInChat'}
UIFont = {Medium = 'Medium'}
Translator = {getLanguage = function() return {name = function() return 'FR' end} end}
local square = {getBuilding = function(self) return self.building end, getRoom = function(self) return self.room end}
function list(data)
    return {data = data, size = function(self) return #self.data end, get = function(self, n) return self.data[n + 1] end}
end
ITEM_SEQUENCE = 100
function item(kind, id)
    if not id then ITEM_SEQUENCE = ITEM_SEQUENCE + 1; id = ITEM_SEQUENCE end
    return {id = id, kind = kind, getID = function(self) return self.id end,
        getFullType = function(self) return self.kind end, getCondition = function(self) return self.condition or 100 end,
        isFavorite = function(self) return self.favorite or false end, isEquipped = function(self) return self.equipped or false end,
        getContainer = function(self) return self.container end, getActualWeight = function() return 0.01 end}
end
function inventory()
    local inv = {items = {}, getCapacityWeight = function() return 0 end,
        getEffectiveCapacity = function(self) return self.capacity or 50 end}
    inv.getItems = function(self) return list(self.items) end
    inv.AddItem = function(self, it) self.items[#self.items + 1] = it; it.container = self; return it end
    inv.Remove = function(self, it) for i, found in ipairs(self.items) do if found == it then table.remove(self.items, i); it.container = nil; return end end end
    -- ItemContainer.getItemWithID: this container only, never inside bags (ItemContainer.java:2922).
    inv.getItemWithID = function(self, id)
        for _, it in ipairs(self.items) do if it.id == id then return it end end
    end
    inv.getItemWithIDRecursiv = function(self, id)
        for _, it in ipairs(self.items) do
            if it.id == id then return it end
            if it.bag then local found = it.bag:getItemWithIDRecursiv(id); if found then return found end end
        end
    end
    return inv
end
instanceItem = function(kind) return item(kind) end
REMOVALS, ADDITIONS, SOUNDS = {}, {}, {}
sendRemoveItemFromContainer = function(container, it) REMOVALS[#REMOVALS + 1] = it.id end
sendAddItemToContainer = function(container, it) ADDITIONS[#ADDITIONS + 1] = it.id end
addSound = function(...) SOUNDS[#SOUNDS + 1] = {...} end
getServerOptions = function() return {
    getOption = function(_, name) return name == 'ChatStreams' and (CHAT_STREAMS or 's,r,all,y,w,f') or '' end,
    getInteger = function(_, name) return name == 'ChatMessageSlowModeTime' and 2 or 1000 end} end
detectBadWords = function(text) return text:find('BLOCKED', 1, true) ~= nil end
function enhance(p)
    p.x, p.y, p.z, p.md, p.inv = 10, 10, 0, {}, inventory()
    p.getX = function(self) return self.x end; p.getY = function(self) return self.y end; p.getZ = function(self) return self.z end
    p.getSquare = function(self) return self.square or square end
    p.getInventory = function(self) return self.inv end; p.getModData = function(self) return self.md end
    p.getPlayerNum = function(self) return self.slot or 0 end
    p.isDead = function(self) return self.dead or false end
    p.isAsleep = function(self) return self.asleep or false end
    p.isAllChatMuted = function(self) return self.muted or false end
    p.hasTrait = function(self) return self.deaf or false end
    p.CanSee = function(self) return self.visible ~= false end
    p.getRole = function() return {hasCapability = function() return false end} end
    return p
end
-- Fake NPC engine conforming to RS_NPCProvider (registered by Simulation unless provider=False).
-- Bodies are loaded characters of the cell; each body id names one incarnation of an NPC.
ZOMBIES, NPCS = {}, {}
getCell = function() if NO_CELL then return nil end; return {getZombieList = function() return list(ZOMBIES) end} end
FAKE_PROVIDER = {name = 'fake'}
function FAKE_PROVIDER.available() return true end
function FAKE_PROVIDER.objects()
    local result = {}
    -- OnInitGlobalModData can precede IsoCell creation on a dedicated server.
    local cell = getCell()
    if not cell then return result end
    local bodies = cell:getZombieList()
    for i = 0, bodies:size() - 1 do
        local z = bodies:get(i)
        if NPCS[z.id] then result[z.id] = z end
    end
    return result
end
function FAKE_PROVIDER.id(object) return NPCS[object.id] and object.id or nil end
function FAKE_PROVIDER.npc(id)
    local n = NPCS[id]
    if not n then return nil end
    return {signature = 'fake|' .. tostring(n.id) .. '|' .. n.name .. '|' .. tostring(n.key), name = n.name,
        group = n.group or '1', hostile = n.hostile, traits = {smoker = true}}
end
-- Engine recreation of an NPC under a new id, announced through the interface event.
function FAKE_PROVIDER.restore(id)
    local n = NPCS[id]
    local newID = id + 1000
    spawn(newID, n.name, n.hostile, n.key)
    local P = require('RadioSurvivor/RS_NPCProvider')
    P.emit('reincarnated', FAKE_PROVIDER.npc(id).signature, newID, FAKE_PROVIDER.npc(newID).signature)
end
function registerFakeProvider()
    local P = require('RadioSurvivor/RS_NPCProvider')
    -- The fake engine relays the death of its bodies, as a real engine would.
    Events.OnZombieDead.Add(function(z) if NPCS[z.id] then P.emit('death', z.id, z) end end)
    return P.register(FAKE_PROVIDER)
end
function spawn(id, name, hostile, key)
    NPCS[id] = {id = id, name = name, hostile = hostile, key = key}
    local z = enhance({id = id, username = name, bubbles = {}, addLineChatElement = function(self, text) self.bubbles[#self.bubbles + 1] = text end})
    z.x = 12
    ZOMBIES[#ZOMBIES + 1] = z
    return z
end
-- ChatType: Java enum NOT exposed to Lua (J/Lua/LuaManager.java exposes no ChatType): any method raises, tostring
-- is its name (E17-T14: "attempted index: getValue of non-table: say" in game).
function CHAT_TYPE(name)
    return setmetatable({}, {__tostring = function() return name end,
        __index = function(_, k) error("attempted index: " .. tostring(k) .. " of non-table: " .. name, 2) end})
end
CHAT = {shown = {}, getType = function() return CHAT_TYPE('say') end,
    isEnabled = function() return CHAT_ENABLED ~= false end}
CHAT.createMessage = function(self, text)
    return {text = text, getChat = function() return CHAT end, getAuthor = function(self) return self.author end,
        setAuthor = function(self, author) self.author = author end, setLocal = function(self, b) self.isLocal = b end,
        setOverHeadSpeech = function(self, b) self.overhead = b end, setShouldAttractZombies = function(self, b) self.noise = b end,
        setShowInChat = function(self, b) self.show = b end}
end
CHAT.showMessage = function(self, msg) self.shown[#self.shown + 1] = msg; fire('OnAddMessage', msg, 0) end
processSayMessage = function(text)
    local msg = CHAT:createMessage(text); msg:setAuthor(getPlayer():getUsername())
    if CHAT:isEnabled() then CHAT:showMessage(msg) end
    SAID_CHAT[#SAID_CHAT + 1] = text
    return 'vanilla-return', nil, 7
end
checkPlayerCanUseChat = function() return CHAT:isEnabled() end
ISChat = {instance = {textEntry = {getText = function() return CHAT_INPUT end}, timerMessageSlowMode = 0,
    currentTabID = 1, chatText = {}, unfocus = function() end, logChatCommand = function() end},
    allChatStreams = {{name = 'say', command = '/say ', shortCommand = '/s ', tabID = 1},
        {name = 'general', command = '/all ', tabID = 1}, {name = 'faction', command = '/f ', tabID = 1},
        {name = 'whisper', command = '/w ', tabID = 1}}, defaultTabStream = {{name = 'say'}}}
luautils = {stringStarts = function(text, prefix) return text:sub(1, #prefix) == prefix end}
processGeneralMessage = function(text) GENERAL = text end
proceedFactionMessage = function(text) FACTION = text end
proceedPM = function(text) PRIVATE = text; return 'someone' end
SendCommandToServer = function(text) ADMIN = text end
showWrongChatTabMessage = function() end
doKeyPress = function() end
'''

# ISUI doubles for the notebook window, faithful to the vanilla 42.21 Lua (media/lua/client/ISUI):
# javaObject exists only after instantiate(), which addChild (ISUIElement.lua:1451-1457), addToUIManager
# (1365-1368), setVisible (659-660) and isVisible (684-685) trigger; instantiate() then calls createChildren (1007).
# ISTextEntryBox methods use self.javaObject unguarded (ISTextEntryBox.lua:61, 113, 171): before instantiate
# they fail like Kahlua ("attempted index: setMaxTextLength of non-table: null"); setPlaceholderText alone keeps the
# text until instantiate (ISTextEntryBox.lua:121-127). getTexture returns nil unless FAKE_TEXTURES is set (a missing
# mod texture): the notebook must stay usable without it. Draw calls are recorded in DRAWS (paper notebook, E06-T06).
# Geometry (fix of the E06-T06 solo test): the Lua fields and the Java object are distinct, as in the game.
# ISUIElement:setX/setWidth/... write both (ISUIElement.lua:230-257); Java setWidth/setHeight store the previous size in
# lastwidth/lastheight on EVERY call (UIElement.java:1419-1425, 1463-1469) and update() then moves the anchored
# children by the difference (onResize, UIElement.java:1132-1163, 1329-1334): JAVA_UPDATE. A vanilla scroll bar
# takes x = parent.width - 16 when it is created (ISScrollBar.lua:268-297), only the Java x follows the anchors;
# ISScrollingListBox creates one in instantiate (ISScrollingListBox.lua:53-64) and cuts its rows at the LUA
# vscroll.x + 3 when it is shown (494-495). ISRichTextPanel:paginate wraps words at width - marginLeft - marginRight
# (ISRichTextPanel.lua:456, 494-530; margins 20/10/10/10, 753-756). VISIBLE_RIGHT(e) is the right edge of what the
# player sees of e; FRAME(window) runs one Java update and one render pass (prerender, children, render).
NOTEBOOK_UI = r'''
for _, name in ipairs({'ISCollapsableWindow', 'ISButton', 'ISScrollingListBox', 'ISRichTextPanel', 'ISTextEntryBox',
        'ISModalDialog', 'ISComboBox', 'ISEquippedItem'}) do
    package.preload['ISUI/' .. name] = function() return true end
end
UIFont.Small = 'Small'
Keyboard = {KEY_G = 34}
UI_ROOTS = {}
getCore = function() return {getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end,
    getKey = function() return 0 end, addKeyBinding = function() end, isKey = function() return false end} end
getTextManager = function() return {getFontHeight = function() return 18 end,
    MeasureStringX = function(_, _, text) return #tostring(text) * 7 end} end
FAKE_TEXTURES = false
TEXTURES_ASKED = {}
getTexture = function(path)
    TEXTURES_ASKED[#TEXTURES_ASKED + 1] = path
    if FAKE_TEXTURES then return {path = path} end
    return nil
end
UIFont.Large = 'Large'
UIFont.Medium = 'Medium'
DRAWS = {}
local function record(kind)
    return function(self, ...) DRAWS[#DRAWS + 1] = {kind = kind, element = self, args = {...}} end
end
local Element = {}
Element.__index = Element
function Element:derive(name) local o = {Type = name}; setmetatable(o, self); self.__index = self; return o end
function Element.new(class, x, y, w, h)
    local o = {x = x, y = y, width = w, height = h, anchorLeft = true, anchorTop = true}
    setmetatable(o, class); class.__index = class; return o
end
function Element:initialise() self.children = {} end
-- Java side of an element: geometry copied from the Lua fields at instantiate (ISUIElement:instantiate).
local function javaGeometry(e)
    local j = e.javaObject
    if j and j.width == nil then
        j.x, j.y, j.width, j.height = e.x or 0, e.y or 0, e.width or 0, e.height or 0
        j.lastwidth, j.lastheight, j.scrollHeight, j.yScroll = j.width, j.height, 0, 0
        j.anchorLeft, j.anchorTop = e.anchorLeft ~= false, e.anchorTop ~= false
        j.anchorRight, j.anchorBottom = e.anchorRight == true, e.anchorBottom == true
    end
    return j
end
function Element:instantiate() self.javaObject = {visible = true}; javaGeometry(self); self:createChildren() end
function Element:createChildren() end
function Element:java(method)
    if self.javaObject == nil then error('attempted index: ' .. method .. ' of non-table: null') end
    return self.javaObject
end
function Element:addChild(child)
    if self.javaObject == nil then self:instantiate() end
    if child.javaObject == nil then child:instantiate() end
    javaGeometry(child)
    self.children = self.children or {}; self.children[#self.children + 1] = child; child.parent = self
end
function Element:removeChild(child)
    for i, c in ipairs(self.children or {}) do if rawequal(c, child) then table.remove(self.children, i); break end end
end
function Element:addToUIManager() if self.javaObject == nil then self:instantiate() end; UI_ROOTS[#UI_ROOTS + 1] = self end
function Element:setVisible(v) if self.javaObject == nil then self:instantiate() end; self.javaObject.visible = v end
function Element:isVisible() if self.javaObject == nil then self:instantiate() end; return self.javaObject.visible end
function Element:bringToTop() end
local function javaSetWidth(j, v) if j.width ~= v then j.dirty = true end; j.lastwidth = j.width; j.width = v end
local function javaSetHeight(j, v) if j.height ~= v then j.dirty = true end; j.lastheight = j.height; j.height = v end
function Element:setX(v) self.x = v; if javaGeometry(self) then self.javaObject.x = v end end
function Element:setY(v) self.y = v; if javaGeometry(self) then self.javaObject.y = v end end
function Element:setWidth(v) self.width = v; if javaGeometry(self) then javaSetWidth(self.javaObject, v) end end
function Element:setHeight(v) self.height = v; if javaGeometry(self) then javaSetHeight(self.javaObject, v) end end
function Element:getScrollHeight() local j = javaGeometry(self); return j and j.scrollHeight or 0 end
function Element:getYScroll() local j = javaGeometry(self); return j and j.yScroll or 0 end
-- ISUIElement:updateScrollbars (ISUIElement.lua:1701-1716): the scroll stays within the content.
function Element:setYScroll(y)
    local j = javaGeometry(self)
    if -y > j.scrollHeight - j.height then y = -(j.scrollHeight - j.height) end
    if -y < 0 then y = 0 end
    j.yScroll, self.yScroll = y, y
end
function Element:setScrollHeight(h) javaGeometry(self).scrollHeight = h; self:setYScroll(self:getYScroll()) end
-- UIElement.onResize (UIElement.java:1132-1163): anchored children follow the LAST size difference of the parent.
local function javaResize(e)
    local j = javaGeometry(e)
    local p = e.parent and e.parent.javaObject
    if p and p.dirty then
        local dx, dy = p.width - p.lastwidth, p.height - p.lastheight
        if not j.anchorTop and j.anchorBottom then j.y = j.y + dy end
        if j.anchorTop and j.anchorBottom then javaSetHeight(j, j.height + dy) end
        if not j.anchorLeft and j.anchorRight then j.x = j.x + dx end
        if j.anchorLeft and j.anchorRight then javaSetWidth(j, j.width + dx) end
    end
    if e.onResize then e:onResize(j.width, j.height) end
    for _, c in ipairs(e.children or {}) do javaResize(c) end
    j.dirty, j.lastwidth, j.lastheight = false, j.width, j.height
end
-- UIElement.update (UIElement.java:1312-1336), resize part.
function JAVA_UPDATE(e)
    local j = javaGeometry(e)
    if not j then return end
    if j.dirty then javaResize(e) end
    for _, c in ipairs(e.children or {}) do JAVA_UPDATE(c) end
end
local function attached(e, child)
    for _, c in ipairs(e.children or {}) do if rawequal(c, child) then return true end end
    return false
end
-- Vanilla scroll bar drawn on e (ISScrollBar:render draws only when the content is taller, ISScrollBar.lua:305-308).
function VANILLA_BAR(e)
    local bar = e.vscroll
    if bar and attached(e, bar) and e:isVisible() and bar.javaObject.height < e:getScrollHeight() then return bar end
    return nil
end
function VISIBLE_RIGHT(e)
    if e.Type == 'ISScrollingListBox' and e:isVScrollBarVisible() then return math.min(e.width, e.vscroll.x + 3) end
    local bar = VANILLA_BAR(e)
    if bar then return math.min(e.width, bar.javaObject.x) end
    return e.width
end
local function renderTree(e)
    if not e:isVisible() then return end
    if e.prerender then e:prerender() end
    for _, c in ipairs(e.children or {}) do renderTree(c) end
    if e.render then e:render() end
end
function FRAME(window) JAVA_UPDATE(window); renderTree(window) end
function Element:isVScrollBarVisible()
    return self.vscroll ~= nil and self.vscroll.javaObject.height < self:getScrollHeight()
end
function Element:addScrollBars()
    self:removeScrollBars()
    self.vscroll = ISScrollBar:new(self, true); self.vscroll:initialise(); self:addChild(self.vscroll)
end
function Element:removeScrollBars() if self.vscroll then self:removeChild(self.vscroll) end end
Element.drawRect = record('rect')
Element.drawRectBorder = record('border')
Element.drawText = record('text')
Element.drawTextCentre = record('textCentre')
Element.drawTextureScaled = record('texture')
Element.drawTextureTiled = record('tiled')
function Element:setStencilRect() end
function Element:clearStencilRect() end
function Element:update() end
function Element:setYScroll(y) self.yScroll = y end

ISScrollBar = Element:derive('ISScrollBar')
function ISScrollBar:new(parent, vertical)
    local o = Element.new(self, 0, 0, 0, 0); o.parent, o.vertical = parent, vertical; return o
end
function ISScrollBar:instantiate()
    self.anchorLeft, self.anchorRight, self.anchorBottom = false, true, true
    self.x, self.y, self.width, self.height = self.parent.width - 16, 0, 17, self.parent.height
    self.javaObject = {visible = true}; javaGeometry(self)
end

ISCollapsableWindow = Element:derive('ISCollapsableWindow')
function ISCollapsableWindow.new(class, x, y, w, h)
    local o = Element.new(class, x, y, w, h); o.titleFontHgt = 18; return o
end
function ISCollapsableWindow:titleBarHeight() return math.max(16, self.titleFontHgt + 1) end
function ISCollapsableWindow:setResizable(v) self.resizable = v end
function ISCollapsableWindow:close() self:setVisible(false) end
function ISCollapsableWindow:prerender() end
function ISCollapsableWindow:resizeWidgetHeight() return 10 end

ISButton = Element:derive('ISButton')
function ISButton:new(x, y, w, h, title, target, onclick)
    local o = Element.new(self, x, y, w, h); o.title, o.target, o.onclick, o.enable = title, target, onclick, true; return o
end
function ISButton:setEnable(v) self.enable = v end

ISScrollingListBox = Element:derive('ISScrollingListBox')
function ISScrollingListBox:new(x, y, w, h)
    local o = Element.new(self, x, y, w, h); o.items, o.selected, o.itemheight = {}, 1, 18; return o
end
function ISScrollingListBox:instantiate() Element.instantiate(self); self:addScrollBars() end
-- Rows drawn by doDrawItem, scroll height = their total (ISScrollingListBox.lua:475-541).
function ISScrollingListBox:prerender()
    local y = 0
    for i, v in ipairs(self.items) do v.index = i; y = self:doDrawItem(y, v, false) end
    self:setScrollHeight(y)
end
function ISScrollingListBox:setOnMouseDownFunction(target, f) self.target, self.onmousedown = target, f end
function ISScrollingListBox:clear() self.items, self.selected = {}, 1 end
function ISScrollingListBox:addItem(text, item)
    local row = {text = text, item = item, index = #self.items + 1}; self.items[row.index] = row; return row
end

ISRichTextPanel = Element:derive('ISRichTextPanel')
function ISRichTextPanel:new(x, y, w, h)
    local o = Element.new(self, x, y, w, h)
    o.marginLeft, o.marginTop, o.marginRight, o.marginBottom, o.autosetheight, o.text = 20, 10, 10, 10, true, ''
    return o
end
function ISRichTextPanel:setText(text) self.text = text end
function ISRichTextPanel:onResize()
    self.width, self.height, self.textDirty = self.javaObject.width, self.javaObject.height, true
end
function ISRichTextPanel:render() if self.textDirty then self:paginate() end end
-- Word wrap of the vanilla paginate (tags: <LINE> starts a line, other tags draw nothing); 18 px per line.
function ISRichTextPanel:paginate()
    self.textDirty, self.lines, self.lineX = false, {}, {}
    local maxLineWidth = self.width - self.marginRight - self.marginLeft
    local tm = getTextManager()
    local current, n = nil, 0
    local function flush()
        if current and current ~= '' then n = n + 1; self.lines[n], self.lineX[n] = current, 0 end
        current = nil
    end
    for token in string.gmatch(tostring(self.text or ''), '%S+') do
        if token == '<LINE>' then flush()
        elseif not (string.sub(token, 1, 1) == '<' and string.sub(token, -1) == '>') then
            local chunk = (current and current ~= '') and (current .. ' ' .. token) or token
            if current and current ~= '' and tm:MeasureStringX(self.font, chunk) > maxLineWidth then
                flush(); current = token
            else current = chunk end
        end
    end
    flush()
    local h = self.marginTop + n * 18 + self.marginBottom
    if self.autosetheight then self:setHeight(h) end
    self:setScrollHeight(h)
end

ISTextEntryBox = Element:derive('ISTextEntryBox')
function ISTextEntryBox:new(title, x, y, w, h) local o = Element.new(self, x, y, w, h); o.title = title; return o end
function ISTextEntryBox:instantiate() self.javaObject = {visible = true, text = self.title} end
function ISTextEntryBox:setMaxTextLength(n) self:java('setMaxTextLength').maxTextLength = n end
function ISTextEntryBox:setText(s) self:java('SetText').text = s or ''; self.title = s or '' end
function ISTextEntryBox:getText() return self:java('getText').text end
function ISTextEntryBox:setEditable(v) self:java('setEditable').editable = v end
function ISTextEntryBox:isEditable() return self:java('isEditable').editable ~= false end
function ISTextEntryBox:setPlaceholderText(s)
    if self.javaObject then self.javaObject.placeholder = s else self.placeholderText = s end
end
function ISTextEntryBox:setTextRGBA(r, g, b, a) self:java('setTextRGBA').textColor = {r, g, b, a} end
-- ISTextEntryBox.lua:85-99: unguarded javaObject calls (UITextBox2.setMultipleLine / setMaxLines, 42.21).
function ISTextEntryBox:setMultipleLine(m) self:java('setMultipleLine').multipleLine = m end
function ISTextEntryBox:setMaxLines(n) self:java('setMaxLines').maxLines = n end
function ISTextEntryBox:setPlaceholderTextRGBA(r, g, b, a) self:java('setPlaceholderTextRGBA').placeholderColor = {r, g, b, a} end
function ISTextEntryBox:focus() self:java('focus').focused = true end
function ISTextEntryBox:unfocus() self:java('unfocus').focused = false end
function ISTextEntryBox:isFocused() return self:java('isFocused').focused == true end

ISComboBox = Element:derive('ISComboBox')
function ISComboBox:new(x, y, w, h, target, onchange)
    local o = Element.new(self, x, y, w, h); o.options, o.selected, o.target, o.onChange = {}, 0, target, onchange; return o
end
function ISComboBox:clear() self.options, self.selected = {}, 0 end
function ISComboBox:addOption(name) self.options[#self.options + 1] = name end

ISModalDialog = Element:derive('ISModalDialog')
function ISModalDialog:new(x, y, w, h, text, yesno, target, onclick)
    local o = Element.new(self, x, y, w, h); o.text, o.onclick = text, onclick; return o
end
ISEquippedItem = Element:derive('ISEquippedItem')
'''


# Living Knox in the notebook bench (E17-T03). Server: the REAL engine (LK_Server and its registries in the exchange
# folder, LK_Stories, LK_API) and the real provider RS_LivingKnox.lua; bodies are tagged reanimated-player doubles put
# in the cell zombie list and bound like LK_Bodies.examine does (no scan). Client: the real provider over a roster
# double of LK_ZombieGuard (server roster onlineId -> NPC id, local copies found by the guard). Game clock: world age
# in hours (WORLD_HOURS). Doubles only: no Java API is proven here.
LK_SERVER_STUBS = r'''
SandboxVars.LivingKnox = {Enabled = LK_ENABLED ~= false}
WORLD_HOURS = 48
local baseGameTime = getGameTime
getGameTime = function()
    local gt = baseGameTime()
    gt.getWorldAgeHours = function() return WORLD_HOURS end
    return gt
end
local baseList = list
list = function(data)
    local l = baseList(data)
    l.contains = function(self, o)
        for _, x in ipairs(self.data) do if rawequal(x, o) then return true end end
        return false
    end
    return l
end
-- New embodied NPC of the registry (generation 1), its tagged body bound at x, optional group membership.
function lkNpc(x, gid, role, opts)
    opts = opts or {}
    local I, r = LivingKnox.Identity, LivingKnox.Store.data()
    local n = assert(I.create(r, {female = opts.female == true}, x, 10, 0))
    I.markEmbodied(n, 1)
    assert(LivingKnox.Store.save())
    local z = enhance({id = 5000 + I.idNumber(n.id), username = n.id, bubbles = {},
        addLineChatElement = function(self, text) self.bubbles[#self.bubbles + 1] = text end})
    z.x = x
    z.getOnlineID = function(self) return self.id end
    z.isReanimatedPlayer = function() return true end
    z.hasModData = function() return true end
    z.getAttackedBy = function(self) return self.attacker end
    z.isOnFire = function() return false end
    I.writeTag(z.md, n.id, 1)
    ZOMBIES[#ZOMBIES + 1] = z
    LivingKnox.Bodies.bound[n.id] = z
    if gid then
        local mid = assert(LivingKnox.Groups.addMember(gid, {role = role or 'worker', npc = n.id, day = 2,
            female = opts.female == true, traits = opts.traits}))
        if opts.leader then assert(LivingKnox.Groups.setLeader(gid, mid, 2)) end
    end
    return n.id, z
end
'''
LK_SERVER_LOAD = r'''
for _, m in ipairs({'LivingKnox/LK_Core', 'LivingKnox/LK_Config', 'LivingKnox/LK_Log', 'LivingKnox/LK_Appearance',
        'LivingKnox/LK_Identity', 'LivingKnox/LK_GroupTypes', 'LivingKnox/Data/LK_Type_neutrals',
        'LivingKnox/Data/LK_Type_raiders', 'LivingKnox/Data/LK_Type_settlers', 'LivingKnox/Data/Stories',
        'RadioSurvivor/RS_LivingKnox', 'LivingKnox/LK_Server', 'LivingKnox/LK_Stories', 'LivingKnox/LK_API'}) do
    require(m)
end
'''
LK_CLIENT_STUBS = r'''
SandboxVars.LivingKnox = {Enabled = true}
-- Copy of a Living Knox body on this client, found by the guard (onlineId of the server roster, reanimated player).
function lkCopy(npcId, onlineId, x)
    local G = LivingKnox.ZombieGuard
    local z = enhance({id = onlineId, username = npcId, bubbles = {},
        addLineChatElement = function(self, text) self.bubbles[#self.bubbles + 1] = text end})
    z.x = x or 12
    z.getOnlineID = function(self) return self.id end
    z.isReanimatedPlayer = function() return true end
    G.roster.byId[npcId] = {id = npcId, o = onlineId}
    G.cache[npcId] = z
    return z
end
'''
LK_CLIENT_LOAD = r'''
require 'LivingKnox/LK_Core'
require 'LivingKnox/LK_Config'
require 'LivingKnox/LK_Log'
LivingKnox.ZombieGuard = {roster = {rev = 1, count = 0, byId = {}, byOnline = {}, byOutfit = {}}, cache = {}}
require 'RadioSurvivor/RS_LivingKnox'
'''


def convert(value):
    if hasattr(value, 'items'):
        return {convert(k): convert(v) for k, v in value.items()}
    return value


def count(table):
    return sum(1 for _ in table.keys())


def network_args(game, args):
    """Arguments as the receiver gets them: deep copy, nil for a missing or empty table (GameClient.java:1760,
    SinglePlayerClient.java:126, GameServer sendServerCommand: `args != null && !args.isEmpty()`)."""
    value = convert(args) if args is not None else None
    if not value:
        return None
    return native_table(game, value)


def native_table(game, value):
    if isinstance(value, dict):
        return game.rt.table_from({k: native_table(game, v) for k, v in value.items()})
    if isinstance(value, list):
        return game.rt.table_from([native_table(game, v) for v in value])
    return value


class Simulation:
    def __init__(self, path: Path, clock=None, world='test', boot_cell=True, new_world=False, saved_players=None,
                 radio_new_world=None,
                 provider=True, living_knox=False):
        """living_knox=True (E17-T03): no fake provider; the real Living Knox engine (registries, API, bodies) and its
        notebook provider RS_LivingKnox.lua are loaded on the server, the provider and a roster double of
        LK_ZombieGuard on each client (see LK_SERVER_STUBS / LK_CLIENT_STUBS)."""
        self.living_knox = living_knox
        if living_knox:
            provider = False
        self.path, self.clock, self.provider = path, clock or Clock(), provider
        # Only the server IsoPlayer is persisted in MP: modData saved per account, as ServerPlayerDB does.
        self.saved_players = dict(saved_players or {})
        self.player_data = {}
        path.mkdir(parents=True, exist_ok=True)
        self.server = Game('server', path, self.clock)
        self.server.g.getTimestampMs = lambda: int(self.clock())
        self.server.rt.execute(STUBS)
        if provider:
            self.server.g.registerFakeProvider()
        self.server.g.NO_CELL = not boot_cell
        self.server.g.getWorld = lambda: self.server.rt.eval("{getGameMode=function() return 'Multiplayer' end, getWorld=function() return '" + world + "' end}")
        if living_knox:
            self.server.rt.execute(LK_SERVER_STUBS)
            self.server.rt.execute(LK_SERVER_LOAD)
        self.server.load('server/RS_Carnet_Server.lua')
        if radio_new_world is not None:   # real order of IsoWorld.init: ZomboidRadio.Init, then GlobalModData.init
            self.server.g.fire('OnLoadRadioScripts', None, radio_new_world)
        self.server.g.fire('OnInitGlobalModData', new_world)
        self.server.g.NO_CELL = False
        self.clients = {}
        self.server.g.sendServerCommand = self.deliver_to_client
        if not living_knox:
            self.zombie = self.server.g.spawn(2001, 'Real Bandit', False, 'original-key')

    def saved(self):
        """Server player files at shutdown, for a restarted Simulation."""
        result = dict(self.saved_players)
        result.update({name: convert(md) for name, md in self.player_data.items()})
        return result

    def add_client(self, name, saved_id=None):
        """saved_id: a value left in the CLIENT modData (a claim), never trusted alone."""
        c = Game('client', self.path, self.clock)
        c.g.getTimestampMs = lambda: int(self.clock())
        c.rt.execute(STUBS)
        if self.provider:
            c.g.registerFakeProvider()
        local = c.g.enhance(c.g.makePlayer(name))
        remote = self.server.g.enhance(self.server.g.makePlayer(name))
        remote.isPlayer = True
        if name not in self.player_data:
            self.player_data[name] = native_table(self.server, self.saved_players.get(name, {}))
        remote.md = self.player_data[name]
        c.g.getPlayer = lambda: local
        c.g.getSpecificPlayer = lambda n: local
        if saved_id:
            local.md.RS_CarnetCharacter = saved_id
        c.g.sendClientCommand = lambda p, module, cmd, args: self.server.g.fire(
            'OnClientCommand', module, cmd, remote, network_args(self.server, args))
        self.clients[name] = c
        # Use the ACTUAL installed vanilla input method, not a lookalike implementation.
        source = (pz_paths.media_dir() / 'lua/client/Chat/ISChat.lua').read_text(encoding='utf-8-sig')
        source = source.split('function ISChat:onCommandEntered()', 1)[1].split('function ISChat:onOtherKey', 1)[0]
        c.rt.execute('function ISChat:onCommandEntered()' + source)
        if self.living_knox:
            c.rt.execute(LK_CLIENT_STUBS)
            c.rt.execute(LK_CLIENT_LOAD)
            c.g.RS_LivingKnox.install()
        c.load('client/RadioSurvivor/RS_Client.lua')
        c.g.RS_CarnetClient.installChat()
        c.g.RS_CarnetClient.hello()
        if not self.living_knox:
            c.g.spawn(2001, 'Real Bandit', False, 'original-key')
        return c

    def deliver_to_client(self, *call):
        # sendServerCommand(player, module, command, args), or (module, command, args) to every client.
        if len(call) == 3:
            targets = list(self.clients.values())
        else:
            targets = [self.clients[call[0].username]] if call[0].username in self.clients else []
            call = call[1:]
        module, command, args = call
        for client in targets:
            client.g.fire('OnServerCommand', module, command, network_args(client, args))

    def command(self, name, command, **args):
        self.clients[name].g.RS_CarnetClient.send(command, native_table(self.clients[name], args))

    def say(self, name, text):
        c = self.clients[name]
        c.g.CHAT_INPUT = text
        c.g.ISChat.onCommandEntered(c.g.ISChat.instance)
        # The vanilla player line reaches listeners. It discovers say, never triggers another LLM.
        if not text.startswith('/all') and not text.startswith('/f ') and not text.startswith('/w '):
            for other, listener in self.clients.items():
                if other != name:
                    msg = listener.g.CHAT.createMessage(listener.g.CHAT, text)
                    msg.setAuthor(msg, name)
                    listener.g.CHAT.showMessage(listener.g.CHAT, msg)

    def tick(self):
        self.server.g.fire('OnTickEvenPaused')

    def state(self):
        return self.server.g.RS_CarnetServer.store.data

    def character(self, name):
        return self.clients[name].g.RS_CarnetClient.character

    def mission(self):
        return next(iter(self.state().missions.values()))

    def select(self, name):
        self.command(name, 'select', incarnation=2001)

    def acquaint(self, name):
        """E17-T08 shortcut: the character already knows every NPC it has contacted (contact stage set directly; the
        rule itself is covered by AcquaintanceTests)."""
        for known in self.state().characters[self.character(name)].contacts.values():
            known.stage = 'acquainted'

    def items(self, name, *kinds):
        p = self.server.g.PLAYERS[name]
        result = []
        for kind in kinds:
            it = self.server.g.item(kind)
            p.inv.AddItem(p.inv, it)
            result.append(it.id)
        return result

    def request_mission(self, name, command, **args):
        m = self.mission()
        self.command(name, command, mission=m.id, revision=m.revision, **args)

    def quote(self, name, ids):
        self.request_mission(name, 'prepare_delivery', items=ids)
        return convert(self.server.g.RS_CarnetServer.quotes[self.character(name)])

    def confirm(self, name, quote):
        self.command(name, 'confirm_delivery', mission=quote['mission'], revision=quote['revision'], token=quote['token'])


class CarnetTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-carnet-')
        self.path = Path(self.tmp.name)
        self.process = None

    def tearDown(self):
        if self.process:
            self.process.terminate()
            output, _ = self.process.communicate(timeout=10)
            if self.process.returncode not in (0, 1, -15):
                print(output)
        self.tmp.cleanup()

    def connected(self):
        sim = Simulation(self.path / 'game')
        sim.add_client('alice'); sim.add_client('bob')
        self.process = start_bridge(sim.path)
        sim.select('alice')
        sim.acquaint('alice')
        sim.say('alice', '/say Bonjour, avez-vous besoin de fournitures ?')
        completed = pump(lambda: count(sim.state().missions) == 1, [sim.tick])
        if not completed:
            print('DIAGNOSTIC pending=', convert(sim.server.g.RS_CarnetServer.pending),
                'client=', convert(sim.clients['alice'].g.RS_CarnetClient.snapshot),
                'error=', sim.clients['alice'].g.RS_CarnetClient.lastError)
            for filename in ('requests.txt', 'responses.txt'):
                path = sim.path / filename
                print(filename, path.read_text(encoding='utf-8') if path.exists() else 'MISSING')
        self.assertTrue(completed, 'offline reply never reached Lua')
        return sim

    def test_complete_two_clients_and_concurrent_transactions(self):
        sim = self.connected()
        self.assertFalse(any(r.kind == 'npc_talk' for r in sim.server.g.RS_CarnetServer.pending.values()))
        npc = next(iter(sim.state().npcs.values()))
        self.assertTrue(npc.personality.smoker)
        self.assertEqual(npc.name, 'Real Bandit')
        for c in sim.clients.values():
            speeches = [m for m in c.g.CHAT.shown.values() if m.author == 'Real Bandit']
            self.assertEqual(len(speeches), 1)
            self.assertTrue(speeches[0].isLocal)
            self.assertFalse(speeches[0].overhead)
            self.assertFalse(speeches[0].noise)
        self.assertEqual(len(sim.server.g.SOUNDS), 1)
        sim.request_mission('alice', 'accept')
        remaining = sim.mission().remainingMs
        sim.request_mission('alice', 'invite', character=sim.character('bob'))
        self.assertIsNone(sim.mission().participants[sim.character('bob')])
        sim.request_mission('bob', 'accept')
        self.assertLessEqual(sim.mission().remainingMs, remaining)
        a_ids = sim.items('alice', *(['Base.Bandage'] * 2 + ['Base.RippedSheets']))
        b_ids = sim.items('bob', *(['Base.Bandage'] * 3))
        qa, qb = sim.quote('alice', a_ids), sim.quote('bob', b_ids)
        sim.confirm('alice', qa)
        self.assertEqual(sim.mission().delivered, 3)
        self.assertEqual(count(sim.state().outcomes), 0, 'partial delivery must not apply reputation')
        sim.confirm('bob', qb)
        self.assertEqual(sim.mission().delivered, 3)
        self.assertEqual(len(sim.server.g.PLAYERS.bob.inv['items']), 3, 'stale quote removed objects')
        qb = sim.quote('bob', b_ids)
        sim.confirm('bob', qb)
        self.assertEqual(sim.mission().state, 'success')
        self.assertEqual(sim.mission().delivered, 6)
        self.assertEqual(count(sim.state().outcomes), 2)
        self.assertTrue(all(not o.applied for o in sim.state().outcomes.values()))
        self.assertEqual(len(sim.server.g.REMOVALS), 6)
        revision = sim.mission().revision
        for name in ('alice', 'bob'):
            sim.command(name, 'claim', mission=sim.mission().id, revision=revision)
        self.assertEqual(sim.mission().claimedBy, sim.character('alice'))
        self.assertEqual(len(sim.server.g.ADDITIONS), 20)
        self.assertEqual(len(sim.server.g.PLAYERS.alice.inv['items']), 20)
        self.assertEqual(len(sim.server.g.PLAYERS.bob.inv['items']), 0)
        sim.command('alice', 'claim', mission=sim.mission().id, revision=sim.mission().revision)
        self.assertEqual(len(sim.server.g.ADDITIONS), 20)
        sim.confirm('bob', qb)
        self.assertEqual(sim.mission().delivered, 6)
        # Private notes never leak into the other listener's projection.
        sim.command('alice', 'note', npc=npc.id, text='Private note A')
        sim.command('bob', 'snapshot')
        self.assertEqual(sim.clients['alice'].g.RS_CarnetClient.snapshot.contacts[1].note, 'Private note A')
        self.assertEqual(sim.clients['bob'].g.RS_CarnetClient.snapshot.contacts[1].note, '')
        # Duplicate speech event renders once and never generates a command.
        c = sim.clients['bob']
        speech = [m for m in c.g.CHAT.shown.values() if m.author == npc.name][0]
        event_id = c.g.RS_CarnetClient.seenOrder[1]
        c.g.RS_CarnetClient.receive('speech', native_table(c, {'id': event_id, 'npc': npc.id, 'incarnation': 2001,
            'world': sim.state().world, 'run': sim.server.g.RS_CarnetServer.store.run,
            'name': npc.name, 'text': speech.text}))
        self.assertEqual(len([m for m in c.g.CHAT.shown.values() if m.author == npc.name]), 1)

    def test_answer_bubble_before_say_chat_is_known(self):
        """E17-T14: in MP the answer bubble is shown at once even while the say chat is still unknown (discovered only
        by a chat message); the chat line waits in the inbox and is shown once the say chat is known, the bubble is
        not shown again."""
        sim = Simulation(self.path / 'nosay'); c = sim.add_client('alice')
        client = c.g.RS_CarnetClient
        self.assertTrue(c.g.isClient())
        self.assertIsNone(client.say)
        zombie = c.g.ZOMBIES[len(c.g.ZOMBIES)]
        args = {'id': 'speech-e17t14', 'npc': 'npc-1', 'incarnation': 2001, 'world': client.world, 'run': client.run,
            'name': 'Real Bandit', 'text': 'Une longue reponse. En plusieurs phrases.'}
        self.assertIsNotNone(args['world'])
        client.receive('speech', native_table(c, args))
        self.assertEqual(list(zombie.bubbles.values()), [args['text']], 'bubble must not wait for the say chat')
        self.assertEqual(count(client.inbox), 1, 'chat line kept until the say chat is known')
        self.assertEqual(count(c.g.CHAT.shown), 0)
        c.g.fire('OnTick')
        self.assertEqual(count(client.inbox), 1)
        self.assertEqual(count(zombie.bubbles), 1, 'bubble shown again by the inbox drain')
        # Any say chat message (another player's line) discovers the chat; the next tick shows the line once.
        msg = c.g.CHAT.createMessage(c.g.CHAT, 'hello'); msg.setAuthor(msg, 'bob')
        c.g.CHAT.showMessage(c.g.CHAT, msg)
        self.assertIsNotNone(client.say)
        c.g.fire('OnTick')
        self.assertEqual(count(client.inbox), 0)
        self.assertEqual([m.text for m in c.g.CHAT.shown.values() if m.author == 'Real Bandit'], [args['text']])
        self.assertEqual(count(zombie.bubbles), 1)

    def test_vanilla_input_restrictions_and_channels(self):
        sim = Simulation(self.path / 'input'); c = sim.add_client('alice'); sim.select('alice')
        sim.say('alice', '/all global')
        sim.clock.offset += 3000
        sim.say('alice', '/f faction')
        sim.clock.offset += 3000
        sim.say('alice', '/w bob private')
        sim.clock.offset += 3000
        self.assertFalse(any(r.kind == 'npc_talk' for r in sim.server.g.RS_CarnetServer.pending.values()))
        sim.say('alice', '/say admitted')
        self.assertEqual(len(sim.server.g.RS_CarnetServer.pending), 1)
        sim.say('alice', '/say blocked by vanilla slow mode')
        self.assertEqual(len(sim.server.g.RS_CarnetServer.pending), 1)
        self.assertTrue(c.g.ISChat.instance.showSlowModeFeedback)
        sim.clock.offset += 11000
        sim.server.g.PLAYERS.alice.muted = True
        sim.say('alice', '/say muted server side')
        self.assertEqual(len(sim.server.g.RS_CarnetServer.pending), 1)
        self.assertEqual(c.g.RS_CarnetClient.lastError, 'Chat')
        sim.server.g.PLAYERS.alice.muted = False
        sim.clock.offset += 11000; sim.say('alice', '/say BLOCKED')
        self.assertEqual(c.g.RS_CarnetClient.lastError, 'Chat')
        sim.server.g.CHAT_STREAMS = 'all,f'
        sim.clock.offset += 11000; sim.say('alice', '/say disabled on server')
        self.assertEqual(c.g.RS_CarnetClient.lastError, 'Chat')
        sim.server.g.CHAT_STREAMS = 's,all'
        c.g.CHAT_ENABLED = False
        sim.clock.offset += 11000; sim.say('alice', '/say disabled locally')
        self.assertEqual(len(sim.server.g.RS_CarnetServer.pending), 1)
        # Direct Walt/programmatic processSayMessage preserves returns and is excluded from capture.
        c.g.CHAT_ENABLED = True
        self.assertEqual(c.g.processSayMessage('Walt radio message'), ('vanilla-return', None, 7))
        self.assertEqual(len(sim.server.g.RS_CarnetServer.pending), 1)

    def test_missing_bridge_expiry_range_and_death(self):
        sim = Simulation(self.path / 'missing'); sim.add_client('alice'); sim.select('alice')
        sim.say('alice', '/say hello')
        sim.clock.offset += 151000; sim.tick()
        self.assertEqual(count(sim.state().missions), 0)
        self.assertEqual(sim.clients['alice'].g.RS_CarnetClient.lastError, 'NoAnswer')
        self.assertFalse(any(r.kind == 'npc_talk' for r in sim.server.g.RS_CarnetServer.pending.values()))
        sim.server.g.PLAYERS.alice.x = 100
        sim.clock.offset += 1001; sim.tick()
        self.assertEqual(sim.clients['alice'].g.RS_CarnetClient.snapshot.selected, '')
        sim.server.g.PLAYERS.alice.x = 10
        sim.select('alice')
        npc = next(iter(sim.state().npcs.values()))
        m = sim.server.rt.eval("require('RadioSurvivor/RS_Missions')").create(sim.state(), npc, sim.character('alice'))
        sim.request_mission('alice', 'accept')
        sim.server.g.ZOMBIES = sim.server.rt.table()
        sim.clock.offset += 1001; sim.tick()
        self.assertEqual(m.state, 'active', 'unload was treated as death')
        sim.zombie.dead = True
        sim.server.g.fire('OnZombieDead', sim.zombie)
        self.assertEqual(m.state, 'cancelled_dead')
        self.assertEqual(count(sim.state().outcomes), 0, 'requester death penalized participants')
        self.assertEqual(npc.deathAttribution, 'unavailable_server_evidence')

    def test_persistence_clock_reconnect_and_new_character(self):
        sim = self.connected(); sim.request_mission('alice', 'accept')
        old_char, world, run = sim.character('alice'), sim.state().world, sim.server.g.RS_CarnetServer.store.run
        sim.clock.offset += 20000; sim.tick()
        remaining = sim.mission().remainingMs
        npc_id = next(iter(sim.state().npcs))
        sim.clock.offset += 3600000 # simulated server stopped, not runtime
        restart = Simulation(sim.path, sim.clock, saved_players=sim.saved())
        restart.add_client('alice') # no client claim: the identity comes from the server player file
        self.assertEqual(restart.state().world, world)
        self.assertNotEqual(restart.server.g.RS_CarnetServer.store.run, run)
        self.assertEqual(restart.character('alice'), old_char)
        self.assertEqual(next(iter(restart.state().npcs)), npc_id)
        self.assertAlmostEqual(restart.mission().remainingMs, remaining, delta=200)
        # OnTickEvenPaused continues without any clients and independent of game-world time.
        actual = restart.server.g.PLAYERS.alice # unbound when it disconnects: death then uses its modData
        restart.server.g.PLAYERS = restart.server.rt.table()
        restart.clock.offset += 5000; restart.tick()
        self.assertAlmostEqual(restart.mission().remainingMs, remaining - 5000, delta=200)
        unrelated = restart.server.g.enhance(restart.server.g.makePlayer('mallory'))
        unrelated.isPlayer = True
        unrelated.md.RS_CarnetCharacter = old_char
        restart.server.g.fire('OnCharacterDeath', unrelated) # another account cannot retire this identity
        restart.server.g.fire('OnCharacterDeath', restart.zombie) # zombies also raise OnCharacterDeath
        self.assertFalse(bool(restart.state().characters[old_char].retired))
        actual.dead = True
        restart.server.g.fire('OnCharacterDeath', actual)
        self.assertTrue(restart.state().characters[old_char].retired)
        self.assertIsNone(actual.md.RS_CarnetCharacter)
        restart.add_client('alice', old_char) # a stale client claim cannot revive a retired identity
        self.assertNotEqual(restart.character('alice'), old_char)
        other = Simulation(sim.path, sim.clock, 'another-world')
        self.assertNotEqual(other.state().world, world)
        reused_name = Simulation(sim.path, sim.clock, new_world=True)
        self.assertNotEqual(reused_name.state().world, world, 'new world reused the previous world identity')
        self.assertEqual(count(reused_name.state().missions), 0)

    def test_dedicated_server_restart_keeps_the_world(self):
        """Run 20261015-043927: a dedicated server ALWAYS passes true to OnInitGlobalModData (WorldDictionary.isNewGame
        is set by GameLoadingState only, WorldDictionary.java:526); the new world is the second argument of
        OnLoadRadioScripts (ZomboidRadio.java:246), fired just before (IsoWorld.java:1905). Faithful double."""
        sim = Simulation(self.path / 'dedicated', new_world=True, radio_new_world=True)
        sim.add_client('alice')
        world, char = sim.state().world, sim.character('alice')
        sim.clock.offset += 60000
        restart = Simulation(sim.path, sim.clock, new_world=True, radio_new_world=False, saved_players=sim.saved())
        restart.add_client('alice')
        self.assertEqual(restart.state().world, world, 'restart of a saved world taken as a new world')
        self.assertEqual(restart.character('alice'), char)
        fresh = Simulation(sim.path, sim.clock, new_world=True, radio_new_world=True)
        self.assertNotEqual(fresh.state().world, world, 'a world created again under the same name kept the old one')

    def test_invalid_or_stale_reply_and_inventory_selection(self):
        sim = Simulation(self.path / 'stale'); c = sim.add_client('alice'); sim.select('alice')
        sim.say('alice', '/say hello')
        req = convert(sim.server.g.RS_CarnetServer.pending[1])
        invalid = protocol.offline(req)
        invalid['run'] = 'old-session'
        bridge_module.write_responses(sim.path / 'responses.txt', {req['id']: invalid})
        sim.clock.offset += 1100; sim.tick()
        self.assertEqual(count(sim.state().missions), 0)
        self.assertEqual(c.g.RS_CarnetClient.lastError, 'NoAnswer')
        npc = next(iter(sim.state().npcs.values()))
        m = sim.server.rt.eval("require('RadioSurvivor/RS_Missions')").create(sim.state(), npc, sim.character('alice'))
        sim.request_mission('alice', 'accept')
        good, dirty = sim.items('alice', 'Base.Bandage', 'Base.BandageDirty')
        sim.request_mission('alice', 'prepare_delivery', items=[good, good])
        self.assertEqual(c.g.RS_CarnetClient.lastError, 'Items')
        sim.request_mission('alice', 'prepare_delivery', items=[dirty])
        self.assertEqual(m.delivered, 0)
        q = sim.quote('alice', [good])
        inv = sim.server.g.PLAYERS.alice.inv
        inv.Remove(inv, inv.getItemWithIDRecursiv(inv, good))
        sim.confirm('alice', q)
        self.assertEqual(m.delivered, 0)

    def test_admission_hearing_reconnect_and_restore(self):
        sim = Simulation(self.path / 'admission', boot_cell=False)
        a = sim.add_client('alice'); sim.add_client('bob')
        self.assertEqual(count(sim.state().npcs), 0, 'fiche created for an unselected spawn')
        sim.select('alice')
        npc = next(iter(sim.state().npcs.values()))
        self.assertIsNotNone(npc.personality, 'selected NPC has no fiche')
        provider = sim.server.rt.eval("require('RadioSurvivor/RS_NPCProvider')")
        bob = sim.server.g.PLAYERS.bob
        self.assertTrue(provider.hears(sim.zombie, bob, 30))
        bob.deaf = True
        self.assertFalse(provider.hears(sim.zombie, bob, 30))
        bob.deaf = False; bob.z = 1
        self.assertFalse(provider.hears(sim.zombie, bob, 30))
        self.assertFalse(provider.near(bob, sim.zombie, 8))
        bob.z = 0; bob.x = 50
        self.assertFalse(provider.hears(sim.zombie, bob, 30))
        bob.x = 10
        bob.square = sim.server.rt.eval('{getBuilding=function() return "building" end, getRoom=function() return "room" end}')
        self.assertFalse(provider.hears(sim.zombie, bob, 30), 'building boundary disclosed intelligible dialogue')
        bob.square = None
        old_char = sim.character('alice')
        # Re-handshake is needed when a client has retained an old runtime session.
        a.g.RS_CarnetClient.run = 'old-run'
        sim.command('alice', 'snapshot')
        self.assertEqual(a.g.RS_CarnetClient.run, sim.server.g.RS_CarnetServer.store.run)
        self.assertEqual(sim.character('alice'), old_char)
        a.g.RS_CarnetClient.receive('speech', native_table(a, {'id': 'old-reply', 'world': sim.state().world,
            'run': 'old-run', 'npc': npc.id, 'name': npc.name, 'text': 'stale'}))
        self.assertFalse(a.g.RS_CarnetClient.seen['old-reply'])
        # The engine recreates the NPC and announces it through the provider 'reincarnated' event.
        sim.server.g.FAKE_PROVIDER.restore(2001)
        sim.clock.offset += 1001; sim.tick()
        self.assertEqual(sim.state().npcs[npc.id].incarnation, 3001)
        self.assertEqual(count(sim.state().npcs), 1)
        self.assertEqual(sim.server.g.RS_CarnetServer.objects[npc.id].id, 3001)
        sim.zombie.dead = True
        sim.server.g.fire('OnZombieDead', sim.zombie)
        self.assertTrue(npc.alive, 'obsolete incarnation killed the restored NPC fiche')

    def test_deadline_late_acceptance_and_uncertain_inventory_blocks(self):
        sim = Simulation(self.path / 'transactions'); a = sim.add_client('alice'); sim.add_client('bob')
        sim.select('alice')
        npc = next(iter(sim.state().npcs.values()))
        missions = sim.server.rt.eval("require('RadioSurvivor/RS_Missions')")
        m = missions.create(sim.state(), npc, sim.character('alice'))
        sim.request_mission('alice', 'accept')
        first, second = sim.items('alice', 'Base.Bandage', 'Base.RippedSheets')
        sim.confirm('alice', sim.quote('alice', [first]))
        sim.clock.offset += 10000; sim.tick()
        remaining = m.remainingMs
        sim.request_mission('alice', 'invite', character=sim.character('bob'))
        sim.request_mission('bob', 'accept')
        self.assertLessEqual(m.remainingMs, remaining, 'late participant extended deadline')
        self.assertEqual(count(m.participants), 2)
        # Native inventory packet failure leaves an explicit persisted transaction.
        q = sim.quote('alice', [second])
        sim.server.rt.execute('sendRemoveItemFromContainer=function() error("native packet failure") end')
        sim.confirm('alice', q)
        self.assertEqual(a.g.RS_CarnetClient.lastError, 'Recovery')
        self.assertEqual(m.transaction.error, 'inventory_remove')
        self.assertEqual(m.delivered, 1)
        sim.confirm('alice', q)
        self.assertEqual(m.delivered, 1, 'ambiguous transfer replayed')
        # A clean separate mission verifies runtime timeout and terminal evidence exactly once.
        sim2 = Simulation(self.path / 'deadline'); sim2.add_client('alice'); sim2.select('alice')
        npc2 = next(iter(sim2.state().npcs.values()))
        m2 = sim2.server.rt.eval("require('RadioSurvivor/RS_Missions')").create(sim2.state(), npc2, sim2.character('alice'))
        sim2.request_mission('alice', 'accept')
        sim2.clock.offset += 7200001; sim2.tick(); sim2.tick()
        self.assertEqual(m2.state, 'failed')
        self.assertEqual(count(sim2.state().outcomes), 1)

    def test_corrupt_state_and_reward_capacity(self):
        sim = Simulation(self.path / 'corrupt'); sim.add_client('alice')
        for path in sim.path.glob('state-*.txt'): path.write_text('partial', encoding='utf-8')
        stopped = Simulation(sim.path)
        self.assertTrue(stopped.server.g.RS_CarnetServer.store.blocked)
        self.assertIsNone(stopped.state(), 'corrupt world silently replaced')
        sim2 = Simulation(self.path / 'capacity'); c = sim2.add_client('alice'); sim2.select('alice')
        npc = next(iter(sim2.state().npcs.values()))
        m = sim2.server.rt.eval("require('RadioSurvivor/RS_Missions')").create(sim2.state(), npc, sim2.character('alice'))
        sim2.request_mission('alice', 'accept')
        sim2.confirm('alice', sim2.quote('alice', sim2.items('alice', *(['Base.Bandage'] * 6))))
        sim2.server.g.PLAYERS.alice.inv.capacity = 0
        sim2.request_mission('alice', 'claim')
        self.assertEqual(c.g.RS_CarnetClient.lastError, 'Capacity')
        self.assertEqual(m.claimedBy, '')
        self.assertEqual(len(sim2.server.g.ADDITIONS), 0)

    def test_reconnect_without_client_modData_keeps_identity(self):
        sim = self.connected(); sim.request_mission('alice', 'accept')
        old_char = sim.character('alice')
        sim.command('alice', 'note', npc=next(iter(sim.state().npcs)), text='keep me')
        # Same running server: the client comes back with an empty local modData.
        del sim.server.g.PLAYERS['alice']
        sim.clock.offset += 1001; sim.tick()
        sim.add_client('alice')
        self.assertEqual(sim.character('alice'), old_char)
        snapshot = sim.clients['alice'].g.RS_CarnetClient.snapshot
        self.assertEqual(snapshot.contacts[1].note, 'keep me')
        self.assertTrue(snapshot.missions[1].engaged)
        # A client claim for another account's identity is refused.
        sim.add_client('bob', old_char)
        self.assertNotEqual(sim.character('bob'), old_char)

    def test_offer_expiry_cooldown_and_second_mission(self):
        sim = Simulation(self.path / 'repeat'); sim.add_client('alice'); sim.select('alice')
        npc = next(iter(sim.state().npcs.values()))
        missions = sim.server.rt.eval("require('RadioSurvivor/RS_Missions')")
        first = missions.create(sim.state(), npc, sim.character('alice'))
        sim.clock.offset += 3600001; sim.tick()
        self.assertEqual(first.state, 'expired')
        self.assertIsNone(npc.mission)
        server = sim.server.g.RS_CarnetServer
        record = sim.server.rt.eval("require('RadioSurvivor/RS_NPCProvider')").npc(2001)
        catalog = sim.server.rt.eval("""function(server, npc, record)
            local n = 0
            for _ in pairs(server.offerCatalogFor(npc, record)) do n = n + 1 end
            return n end""")
        self.assertEqual(catalog(server, npc, record), 0, 'no cooldown after a closed offer')
        sim.clock.offset += 1800001
        self.assertEqual(catalog(server, npc, record), 1)
        second = missions.create(sim.state(), npc, sim.character('alice'))
        self.assertNotEqual(second.id, first.id)
        self.assertEqual(count(sim.state().missions), 2)
        # Closed missions are dropped after retention; known mission ids disappear with them.
        sim.clock.offset += 86400001 - 1800001 + 60001; sim.tick()
        self.assertNotIn(first.id, list(sim.state().missions.keys()))
        self.assertIn(second.id, list(sim.state().missions.keys()))

    def test_lazy_fiches_enrichment_and_pruning(self):
        sim = Simulation(self.path / 'lazy'); sim.add_client('alice')
        for i in range(30):
            sim.server.g.spawn(5000 + i, 'Crowd %d' % i, False, 'k%d' % i)
        sim.clock.offset += 1001; sim.tick()
        self.assertEqual(count(sim.state().npcs), 0, 'every spawn produced a fiche')
        self.assertFalse(any(r.kind == 'npc_enrich' for r in sim.server.g.RS_CarnetServer.pending.values()))
        sim.select('alice')
        npc = next(iter(sim.state().npcs.values()))
        # Personality fixed by the spawn identity: identical whenever the NPC is first met.
        provider = sim.server.rt.eval("require('RadioSurvivor/RS_NPCProvider')")
        fixed = convert(provider.personality(npc.signature))
        self.assertEqual(fixed, convert(provider.personality(npc.signature)))
        self.assertEqual({k: convert(npc.personality)[k] for k in fixed}, fixed)
        sim.clock.offset += 5001; sim.tick()
        self.assertEqual([r.npc for r in sim.server.g.RS_CarnetServer.pending.values() if r.kind == 'npc_enrich'], [npc.id])
        # An uncontacted fiche (created by another path) without a loaded body is pruned.
        stray = sim.server.g.RS_CarnetServer.ensure(5001)
        sim.server.g.ZOMBIES = sim.server.rt.table()
        sim.clock.offset += 3600001 + 60001; sim.tick()
        self.assertNotIn(stray.id, list(sim.state().npcs.keys()))
        self.assertIn(npc.id, list(sim.state().npcs.keys()), 'contacted fiche pruned')
        self.assertNotIn(stray.id, list(sim.state().bindings.values()))

    def test_without_provider_notebook_empty_and_walt_available(self):
        sim = Simulation(self.path / 'noprovider', provider=False)
        c = sim.add_client('alice')
        provider = sim.server.rt.eval("require('RadioSurvivor/RS_NPCProvider')")
        self.assertFalse(provider.available())
        self.assertEqual(provider.active().name, 'none')
        self.assertEqual(count(provider.objects()), 0)
        self.assertIsNone(provider.npc(2001), 'empty provider returned an NPC')
        logs = lua_list(sim.server.g.LOGS)
        self.assertIn('[RS_Carnet] authoritative state ready, NPC provider=none, available=false', logs)
        snapshot = c.g.RS_CarnetClient.snapshot
        self.assertFalse(snapshot.npcProvider, 'snapshot does not report the missing provider')
        self.assertTrue(snapshot.storage)
        self.assertEqual(count(snapshot.contacts), 0)
        self.assertEqual(count(snapshot.missions), 0)
        # A loaded body of no provider cannot become a contact.
        sim.select('alice')
        self.assertEqual(c.g.RS_CarnetClient.lastError, 'Range')
        self.assertEqual(count(sim.state().npcs), 0)
        sim.clock.offset += 1001; sim.tick()
        sim.server.g.fire('OnZombieDead', sim.zombie)
        # Walt radio is independent of the NPC provider: request, then the no-bridge fallback broadcast.
        sim.server.load('shared/RadioSurvivor/RadioSurvivor_Const.lua', 'server/RadioSurvivor_Server.lua')
        sim.server.g.fire('OnLoadRadioScripts', sim.server.g.MANAGER, True)
        c.load('shared/RadioSurvivor/RadioSurvivor_Const.lua', 'client/RadioSurvivor_Client.lua')
        c.g.fire('OnGameStart')  # the client asks for Walt's frequencies (E05-T02)
        alice = c.g.getPlayer()
        self.assertEqual(c.g.talk(alice, 'Walt, tu me recois ?'), 'ok')
        self.assertIn('Walt, tu me recois ?', lua_list(c.g.SAID_CHAT))
        sim.clock.offset += 91000
        sim.server.g.fire('OnTick')
        self.assertEqual(lua_list(sim.server.g.BROADCASTS[1]), ['<fzzt>', '<szzt>'])
        for logs in (lua_list(sim.server.g.LOGS), lua_list(c.g.LOGS)):
            self.assertFalse([line for line in logs if 'error' in line.lower() or 'refused' in line.lower()], logs)

    def test_second_provider_refused(self):
        sim = Simulation(self.path / 'second')
        provider = sim.server.rt.eval("require('RadioSurvivor/RS_NPCProvider')")
        self.assertFalse(sim.server.rt.eval("require('RadioSurvivor/RS_NPCProvider').register({name = 'other'})"))
        self.assertEqual(provider.active().name, 'fake')
        self.assertIn('[RS_NPCProvider] refused provider other: provider fake is already active',
                      lua_list(sim.server.g.LOGS))

    def test_no_periodic_snapshot_broadcast(self):
        sim = Simulation(self.path / 'quiet'); sim.add_client('alice'); sim.add_client('bob')
        sent = []
        original = sim.server.g.sendServerCommand
        sim.server.g.sendServerCommand = lambda p, m, c, a: (sent.append(c), original(p, m, c, a))
        for _ in range(10):
            sim.clock.offset += 1001; sim.tick()
        self.assertEqual(sent.count('snapshot'), 0, 'idle server keeps broadcasting snapshots')

    def test_notebook_window_opens_with_vanilla_instantiation_order(self):
        sim = Simulation(self.path / 'window'); c = sim.add_client('alice'); sim.select('alice')
        self.assertGreater(count(c.g.RS_CarnetClient.snapshot.contacts), 0)
        c.rt.execute(NOTEBOOK_UI)
        # The double fails like the vanilla text box when its Java object does not exist yet.
        with self.assertRaisesRegex(Exception, 'setMaxTextLength of non-table'):
            c.rt.execute("local b = ISTextEntryBox:new('', 0, 0, 10, 10); b:initialise(); b:setMaxTextLength(5)")
        c.load('client/RS_Carnet_Client.lua')
        notebook = c.g.RS_UI_Notebook
        notebook.toggle()  # Notebook:new, initialise, addToUIManager -> instantiate -> createChildren
        window = c.g.RS_CarnetClient.window
        self.assertIsNotNone(window)
        self.assertEqual(window.note.javaObject.maxTextLength, 2000)
        self.assertTrue(window.note.isVisible(window.note))
        self.assertEqual(window.tab, 'Contacts')
        self.assertIsNotNone(window.row)
        window.prerender(window)
        # ISRichTextPanel:render resets its colour to white each frame: only an <RGB:> tag darkens the text.
        self.assertTrue(window.detail.text.startswith('<RGB:'))
        for tab in ('Missions', 'Reputation', 'Contacts'):
            window.changeTab(window, tab)
            self.assertTrue(window.detail.text.startswith('<RGB:'), tab)
        # Paper notebook (E06-T06): ink stamps, never painted black when disabled (no ISButton:setEnable), ink note.
        talk = window.talk
        self.assertEqual((talk.borderColor.r, talk.textColor.r), (0.478, 0.478))
        self.assertEqual(talk.backgroundColor.a, 0)
        self.assertTrue(talk.enable)
        window.row.alive = False
        window.showDetail(window)
        self.assertFalse(talk.enable, 'dead contact: Talk must be disabled')
        self.assertEqual(talk.backgroundColor.a, 0)
        self.assertLess(talk.borderColor.a, 1)
        self.assertEqual(lua_list(window.note.javaObject.textColor)[:3], [0.169, 0.165, 0.149])
        # Bookmarks on the right edge switch tabs; the Radio one is first.
        self.assertEqual([t.rsTab.name for t in window.tabs.values()], ['Radio', 'Contacts', 'Missions', 'Reputation',
                                                                   'Team'])
        for t in window.tabs.values():
            t.onclick(window)
            self.assertEqual(window.tab, t.rsTab.name)
            window.prerender(window)
            t.prerender(t)
            self.assertGreater(t.x, window.geo.rightX)
        window.tabs[2].onclick(window)
        row = window.list['items'][1]
        c.g.DRAWS = c.rt.table()
        window.list.doDrawItem(window.list, 0, row)
        texts = [list(d.args.values())[0] for d in c.g.DRAWS.values() if d.kind == 'text']
        self.assertEqual(texts[0], 'Real Bandit')
        notebook.toggle()
        self.assertFalse(window.isVisible(window))


def solo_game(path: Path, clock):
    """Solo game (E17-T06): server and client files in ONE Lua machine (isClient and isServer false), no chat; a client
    command is handled during sendClientCommand (SinglePlayerClient, copied arguments) and the server answers by calling
    RS_CarnetClient.receive directly. Fake NPC engine, body 2001 near the player."""
    path.mkdir(parents=True, exist_ok=True)
    game = Game('solo', path, clock)
    game.g.getTimestampMs = lambda: int(clock())
    game.rt.execute(STUBS)
    game.g.registerFakeProvider()
    game.g.getWorld = lambda: game.rt.eval(
        "{getGameMode=function() return 'Survivor' end, getWorld=function() return 'solo' end}")
    game.load('server/RS_Carnet_Server.lua')
    game.g.fire('OnInitGlobalModData', False)
    zombie = game.g.spawn(2001, 'Real Bandit', False, 'original-key')
    player = game.g.enhance(game.g.makePlayer('solo'))
    player.isPlayer = True
    game.g.getPlayer = lambda: player
    game.g.getSpecificPlayer = lambda n: player
    game.g.sendClientCommand = lambda p, module, cmd, args: game.g.fire(
        'OnClientCommand', module, cmd, p, network_args(game, args))
    game.load('client/RadioSurvivor/RS_Client.lua')
    game.g.RS_CarnetClient.installChat()
    game.g.RS_CarnetClient.hello()
    return game, player, zombie


def open_notebook(game):
    game.rt.execute(NOTEBOOK_UI)
    game.load('client/RS_Carnet_Client.lua')
    game.g.RS_UI_Notebook.toggle()
    return game.g.RS_CarnetClient.window


def talk_requests(server_g):
    return [r for r in server_g.RS_CarnetServer.pending.values() if r.kind == 'npc_talk']


def report_turn(sim, name, text, intent='none', incarnation=2001):
    """E11-T13: `name` selects the NPC `incarnation` and says `text` to it; the bridge answers every pending request
    as a model would, the sentence with `intent` (none, report_done...), an enrichment with a background. Returns the
    npc_talk request of the sentence (Lua table, its context as sent to the bridge)."""
    server = sim.server.g.RS_CarnetServer
    sim.clock.offset += 11000
    sim.command(name, 'select', incarnation=incarnation)
    before = {r.id for r in server.pending.values()}
    sim.say(name, '/say ' + text)
    [req] = [r for r in talk_requests(sim.server.g) if r.id not in before]
    out = ''
    for r in server.pending.values():
        body = {'version': 2, 'kind': 'npc_reply', 'id': r.id, 'world': r.world, 'run': r.run, 'npc': r.npc,
                'order': r.order, 'revision': r.revision, 'text': 'Noted.', 'intent': 'none', 'offer': ''}
        if r.id == req.id:
            body['intent'] = intent
        if r.kind == 'npc_enrich':
            body['background'] = 'A Knox survivor.'
        out += f"resp={r.id}\npayload={protocol.encode(body).hex()}\n"
    (sim.path / 'responses.txt').write_text(out + 'end\n', encoding='utf-8')
    for _ in range(3):
        sim.clock.offset += 1001
        sim.tick()
    assert not [r for r in server.pending.values() if r.id == req.id], 'sentence not answered'
    return req


def last_ack(sim, req):
    """Acknowledgement the server wrote for the request req (dict), or None."""
    for ack in sim.server.g.RS_CarnetServer.store.data.acks.values():
        if ack.request == req.id:
            return convert(ack)
    return None


class ReportCases:
    """E11-T13 : cas communs du compte rendu au PNJ demandeur, joués pour chaque gabarit (clear, recover, signal) par
    les bancs test_mission_*.py. La classe de test fournit active(name) -> (sim, npc, m, missions) (mission acceptée
    par alice, PNJ 2001 demandeur, alice à portée) et fulfil(sim, m) (objectif rempli par le serveur, alice remise à
    portée du demandeur). Le modèle est simulé par la réponse du pont (report_turn) : le serveur revérifie tout."""

    def notebook(self, sim):
        c = sim.clients['alice']
        if c.g.RS_CarnetClient.window is None:
            c.rt.execute(MAP_DOUBLE)
            c.rt.execute(NOTEBOOK_UI)
            c.rt.execute("getScriptManager = function() return {FindItem = function() return nil end} end")
            c.load('client/RS_Carnet_Client.lua')
            c.g.RS_UI_Notebook.toggle()
        sim.command('alice', 'snapshot', world=c.g.RS_CarnetClient.world, run=c.g.RS_CarnetClient.run)
        window = c.g.RS_CarnetClient.window
        window.changeTab(window, 'Missions')
        return c, window

    def test_report_objective_waits_for_the_report_to_the_requester(self):
        sim, npc, m, missions = self.active('report-wait')
        char = sim.character('alice')
        # A claim before the objective: nothing reportable is sent, report_done and the button change nothing.
        req = report_turn(sim, 'alice', 'It is done.', 'report_done')
        self.assertIsNone(req.context.reportable)
        self.assertFalse(convert(req.context.mission)['toReport'])
        sim.request_mission('alice', 'report')
        self.assertEqual(sim.clients['alice'].g.RS_CarnetClient.lastError, 'State')
        self.assertEqual((m.state, count(m.receipts)), ('active', 0))
        # Objective met by the server: still active, "to report" in the projection and the notebook.
        self.fulfil(sim, m)
        self.assertEqual(m.state, 'active', 'the objective alone succeeded')
        self.assertTrue(missions.reportReady(m))
        c, window = self.notebook(sim)
        row = convert(c.g.RS_CarnetClient.snapshot.missions[1])
        self.assertEqual((row['state'], row['toReport']), ('active', True))
        self.assertIn('IGUI_RS_State_toReport', window.detail.text)
        self.assertIn('IGUI_RS_ReportInPerson|' + row['requester'], window.detail.text)
        self.assertEqual(c.g.RS_UI_Notebook.rowSecondLine(c.g.RS_CarnetClient.snapshot.missions[1]),
                         'IGUI_RS_StateShort_toReport')
        self.assertTrue(window.report.isVisible(window.report), 'no Report button')
        # Said to another NPC: nothing reportable, a report_done there changes nothing.
        other = sim.server.g.spawn(2002, 'Other Bandit', False, 'other-key')
        other.x = 11
        req = report_turn(sim, 'alice', 'Job done.', 'report_done', incarnation=2002)
        self.assertNotEqual(req.npc, m.npc)
        self.assertIsNone(req.context.reportable)
        self.assertEqual(m.state, 'active')
        # Said to the requester without reporting (model intent none): still to report.
        req = report_turn(sim, 'alice', 'Nice weather.', 'none')
        self.assertEqual(convert(req.context.reportable), {'mission': m.id, 'revision': m.revision})
        self.assertTrue(convert(req.context.mission)['toReport'])
        self.assertEqual(m.state, 'active')
        # The report to the requester (model intent report_done, checked again): success, reputation, reward lot.
        req = report_turn(sim, 'alice', 'Done, as you asked.', 'report_done')
        self.assertEqual(m.state, 'success')
        self.assertEqual(convert(m.receipts), {'speech-' + char: {'character': char, 'count': 1}})
        outcome = sim.state().outcomes[m.id + '-' + char + '-result']
        self.assertEqual((outcome.action, outcome.proposedDelta), ('mission.success', 5))
        self.assertEqual(last_ack(sim, req)['applied'], {'report': m.id})
        self.assertIsNone(npc.mission)
        sim.request_mission('alice', 'claim')
        self.assertEqual(m.claimedBy, char)

    def test_report_button_next_to_the_requester_only(self):
        sim, npc, m, missions = self.active('report-button')
        self.fulfil(sim, m)
        alice = sim.server.g.PLAYERS.alice
        alice.x, alice.y = 40, 40
        sim.request_mission('alice', 'report')
        self.assertEqual(m.state, 'active', 'reported away from the requester')
        alice.x, alice.y = 10, 10
        sim.request_mission('bob', 'report')
        self.assertEqual(m.state, 'active', 'reported by a non-participant')
        sim.request_mission('alice', 'report')
        self.assertEqual(m.state, 'success')
        self.assertEqual(sim.state().outcomes[m.id + '-' + sim.character('alice') + '-result'].action,
                         'mission.success')

    def test_requester_death_cancels_a_mission_to_report(self):
        sim, npc, m, missions = self.active('report-death')
        self.fulfil(sim, m)
        self.assertTrue(missions.reportReady(m))
        sim.zombie.dead = True
        sim.server.g.fire('OnZombieDead', sim.zombie)
        self.assertEqual(m.state, 'cancelled_dead')
        self.assertFalse(missions.reportReady(m))
        self.assertIsNone(sim.state().outcomes[m.id + '-' + sim.character('alice') + '-result'],
                          'requester death penalized or rewarded the participant')


class ContactsTalkTests(unittest.TestCase):
    """E17-T06 : ligne « Dire » de l'onglet Contacts. Solo simulé (une seule machine Lua, sans chat) et MP simulé (deux
    clients, chat vanilla ISChat:onCommandEntered installé) ; vrai pont hors ligne pour la réponse en solo. Doublures
    ISUI de NOTEBOOK_UI : ne prouve ni l'API Java ni l'affichage en jeu."""
    TEXT = 'Bonjour, avez-vous besoin de fournitures ?'

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-carnet-talk-')
        self.path = Path(self.tmp.name)
        self.process = None

    def tearDown(self):
        if self.process:
            self.process.terminate()
            self.process.communicate(timeout=10)
        self.tmp.cleanup()

    @staticmethod
    def status(window):
        window.update(window)
        return window.talkStatus, window.speak.javaObject.editable is not False, window.speakSend.enable

    def send(self, window, text):
        window.speak.setText(window.speak, text)
        window.sendTalk(window)

    def test_solo_say_line_reaches_the_selected_npc_who_answers(self):
        clock = Clock()
        game, player, zombie = solo_game(self.path / 'solo', clock)
        client, server = game.g.RS_CarnetClient, game.g.RS_CarnetServer
        window = open_notebook(game)
        self.assertEqual(window.tab, 'Contacts')
        self.assertFalse(window.speak.isVisible(window.speak), 'Say line without any contact')
        # Ctrl+G selects the nearest NPC: the contact appears, the Say line opens on it.
        client.selectNearest()
        self.assertNotEqual(client.snapshot.selected, '')
        self.assertTrue(window.speak.isVisible(window.speak))
        self.assertEqual(self.status(window), (None, True, True))
        self.assertEqual(window.speak.javaObject.placeholder, 'IGUI_RS_TalkPlaceholder|Real Bandit')
        self.assertEqual(window.speak.javaObject.maxTextLength, 200)
        # Refusal: no target (deselected). Greyed with the reason; a forced send does nothing.
        client.send('deselect')
        self.assertEqual(self.status(window), ('IGUI_RS_TalkSelectFirst', False, False))
        self.send(window, 'nobody listens')
        self.assertEqual(talk_requests(game.g), [])
        client.selectNearest()
        self.assertEqual(self.status(window), (None, True, True))
        # Admitted: one npc_talk request to the selected NPC, said aloud by the character (no chat in solo).
        # (Clock not advanced before this request: the bridge ignores a request dated in the future.)
        self.send(window, '  ' + self.TEXT + '  ')
        reqs = talk_requests(game.g)
        self.assertEqual(len(reqs), 1)
        req = reqs[0]
        npc = server.store.data.npcs[client.snapshot.selected]
        self.assertEqual((req.text, req.channel, req.language, req.npc, req.character),
                         (self.TEXT, 'say', 'FR', npc.id, client.character))
        self.assertEqual(req.context.name, 'Real Bandit')
        # E17-T08: first contact, a stranger: no offer even when asked.
        self.assertEqual((req.context.stage, list(req.offers.keys())), ('stranger', []))
        self.assertEqual(lua_list(player.said), [self.TEXT])
        self.assertEqual(lua_list(game.g.SAID_CHAT), [], 'solo must not use the chat')
        self.assertEqual(window.speak.getText(window.speak), '')
        self.assertEqual(self.status(window), ('IGUI_RS_TalkWaiting', False, False))
        self.send(window, 'second sentence while waiting')
        self.assertEqual(len(talk_requests(game.g)), 1)
        # The NPC answers through the offline bridge: bubble over its body, line kept in the notebook history.
        self.process = start_bridge(self.path / 'solo')
        self.assertTrue(pump(lambda: len(zombie.bubbles) > 0, [lambda: game.g.fire('OnTickEvenPaused')]),
                        'offline reply never reached the solo player')
        self.assertIsNone(client.waiting)
        contact = client.snapshot.contacts[1]
        history = [(h.author, h.text) for h in contact.history.values()]
        self.assertEqual(history[0], ('solo Doe', self.TEXT))
        self.assertEqual(history[1], ('Real Bandit', zombie.bubbles[1]))
        self.assertIn(zombie.bubbles[1].split(' ')[0], window.detail.text)
        self.assertEqual(self.status(window)[0], 'IGUI_RS_Error_Cooldown')
        clock.offset += 11000
        self.assertEqual(self.status(window), (None, True, True))
        # Refusal: too far. The line is greyed; a client bypassing it is refused by the server (Range), never said.
        zombie.x = 100
        client.send('snapshot')
        self.assertEqual(self.status(window), ('IGUI_RS_TalkOutOfRange', False, False))
        self.send(window, 'too far')
        self.assertEqual(len(talk_requests(game.g)), 0)
        self.assertTrue(client.talk('forced far', True))
        self.assertEqual((len(talk_requests(game.g)), client.lastError, client.waiting), (0, 'Range', None))
        self.assertEqual(lua_list(player.said), [self.TEXT], 'refused sentence said aloud')
        self.assertEqual(client.snapshot.selected, '', 'server keeps a target out of range')
        logs = lua_list(game.g.LOGS)
        self.assertFalse([line for line in logs if 'error' in line.lower()], logs)

    def test_mp_say_line_matches_the_chat_and_never_doubles(self):
        sim = Simulation(self.path / 'mp')
        alice, bob = sim.add_client('alice'), sim.add_client('bob')
        sim.select('alice'); sim.select('bob')
        window = open_notebook(alice)
        self.assertEqual(self.status(window), (None, True, True))
        # Notebook sentence: one request, then said aloud once by the vanilla chat (never captured again).
        self.send(window, self.TEXT)
        reqs = talk_requests(sim.server.g)
        self.assertEqual(len(reqs), 1)
        self.assertEqual(lua_list(alice.g.SAID_CHAT), [self.TEXT])
        self.assertEqual(self.status(window), ('IGUI_RS_TalkWaiting', False, False))
        # The same sentence in the chat (bob): same request, field by field, except the sender.
        sim.say('bob', '/say ' + self.TEXT)
        reqs = talk_requests(sim.server.g)
        self.assertEqual(len(reqs), 2)
        own = ('id', 'order', 'character', 'sent')

        def shape(r):
            d = convert(r)
            for k in own:
                d.pop(k)
            d['context'].pop('caller')
            return d
        self.assertEqual(shape(reqs[0]), shape(reqs[1]))
        self.assertEqual((reqs[0].character, reqs[1].character), (sim.character('alice'), sim.character('bob')))
        self.assertEqual((reqs[0].context.caller, reqs[1].context.caller), ('alice Doe', 'bob Doe'))
        # Alice speaks in the chat while her notebook sentence is awaited: that sentence only, never twice.
        sim.clock.offset += 11000
        sim.say('alice', '/say Et des munitions ?')
        self.assertEqual([r.text for r in talk_requests(sim.server.g)], [self.TEXT, self.TEXT, 'Et des munitions ?'])
        self.assertEqual(lua_list(alice.g.SAID_CHAT).count(self.TEXT), 1)
        self.assertEqual(self.status(window)[0], 'IGUI_RS_TalkWaiting')
        # Fake engine: group id '1' without a readable name -> no group line, never the identifier.
        self.assertNotIn('IGUI_RS_Group', window.detail.text)
        self.assertIsNone(alice.g.RS_CarnetClient.snapshot.contacts[1].clan)
        # Multi-line private note: Java text box set after addChild; line breaks kept by the server.
        self.assertEqual((window.note.javaObject.multipleLine, window.note.javaObject.maxLines), (True, 4))
        npc = alice.g.RS_CarnetClient.snapshot.selected
        sim.command('alice', 'note', npc=npc, text='Ligne 1\nLigne 2\r\nLigne 3\tfin')
        self.assertEqual(alice.g.RS_CarnetClient.snapshot.contacts[1].note, 'Ligne 1\nLigne 2\nLigne 3 fin')

    def test_client_sends_the_real_game_language(self):
        """E17-T11: the Say line sends Translator.getLanguage():name() as is (game in Spanish -> ES, Brazilian
        Portuguese -> PTBR), not FR or EN; a malformed name falls back to EN on the client already."""
        clock = Clock()
        game, _, _ = solo_game(self.path / 'solo', clock)
        client, server = game.g.RS_CarnetClient, game.g.RS_CarnetServer
        client.selectNearest()
        sent = []
        for name in ('ES', 'PTBR', 'bad code'):
            game.rt.execute("local n = ...; Translator = {getLanguage = function() return {name = function() return n end} end}",
                            name)
            server.lastTalk[client.character] = None
            server.pending = game.rt.table_from({})
            client.waiting = None
            self.assertTrue(client.talk('Hola'))
            reqs = talk_requests(game.g)
            self.assertEqual(len(reqs), 1, name)
            sent.append(reqs[0].language)
        self.assertEqual(sent, ['ES', 'PTBR', 'EN'])


class PlayerSpeechTests(unittest.TestCase):
    """LK11-T09 : une phrase dite par une ligne « Dire » du carnet (onglet Radio : RS_RadioTalk.handle ; onglet
    Contacts : RS_CarnetClient.receive) s'affiche UNE fois au-dessus du personnage, après acceptation par le serveur,
    jamais sur refus. Solo : player:Say (IsoGameCharacter.java:6655-6660, 6686-6688 -> ChatManager.showInfoMessage ->
    SayChat.showMessage -> RangeBasedChat.showInSpeechBubble : ChatElement du joueur) ; client MP : processSayMessage
    seul (le chat « dire » affiche déjà la bulle localement, base ui-windows.md), jamais les deux. Doublures : Say et
    processSayMessage notés ; ne prouve pas l'affichage en jeu."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-player-speech-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def radio(self, mode):
        game = Game(mode, self.path / mode, Clock())
        player = game.g.makePlayer('kate')
        game.g.getPlayer = lambda: player
        game.g.getSpecificPlayer = lambda n: player
        talk = game.g.require('RadioSurvivor/RS_RadioTalk')
        return game, player, talk, game.g.require('RadioSurvivor/RadioSurvivor_Const').CMD

    def test_radio_tab_sentence_shown_once_after_acceptance_never_on_refusal(self):
        for mode in ('solo', 'client'):
            game, player, talk, cmd = self.radio(mode)
            talk.handle(cmd.REJECTED, game.rt.table_from({'reason': 'Cooldown'}))
            self.assertEqual((lua_list(player.said), lua_list(game.g.SAID_CHAT)), ([], []), mode)
            talk.handle(cmd.ACCEPTED, game.rt.table_from({'text': 'Ici Kate.'}))
            talk.handle(cmd.DONE, game.rt.table_from({}))
            said = (['Ici Kate.'], []) if mode == 'solo' else ([], ['Ici Kate.'])
            self.assertEqual((lua_list(player.said), lua_list(game.g.SAID_CHAT)), said, mode)

    def test_contacts_tab_sentence_shown_once_after_queued_never_on_refusal(self):
        game, player, _ = solo_game(self.path / 'solo', Clock())
        client = game.g.RS_CarnetClient
        receive = lambda command, args: client.receive(command, game.rt.table_from(args))
        client.waiting = game.rt.table_from({'at': 0, 'npc': 'x', 'text': 'Bonjour.'})
        receive('error', {'reason': 'Range'})                                   # refus : jamais dit
        self.assertEqual(lua_list(player.said), [])
        client.waiting = game.rt.table_from({'at': 0, 'npc': 'x', 'text': 'Bonjour.'})
        receive('queued', {'id': 'r1'})
        receive('queued', {'id': 'r1'})                                         # accusé répété : une seule fois
        self.assertEqual(lua_list(player.said), ['Bonjour.'])
        client.waiting = game.rt.table_from({'at': 0, 'npc': 'x'})              # phrase du chat : déjà dite
        receive('queued', {'id': 'r2'})
        self.assertEqual((lua_list(player.said), lua_list(game.g.SAID_CHAT)), (['Bonjour.'], []))


TESTS_SHARED = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / 'shared'
IDENTITY_SUITE =TESTS_SHARED / 'RST' / 'suites' / 'RS_Identity.lua'


PROBE_TEMPLATE = """
local Config = require('RadioSurvivor/RS_Config')
local M = require('RadioSurvivor/RS_Missions')
Config.Missions.probe = {id = 'probe_v1', titleKey = 'IGUI_RS_Probe', durationMs = 1000, needed = 2,
    rewardType = 'Base.Bullets9mm', rewardCount = 2}
PROBE_CALLS = {}
M.register('probe', {
    idPrefix = 'probe',
    offer = function(c) return {needed = c.needed, durationMs = c.durationMs} end,
    create = function(m, c) m.needed, m.done = c.needed, 0 end,
    check = function(m, player, payload)
        if payload ~= 'ok' then return nil, 'Items' end
        return {n = 1}
    end,
    prepare = function(m, e) return {kind = 'probe', before = m.done} end,
    apply = function(m, e) PROBE_CALLS[#PROBE_CALLS + 1] = 'apply:' .. m.transaction.stage end,
    progress = function(m, e) m.done = m.done + e.n; return e.n, m.done == m.needed end,
    complete = function(state, m) PROBE_CALLS[#PROBE_CALLS + 1] = 'complete:' .. m.state end,
    project = function(m, p) p.needed, p.done = m.needed, m.done end,
    context = function(m, ctx) ctx.needed = m.needed end,
})
"""


# Living Knox world of LivingKnoxCarnetTests: settlers grp-1 whose story (seed 77) keeps its secrets on the server,
# exact home (10637, 9412) never to be told; food short (20: one offer of 60 V), medical high (80: reward reserve).
LK_WORLD = r'''
local G, S = LivingKnox.Groups, LivingKnox.Stories
LK_STORY = assert(S.compose('settlers', 77))
local g = assert(G.create({type = 'settlers', name = LK_STORY.leader.name, story = LK_STORY.summary.en, storySeed = 77,
    home = {x = 10637, y = 9412, z = 0}, day = 2}))
LK_GROUP = g.id
assert(G.setNeed(g.id, 'food', 20)); assert(G.setNeed(g.id, 'medical', 80)); assert(G.setNeed(g.id, 'ammo', 50))
LK_LEADER = lkNpc(12, g.id, 'worker', {leader = true, female = LK_STORY.leader.female, traits = {'smoker', 'drinker'}})
LK_MATE = lkNpc(14, g.id, 'fighter')
local raiders = assert(G.create({type = 'raiders', name = 'Crows', day = 3}))
LK_RAIDERS = raiders.id
LK_RAIDER = lkNpc(16, raiders.id, 'fighter')
LK_LONER = lkNpc(18)
'''


class LivingKnoxCarnetTests(unittest.TestCase):
    """E17-T03 : parcours du carnet 0.2 rejoué avec un PNJ de Living Knox (vrai moteur : registres, API, corps,
    histoires, attitudes ; vrai fournisseur RS_LivingKnox.lua ; vrai pont hors ligne) : sélection Ctrl+G sur la copie
    cliente, conversation avec le contexte public du groupe, offre M01 tirée d'un besoin réel, acceptation, livraisons
    en points de valeur qui remontent la réserve une seule fois, réputation et fait d'attitude, lot du moteur, mort du
    PNJ qui ferme la fiche ; aucun secret ni foyer exact dans les requêtes. Doublures : ne prouve pas l'API Java."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-carnet-lk-')
        self.path = Path(self.tmp.name)
        self.process = None

    def tearDown(self):
        if self.process:
            self.process.terminate()
            self.process.communicate(timeout=10)
        self.tmp.cleanup()

    def world(self, name='lk'):
        sim = Simulation(self.path / name, living_knox=True)
        sim.server.rt.execute(LK_WORLD)
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.api = self.rt.eval('LivingKnox.API')
        return sim

    def tick(self):
        self.sim.clock.offset += 1001
        self.sim.tick()

    def food(self):
        return self.api.getGroup(self.g.LK_GROUP).needs.food

    def secrets(self):
        out = []
        for s in lua_list(self.g.LK_STORY.secrets):
            out += [s.en, s.fr]
        return out

    def ctrl_g(self, name, npc_id, online_id, x=12):
        client = self.sim.clients[name]
        client.rt.eval('lkCopy')(npc_id, online_id, x)
        client.g.RS_CarnetClient.selectNearest()
        return client

    def assert_private(self, value, where):
        text = json.dumps(convert(value), ensure_ascii=False)
        for secret in self.secrets():
            self.assertNotIn(secret, text, f'story secret in {where}')
        # Whole numbers only: a millisecond timestamp may contain these digits.
        self.assertNotRegex(text, r'(?<![0-9])10637(?![0-9])', f'exact home in {where}')
        self.assertNotRegex(text, r'(?<![0-9])9412(?![0-9])', f'exact home in {where}')

    def test_notebook_journey_with_a_living_knox_npc(self):
        sim = self.world()
        sim.add_client('alice')
        alice = sim.character('alice')
        leader = self.g.LK_LEADER
        # Selection by Ctrl+G on the client copy (roster onlineId of the guard): the server creates the fiche.
        client = self.ctrl_g('alice', leader, 5001)
        fiche = sim.server.g.RS_CarnetServer.find(leader)
        self.assertIsNotNone(fiche)
        self.assertEqual(client.g.RS_CarnetClient.snapshot.selected, fiche.id)
        self.assertEqual((fiche.incarnation, fiche.signature, fiche.clan), (leader, 'lk:' + leader, self.g.LK_GROUP))
        self.assertEqual(fiche.name, self.g.LK_STORY.leader.name, 'the leader carries the name of its story')
        self.assertTrue(fiche.personality.smoker and fiche.personality.alcoholic)
        self.assertTrue(client.g.RS_CarnetClient.snapshot.npcProvider)
        # Conversation: public context of the group, offer drawn from the real food need, nothing private.
        self.process = start_bridge(sim.path)
        sim.acquaint('alice') # E17-T08: the stranger stage is covered by AcquaintanceTests
        sim.say('alice', '/say Bonjour, avez-vous besoin de quelque chose ?')
        req = convert(sim.server.g.RS_CarnetServer.pending[1])
        group = req['context']['group']
        self.assertEqual(group['summary'], self.g.LK_STORY.summary.fr, 'public summary in the request language')
        self.assertEqual((group['group'], group['type'], group['leaderName'], group['isLeader'], group['role']),
                         (self.g.LK_STORY.leader.name, 'settlers', self.g.LK_STORY.leader.name, True, 'worker'))
        self.assertEqual(group['needs'], {'food': 20, 'medical': 80, 'ammo': 50})
        self.assertIn(group['attitude']['level'], ('hostile', 'wary', 'cautious', 'favorable', 'trusting'))
        self.assertNotIn('area', group)
        terms = req['offers']['first_aid_v1']
        self.assertEqual((terms['kind'], terms['unit'], terms['need'], terms['quantity'], terms['supply']),
                         ('supply', 'value', 'food', 60, self.g.LK_GROUP + '-food-1'))
        self.assertEqual((terms['rewardType'], terms['rewardCount']), ('Base.Antibiotics', 2))
        self.assertEqual(terms['values']['Base.TinnedBeans'], 2)
        self.assert_private(req, 'npc_talk request')
        # The request as written for the bridge (requests.txt), decoded by the bridge itself.
        _, records = bridge_module.read_requests(sim.path / 'requests.txt')
        decoded = [protocol.unpack_request(r) for r in records if r.get('kind') == 'npc_talk']
        self.assertEqual(len(decoded), 1)
        self.assertEqual(decoded[0]['context']['group']['summary'], self.g.LK_STORY.summary.fr)
        self.assert_private(decoded[0], 'bridge file')
        self.assertTrue(pump(lambda: count(sim.state().missions) == 1, [sim.tick]), 'offline reply never reached Lua')
        speech = [msg.text for msg in client.g.CHAT.shown.values() if msg.author == fiche.name]
        self.assertEqual(len(speech), 1)
        self.assertIn('manque de nourriture', speech[0], 'offline bridge text of a supply offer')
        m = sim.mission()
        self.assertEqual((m.template, m.unit, m.quantity, m.delivered, m.titleKey),
                         ('deliver', 'value', 60, 0, 'IGUI_RS_Supply_food'))
        self.assertEqual((m.supply.ref, m.supply.offer, m.rewardType, m.rewardCount),
                         (self.g.LK_GROUP, self.g.LK_GROUP + '-food-1', 'Base.Antibiotics', 2))
        sim.request_mission('alice', 'accept')
        view = client.g.RS_CarnetClient.snapshot.missions[1]
        self.assertEqual((view.unit, view.need, view.quantity, view['values']['Base.Rice']), ('value', 'food', 60, 2))
        # One item more than needed: refused before any effect (no marker, nothing removed, reserve unchanged).
        beans = sim.items('alice', *(['Base.TinnedBeans'] * 31))
        sim.confirm('alice', sim.quote('alice', beans))
        self.assertEqual(client.g.RS_CarnetClient.lastError, 'TooMany')
        self.assertIsNone(m.transaction)
        self.assertEqual((m.delivered, self.food(), len(sim.server.g.REMOVALS)), (0, 20, 0))
        # First delivery: 10 cans = 20 V, food 20 -> 25, once.
        quote = sim.quote('alice', beans[:10])
        sim.confirm('alice', quote)
        self.assertEqual((m.delivered, self.food(), len(sim.server.g.REMOVALS)), (20, 25, 10))
        replay = self.api.deliver(self.g.LK_GROUP, m.supply.offer, self.rt.table_from({'Base.TinnedBeans': 10}),
                                  quote['token'], alice)
        self.assertEqual((replay.duplicate, replay.applied, self.food()), (True, False, 25), 'receipt replayed')
        missions = self.rt.eval("require('RadioSurvivor/RS_Missions')")
        self.assertTrue(missions.deliver(sim.server.g.RS_CarnetServer.store, m, sim.server.g.PLAYERS.alice, alice,
                                         self.rt.table_from(beans[10:20]), quote['token']))
        self.assertEqual((m.delivered, self.food(), len(sim.server.g.REMOVALS)), (20, 25, 10), 'notebook replay')
        sim.confirm('alice', quote)  # quote already consumed
        self.assertEqual(client.g.RS_CarnetClient.lastError, 'State')
        self.assertEqual(count(sim.state().outcomes), 0, 'partial delivery must not apply reputation')
        # Last delivery: 20 cans = 40 V completes the offer: food 35, reward lot of the engine, reputation, attitude.
        before = self.api.attitude(self.g.LK_GROUP, alice).level
        sim.confirm('alice', sim.quote('alice', beans[10:30]))
        self.assertEqual((m.state, m.delivered, self.food()), ('success', 60, 35))
        self.assertEqual(self.api.getGroup(self.g.LK_GROUP).needs.medical, 76, 'reward taken from the medical reserve')
        self.assertEqual((m.rewardType, m.rewardCount), ('Base.Antibiotics', 2))
        self.assertEqual(count(sim.state().outcomes), 1)
        attitude = self.api.attitude(self.g.LK_GROUP, alice)
        self.assertEqual(attitude.trend, 'up', 'delivery fact recorded for the delivering character')
        self.assertGreaterEqual(['hostile', 'wary', 'cautious', 'favorable', 'trusting'].index(attitude.level),
                                ['hostile', 'wary', 'cautious', 'favorable', 'trusting'].index(before))
        open_ids = [o.id for o in lua_list(self.api.missionOffers(self.g.LK_GROUP))]
        self.assertNotIn(self.g.LK_GROUP + '-food-1', open_ids, 'completed offer closed by the engine')
        sim.request_mission('alice', 'claim')
        self.assertEqual(m.claimedBy, alice)
        given = [it.kind for it in sim.server.g.PLAYERS.alice.inv['items'].values()]
        self.assertEqual(given.count('Base.Antibiotics'), 2)
        self.assertEqual(given.count('Base.TinnedBeans'), 1)
        # E08-T07 observation of the requester: mission done by alice.
        obs = self.rt.eval("require('RadioSurvivor/RS_Observations')")
        done = [convert(o) for o in lua_list(obs.list(fiche.id))]
        self.assertEqual([(o['fact'], o['subject']) for o in done], [('mission_done', alice)])
        # Death of the NPC body: the engine marks it dead, the notebook closes the fiche, its group mate saw it.
        mate = sim.server.g.RS_CarnetServer.ensure(self.g.LK_MATE)
        self.tick()
        body = self.g.LivingKnox.Bodies.bound[leader]
        body.dead = True
        self.g.fire('OnZombieDead', body)
        self.assertFalse(fiche.alive)
        self.assertEqual(self.rt.eval('LivingKnox.Store.data()').npcs[leader].state, 'dead')
        seen = [convert(o) for o in lua_list(obs.list(mate.id))]
        self.assertEqual([(o['fact'], o['subject']) for o in seen], [('group_death', fiche.id)])
        contact = [c for c in client.g.RS_CarnetClient.snapshot.contacts.values() if c.id == fiche.id][0]
        self.assertFalse(contact.alive)
        self.assertEqual(sim.server.g.RS_CarnetServer.find(leader).id, fiche.id, 'fiche kept, closed')

    def test_stranger_never_learns_the_group_nor_its_home(self):
        """E17-T08: first greeting of a Living Knox NPC: no group name, leader, public story, needs nor offer in the
        request or the prompt; the background stays private (known, never recited)."""
        sim = self.world('lk-stranger')
        sim.add_client('alice')
        leader = self.g.LK_LEADER
        self.ctrl_g('alice', leader, 5001)
        fiche = sim.server.g.RS_CarnetServer.find(leader)
        fiche.background = 'Chef du groupe, installe a l eglise baptiste de Riverside.'
        sim.say('alice', '/say Salut')
        req = convert(sim.server.g.RS_CarnetServer.pending[1])
        self.assertEqual((req['context']['stage'], req['offers']), ('stranger', {}))
        group = req['context']['group']
        self.assertEqual(set(group) - {'member', 'role', 'attitude'}, set(), group)
        system = protocol.prompt(req, [])[0]['content']
        story = self.g.LK_STORY
        for private in (story.summary.fr, story.summary.en, story.leader.name):
            if fiche.name != private: # the NPC's own name may be said, its leader's or story's never sent
                self.assertNotIn(private, system)
        self.assertIn('Your background is private knowledge: never recite it.', system)
        self.assertIn('nor where you live or shelter', system)
        self.assert_private(req, 'stranger request')

    def test_notebook_shows_the_group_name_never_its_id(self):
        """E17-T06: the contact page names the Living Knox group (name of the registry), never "grp-<n>"; nothing
        for an NPC without a group."""
        sim = self.world('groupname')
        sim.add_client('alice')
        client = self.ctrl_g('alice', self.g.LK_LEADER, 5001)
        leader = sim.server.g.RS_CarnetServer.find(self.g.LK_LEADER)
        self.assertEqual(leader.clan, self.g.LK_GROUP)
        self.assertEqual(leader.groupName, self.g.LK_STORY.leader.name)
        window = open_notebook(client)
        contact = [c for c in client.g.RS_CarnetClient.snapshot.contacts.values() if c.id == leader.id][0]
        self.assertEqual(contact.groupName, self.g.LK_STORY.leader.name)
        self.assertIsNone(contact.clan, 'raw group id sent to the client')
        self.assertIn('IGUI_RS_Group|' + self.g.LK_STORY.leader.name, window.detail.text)
        self.assertNotIn('grp-', window.detail.text)
        # A groupless NPC: no group line at all.
        self.g.LivingKnox.Bodies.bound[self.g.LK_LONER].x = 12
        sim.command('alice', 'select', incarnation=self.g.LK_LONER)
        loner = sim.server.g.RS_CarnetServer.find(self.g.LK_LONER)
        self.assertEqual(client.g.RS_CarnetClient.snapshot.selected, loner.id)
        window.selectedId = loner.id
        window.showDetail(window)
        self.assertEqual(window.row.groupName, '')
        self.assertNotIn('IGUI_RS_Group', window.detail.text)
        self.assertNotIn('grp-', window.detail.text)

    def test_in_game_suite_on_the_simulated_server(self):
        """rs.carnet.lk and rs.carnet.lk.supply (dev mod) run by the real RST engine on the simulated server (test
        save "rstest-lk"; item scripts: every Base.* type known)."""
        sim = Simulation(self.path / 'suite', living_knox=True)
        sim.server.rt.execute(LK_WORLD)
        sim.add_client('alice')
        shared = (ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / 'shared').as_posix()
        sim.server.rt.execute(f'package.path = [[{shared}/?.lua;]] .. package.path')
        sim.server.rt.execute("""
            getScriptManager = function() return {FindItem = function(_, t)
                if string.find(t, '^Base%.') then return {} end end} end
            getWorld = function() return {getGameMode = function() return 'Multiplayer' end,
                getWorld = function() return 'rstest-lk' end} end
            require 'RST/RST'
            require 'RST/RST_Fixtures'
            RST.Fixtures.WAIT_LOADED = false   -- no cell squares in this double: moves do not wait for them
        """)
        suite = ROOT / 'dev' / 'batman_RadioSurvivorTests' / '42.21' / 'media' / 'lua' / 'shared' / 'RST' / 'suites'
        sim.server.rt.execute((suite / 'RS_CarnetLK.lua').read_text(encoding='utf-8'))
        report = sim.server.rt.eval('RST.runSync("rs.carnet.lk")')
        results = {(r.suite, r.test): r.status for r in report.results.values()}
        self.assertEqual(set(results.values()), {'PASS'}, {k: (r.status, r.message) for k, r in
                                                           ((x.test, x) for x in report.results.values())})
        self.assertEqual(len(results), 5)

    def test_hostile_groupless_or_satisfied_npc_offers_no_supply(self):
        sim = self.world('none')
        sim.add_client('alice')
        alice = sim.character('alice')
        server = sim.server.g.RS_CarnetServer
        provider = self.rt.eval("require('RadioSurvivor/RS_NPCProvider')")
        for npc_id, hostile in ((self.g.LK_RAIDER, True), (self.g.LK_LONER, None)):
            fiche = server.ensure(npc_id)
            self.assertEqual(provider.npc(npc_id).hostile, hostile)
            self.assertEqual(convert(server.offerCatalogFor(fiche, provider.npc(npc_id), alice)), {}, npc_id)
        self.assertEqual(server.ensure(self.g.LK_RAIDER).clan, self.g.LK_RAIDERS)
        self.assertEqual(server.ensure(self.g.LK_LONER).clan, '')
        # No need below the threshold: no `deliver` offer at all (the static first-aid catalogue is not offered).
        self.rt.execute('assert(LivingKnox.Groups.setNeed(LK_GROUP, "food", 50))')
        fiche = server.ensure(self.g.LK_LEADER)
        self.assertNotIn('first_aid_v1', convert(server.offerCatalogFor(fiche, provider.npc(self.g.LK_LEADER), alice)) or {})
        missions = self.rt.eval("require('RadioSurvivor/RS_Missions')")
        self.assertIsNone(missions.create(sim.state(), fiche, alice, 'first_aid_v1'))
        # Context of a groupless NPC: nothing about a group.
        self.assertEqual(convert(provider.context(self.g.LK_LONER, alice, 'EN')), {'member': False})

    def test_offer_closed_by_the_engine_cancels_without_penalty(self):
        sim = self.world('closed')
        sim.add_client('alice')
        alice = sim.character('alice')
        server = sim.server.g.RS_CarnetServer
        provider = self.rt.eval("require('RadioSurvivor/RS_NPCProvider')")
        fiche = server.ensure(self.g.LK_LEADER)
        terms = server.offerCatalogFor(fiche, provider.npc(self.g.LK_LEADER), alice).first_aid_v1
        missions = self.rt.eval("require('RadioSurvivor/RS_Missions')")
        m = missions.create(sim.state(), fiche, alice, 'first_aid_v1', terms)
        sim.state().characters[alice].knownMissions[m.id] = True
        sim.request_mission('alice', 'accept')
        self.tick()
        self.assertEqual(m.state, 'active')
        self.g.WORLD_HOURS = self.g.WORLD_HOURS + 48  # the engine offer expires in game time
        sim.clock.offset += 10001
        self.tick()
        self.assertEqual(m.state, 'cancelled_closed')
        self.assertEqual(count(sim.state().outcomes), 0, 'closed engine offer penalized participants')
        self.assertIsNone(fiche.mission)
        # A delivery on a closed offer is refused before any effect.
        self.assertEqual(missions.deliver(server.store, m, sim.server.g.PLAYERS.alice, alice,
                                          self.rt.table_from(sim.items('alice', 'Base.Rice')), 'tok-1'), (False, 'State'))

    def test_one_npc_engine_disabled_or_other_provider(self):
        # Disabled in the sandbox: nothing registered, the notebook keeps "No NPC engine active".
        game = Game('server', self.path / 'off2', Clock())
        game.rt.execute(STUBS)
        game.g.LK_ENABLED = False
        game.rt.execute(LK_SERVER_STUBS)
        game.rt.execute(LK_SERVER_LOAD)
        game.g.fire('OnInitGlobalModData', False)
        provider = game.rt.eval("require('RadioSurvivor/RS_NPCProvider')")
        self.assertEqual((provider.active().name, provider.available()), ('none', False))
        # Another NPC engine already registered: Living Knox is not a second provider, a warning names the active one.
        other = Game('server', self.path / 'other', Clock())
        other.rt.execute(STUBS)
        other.g.registerFakeProvider()
        other.rt.execute(LK_SERVER_STUBS)
        other.rt.execute(LK_SERVER_LOAD)
        other.g.fire('OnInitGlobalModData', False)
        provider = other.rt.eval("require('RadioSurvivor/RS_NPCProvider')")
        self.assertEqual(provider.active().name, 'fake')
        self.assertIn('[RS_LivingKnox] another NPC provider (fake) is active: Living Knox is not registered in the '
                      'notebook (one NPC engine per server)', lua_list(other.g.LOGS))
        self.assertFalse(other.g.LivingKnox.Bodies.onDied)


class AcquaintanceTests(unittest.TestCase):
    """E17-T08 : faire connaissance avant de se dévoiler et de proposer une mission. Stade tenu par le serveur par PNJ et
    par personnage (inconnu, puis connu après une reprise de conversation une heure de jeu plus tard ou 4 échanges
    répondus), offres seulement au stade connu et sur demande d'aide ou de travail, consignes du prompt, présentation
    d'enrichissement hors de la mémoire du pont. Vrai serveur Lua, vrai pont hors ligne ; doublures du banc carnet."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-acquaint-')
        self.path = Path(self.tmp.name)
        self.process = None

    def tearDown(self):
        if self.process:
            self.process.terminate()
            self.process.communicate(timeout=10)
        self.tmp.cleanup()

    def start(self):
        sim = Simulation(self.path / 'game')
        sim.add_client('alice')
        sim.select('alice')
        self.process = start_bridge(sim.path)
        self.sim, self.server = sim, sim.server.g.RS_CarnetServer
        return sim

    def known(self):
        return next(iter(self.sim.state().characters[self.sim.character('alice')].contacts.values()))

    def exchange(self, text):
        """One sentence of alice, answered by the offline bridge. Returns the npc_talk request (Python dict) and the
        prompt the bridge builds for it."""
        sim = self.sim
        # Cooldown cleared instead of advancing the clock (the bridge refuses a request dated ahead).
        self.server.lastTalk[sim.character('alice')] = None
        before = self.known().exchanges or 0
        # The talk command itself (the vanilla chat double has its own slow mode tied to the clock).
        sim.command('alice', 'talk', channel='say', text=text, language='FR')
        reqs = talk_requests(sim.server.g)
        self.assertEqual(len(reqs), 1, text)
        req = convert(reqs[0])
        self.assertTrue(pump(lambda: (self.known().exchanges or 0) == before + 1, [sim.tick]), 'no reply: ' + text)
        system = protocol.prompt(req, [])[0]['content']
        return req, system

    def test_stranger_then_acquainted_after_an_hour(self):
        sim = self.start()
        sim.server.g.WORLD_AGE_HOURS = 30
        req, system = self.exchange('Salut')
        self.assertEqual((req['context']['stage'], req['offers']), ('stranger', {}))
        self.assertIn('Never say the name of your group', system)
        self.assertIn('Offer no mission', system)
        self.assertNotIn('you may offer one admissible mission', system)
        known = self.known()
        self.assertEqual((known.stage, known.exchanges, known.firstHour), ('stranger', 1, 30))
        # Still a stranger: whatever the sentence, no catalog is sent (server fact), and no mission is created.
        req, _ = self.exchange("Vous avez besoin d'aide ?")
        self.assertEqual((req['context']['stage'], req['offers']), ('stranger', {}))
        self.assertEqual(count(sim.state().missions), 0)
        # Second meeting one game hour after the first exchange: acquainted. E17-T10: the catalog is sent with every
        # sentence; the model alone judges whether the player asks for help or work (prompt rule, any language). The
        # offline bridge stands for a model that offers: the server creates the offer.
        sim.server.g.WORLD_AGE_HOURS = 31
        req, system = self.exchange("Vous avez besoin d'aide ?")
        self.assertEqual(req['context']['stage'], 'acquainted')
        self.assertIn('first_aid_v1', req['offers'])
        self.assertIn('Offer one admissible mission (intent offer) only if their latest sentence', system)
        self.assertNotIn('Never say the name of your group', system)
        self.assertEqual(count(sim.state().missions), 1)
        self.assertEqual(sim.mission().state, 'offer')
        # Acquaintance is kept for good, even back at an earlier hour.
        sim.server.g.WORLD_AGE_HOURS = 30
        self.server.lastTalk[sim.character('alice')] = None
        sim.command('alice', 'talk', channel='say', text='Salut', language='FR')
        self.assertEqual(talk_requests(sim.server.g)[0].context.stage, 'acquainted')

    def test_acquainted_after_four_answered_exchanges_and_state_saved(self):
        sim = self.start()
        for _ in range(4):
            req, _ = self.exchange('Il fait chaud aujourd hui.')
            self.assertEqual((req['context']['stage'], req['offers']), ('stranger', {}))
        req, _ = self.exchange('On peut parler ?')
        self.assertEqual(req['context']['stage'], 'acquainted')
        self.assertTrue(req['offers'], 'acquainted: catalog sent with the sentence')
        # Persisted with the contact: a restarted server keeps the stage.
        restart = Simulation(sim.path, sim.clock, saved_players=sim.saved())
        restart.add_client('alice')
        known = next(iter(restart.state().characters[restart.character('alice')].contacts.values()))
        self.assertEqual((known.stage, known.exchanges), ('acquainted', 5))

    def test_participant_of_a_mission_of_this_npc_is_acquainted(self):
        """Contacts saved before E17-T08 (no stage) with a mission of this NPC: never brought back to stranger."""
        sim = self.start()
        known = self.known()
        known.stage, known.exchanges = None, None
        npc = next(iter(sim.state().npcs.values()))
        missions = sim.server.rt.eval("require('RadioSurvivor/RS_Missions')")
        record = sim.server.rt.eval("require('RadioSurvivor/RS_NPCProvider')").npc(2001)
        terms = sim.server.g.RS_CarnetServer.offerCatalogFor(npc, record).first_aid_v1
        missions.create(sim.state(), npc, sim.character('alice'), 'first_aid_v1', terms)
        sim.request_mission('alice', 'accept')
        req, _ = self.exchange('Salut')
        self.assertEqual(req['context']['stage'], 'acquainted')

    def test_openness_follows_the_personality(self):
        self.assertEqual(protocol.openness({'style': 'Helpful', 'sociability': 3}), 'open')
        self.assertEqual(protocol.openness({'style': 'Direct', 'sociability': 5}), 'open')
        self.assertEqual(protocol.openness({'style': 'Prudent', 'sociability': 3}), 'wary')
        self.assertEqual(protocol.openness({'style': 'Reserved', 'sociability': 1}), 'wary')
        self.assertEqual(protocol.openness({'style': 'Prudent', 'sociability': 4}), 'reserved')
        self.assertEqual(protocol.openness({}), 'reserved')
        base = {'kind': 'npc_talk', 'language': 'FR', 'character': 'c-1', 'revision': 1, 'offers': {}, 'text': 'Salut',
                'context': {'stage': 'stranger'}}
        open_prompt = protocol.prompt(dict(base, personality={'style': 'Helpful', 'sociability': 4}), [])[0]['content']
        wary_prompt = protocol.prompt(dict(base, personality={'style': 'Prudent', 'sociability': 1}), [])[0]['content']
        self.assertIn('first and last name', open_prompt)
        self.assertIn('stay vague about yourself', wary_prompt)
        # A request of an older server (no stage) keeps the prompt unchanged; an enrichment never gets these rules.
        old = protocol.prompt(dict(base, personality={}, context={}), [])[0]['content']
        enrich = protocol.prompt(dict(base, kind='npc_enrich', personality={}), [])[0]['content']
        self.assertNotIn('Acquaintance', old)
        self.assertNotIn('Acquaintance', enrich)

    def test_enrichment_never_enters_the_bridge_memory(self):
        """The generated presentation ("Describe your background.") is the fiche's background, not a past reply: the
        model must not see it as something it already said to the player at a first meeting."""
        conv = bridge_module.NpcConversations(self.path)
        base = {'version': 2, 'world': 'w', 'run': 'r', 'npc': 'npc-1', 'revision': 1, 'channel': 'say',
                'language': 'FR', 'personality': {}, 'offers': {}, 'sent': 1}
        enrich = dict(base, kind='npc_enrich', id='r-1-npc-1', order=1, character='system',
                      text='Describe your background.', context={'name': 'Daryl Velez'})
        reply = conv.propose({'OFFLINE': '1'}, enrich)
        self.assertTrue(conv.acknowledge({'request': enrich['id'], 'world': 'w', 'run': 'r', 'npc': 'npc-1', 'order': 1,
                                          'revision': 1, 'status': 'accepted', 'applied': {}}))
        self.assertEqual(conv.load(enrich)['messages'], [], 'enrichment kept as a spoken turn')
        self.assertTrue(reply['background'])
        # Journals written before E17-T08: the enrichment turn is skipped when the history is sent to the model.
        old = [{'role': 'user', 'content': 'system: Describe your background.'},
               {'role': 'assistant', 'content': "Je m'appelle Daryl Velez, du groupe de Sasha Rhee."},
               {'role': 'user', 'content': 'character-1: Salut'},
               {'role': 'assistant', 'content': 'Salut.'}]
        self.assertEqual(protocol.talk_history(old), old[2:])

    def test_real_game_language_reaches_the_bridge(self):
        """E17-T11: the game language code of the client is sent as is (checked by its form, no list of known
        languages); an invalid code falls back to EN. The bridge names the language in the prompt when it knows it,
        otherwise gives the code; the offline reply is in French for FR, in English for any other code."""
        sim = self.start()
        config = sim.server.rt.eval("require('RadioSurvivor/RS_Config')")
        for given, expected in (('ES', 'ES'), ('es_cl', 'ES_CL'), ('PTBR', 'PTBR'), ('STREW', 'STREW'), ('FR', 'FR'),
                                ('E', 'EN'), ('E1', 'EN'), ('_ES', 'EN'), ('ABCDEFGHI', 'EN'), ('FR;EN', 'EN'),
                                ('', 'EN'), (None, 'EN'), (42, 'EN')):
            self.assertEqual(config.languageCode(given), expected, repr(given))
        sent = []
        for number, given in enumerate(('ES', 'xx-1'), 1):
            self.server.lastTalk[sim.character('alice')] = None
            sim.command('alice', 'talk', channel='say', text='Hola, ¿qué tal?', language=given)
            reqs = talk_requests(sim.server.g)
            self.assertEqual(len(reqs), 1, given)
            sent.append(convert(reqs[0]))
            self.assertTrue(pump(lambda: (self.known().exchanges or 0) == number, [sim.tick]), 'no reply: ' + given)
        self.assertEqual([r['language'] for r in sent], ['ES', 'EN'])
        es = sent[0]
        self.assertEqual(protocol.unpack_request(envelope(es))['language'], 'ES')
        system = protocol.prompt(es, [])[0]['content']
        self.assertIn('answer in Spanish (Spain) (the language of their game)', system)
        self.assertIn('Answer in the language the character uses in their latest sentence', system)
        # A language added by a mod: unknown name, the code is given to the model as is.
        self.assertIn('the language whose game code is ZZ_MOD',
                      protocol.prompt(dict(es, language='ZZ_MOD'), [])[0]['content'])
        self.assertIn('answer in Spanish (Argentina)', protocol.prompt(dict(es, language='AR'), [])[0]['content'])
        # Offline: French text only for FR, English otherwise (the sentence itself is never read).
        stranger = dict(es, offers={})
        self.assertEqual(protocol.offline(stranger)['text'], "I'm listening. The notebook terms remain fixed.")
        self.assertEqual(protocol.offline(dict(stranger, language='FR'))['text'],
                         'Je vous écoute. Les conditions du carnet restent fixes.')
        for bad in ('es', 'E', 'ABCDEFGHI', 'FR;EN', '_ES'):
            with self.assertRaises(ValueError): protocol.unpack_request(envelope({**request(), 'language': bad}))


class SpokenAcceptanceTests(unittest.TestCase):
    """E17-T09, E17-T10 : une offre d'un PNJ s'accepte en lui répondant (intention `accept` rendue par le modèle,
    revérifiée par le serveur : offre ouverte, même PNJ, même personnage, même révision) ou par le bouton ; un message à
    l'écran signale chaque nouvelle offre. Vrai serveur Lua, vrai pont hors ligne (drapeau de banc `RS_OFFLINE_INTENT`
    pour un modèle qui accepte) ; doublures du banc carnet."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-accept-')
        self.path = Path(self.tmp.name)
        self.process = None

    def tearDown(self):
        if self.process:
            self.process.terminate()
            self.process.communicate(timeout=10)
        self.tmp.cleanup()

    def start(self, intent=''):
        sim = Simulation(self.path / 'game')
        sim.add_client('alice')
        sim.select('alice')
        sim.acquaint('alice')
        self.process = start_bridge(sim.path, intent)
        self.sim, self.server = sim, sim.server.g.RS_CarnetServer
        return sim

    def say(self, text):
        """One sentence of alice to her selected NPC, answered by the offline bridge. Returns the request (dict)."""
        sim = self.sim
        self.server.lastTalk[sim.character('alice')] = None
        sim.command('alice', 'talk', channel='say', text=text, language='FR')
        [req] = talk_requests(sim.server.g)
        rid = req.id
        self.assertTrue(pump(lambda: not any(r.id == rid for r in self.server.pending.values()), [sim.tick]),
                        'no reply: ' + text)
        req = convert(req)
        self.assertTrue(sim.clients['alice'].g.RS_CarnetClient.seen[rid], 'reply not said: ' + text)
        return req

    def offer_signals(self):
        return lua_list(self.sim.clients['alice'].g.getPlayer().halos).count('IGUI_RS_NewOffer')

    def test_model_accept_takes_the_open_offer_once(self):
        sim = self.start('accept')
        req = self.say("Vous avez besoin d'aide ?")
        self.assertNotIn('acceptable', req['context'])
        m = sim.mission()
        self.assertEqual((m.state, count(m.participants), self.offer_signals()), ('offer', 0, 1))
        revision = m.revision
        req = self.say("D'accord, je m'en occupe.")
        self.assertEqual(req['context']['acceptable'], {'mission': m.id, 'revision': revision})
        self.assertEqual(m.state, 'active')
        self.assertEqual(list(convert(m.participants)), [sim.character('alice')])
        row = convert(sim.clients['alice'].g.RS_CarnetClient.snapshot.missions[1])
        self.assertEqual((row['state'], row['engaged']), ('active', True))
        self.assertEqual(self.offer_signals(), 1, 'an acceptance signalled a new offer')
        # The bridge took the acknowledgement carrying the acceptance (applied.accept = this mission) as applied: the
        # turn is committed and enters the NPC memory.
        memory = bridge_module.NpcConversations(sim.path)
        self.assertTrue(pump(lambda: req['id'] in memory.load(req)['committed'], [sim.tick]), 'acceptance ack refused')
        self.assertIn("je m'en occupe", json.dumps(memory.load(req)['messages'], ensure_ascii=False))
        # A second yes: no open offer any more, nothing applied again.
        revision = m.revision
        req = self.say('Oui, ok.')
        self.assertNotIn('acceptable', req['context'])
        self.assertEqual((m.revision, count(m.participants)), (revision, 1))

    def test_offer_of_another_npc_is_not_acceptable_and_the_button_stays(self):
        sim = self.start('accept')
        req = self.say("Vous avez besoin d'aide ?")
        self.assertNotIn('acceptable', req['context'])
        m = sim.mission()
        # Said to another NPC (second body, still a stranger): no acceptable offer in the request, nothing applied.
        sim.server.g.spawn(2002, 'Other Bandit', False, 'other-key')
        sim.command('alice', 'select', incarnation=2002)
        req = self.say("D'accord, je m'en occupe.")
        self.assertNotEqual(req['npc'], m.npc)
        self.assertNotIn('acceptable', req['context'])
        self.assertEqual((m.state, count(m.participants)), ('offer', 0))
        self.assertEqual(count(sim.state().missions), 1)
        # Back to the first NPC: the notebook button still accepts the offer.
        sim.select('alice')
        sim.request_mission('alice', 'accept')
        self.assertEqual((m.state, count(m.participants)), ('active', 1))
        self.assertEqual(self.offer_signals(), 1)

    def test_bridge_contract_for_accept(self):
        base = {'kind': 'npc_talk', 'id': 'r-1-npc-1', 'world': 'w', 'run': 'r', 'npc': 'npc-1', 'order': 1,
                'revision': 1, 'language': 'FR', 'character': 'c-1', 'personality': {}, 'offers': {}, 'text': 'Ok',
                'context': {'stage': 'acquainted'}}
        # No open offer: intent accept is out of contract; the model's speech is kept without effect.
        with self.assertRaises(ValueError):
            protocol.bounded_reply(base, {'text': 'Bien.', 'intent': 'accept'})
        reply, reason = protocol.model_reply(base, '{"text": "Bien.", "intent": "accept"}')
        self.assertEqual((reply['intent'], reason), ('none', 'no open offer to accept'))
        self.assertNotIn('Open offer', protocol.prompt(base, [])[0]['content'])
        open_req = dict(base, context={'stage': 'acquainted', 'acceptable': {'mission': 'npc-1-delivery1', 'revision': 2}})
        self.assertEqual(protocol.bounded_reply(open_req, {'text': 'Bien.', 'intent': 'accept'})['intent'], 'accept')
        with self.assertRaises(ValueError):
            protocol.bounded_reply(open_req, {'text': 'Bien.', 'intent': 'accept', 'offer': 'first_aid_v1'})
        system = protocol.prompt(open_req, [])[0]['content']
        self.assertIn('Return intent accept, offer empty, only if their latest sentence clearly agrees', system)
        # Offline (E17-T10): an acceptance only with the explicit bench flag, and only for an open offer.
        self.assertEqual(protocol.offline(open_req, '')['intent'], 'none')
        self.assertEqual(protocol.offline(open_req, 'accept')['intent'], 'accept')
        self.assertEqual(protocol.offline(base, 'accept')['intent'], 'none')
        # Bridge acknowledgement: only the open offer named in the request may be applied.
        conv = bridge_module.NpcConversations(self.path)
        req = dict(open_req, version=2, channel='say', sent=1)
        with mock.patch.dict(os.environ, {'RS_OFFLINE_INTENT': 'accept'}):
            self.assertEqual(conv.propose({'OFFLINE': '1'}, req)['intent'], 'accept')
        ack = {'request': req['id'], 'world': 'w', 'run': 'r', 'npc': 'npc-1', 'order': 1, 'revision': 1,
               'status': 'accepted'}
        self.assertFalse(conv.acknowledge(dict(ack, applied={'accept': 'npc-1-delivery9'})))
        self.assertTrue(conv.acknowledge(dict(ack, applied={'accept': 'npc-1-delivery1'})))


class MissionTemplateTests(unittest.TestCase):
    """Moteur de gabarits (E11-T02) : M01 = gabarit `deliver`, gabarit factice, mission sauvegardée sans `template`."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-templates-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_m01_is_the_registered_deliver_template(self):
        sim = Simulation(self.path / 'deliver'); sim.add_client('alice'); sim.select('alice')
        config = sim.server.rt.eval("require('RadioSurvivor/RS_Config')")
        same = sim.server.rt.eval('rawequal')
        self.assertTrue(same(config.Delivery, config.Missions.deliver), 'historical alias of the M01 entry')
        npc = next(iter(sim.state().npcs.values()))
        missions = sim.server.rt.eval("require('RadioSurvivor/RS_Missions')")
        m = missions.create(sim.state(), npc, sim.character('alice'), 'first_aid_v1')
        self.assertEqual((m.template, m.offer, m.id), ('deliver', 'first_aid_v1', npc.id + '-delivery1'))
        self.assertTrue(same(missions.template(m), missions.template(sim.server.rt.eval('{}'))), 'missing template = deliver')
        context = convert(missions.context(m))
        self.assertEqual(context, {'state': 'offer', 'quantity': 6, 'delivered': 0, 'remainingMs': 7200000,
                                   'accepted': {'Base.Bandage': True, 'Base.RippedSheets': True},
                                   'rewardType': 'Base.Bullets9mm', 'rewardCount': 20})

    def test_mission_saved_without_template_still_completes_after_restart(self):
        sim = Simulation(self.path / 'legacy'); sim.add_client('alice'); sim.select('alice')
        npc = next(iter(sim.state().npcs.values()))
        m = sim.server.rt.eval("require('RadioSurvivor/RS_Missions')").create(sim.state(), npc, sim.character('alice'))
        sim.request_mission('alice', 'accept')
        sim.server.rt.eval('function(m) m.template = nil end')(m)  # schema written before E11-T02
        self.assertTrue(sim.server.g.RS_CarnetServer.store.save())
        restart = Simulation(sim.path, sim.clock, saved_players=sim.saved())
        restart.add_client('alice')
        old = restart.mission()
        self.assertIsNone(old.template)
        self.assertEqual(old.state, 'active')
        restart.confirm('alice', restart.quote('alice', restart.items('alice', *(['Base.Bandage'] * 6))))
        self.assertEqual((old.delivered, old.state), (6, 'success'))
        self.assertEqual(convert(old.supplies), {'Base.Bandage': 6})
        restart.request_mission('alice', 'claim')
        self.assertEqual(old.claimedBy, restart.character('alice'))
        self.assertEqual(len(restart.server.g.ADDITIONS), 20)
        snapshot = restart.clients['alice'].g.RS_CarnetClient.snapshot
        self.assertEqual((snapshot.missions[1].quantity, snapshot.missions[1].delivered), (6, 6))

    def test_registered_template_uses_the_common_engine(self):
        sim = Simulation(self.path / 'probe'); sim.add_client('alice'); sim.select('alice')
        sim.server.rt.execute(PROBE_TEMPLATE)
        missions = sim.server.rt.eval("require('RadioSurvivor/RS_Missions')")
        server, state = sim.server.g.RS_CarnetServer, sim.state()
        npc = next(iter(state.npcs.values()))
        record = sim.server.rt.eval("require('RadioSurvivor/RS_NPCProvider')").npc(2001)
        catalog = convert(server.offerCatalogFor(npc, record))
        self.assertEqual(sorted(catalog), ['first_aid_v1', 'probe_v1'])
        self.assertEqual(catalog['probe_v1'], {'needed': 2, 'durationMs': 1000})
        self.assertIsNone(missions.create(state, npc, sim.character('alice'), 'unknown_v1'))
        self.assertIsNone(npc.mission, 'unknown offer id created a mission')
        m = missions.create(state, npc, sim.character('alice'), 'probe_v1')
        self.assertEqual((m.id, m.template, m.offer, m.done, m.remainingMs), (npc.id + '-probe1', 'probe', 'probe_v1', 0, 1000))
        self.assertEqual(convert(server.offerCatalogFor(npc, record)), {}, 'second offer while one is open')
        sim.request_mission('alice', 'accept')
        store, player, char = server.store, sim.server.g.PLAYERS.alice, sim.character('alice')
        report = sim.server.rt.eval("""function(M, store, m, player, char, payload, token)
            return {M.report(store, m, player, char, payload, token)} end""")
        self.assertEqual(convert(report(missions, store, m, player, char, 'bad', 't1')), {1: False, 2: 'Items'})
        self.assertEqual(convert(report(missions, store, m, player, char, 'ok', 't1')), {1: True})
        self.assertEqual(convert(report(missions, store, m, player, char, 'ok', 't1')), {1: True}, 'replayed token')
        self.assertEqual((m.done, m.state, m.transaction), (1, 'active', None))
        self.assertEqual(convert(report(missions, store, m, player, char, 'ok', 't2')), {1: True})
        self.assertEqual((m.done, m.state), (2, 'success'))
        self.assertEqual(lua_list(sim.server.g.PROBE_CALLS), ['apply:prepared', 'apply:prepared', 'complete:success'])
        self.assertEqual(convert(m.receipts), {'t1': {'character': char, 'count': 1}, 't2': {'character': char, 'count': 1}})
        outcome = state.outcomes[m.id + '-' + char + '-result']
        self.assertEqual((outcome.action, outcome.proposedDelta), ('mission.success', 5))
        self.assertIsNone(npc.mission)
        projection = convert(missions.projection(m, char))
        self.assertEqual((projection['needed'], projection['done'], projection['rewardCount']), (2, 2, 2))
        self.assertNotIn('quantity', projection)
        sim.request_mission('alice', 'claim')
        self.assertEqual(m.claimedBy, char)
        self.assertEqual(len(sim.server.g.ADDITIONS), 2)
        self.assertEqual(convert(missions.context(m)), {'state': 'success', 'remainingMs': 1000, 'needed': 2,
                                                         'rewardType': 'Base.Bullets9mm', 'rewardCount': 2})


# Metagrid double for the scout template (E11-T03), same shape as tests/test_rescue.py (IsoMetaGrid, IsoMetaCell
# getBuildingsIntersecting without duplicates, BuildingDef with exclusive ends, RoomDef, RoomRect), installed on the
# server machine of a Simulation: getWorld() keeps the world name of the state and gains getMetaGrid().
SCOUT_GRID = r"""
local function jlist(items)
    local l = {items = items or {}}
    function l:size() return #self.items end
    function l:get(i) local v = self.items[i + 1]; if v == nil then error('IndexOutOfBounds ' .. i) end; return v end
    function l:add(v) self.items[#self.items + 1] = v; return true end
    function l:contains(v) for _, x in ipairs(self.items) do if x == v then return true end end; return false end
    return l
end
ArrayList = {new = function() return jlist({}) end}
SCOUT_BUILDINGS, GRID_READS = {}, 0
function scoutHouse(id, x, y, w, h)
    local r = {getX = function() return x end, getY = function() return y end,
        getX2 = function() return x + w end, getY2 = function() return y + h end}
    local function room(name)
        return {getName = function() return name end, getZ = function() return 0 end,
            getArea = function() return w * h end, getRects = function() return jlist({r}) end}
    end
    local b = {id = id, x1 = x, y1 = y, x2 = x + w, y2 = y + h, rooms = jlist({room('livingroom'), room('bedroom'), room('kitchen')})}
    function b:getRooms() return self.rooms end
    function b:getX() return self.x1 end
    function b:getY() return self.y1 end
    function b:getX2() return self.x2 end
    function b:getY2() return self.y2 end
    function b:getArea() return 3 * w * h end
    function b:getMinLevel() return 0 end
    function b:getMaxLevel() return 0 end
    function b:isBasement() return false end
    function b:isUserDefined() return false end
    function b:getIDString() return tostring(self.id) end
    SCOUT_BUILDINGS[#SCOUT_BUILDINGS + 1] = b
    return b
end
local cells = {}
SCOUT_GRID = {}
function SCOUT_GRID:isValidSquare(x, y) return x >= 0 and y >= 0 and x < 4096 and y < 4096 end
function SCOUT_GRID:getZonesAt() return jlist({}) end
function SCOUT_GRID:getCellData(cx, cy)
    if cx < 0 or cy < 0 or cx >= 16 or cy >= 16 then return nil end
    local key = cx .. ',' .. cy
    if not cells[key] then
        cells[key] = {getBuildingsIntersecting = function(_, x, y, w, h, result)
            GRID_READS = GRID_READS + 1
            local ix1, iy1 = math.max(x, cx * 256), math.max(y, cy * 256)
            local ix2, iy2 = math.min(x + w, cx * 256 + 256), math.min(y + h, cy * 256 + 256)
            for _, b in ipairs(SCOUT_BUILDINGS) do
                if b.x1 < ix2 and ix1 < b.x2 and b.y1 < iy2 and iy1 < b.y2 and not result:contains(b) then result:add(b) end
            end
        end}
    end
    return cells[key]
end
getWorld = function() return {getGameMode = function() return 'Multiplayer' end,
    getWorld = function() return 'test' end, getMetaGrid = function() return SCOUT_GRID end} end
"""


class ScoutMissionTests(unittest.TestCase):
    """Gabarit « reconnaître » (E11-T03) : lieu tiré par le serveur, présence par sondage serveur, compte rendu de vive
    voix après la visite seulement. Doublures : métagrille ci-dessus, joueurs et PNJ du banc carnet."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-scout-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def scout_sim(self, name='scout', far_only=False):
        sim = Simulation(self.path / name)
        sim.server.rt.execute(SCOUT_GRID)
        # Requester body at (12, 10), players at (10, 10). Too close (gap < 60), reachable (gap 87), too far (> 250).
        if not far_only:
            sim.server.g.scoutHouse(5001, 20, 12, 8, 8)
            sim.server.g.scoutHouse(5002, 100, 10, 10, 10)
        sim.server.g.scoutHouse(5003, 600, 10, 10, 10)
        sim.add_client('alice'); sim.add_client('bob'); sim.select('alice')
        npc = next(iter(sim.state().npcs.values()))
        record = sim.server.rt.eval("require('RadioSurvivor/RS_NPCProvider')").npc(2001)
        missions = sim.server.rt.eval("require('RadioSurvivor/RS_Missions')")
        return sim, npc, record, missions

    def catalog(self, sim, npc, record):
        return convert(sim.server.g.RS_CarnetServer.offerCatalogFor(npc, record))

    def active_scout(self, name='scout'):
        sim, npc, record, missions = self.scout_sim(name)
        self.assertIn('scout_v1', self.catalog(sim, npc, record))
        m = missions.create(sim.state(), npc, sim.character('alice'), 'scout_v1')
        sim.request_mission('alice', 'accept')
        self.assertEqual(m.state, 'active')
        return sim, npc, m

    def poll(self, sim):
        sim.clock.offset += 1001; sim.tick()

    def talk(self, sim, name, text):
        sim.clock.offset += 11000
        sim.select(name)
        sim.say(name, '/say ' + text)

    def test_offer_names_a_reachable_place_without_coordinates(self):
        sim, npc, record, missions = self.scout_sim()
        catalog = self.catalog(sim, npc, record)
        self.assertEqual(sorted(catalog), ['first_aid_v1', 'scout_v1', 'signal_v1'])  # signal_v1: required mod Signal Smoke (bench double), same places as scout
        offer = catalog['scout_v1']
        self.assertEqual(set(offer), {'kind', 'place', 'clues', 'report', 'durationMs', 'rewardType', 'rewardCount'})
        self.assertEqual((offer['kind'], offer['place'], offer['report']), ('scout', 'house', 'in_person'))
        self.assertEqual((offer['durationMs'], offer['rewardType'], offer['rewardCount']), (7200000, 'Base.Bullets9mm', 20))
        clues = [offer['clues'][i] for i in sorted(offer['clues'])]
        self.assertTrue(clues and clues[0].startswith('The place is '), clues)
        self.assertFalse(any(ch.isdigit() for line in clues for ch in line), 'a clue carries a number')
        self.assertEqual(self.catalog(sim, npc, record)['scout_v1'], offer, 'the kept place changed between two offers')
        m = missions.create(sim.state(), npc, sim.character('alice'), 'scout_v1')
        self.assertEqual((m.id, m.template, m.offer, m.place, m.zoneReached), (npc.id + '-scout1', 'scout', 'scout_v1', 'house', False))
        self.assertEqual(convert(m.zone), {'x1': 98, 'y1': 8, 'x2': 112, 'y2': 22}, 'building 5002 widened by the margin')
        # Neither the bridge context nor the client projection carries the zone.
        context = convert(missions.context(m))
        self.assertEqual((context['kind'], context['zoneReached'], context['report']), ('scout', False, 'in_person'))
        self.assertNotIn('zone', context)
        projection = convert(missions.projection(m, sim.character('alice')))
        self.assertEqual((projection['template'], projection['zoneReached']), ('scout', False))
        for key in ('zone', 'siteKey', 'quantity'):
            self.assertNotIn(key, projection)
        # E11-T09: the clues reach the notebook as translatable data only (keys and codes, never English text nor a
        # number), in the order of the English clues of the bridge.
        data = [projection['clues'][i] for i in sorted(projection['clues'])]
        self.assertEqual([d['key'] for d in data], ['Kind', 'NoLandmark', 'FewHouses'])
        self.assertEqual(data[0]['args'], {1: 'house', 2: 'large', 3: 'single'})
        self.assertEqual(len(data), len(clues))
        self.assertFalse(any(ch.isdigit() for d in data for v in d['args'].values() for ch in str(v)))
        self.assertGreater(sim.server.g.GRID_READS, 0)

    def test_no_place_no_offer_and_no_mission(self):
        sim, npc, record, missions = self.scout_sim('far', far_only=True)
        self.assertEqual(sorted(self.catalog(sim, npc, record)), ['first_aid_v1'])
        self.assertIsNone(missions.create(sim.state(), npc, sim.character('alice'), 'scout_v1'))
        self.assertIsNone(npc.mission)

    def test_forged_positions_are_never_trusted(self):
        sim, npc, m = self.active_scout('forged')
        args = dict(mission=m.id, revision=m.revision, x=105, y=15, z=0)
        for command in ('report', 'scout_reached', 'zone', 'position'):
            sim.command('alice', command, **args)
        sim.command('alice', 'talk', channel='say', text='I am there', x=105, y=15, z=0)
        # The client's own copy of the player is in the zone; the server copy is not.
        local = sim.clients['alice'].g.getPlayer()
        local.x, local.y = 105, 15
        self.poll(sim)
        self.assertFalse(m.zoneReached)
        self.assertEqual(m.state, 'active')
        # A non-participant inside the zone does not count either.
        bob = sim.server.g.PLAYERS.bob
        bob.x, bob.y = 105, 15
        self.poll(sim)
        self.assertFalse(m.zoneReached)

    def test_report_only_after_the_visit(self):
        sim, npc, m = self.active_scout('report')
        alice, char = sim.server.g.PLAYERS.alice, sim.character('alice')
        # E11-T13: a claim without the visit: nothing reportable is sent, a report_done of the model is ignored.
        req = report_turn(sim, 'alice', 'I went there, all quiet', 'report_done')
        self.assertEqual((m.state, m.zoneReached), ('active', False))
        self.assertEqual(count(m.receipts), 0)
        mission = convert(req.context.mission)
        self.assertEqual((mission['kind'], mission['zoneReached'], mission['toReport']), ('scout', False, False))
        self.assertNotIn('zone', mission)
        self.assertIsNone(req.context.reportable)
        # Visit, polled on the server copy of the player.
        revision = m.revision
        alice.x, alice.y = 111.5, 21.5
        self.poll(sim)
        self.assertTrue(m.zoneReached)
        self.assertEqual((m.reachedBy, m.revision, m.state), ('alice Doe', revision + 1, 'active'))
        snapshot = sim.clients['alice'].g.RS_CarnetClient.snapshot
        self.assertEqual((snapshot.missions[1].template, snapshot.missions[1].zoneReached), ('scout', True))
        # Visit without report: still running, even long after.
        alice.x, alice.y = 10, 10
        sim.clock.offset += 600000; sim.tick()
        self.assertEqual(m.state, 'active')
        # A non-participant speaking to the requester is not a report (nothing reportable for bob).
        req = report_turn(sim, 'bob', 'She went there', 'report_done')
        self.assertIsNone(req.context.reportable)
        self.assertEqual(m.state, 'active')
        # E11-T13: the participant talks without reporting (model intent none): still "to report".
        req = report_turn(sim, 'alice', 'Nice weather today', 'none')
        self.assertEqual(convert(req.context.reportable), {'mission': m.id, 'revision': m.revision})
        self.assertTrue(convert(req.context.mission)['toReport'])
        self.assertEqual(m.state, 'active')
        # The participant's report (model intent report_done, checked again) closes the mission.
        req = report_turn(sim, 'alice', 'I have seen the place', 'report_done')
        self.assertEqual(m.state, 'success')
        self.assertEqual(convert(m.receipts), {'speech-' + char: {'character': char, 'count': 1}})
        outcome = sim.state().outcomes[m.id + '-' + char + '-result']
        self.assertEqual((outcome.action, outcome.proposedDelta), ('mission.success', 5))
        self.assertIsNone(npc.mission)
        self.assertEqual(last_ack(sim, req)['applied'], {'report': m.id}, 'the bridge learns the applied report')
        sim.request_mission('alice', 'claim')
        self.assertEqual(m.claimedBy, char)
        self.assertEqual(len(sim.server.g.ADDITIONS), 20)

    def test_visit_is_saved_and_survives_a_restart(self):
        sim, npc, m = self.active_scout('restart')
        alice = sim.server.g.PLAYERS.alice
        alice.x, alice.y = 100, 10
        self.poll(sim)
        self.assertTrue(m.zoneReached)
        restart = Simulation(sim.path, sim.clock, saved_players=sim.saved())
        restart.add_client('alice')
        old = restart.mission()
        self.assertEqual((old.template, old.state, old.zoneReached, old.reachedBy), ('scout', 'active', True, 'alice Doe'))
        self.assertEqual(convert(old.zone), {'x1': 98, 'y1': 8, 'x2': 112, 'y2': 22})
        report_turn(restart, 'alice', 'Back from the house', 'report_done')
        self.assertEqual(old.state, 'success')

    def test_expiry_after_a_visit_without_report(self):
        sim, npc, m = self.active_scout('expiry')
        alice = sim.server.g.PLAYERS.alice
        alice.x, alice.y = 105, 15
        self.poll(sim)
        self.assertTrue(m.zoneReached)
        sim.clock.offset += 7200001; sim.tick()
        self.assertEqual(m.state, 'failed')
        outcome = sim.state().outcomes[m.id + '-' + sim.character('alice') + '-result']
        self.assertEqual((outcome.action, outcome.proposedDelta), ('mission.failed', -5))
        alice.x, alice.y = 10, 10
        report_turn(sim, 'alice', 'I was there', 'report_done')
        self.assertEqual(m.state, 'failed', 'a late report reopened the mission')

    def test_notebook_shows_the_scout_mission_without_delivery_fields(self):
        sim, npc, m = self.active_scout('notebook')
        c = sim.clients['alice']
        c.rt.execute(NOTEBOOK_UI)
        c.rt.execute("getScriptManager = function() return {FindItem = function() return nil end} end")
        c.load('client/RS_Carnet_Client.lua')
        c.g.RS_UI_Notebook.toggle()
        window = c.g.RS_CarnetClient.window
        window.changeTab(window, 'Missions')
        self.assertIn('IGUI_RS_ScoutNotReached', window.detail.text)
        self.assertIn('IGUI_RS_ScoutReport', window.detail.text)
        self.assertNotIn('IGUI_RS_Progress', window.detail.text)
        # E11-T09: title of the template (list and sheet), clues translated by the client, no technical line.
        label = c.rt.eval('RS_CarnetClient.window.list.items[1].text')
        self.assertTrue(label.startswith('IGUI_RS_Scout - '), label)
        self.assertIn('IGUI_RS_ScoutClues', window.detail.text)
        self.assertIn('- IGUI_RS_Clue_Kind|IGUI_RS_Place_house', window.detail.text)  # stub: first argument only
        self.assertIn('IGUI_RS_Clue_FewHouses', window.detail.text)
        self.assertNotIn('ReputationUnavailable', window.detail.text)
        self.assertFalse(window.deliver.isVisible(window.deliver), 'delivery button on a scout mission')
        self.assertTrue(window.abandon.isVisible(window.abandon))
        alice = sim.server.g.PLAYERS.alice
        alice.x, alice.y = 105, 15
        self.poll(sim)
        window.changeTab(window, 'Missions')
        self.assertIn('IGUI_RS_ScoutReached|alice Doe', window.detail.text)

    def test_in_game_suite_on_the_simulated_server(self):
        """rs.missions.scout (dev mod) run by the real RST engine on the server machine; the server move of
        RST_Fixtures (sendServerCommand "RST" "fx.move", answered by the client's /teleportto) is played directly on
        the server copy of the player."""
        sim, npc, record, missions = self.scout_sim('suite')
        shared = (TESTS_SHARED.as_posix() + '/?.lua')
        sim.server.rt.execute(f'package.path = [[{shared};]] .. package.path')
        sim.server.rt.execute("""
            local relay = sendServerCommand
            sendServerCommand = function(p, module, command, args)
                if module == 'RST' then p.x, p.y, p.z = args.x, args.y, args.z; return end
                return relay(p, module, command, args)
            end
            local grid = getWorld():getMetaGrid()
            getWorld = function() return {getGameMode = function() return 'Multiplayer' end,
                getWorld = function() return 'rstest-scout' end, getMetaGrid = function() return grid end} end
            require 'RST/RST'
            require 'RST/RST_Fixtures'
            RST.Fixtures.WAIT_LOADED = false   -- no cell squares in this double: moves do not wait for them
        """)
        sim.server.rt.execute((TESTS_SHARED / 'RST' / 'suites' / 'RS_MissionScout.lua').read_text(encoding='utf-8'))
        alice = sim.server.g.PLAYERS.alice
        self.assertTrue(sim.server.rt.eval('function(p) return RST.start("rs.missions.scout", '
                                           '{ attach = false, ctx = { player = p } }) end')(alice))
        for _ in range(200):
            if not sim.server.rt.eval('RST.step()'):
                break
            sim.clock.offset += 100
        report = sim.server.rt.eval('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        results = {r.test: (r.status, r.message) for r in report.results.values()}
        self.assertEqual(results, {'place, server poll of the visit, report only after it': ('PASS', None)})
        self.assertEqual((alice.x, alice.y), (10, 10), 'the fixture did not move the player back')

    def test_offer_not_accepted_is_not_watched(self):
        sim, npc, record, missions = self.scout_sim('offer')
        self.catalog(sim, npc, record)
        m = missions.create(sim.state(), npc, sim.character('alice'), 'scout_v1')
        alice = sim.server.g.PLAYERS.alice
        alice.x, alice.y = 105, 15
        self.poll(sim)
        self.assertEqual((m.state, m.zoneReached), ('offer', False))

    # E11-T10: approximate area on the player's world map ------------------------------------------------------

    def test_map_area_holds_the_building_off_centre(self):
        sim, npc, record, missions = self.scout_sim('area-draw')
        scout = sim.server.rt.eval("require('RadioSurvivor/RS_MissionScout')")
        c = sim.server.rt.eval("require('RadioSurvivor/RS_Config').Missions.scout")
        self.assertEqual(c.mapZoneRadius, 30)
        t = sim.server.rt.table_from
        for (x1, y1, w, h) in ((100, 10, 10, 10), (500, 700, 1, 1), (2000, 2000, 80, 60), (300, 40, 24, 9)):
            bounds = {'x1': x1, 'y1': y1, 'x2': x1 + w, 'y2': y1 + h}
            cx, cy = x1 + w / 2, y1 + h / 2
            offsets = set()
            for seed in range(200):
                z = convert(scout.mapZone(t(bounds), c, f'npc-scout{seed}:key'))
                self.assertEqual(convert(scout.mapZone(t(bounds), c, f'npc-scout{seed}:key')), z, 'not reproducible')
                self.assertTrue(all(isinstance(z[k], int) for k in ('x', 'y', 'r')), z)
                self.assertGreaterEqual(z['r'], 30)
                for px, py in ((x1, y1), (x1 + w, y1), (x1, y1 + h), (x1 + w, y1 + h)):
                    self.assertLessEqual(math.hypot(px - z['x'], py - z['y']), z['r'], (bounds, z))
                offset = math.hypot(z['x'] - cx, z['y'] - cy)
                self.assertGreaterEqual(offset, 4, (bounds, z))
                offsets.add((z['x'], z['y']))
            self.assertGreater(len(offsets), 50, 'the centre barely moves between missions')
        # A large building widens the area so that the centre can still move.
        z = convert(scout.mapZone(t({'x1': 0, 'y1': 0, 'x2': 80, 'y2': 60}), c, 'big'))
        self.assertGreater(z['r'], 30)

    def install_map(self, c):
        c.rt.execute(MAP_DOUBLE)
        c.rt.eval("require('RadioSurvivor/RS_MapActions')").resetForTests()
        c.rt.eval("require('RadioSurvivor/RS_MapActions')").resetZonesForTests()

    @staticmethod
    def symbols(c):
        return [convert(s) for s in lua_list(c.rt.eval('mapSymbols()'))]

    def test_map_area_drawn_for_the_participant_then_removed(self):
        sim, npc, record, missions = self.scout_sim('area-map')
        alice, bob = sim.clients['alice'], sim.clients['bob']
        self.install_map(alice); self.install_map(bob)
        alice.rt.execute("addPlayerSymbol('Circle', 50, 50)")  # a note of the player, never touched
        self.assertIn('scout_v1', self.catalog(sim, npc, record))
        m = missions.create(sim.state(), npc, sim.character('alice'), 'scout_v1')
        zone = convert(m.mapZone)
        # Building 5002 (100..110 x 10..20) inside the circle, centre moved away from the building centre.
        for px, py in ((100, 10), (110, 10), (100, 20), (110, 20)):
            self.assertLessEqual(math.hypot(px - zone['x'], py - zone['y']), zone['r'])
        self.assertNotEqual((zone['x'], zone['y']), (105, 15))
        # An offer not accepted yet draws nothing; neither the bridge nor the offer carry the area.
        sim.command('alice', 'snapshot', world=alice.g.RS_CarnetClient.world, run=alice.g.RS_CarnetClient.run)
        self.assertEqual(len(self.symbols(alice)), 1)
        self.assertNotIn('mapZone', convert(missions.context(m)))
        sim.request_mission('alice', 'accept')
        self.assertEqual(m.state, 'active')
        row = convert(alice.g.RS_CarnetClient.snapshot.missions[1])
        self.assertEqual(row['mapZone'], zone)
        for key in ('zone', 'siteKey'):
            self.assertNotIn(key, row)
        self.assertNotIn('mapZone', convert(missions.context(m)))
        self.assertEqual(len(lua_list(bob.g.RS_CarnetClient.snapshot.missions)), 0)
        drawn = self.symbols(alice)
        self.assertEqual(len(drawn), 3, drawn)
        ring = [s for s in drawn if s['kind'] == 'texture' and s['a'] < 1]
        text = [s for s in drawn if s['kind'] == 'text']
        self.assertEqual(len(ring), 1)
        self.assertEqual((ring[0]['id'], ring[0]['x'], ring[0]['y']), ('Circle', zone['x'], zone['y']))
        self.assertAlmostEqual(ring[0]['scale'], 2 * zone['r'] / (20 * 50 / 64), places=5)
        self.assertEqual((text[0]['x'], text[0]['y'], text[0]['text']),
                         (zone['x'], zone['y'] - zone['r'], 'IGUI_RS_MapZone|Real Bandit'))
        self.assertEqual(self.symbols(bob), [])
        # Later snapshots add nothing more.
        sim.command('alice', 'snapshot', world=alice.g.RS_CarnetClient.world, run=alice.g.RS_CarnetClient.run)
        self.assertEqual(len(self.symbols(alice)), 3)
        # New session, symbols kept by map_symbols.bin: no duplicate. Symbols lost: drawn again once.
        alice.rt.eval("require('RadioSurvivor/RS_MapActions')").resetZonesForTests()
        sim.command('alice', 'snapshot', world=alice.g.RS_CarnetClient.world, run=alice.g.RS_CarnetClient.run)
        self.assertEqual(len(self.symbols(alice)), 3)
        alice.rt.execute("MAP_SYMBOLS = { MAP_SYMBOLS[1] }")
        alice.rt.eval("require('RadioSurvivor/RS_MapActions')").resetZonesForTests()
        sim.command('alice', 'snapshot', world=alice.g.RS_CarnetClient.world, run=alice.g.RS_CarnetClient.run)
        self.assertEqual(len(self.symbols(alice)), 3)
        # End of the mission (abandon): the area is removed, the player's own circle stays.
        sim.request_mission('alice', 'abandon')
        self.assertEqual(m.state, 'abandoned')
        left = self.symbols(alice)
        self.assertEqual(len(left), 1)
        self.assertEqual((left[0]['x'], left[0]['y'], left[0]['a']), (50, 50, 1))

    def test_map_area_removed_on_expiry_even_after_a_disconnection(self):
        sim, npc, record, missions = self.scout_sim('area-expiry')
        alice = sim.clients['alice']
        self.install_map(alice)
        self.catalog(sim, npc, record)
        m = missions.create(sim.state(), npc, sim.character('alice'), 'scout_v1')
        sim.request_mission('alice', 'accept')
        self.assertEqual(len(self.symbols(alice)), 2)
        # The mission expires while alice's client hears nothing (disconnected): her next snapshot removes the area.
        deliver = sim.server.g.sendServerCommand
        sim.server.g.sendServerCommand = lambda *call: None
        sim.clock.offset += 7200001; sim.tick()
        self.assertEqual(m.state, 'failed')
        self.assertEqual(len(self.symbols(alice)), 2)
        sim.server.g.sendServerCommand = deliver
        # Reconnection: the hello sent at game start brings the snapshot that removes the area.
        alice.g.RS_CarnetClient.hello()
        self.assertEqual(self.symbols(alice), [])

    def npc_offer(self, sim, user, offer='scout_v1'):
        """E11-T11: the real path of an NPC offer: a phrase said to the selected NPC (npc_talk request), then the
        bridge reply intent 'offer' read from responses.txt by the server poll (RS_Carnet_Server reply)."""
        sim.acquaint(user) # E17-T08: offers only to an acquainted character
        self.talk(sim, user, 'Got any work for me?')
        [req] = [r for r in sim.server.g.RS_CarnetServer.pending.values() if r.kind == 'npc_talk']
        self.assertIn(offer, list(req.offers.keys()))
        body = {'version': 2, 'kind': 'npc_reply', 'id': req.id, 'world': req.world, 'run': req.run, 'npc': req.npc,
                'order': req.order, 'revision': req.revision, 'text': 'I need eyes on a house.', 'intent': 'offer',
                'offer': offer}
        (sim.path / 'responses.txt').write_text(f"resp={req.id}\npayload={protocol.encode(body).hex()}\nend\n",
                                                encoding='utf-8')
        sim.clock.offset += 1000
        sim.tick()
        [m] = [x for x in sim.state().missions.values() if x.state == 'offer'] # E17-T09: earlier missions closed
        return m

    def test_npc_offer_area_only_after_acceptance_then_removed(self):
        """E11-T11: an offer told by an NPC draws nothing; the acceptance draws the area under the NPC name, the end of
        the mission (abandon) removes it."""
        sim, npc, record, missions = self.scout_sim('area-npc')
        alice, bob = sim.clients['alice'], sim.clients['bob']
        self.install_map(alice); self.install_map(bob)
        m = self.npc_offer(sim, 'alice')
        self.assertEqual((m.template, m.state, count(m.participants)), ('scout', 'offer', 0))
        zone = convert(m.mapZone)
        row = convert(alice.g.RS_CarnetClient.snapshot.missions[1])
        self.assertEqual((row['state'], row['invited'], row['engaged']), ('offer', True, False))
        self.assertNotIn('mapZone', row)
        self.assertEqual(self.symbols(alice), [], 'an offer drew the area')
        sim.request_mission('alice', 'accept')
        self.assertEqual(m.state, 'active')
        row = convert(alice.g.RS_CarnetClient.snapshot.missions[1])
        self.assertEqual((row['requester'], row['mapZone']), ('Real Bandit', zone))
        drawn = self.symbols(alice)
        self.assertEqual(sorted((s['kind'], s['x'], s['y']) for s in drawn),
                         [('text', zone['x'], zone['y'] - zone['r']), ('texture', zone['x'], zone['y'])])
        self.assertEqual([s['text'] for s in drawn if s['kind'] == 'text'], ['IGUI_RS_MapZone|Real Bandit'])
        self.assertEqual(self.symbols(bob), [])
        sim.request_mission('alice', 'abandon')
        self.assertEqual(m.state, 'abandoned')
        self.assertEqual(self.symbols(alice), [])

    def respond(self, sim, text, intent='none'):
        """Bridge reply (as written by the bridge) to the pending npc_talk request, read by the next server poll."""
        [req] = [r for r in sim.server.g.RS_CarnetServer.pending.values() if r.kind == 'npc_talk']
        out = ''
        # An enrichment queued before the sentence would hold it back (one request per NPC at a time): answered too.
        for r in sim.server.g.RS_CarnetServer.pending.values():
            body = {'version': 2, 'kind': 'npc_reply', 'id': r.id, 'world': r.world, 'run': r.run, 'npc': r.npc,
                    'order': r.order, 'revision': r.revision, 'text': text, 'intent': intent, 'offer': ''}
            if r.kind == 'npc_enrich':
                body.update(intent='none', background='A Knox survivor.')
            out += f"resp={r.id}\npayload={protocol.encode(body).hex()}\n"
        (sim.path / 'responses.txt').write_text(out + 'end\n', encoding='utf-8')
        for _ in range(3):
            self.poll(sim)
        self.assertEqual([r for r in sim.server.g.RS_CarnetServer.pending.values() if r.id == req.id], [])
        return req

    def test_npc_offer_accepted_by_speaking_draws_the_area(self):
        """E17-T09: the offer is signalled once on screen; the model's intent accept, checked by the server, accepts it
        by the button path: the area is drawn for the participant. The reply is said."""
        sim, npc, record, missions = self.scout_sim('spoken-accept')
        alice = sim.clients['alice']
        self.install_map(alice)
        m = self.npc_offer(sim, 'alice')
        self.assertEqual(lua_list(alice.g.getPlayer().halos).count('IGUI_RS_NewOffer'), 1)
        self.assertEqual(self.symbols(alice), [])
        revision = m.revision
        # The model's intent decides (E17-T10), the server checks it.
        self.talk(sim, 'alice', 'Je pars tout de suite.')
        req = self.respond(sim, 'Bien, reviens me raconter.', 'accept')
        self.assertEqual(convert(req.context.acceptable), {'mission': m.id, 'revision': revision})
        self.assertEqual((m.state, list(convert(m.participants))), ('active', [sim.character('alice')]))
        self.assertTrue(alice.g.RS_CarnetClient.seen[req.id])
        self.assertEqual(sim.state().acks[len(sim.state().acks)].applied.accept, m.id)
        row = convert(alice.g.RS_CarnetClient.snapshot.missions[1])
        self.assertEqual((row['engaged'], row['mapZone']), (True, convert(m.mapZone)))
        self.assertEqual(sorted(s['kind'] for s in self.symbols(alice)), ['text', 'texture'])
        self.assertEqual(lua_list(alice.g.getPlayer().halos).count('IGUI_RS_NewOffer'), 1)

    def test_spoken_yes_needs_the_same_open_offer(self):
        """E17-T09, E17-T10: the model's intent accept is checked by the server: another character, an offer changed or
        expired before the reply, or a mission already accepted: nothing applied, the reply is still said."""
        sim, npc, record, missions = self.scout_sim('spoken-refusals')
        alice, bob = sim.clients['alice'], sim.clients['bob']
        m = self.npc_offer(sim, 'alice')
        # Bob, not invited, says yes and the model returns accept: no acceptable offer in his request, nothing applied.
        self.talk(sim, 'bob', "D'accord, je m'en occupe.")
        req = self.respond(sim, 'Pas toi.', 'accept')
        self.assertIsNone(req.context.acceptable)
        self.assertEqual((m.state, count(m.participants)), ('offer', 0))
        self.assertTrue(bob.g.RS_CarnetClient.seen[req.id])
        # Alice's sentence, model intent accept, but the offer changed (new revision) before the reply: not applied.
        self.talk(sim, 'alice', "D'accord, je m'en occupe.")
        m.revision = m.revision + 1
        req = self.respond(sim, 'Merci.', 'accept')
        self.assertEqual(convert(req.context.acceptable)['revision'], m.revision - 1)
        self.assertEqual((m.state, count(m.participants)), ('offer', 0))
        self.assertTrue(alice.g.RS_CarnetClient.seen[req.id])
        # Same sentence again, model intent accept on the current revision: accepted, once.
        self.talk(sim, 'alice', "D'accord, je m'en occupe.")
        current = m.revision
        req = self.respond(sim, 'Merci.', 'accept')
        self.assertEqual(convert(req.context.acceptable)['revision'], current)
        self.assertEqual((m.state, count(m.participants)), ('active', 1))
        revision = m.revision
        self.talk(sim, 'alice', 'Oui, ok.')
        req = self.respond(sim, 'Oui, je sais.', 'accept')
        self.assertIsNone(req.context.acceptable)
        self.assertEqual((m.revision, count(m.participants)), (revision, 1))
        self.assertTrue(alice.g.RS_CarnetClient.seen[req.id])
        # A new offer that expires between the sentence and the reply: refused without effect.
        sim.request_mission('alice', 'abandon')
        npc.nextOfferAt = None
        m2 = self.npc_offer(sim, 'alice')
        self.assertNotEqual(m2.id, m.id)
        self.assertEqual(lua_list(alice.g.getPlayer().halos).count('IGUI_RS_NewOffer'), 2)
        self.talk(sim, 'alice', 'Oui.')
        m2.offerRemainingMs = 1
        req = self.respond(sim, 'Trop tard.', 'accept')
        self.assertEqual(convert(req.context.acceptable)['mission'], m2.id)
        self.assertEqual((m2.state, count(m2.participants)), ('expired', 0))
        self.assertTrue(alice.g.RS_CarnetClient.seen[req.id])

    def test_map_area_removed_after_the_report(self):
        sim, npc, record, missions = self.scout_sim('area-success')
        alice = sim.clients['alice']
        self.install_map(alice)
        self.catalog(sim, npc, record)
        m = missions.create(sim.state(), npc, sim.character('alice'), 'scout_v1')
        sim.request_mission('alice', 'accept')
        self.assertEqual(len(self.symbols(alice)), 2)
        player = sim.server.g.PLAYERS.alice
        player.x, player.y = 105, 15
        self.poll(sim)
        self.assertTrue(m.zoneReached)
        self.assertEqual(len(self.symbols(alice)), 2, 'the area must stay until the mission ends')
        player.x, player.y = 10, 10
        report_turn(sim, 'alice', 'I have seen the place', 'report_done')
        self.assertEqual(m.state, 'success')
        self.assertEqual(self.symbols(alice), [])

    def test_clues_read_without_missing_arguments(self):
        """E11-T12: translator double faithful to Translator.getText/getTextOrNull (42.21): the English table of the
        mod, nil for an unknown key (getTextOrNull only), and a text with %N read with fewer than N arguments logs
        "Missing arguments" (reportMissingArgumentsFromPastAbuse) and comes back unformatted."""
        sim, npc, m = self.active_scout('clue-args')
        c = sim.clients['alice']
        c.rt.execute(NOTEBOOK_UI)
        c.rt.execute("getScriptManager = function() return {FindItem = function() return nil end} end")
        en = ROOT / 'Contents/mods/batman_RadioSurvivor/42.21/media/lua/shared/Translate/EN/IG_UI.json'
        c.g.EN_TEXTS = c.rt.table_from(json.loads(en.read_text(encoding='utf-8-sig')))
        c.rt.execute(r"""
            MISSING_ARGS = {}
            local function format(key, text, n, ...)
                local args = { ... }
                for i in string.gmatch(text, '%%(%d)') do
                    if tonumber(i) > n then MISSING_ARGS[#MISSING_ARGS + 1] = key; return text end
                end
                return (string.gsub(text, '%%(%d)', function(i) return tostring(args[tonumber(i)]) end))
            end
            getTextOrNull = function(key, ...)
                local text = EN_TEXTS[key]
                if text == nil then return nil end
                return format(key, text, select('#', ...), ...)
            end
            getText = function(key, ...) return format(key, EN_TEXTS[key] or key, select('#', ...), ...) end
        """)
        c.load('client/RS_Carnet_Client.lua')
        c.g.RS_UI_Notebook.toggle()
        window = c.g.RS_CarnetClient.window
        window.changeTab(window, 'Missions')
        text = window.detail.text
        self.assertIn('- Building: house (', text)
        self.assertNotIn('%1', text)
        self.assertEqual(list(c.g.MISSING_ARGS.values()), [], 'a clue key read without its arguments')


# E11-T10: world map symbols of a client (WorldMapSymbolsV2 reached through a hidden UIWorldMap, see RS_MapActions).
# Colours are stored as bytes like WorldMapBaseSymbol.save ((byte)(c * 255), read back / 255).
MAP_DOUBLE = r"""
MAP_SYMBOLS = {}
local function q(v) return math.floor(v * 255) / 255 end
local function symbol(kind, id, x, y)
    local s = {kind = kind, id = id, x = x, y = y, r = 1, g = 1, b = 1, a = 1, scale = 0.666}
    function s:isTexture() return self.kind == 'texture' end
    function s:isText() return self.kind == 'text' end
    function s:getSymbolID() return self.id end
    function s:getWorldX() return self.x end
    function s:getWorldY() return self.y end
    function s:setRGBA(r, g, b, a) self.r, self.g, self.b, self.a = q(r), q(g), q(b), q(a) end
    function s:getRed() return self.r end
    function s:getGreen() return self.g end
    function s:getBlue() return self.b end
    function s:getAlpha() return self.a end
    function s:setAnchor(x, y) self.ax, self.ay = x, y end
    function s:setScale(v) self.scale = v end
    MAP_SYMBOLS[#MAP_SYMBOLS + 1] = s
    return s
end
local api = {}
function api:getSymbolCount() return #MAP_SYMBOLS end
function api:getSymbolByIndex(i) return MAP_SYMBOLS[i + 1] end
function api:removeSymbolByIndex(i) table.remove(MAP_SYMBOLS, i + 1) end
function api:addTexture(id, x, y) return symbol('texture', id, x, y) end
function api:addTranslatedText(text, layer, x, y) local s = symbol('text', nil, x, y); s.text = text; return s end
function api:getDefaultTextLayerID() return 'text' end
function addPlayerSymbol(id, x, y) symbol('texture', id, x, y) end
MAP_ITEM = {}
MapItem = {getSingleton = function() return MAP_ITEM end}
UIWorldMap = {new = function(ui)
    return {getAPIv3 = function()
        return {setMapItem = function() end, getSymbolsAPIv2 = function() return api end}
    end}
end}
getText = function(k, ...) local t = { k } for i = 1, select('#', ...) do t[#t + 1] = tostring(select(i, ...)) end
    return table.concat(t, '|') end
function mapSymbols()
    local out = {}
    for i, s in ipairs(MAP_SYMBOLS) do
        out[i] = {kind = s.kind, id = s.id, x = s.x, y = s.y, a = s.a, scale = s.scale, text = s.text}
    end
    return out
end
"""


VOICE_SHEET = """format=1
id=scouter
name=Scout Voice
frequencies=160.0
actions=say,start_mission
budget.start_mission=3
place=depot 10600,9300,0 Fuel depot
place=farm 8000,8000,0 Old farm
[prompt]
You are Scout Voice, a voice of the offline test bench who gives scouting jobs.
"""

# E11-T13: another voice that gives missions, on another frequency.
OTHER_SHEET = """format=1
id=other
name=Other Voice
frequencies=161.0
actions=say,start_mission
[prompt]
You are Other Voice, a second voice of the offline test bench.
"""


class VoiceMissionTests(unittest.TestCase):
    """Voix radio donneuse de missions (E11-T08) : vrai RadioSurvivor_Server + vrai RS_Carnet_Server, SANS moteur de
    PNJ (Living Knox désactivé : provider=False), métagrille de ScoutMissionTests. Action start_mission jugée par
    RS_Actions, lieu tiré autour de la copie serveur de l'appelant, une mission par appelant, compte rendu par une
    phrase dite à la voix sur sa fréquence après la visite seulement, récompense en réputation et en repère."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-voice-mission-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def voice_sim(self, name='voice', far_only=False):
        sim = Simulation(self.path / name, provider=False)
        sim.server.rt.execute(SCOUT_GRID)
        # Players at (10, 10): building 5002 reachable (gap 87), 5001 too close, 5003 too far.
        if not far_only:
            sim.server.g.scoutHouse(5001, 20, 12, 8, 8)
            sim.server.g.scoutHouse(5002, 100, 10, 10, 10)
        sim.server.g.scoutHouse(5003, 600, 10, 10, 10)
        (sim.path / 'personas').mkdir(parents=True, exist_ok=True)
        (sim.path / 'personas' / 'scouter.txt').write_text(VOICE_SHEET, encoding='utf-8')
        (sim.path / 'personas' / 'other.txt').write_text(OTHER_SHEET, encoding='utf-8')
        sim.server.load('shared/RadioSurvivor/RadioSurvivor_Const.lua', 'server/RadioSurvivor_Server.lua')
        sim.server.g.fire('OnLoadRadioScripts', sim.server.g.MANAGER, True)
        self.sent = []
        deliver = sim.server.g.sendServerCommand
        sim.server.g.sendServerCommand = lambda *call: (self.sent.append(call), deliver(*call))[1]
        for user in ('alice', 'bob'):
            c = sim.add_client(user)
            c.rt.execute("getText = function(k, ...) local t = { k } for i = 1, select('#', ...) do "
                         "t[#t + 1] = tostring(select(i, ...)) end return table.concat(t, '|') end")
            c.rt.execute("Talk = require('RadioSurvivor/RS_RadioTalk'); History = Talk.History; "
                         "local Const = require('RadioSurvivor/RadioSurvivor_Const'); "
                         "Events.OnServerCommand.Add(function(m, cmd, a) if m == Const.MODULE then "
                         "Talk.handle(cmd, a or {}) end end); "
                         "local d = getPlayer().radio.device; function d:getPower() return 1 end; d.channel = 160000; "
                         "function texts(khz) local out = {} for _, l in ipairs(History.lines(khz)) do "
                         "out[#out + 1] = l.kind .. ':' .. l.text end return out end")
            sim.server.g.PLAYERS[user].radio.device.channel = 160000
        return sim

    def talk(self, sim, user, text):
        """A phrase said into the radio on 160.0 MHz; returns the radio request the server wrote for the bridge."""
        sim.clock.offset += 11000
        c = sim.clients[user]
        self.assertTrue(c.rt.eval(f"Talk.send(getPlayer(), getPlayer().radio, {json.dumps(text)})"))
        parsed = bridge_module.parse_requests((sim.path / 'requests.txt').read_text(encoding='utf-8'))
        mine = [r for r in parsed[1] if r.get('voice') == 'scouter' and r.get('caller') == user]
        self.assertTrue(mine, parsed)
        return mine[-1]

    def respond(self, sim, req, actions=(), say='Copy that.'):
        body = {'version': 2, 'kind': 'radio_reply', 'id': req['id'], 'say': [say], 'actions': list(actions)}
        (sim.path / 'responses.txt').write_text(f"resp={req['id']}\npayload={protocol.encode(body).hex()}\nend\n",
                                                encoding='utf-8')
        sim.clock.offset += 1000
        sim.server.g.fire('OnTick')

    def decide(self, sim, user, acts, player=True, cid=True, day='1993-07-12', voice='scouter', khz=160000):
        g = sim.server.g
        t = sim.server.rt.table_from
        ctx = {'khz': khz, 'day': day}
        if player:
            ctx['player'] = g.PLAYERS[user]
        if cid:
            ctx['cid'] = sim.character(user)
        decisions = g.require('RadioSurvivor/RS_Actions').decide(
            g.require('RadioSurvivor/RS_Personas').get(voice), user, t([t(a) for a in acts]), sim.clock(), t(ctx))
        return [(d.type, d.reason) for d in lua_list(decisions)]

    def voice_missions(self, sim):
        return [m for m in sim.state().missions.values() if m.donor == 'voice']

    def poll(self, sim):
        sim.clock.offset += 1001
        sim.tick()

    @staticmethod
    def mission_field(req):
        return convert(protocol.decode(bytes.fromhex(req['mission']))) if 'mission' in req else None

    def test_voice_mission_area_for_the_caller_only_removed_at_success(self):
        """E11-T10: the area of a voice mission reaches the caller's map only, and leaves it at the report."""
        sim = self.voice_sim('voice-area')
        alice, bob = sim.clients['alice'], sim.clients['bob']
        for c in (alice, bob):
            c.rt.execute(MAP_DOUBLE)
            c.rt.eval("require('RadioSurvivor/RS_MapActions')").resetForTests()
            c.rt.eval("require('RadioSurvivor/RS_MapActions')").resetZonesForTests()
        req = self.talk(sim, 'alice', 'Got any work for me?')
        self.respond(sim, req, [{'type': 'start_mission', 'template': 'scout'}], 'I need eyes on a place.')
        [m] = self.voice_missions(sim)
        zone = convert(m.mapZone)
        for px, py in ((100, 10), (110, 10), (100, 20), (110, 20)):
            self.assertLessEqual(math.hypot(px - zone['x'], py - zone['y']), zone['r'])
        self.assertNotEqual((zone['x'], zone['y']), (105, 15))
        shown = [convert(s) for s in lua_list(alice.rt.eval('mapSymbols()'))]
        self.assertEqual(sorted((s['kind'], s['x'], s['y']) for s in shown),
                         [('text', zone['x'], zone['y'] - zone['r']), ('texture', zone['x'], zone['y'])])
        self.assertEqual([s['text'] for s in shown if s['kind'] == 'text'], ['IGUI_RS_MapZone|Scout Voice'])
        self.assertEqual(lua_list(bob.rt.eval('mapSymbols()')), [])
        # The snapshot sent to bob carries no area; the bridge context neither.
        for call in self.sent:
            if len(call) == 4 and call[0].username == 'bob' and call[2] == 'snapshot':
                self.assertNotIn('mapZone', json.dumps(convert(call[3])))
        parsed = bridge_module.parse_requests((sim.path / 'requests.txt').read_text(encoding='utf-8'))
        [brief] = [r for r in parsed[1] if r['id'].endswith('-brief')]
        self.assertNotIn('mapZone', self.mission_field(brief))
        self.respond(sim, brief)
        sim.server.g.PLAYERS.alice.x, sim.server.g.PLAYERS.alice.y = 105, 15
        self.poll(sim)
        self.assertTrue(m.zoneReached)
        sim.server.g.PLAYERS.alice.x, sim.server.g.PLAYERS.alice.y = 10, 10
        req = self.talk(sim, 'alice', 'Back from the house, it is empty.')
        self.assertEqual(m.state, 'active', 'E11-T13: the call alone is no report')
        self.respond(sim, req, [{'type': 'report_mission'}], 'Good work.')
        self.assertEqual(m.state, 'success')
        # Only the reward mark (map_mark: Target icon and label, opaque) is left on the map; the area is gone.
        left = [convert(s) for s in lua_list(alice.rt.eval('mapSymbols()'))]
        self.assertEqual([s for s in left if s['a'] < 1], [])
        self.assertEqual(sorted(s['kind'] for s in left), ['text', 'texture'])
        self.assertEqual([s['id'] for s in left if s['kind'] == 'texture'], ['Target'])

    def test_voice_gives_one_mission_report_on_the_radio_after_the_visit(self):
        sim = self.voice_sim()
        g = sim.server.g
        alice, char = g.PLAYERS.alice, sim.character('alice')
        self.assertFalse(sim.server.rt.eval("require('RadioSurvivor/RS_NPCProvider').available()"), 'Living Knox on')
        # No mission yet: no mission= field, prompt unchanged.
        req = self.talk(sim, 'alice', 'Got any work for me?')
        self.assertNotIn('mission', req)
        self.respond(sim, req, [{'type': 'start_mission', 'template': 'scout'}], 'I need eyes on a place.')
        logs = [line for line in lua_list(g.LOGS) if line.startswith('[RadioSurvivor] action ')]
        self.assertEqual(logs[-1], '[RadioSurvivor] action start_mission voice=scouter caller=alice accepted reason=ok')
        [m] = self.voice_missions(sim)
        self.assertEqual((m.donor, m.voice, m.npc, m.template, m.state, m.report, m.requesterName),
                         ('voice', 'scouter', 'voice:scouter:' + char, 'scout', 'active', 'radio', 'Scout Voice'))
        self.assertEqual((m.place, m.placeKind, m.rewardCount, m.durationMs), ('house', 'house', 0, 7200000))
        self.assertEqual(convert(m.zone), {'x1': 98, 'y1': 8, 'x2': 112, 'y2': 22}, 'drawn around the caller')
        self.assertTrue(m.participants[char] is not None and sim.state().characters[char].knownMissions[m.id])
        self.assertEqual(count(sim.state().npcs), 0, 'a voice requester created an NPC fiche')
        # E11-T09: the mission just created is told to the bridge at once (briefing request, same caller and voice),
        # with its clues and the order to say them; the caller may still talk meanwhile.
        parsed = bridge_module.parse_requests((sim.path / 'requests.txt').read_text(encoding='utf-8'))
        [brief] = [r for r in parsed[1] if r['id'].endswith('-brief')]
        self.assertEqual((brief['caller'], brief['voice']), ('alice', 'scouter'))
        field = self.mission_field(brief)
        self.assertEqual((field['turn'], field['state'], field['place']), ('briefing', 'active', 'house'))
        clues = [field['clues'][i] for i in sorted(field['clues'])]
        self.assertTrue(clues and clues[0].startswith('The place is '), clues)
        sheet = bridge_module.Voices(sim.path / 'personas').get('scouter')
        prompt = bridge_module.mission_prompt(bridge_module.mission_context(brief, sheet), '[Caller 1]')
        self.assertIn('Tell them NOW where to go', prompt)
        for clue in clues:
            self.assertIn(f'- What you know of the place: {clue}', prompt)
        self.assertNotIn('has NOT been there yet', prompt)
        self.assertFalse(re.search(r'\d', re.sub(r'\[Caller 1\]|about 120 minutes', '', prompt)), prompt)
        # The briefing reply is aired on the voice's frequency, without a DONE notice to the caller.
        before = len(self.sent)
        self.respond(sim, brief, (), 'Go north to the house.')
        self.assertFalse(any(call[2] == 'done' for call in self.sent[before:] if len(call) > 2), self.sent[before:])
        parsed = bridge_module.parse_requests((sim.path / 'requests.txt').read_text(encoding='utf-8'))
        self.assertFalse([r for r in parsed[1] if r['id'].endswith('-brief')], 'briefing still pending')
        # Notebook row: clues as translatable data, title of the template.
        row = sim.clients['alice'].g.RS_CarnetClient.snapshot.missions[1]
        self.assertEqual(row.titleKey, 'IGUI_RS_Scout')
        self.assertEqual(row.clues[1].key, 'Kind')
        # History line "Mission received" (kind of place only) on the voice's frequency, for alice only.
        texts = lua_list(sim.clients['alice'].rt.eval('texts(160000)'))
        self.assertIn('mission:house', texts)
        self.assertNotIn('mission:house', lua_list(sim.clients['bob'].rt.eval('texts(160000)')))
        # Notebook projection: requester = the voice's name, no body.
        snapshot = sim.clients['alice'].g.RS_CarnetClient.snapshot
        row = snapshot.missions[1]
        self.assertEqual((row.requester, row.donor, row.template, row.near, row.zoneReached, row.report),
                         ('Scout Voice', 'voice', 'scout', False, False, 'radio'))
        # One mission per caller: a second start for alice is refused; bob may get his own.
        sim.clock.offset += 61000
        self.assertEqual(self.decide(sim, 'alice', [{'type': 'start_mission', 'template': 'scout'}]),
                         [('start_mission', 'mission_open')])
        # Before the visit: the phrase is no report, the bridge hears "not yet", without any coordinate.
        req = self.talk(sim, 'alice', 'I went there, all quiet.')
        self.assertEqual(m.state, 'active')
        self.assertEqual(count(m.receipts), 0)
        field = self.mission_field(req)
        self.assertEqual(set(field), {'state', 'remainingMs', 'kind', 'place', 'clues', 'zoneReached', 'report', 'turn',
                                      'toReport'})
        self.assertEqual((field['state'], field['turn'], field['zoneReached'], field['report'], field['place'],
                          field['toReport']), ('active', 'not_yet', False, 'radio', 'house', False))
        self.assertFalse(any(ch.isdigit() for clue in field['clues'].values() for ch in clue))
        sheet = bridge_module.Voices(sim.path / 'personas').get('scouter')
        prompt = bridge_module.mission_prompt(bridge_module.mission_context(req, sheet), '[Caller 1]')
        self.assertIn('has NOT been there yet', prompt)
        self.assertIn('about 120 minutes', prompt)
        self.assertFalse(re.search(r'\d', re.sub(r'\[Caller 1\]|about 120 minutes', '', prompt)), prompt)
        # E11-T13: a report_mission proposed before the visit is refused (a claim validates nothing).
        self.respond(sim, req, [{'type': 'report_mission'}])
        self.assertEqual(m.state, 'active')
        logs = [line for line in lua_list(sim.server.g.LOGS) if line.startswith('[RadioSurvivor] action ')]
        self.assertEqual(logs[-1], '[RadioSurvivor] action report_mission voice=scouter caller=alice refused '
                                   'reason=not_done')
        # Visit, polled on the server copy of the player (never a client position).
        local = sim.clients['alice'].g.getPlayer()
        local.x, local.y = 105, 15
        self.poll(sim)
        self.assertFalse(m.zoneReached, 'the client copy was trusted')
        alice.x, alice.y = 105, 15
        self.poll(sim)
        self.assertTrue(m.zoneReached)
        self.assertEqual(m.state, 'active', 'a visit alone is not a success')
        alice.x, alice.y = 10, 10
        # Bob speaking to the voice is not alice's report.
        req_bob = self.talk(sim, 'bob', 'She went there.')
        self.assertNotIn('mission', req_bob)
        self.respond(sim, req_bob)
        self.assertEqual(m.state, 'active')
        # E11-T13: bob's report_mission (no mission of this voice for him) and the same action of another voice (another
        # frequency: another sheet, not the requester) change nothing.
        self.assertEqual(self.decide(sim, 'bob', [{'type': 'report_mission'}]), [('report_mission', 'no_mission')])
        self.assertEqual(self.decide(sim, 'alice', [{'type': 'report_mission'}], voice='other', khz=161000),
                         [('report_mission', 'no_mission')])
        self.assertEqual(self.decide(sim, 'alice', [{'type': 'report_mission', 'x': 1}]),
                         [('report_mission', 'bad_params')])
        self.assertEqual(m.state, 'active')
        # After the visit the call is judged by the voice (turn report_due): a call that is no report (no action) leaves
        # the mission "to report"; the place the report gives is told beforehand.
        self.sent.clear()
        req = self.talk(sim, 'alice', 'Back from the house, it is empty.')
        self.assertEqual(m.state, 'active', 'the call alone is no report')
        field = self.mission_field(req)
        self.assertEqual((field['state'], field['turn'], field['toReport'], field['reward']),
                         ('active', 'report_due', True, 'Fuel depot'))
        prompt = bridge_module.mission_prompt(bridge_module.mission_context(req, sheet), '[Caller 1]')
        self.assertIn('you only wait for their report', prompt)
        self.assertIn('report_mission', prompt)
        self.assertIn('Fuel depot', prompt)
        self.assertNotIn('has NOT been there yet', prompt)
        self.respond(sim, req)
        self.assertEqual(m.state, 'active')
        row = sim.clients['alice'].g.RS_CarnetClient.snapshot.missions[1]
        self.assertEqual((row.state, row.toReport), ('active', True))
        # Report on the radio (action report_mission of the voice, checked again): success, reputation (scale of M01),
        # map mark of a sheet place.
        req = self.talk(sim, 'alice', 'I told you, the house is empty.')
        self.respond(sim, req, [{'type': 'report_mission'}], 'Good work, thanks.')
        self.assertEqual(m.state, 'success')
        logs = [line for line in lua_list(sim.server.g.LOGS) if line.startswith('[RadioSurvivor] action ')]
        self.assertEqual(logs[-1], '[RadioSurvivor] action report_mission voice=scouter caller=alice accepted reason=ok')
        self.assertEqual(convert(m.receipts), {'speech-' + char: {'character': char, 'count': 1}})
        outcome = sim.state().outcomes[m.id + '-' + char + '-result']
        self.assertEqual((outcome.action, outcome.proposedDelta), ('mission.success', 5))
        marks = [convert(c[3]) for c in self.sent if c[1] == 'RadioSurvivor' and c[2] == 'map_mark']
        self.assertEqual([(c[0].username) for c in self.sent if c[2] == 'map_mark'], ['alice'])
        self.assertEqual(marks, [{'x': 10600, 'y': 9300, 'z': 0, 'label': 'Fuel depot'}])
        self.assertIn('mark:Fuel depot', lua_list(sim.clients['alice'].rt.eval('texts(160000)')))
        # A second report finds no open mission.
        self.assertEqual(self.decide(sim, 'alice', [{'type': 'report_mission'}]), [('report_mission', 'no_mission')])
        # Closed: the next phrase carries no mission; a new one waits the M01 delay, then gives the next place.
        req = self.talk(sim, 'alice', 'Anything else?')
        self.assertNotIn('mission', req)
        self.respond(sim, req)
        self.assertEqual(self.decide(sim, 'alice', [{'type': 'start_mission', 'template': 'scout'}]),
                         [('start_mission', 'recent_mission')])
        sim.clock.offset += 1800001
        self.assertEqual(self.decide(sim, 'alice', [{'type': 'start_mission', 'template': 'scout'}]),
                         [('start_mission', 'ok')])
        second = [x for x in self.voice_missions(sim) if x.state == 'active']
        self.assertEqual(len(second), 1)
        self.assertNotEqual(second[0].id, m.id)

    def test_refusals_and_budget(self):
        sim = self.voice_sim('refusals')
        start = [{'type': 'start_mission', 'template': 'scout'}]
        self.assertEqual(self.decide(sim, 'alice', start, player=False), [('start_mission', 'no_player')])
        self.assertEqual(self.decide(sim, 'alice', start, cid=False), [('start_mission', 'no_character')])
        self.assertEqual(self.decide(sim, 'alice', [{'type': 'start_mission', 'template': 'deliver'}]),
                         [('start_mission', 'bad_params')])
        self.assertEqual(self.decide(sim, 'alice', [{'type': 'start_mission'}]), [('start_mission', 'bad_params')])
        self.assertEqual(self.decide(sim, 'alice', [{'type': 'start_mission', 'template': 'scout', 'x': 1}]),
                         [('start_mission', 'bad_params')])
        self.assertEqual(self.voice_missions(sim), [])
        # Accepted for alice; the delay of the voice (all callers) holds bob back, then he gets his own mission.
        self.assertEqual(self.decide(sim, 'alice', start), [('start_mission', 'ok')])
        self.assertEqual(self.decide(sim, 'bob', start), [('start_mission', 'cooldown')])
        sim.clock.offset += 60001
        self.assertEqual(self.decide(sim, 'bob', start), [('start_mission', 'ok')])
        self.assertEqual(sorted(m.npc for m in self.voice_missions(sim)),
                         sorted('voice:scouter:' + sim.character(u) for u in ('alice', 'bob')))
        # Abandon from the notebook (no body to join): failure for the caller, budget left = 1 of 3 today.
        m = next(x for x in self.voice_missions(sim) if x.participants[sim.character('alice')])
        sim.command('alice', 'abandon', mission=m.id, revision=m.revision)
        self.assertEqual(m.state, 'abandoned')
        self.assertEqual(sim.state().outcomes[m.id + '-' + sim.character('alice') + '-result'].proposedDelta, -5)
        sim.command('alice', 'claim', mission=m.id, revision=m.revision)
        self.assertEqual(m.claimedBy, '')
        # budget.start_mission=3 per game day and per voice: alice's third start of the day, then bob is refused.
        sim.clock.offset += 1800001
        self.assertEqual(self.decide(sim, 'alice', start), [('start_mission', 'ok')])
        b = next(x for x in self.voice_missions(sim) if x.participants[sim.character('bob')])
        sim.command('bob', 'abandon', mission=b.id, revision=b.revision)
        sim.clock.offset += 1800001
        self.assertEqual(self.decide(sim, 'bob', start), [('start_mission', 'budget')])
        self.assertEqual(self.decide(sim, 'bob', start, day='1993-07-13'), [('start_mission', 'ok')])

    def test_no_place_around_the_caller(self):
        sim = self.voice_sim('noplace', far_only=True)
        self.assertEqual(self.decide(sim, 'alice', [{'type': 'start_mission', 'template': 'scout'}]),
                         [('start_mission', 'no_place')])
        self.assertEqual(self.voice_missions(sim), [])
        self.assertIsNone(sim.state().voiceDonors['voice:scouter:' + sim.character('alice')].mission)

    def test_mission_survives_a_restart_and_shows_in_the_notebook(self):
        sim = self.voice_sim('restart')
        self.assertEqual(self.decide(sim, 'alice', [{'type': 'start_mission', 'template': 'scout'}]),
                         [('start_mission', 'ok')])
        c = sim.clients['alice']
        c.rt.execute(NOTEBOOK_UI)
        c.rt.execute("getScriptManager = function() return {FindItem = function() return nil end} end")
        c.load('client/RS_Carnet_Client.lua')
        c.g.RS_UI_Notebook.toggle()
        window = c.g.RS_CarnetClient.window
        window.changeTab(window, 'Missions')
        text = window.detail.text
        for key in ('IGUI_RS_Requester|Scout Voice', 'IGUI_RS_ScoutPlace|IGUI_RS_Place_house', 'IGUI_RS_ScoutNotReached',
                    'IGUI_RS_ScoutReportRadio', 'IGUI_RS_RewardInformation'):
            self.assertIn(key, text)
        for key in ('IGUI_RS_JoinRequester', 'IGUI_RS_Reward|', 'IGUI_RS_ScoutReport ', 'IGUI_RS_Progress'):
            self.assertNotIn(key, text)
        # E11-T09: clues translated by the client with every argument, title of the template, no technical line.
        for key in ('IGUI_RS_ScoutClues',
                    '- IGUI_RS_Clue_Kind|IGUI_RS_Place_house|IGUI_RS_ClueSize_large|IGUI_RS_ClueFloors_single',
                    '- IGUI_RS_Clue_FewHouses'):
            self.assertIn(key, text)
        self.assertNotIn('ReputationUnavailable', text)
        self.assertEqual(c.rt.eval('RS_CarnetClient.window.list.items[1].text'), 'IGUI_RS_Scout - Scout Voice')
        self.assertTrue(window.abandon.isVisible(window.abandon))
        for button in (window.deliver, window.claim, window.invite, window.accept):
            self.assertFalse(button.isVisible(button))
        sim.server.g.PLAYERS.alice.x, sim.server.g.PLAYERS.alice.y = 100, 10
        self.poll(sim)
        window.changeTab(window, 'Missions')
        self.assertIn('IGUI_RS_ScoutReachedRadio|alice Doe', window.detail.text)
        self.assertTrue(sim.server.g.RS_CarnetServer.store.save())
        restart = Simulation(sim.path, sim.clock, saved_players=sim.saved(), provider=False)
        restart.server.rt.execute(SCOUT_GRID)
        restart.add_client('alice')
        [old] = [m for m in restart.state().missions.values() if m.donor == 'voice']
        self.assertEqual((old.state, old.zoneReached, old.voice), ('active', True, 'scouter'))
        donor = restart.state().voiceDonors['voice:scouter:' + restart.character('alice')]
        self.assertEqual(donor.mission, old.id)

    def test_in_game_suite_on_the_simulated_server(self):
        """rs.missions.radio (dev mod) run by the real RST engine on the server machine; the server move of
        RST_Fixtures is played directly on the server copy of the player, as for rs.missions.scout."""
        sim = self.voice_sim('suite')
        shared = (TESTS_SHARED.as_posix() + '/?.lua')
        sim.server.rt.execute(f'package.path = [[{shared};]] .. package.path')
        sim.server.rt.execute("""
            local relay = sendServerCommand
            sendServerCommand = function(p, module, command, args)
                if module == 'RST' then p.x, p.y, p.z = args.x, args.y, args.z; return end
                return relay(p, module, command, args)
            end
            local grid = getWorld():getMetaGrid()
            getWorld = function() return {getGameMode = function() return 'Multiplayer' end,
                getWorld = function() return 'rstest-radio' end, getMetaGrid = function() return grid end} end
            require 'RST/RST'
            require 'RST/RST_Fixtures'
            RST.Fixtures.WAIT_LOADED = false   -- no cell squares in this double: moves do not wait for them
        """)
        sim.server.rt.execute((TESTS_SHARED / 'RST' / 'suites' / 'RS_MissionRadio.lua').read_text(encoding='utf-8'))
        alice = sim.server.g.PLAYERS.alice
        self.assertTrue(sim.server.rt.eval('function(p) return RST.start("rs.missions.radio", '
                                           '{ attach = false, ctx = { player = p } }) end')(alice))
        for _ in range(200):
            if not sim.server.rt.eval('RST.step()'):
                break
            sim.clock.offset += 100
        report = sim.server.rt.eval('RST.last()')
        self.assertIsNotNone(report, 'run not finished')
        results = {r.test: (r.status, r.message) for r in report.results.values()}
        self.assertEqual(results, {'voice mission: one per caller, report on the radio only after the visit':
                                   ('PASS', None)})
        self.assertEqual((alice.x, alice.y), (10, 10), 'the fixture did not move the player back')


class IdentitySuiteTests(unittest.TestCase):
    """Suites rs.identity* (E03-T04) run by the real RST engine on the server machine of the simulation.

    Each scenario is the one of the in-game protocol: snapshot, then reconnection, restart or death, then the
    matching step. The simulation does not prove the Java API; it proves the suite tells a kept identity from a
    lost one.
    """

    LIVE_NPC = 'clock of a mission engaged with a real Living Knox NPC runs (world run)'
    BEFORE_MISSION = 'a mission of a real Living Knox NPC engages every online account'

    def live_statuses(self, sim):
        """rs.identity statuses; its test with a real Living Knox NPC needs a world run of the game (SKIP here)."""
        results = self.run_suite(sim, 'rs.identity')
        self.assertEqual(results.pop(self.LIVE_NPC)[0], 'SKIP')
        return results

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-identity-')
        self.path = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    @staticmethod
    def load_suite(sim):
        rt = sim.server.rt
        rt.execute(f'package.path = [[{TESTS_SHARED.as_posix()}/?.lua;]] .. package.path')
        # A Python clock is userdata for type(): RST must read the simulated clock explicitly.
        rt.execute('require "RST/RST"; RST.clock = function() return getTimestampMs() end')
        rt.execute(f'dofile([[{IDENTITY_SUITE.as_posix()}]])')

    @staticmethod
    def run_suite(sim, name):
        report = sim.server.rt.execute(f'return RST.runSync("{name}")')
        return {r.test: (r.status, r.message) for _, r in report.results.items()}

    def assert_statuses(self, results, expected):
        self.assertEqual({k: v[0] for k, v in results.items()}, expected, results)

    def engaged(self, name):
        """Alice and Bob engaged in one mission, Alice with a note: what the protocol prepares."""
        sim = Simulation(self.path / name)
        sim.add_client('alice'); sim.add_client('bob')
        sim.select('alice'); sim.select('bob')
        npc = next(iter(sim.state().npcs.values()))
        sim.server.rt.eval("require('RadioSurvivor/RS_Missions')").create(sim.state(), npc, sim.character('alice'))
        sim.request_mission('alice', 'accept')
        sim.request_mission('alice', 'invite', character=sim.character('bob'))
        sim.request_mission('bob', 'accept')
        sim.command('alice', 'note', npc=npc.id, text='keep me')
        self.assertEqual(count(sim.mission().participants), 2)
        self.load_suite(sim)
        before = self.run_suite(sim, 'rs.identity.before')
        self.assert_statuses(before, {self.BEFORE_MISSION: 'PASS', 'snapshot of the online accounts written': 'PASS'})
        return sim

    @staticmethod
    def disconnect(sim, name):
        del sim.server.g.PLAYERS[name]
        sim.clock.offset += 1001; sim.tick()

    def test_live_invariants(self):
        sim = Simulation(self.path / 'live')
        self.load_suite(sim)
        alone = self.live_statuses(sim)
        self.assertEqual(alone['online players carry a usable identity of their own account'], ('SKIP', 'no online player'))
        self.assertEqual(alone['notebook state ready'][0], 'PASS')
        sim.add_client('alice'); sim.add_client('bob')
        self.assertEqual({v[0] for v in self.live_statuses(sim).values()}, {'PASS'})
        # Bob's server modData claims Alice's identity: both invariants catch it.
        sim.server.g.PLAYERS.bob.md.RS_CarnetCharacter = sim.character('alice')
        broken = self.live_statuses(sim)
        self.assertEqual(broken['online players carry a usable identity of their own account'][0], 'FAIL')
        self.assertIn('bob/0 modData', broken['online players carry a usable identity of their own account'][1])
        self.assertEqual(broken['no identity shared by two online players'][0], 'FAIL')

    def test_manual_steps_are_opt_in(self):
        sim = Simulation(self.path / 'select')
        self.load_suite(sim)
        names = lambda flt: [e.name for _, e in sim.server.rt.execute(f'return RST.list({flt}, true)').items()]
        self.assertEqual(names('"rs"'), ['rs.identity'])
        self.assertEqual(names('"rs.identity"'), ['rs.identity'])
        self.assertEqual(names('"rs.identity.after-death"'), ['rs.identity.after-death'])
        self.assertEqual(names('{ tags = "manual" }'), ['rs.identity.before', 'rs.identity.after-reconnect',
                                                         'rs.identity.after-restart', 'rs.identity.after-death'])
        # Without a snapshot, a step fails with the instruction to take one.
        status, message = self.run_suite(sim, 'rs.identity.after-reconnect')['same world and session']
        self.assertEqual(status, 'FAIL')
        self.assertIn("run RST.server('rs.identity.before') first", message)

    def test_reconnect_keeps_identity_notes_engagement_and_clock(self):
        sim = self.engaged('reconnect')
        self.disconnect(sim, 'alice')
        sim.clock.offset += 30000; sim.tick()
        sim.add_client('alice')  # new client machine: empty client modData
        self.assert_statuses(self.run_suite(sim, 'rs.identity.after-reconnect'), {
            'same world and session': 'PASS', 'same identity for each account': 'PASS',
            'notes and engagements kept': 'PASS', 'mission clock ran during the disconnection': 'PASS'})

    def test_reconnect_detects_a_lost_server_identity(self):
        sim = self.engaged('lost')
        self.disconnect(sim, 'alice')
        del sim.player_data['alice'].RS_CarnetCharacter  # E00-T01 regression: server copy not kept
        sim.add_client('alice')
        results = self.run_suite(sim, 'rs.identity.after-reconnect')
        self.assertEqual(results['same identity for each account'][0], 'FAIL')
        self.assertIn('alice/0 modData identity', results['same identity for each account'][1])
        self.assertEqual(results['notes and engagements kept'][0], 'PASS', 'old record keeps its notes')

    def restarted(self, sim, downtime=600000):
        sim.clock.offset += downtime
        restart = Simulation(sim.path, sim.clock, saved_players=sim.saved())
        restart.add_client('alice'); restart.add_client('bob')
        self.load_suite(restart)
        return restart

    def test_restart_keeps_identity_and_excludes_downtime(self):
        restart = self.restarted(self.engaged('restart'))
        restart.clock.offset += 2000; restart.tick()
        results = self.run_suite(restart, 'rs.identity.after-restart')
        self.assert_statuses(results, {
            'new session of the same world': 'PASS', 'same identity for each account': 'PASS',
            'notes and engagements kept': 'PASS', 'mission clock excludes the downtime': 'PASS'})
        # The same step on the session of the snapshot is refused: no restart happened.
        self.assertEqual(self.run_suite(restart, 'rs.identity.after-reconnect')['same world and session'][0], 'FAIL')

    def test_restart_detects_downtime_counted_or_too_short(self):
        restart = self.restarted(self.engaged('downtime'))
        restart.mission().remainingMs -= 600000  # the clock ran while the server was down
        status, message = self.run_suite(restart, 'rs.identity.after-restart')['mission clock excludes the downtime']
        self.assertEqual(status, 'FAIL')
        self.assertIn('used', message)
        short = self.restarted(self.engaged('short'), downtime=30000)
        status, message = self.run_suite(short, 'rs.identity.after-restart')['mission clock excludes the downtime']
        self.assertEqual(status, 'FAIL')
        self.assertIn('needed to tell the downtime from the runtime', message)

    def test_death_retires_identity_and_new_character_starts_clean(self):
        sim = self.engaged('death')
        old = sim.character('alice')
        body = sim.server.g.PLAYERS.alice
        body.dead = True
        sim.server.g.fire('OnCharacterDeath', body)
        self.disconnect(sim, 'alice')  # the dead IsoPlayer is replaced by the new character's
        sim.add_client('alice')
        self.assertNotEqual(sim.character('alice'), old)
        results = self.run_suite(sim, 'rs.identity.after-death')
        self.assert_statuses(results, {
            'same world': 'PASS', 'dead account: old identity retired and unused': 'PASS',
            'new character: new identity without the old missions or notes': 'PASS',
            'other accounts keep their identity and missions': 'PASS'})
        self.assertEqual(sim.mission().state, 'active', 'the death closed the common mission')
        # Live invariants hold after the death too.
        self.assertEqual({v[0] for v in self.live_statuses(sim).values()}, {'PASS'})

    def test_death_without_retirement_is_detected(self):
        sim = self.engaged('nodeath')
        sim.server.g.PLAYERS.alice.dead = True  # OnCharacterDeath never reaches the server (E00-T02 regression)
        self.disconnect(sim, 'alice')
        sim.add_client('alice')
        results = self.run_suite(sim, 'rs.identity.after-death')
        self.assertEqual(results['dead account: old identity retired and unused'][0], 'FAIL')
        self.assertIn('did A die', results['dead account: old identity retired and unused'][1])


def request(npc='npc-a', world='world-a', order=1, run='run-a', **changes):
    value = {'version': 2, 'kind': 'npc_talk', 'id': f'{run}-{npc}-{order}', 'world': world, 'run': run,
        'npc': npc, 'character': 'character-a', 'order': order, 'revision': 1, 'sent': int(time.time() * 1000),
        'channel': 'say', 'language': 'FR', 'text': 'Bonjour', 'personality': {'style': 'Prudent'}, 'context': {},
        'offers': {'first_aid_v1': {'quantity': 6, 'durationMs': 7200000, 'rewardCount': 20}}}
    value.update(changes)
    return value


def ack(req, accepted=True, offer='first_aid_v1'):
    result = {k: req[k] for k in ('version', 'world', 'run', 'npc', 'order', 'revision', 'sent')}
    result.update(id=req['id'] + '-ack', kind='ack', request=req['id'], status='accepted' if accepted else 'rejected',
                  applied={'offer': offer} if accepted and offer else {})
    return result


def envelope(req):
    return {'id': req['id'], 'kind': req['kind'], 'payload': protocol.encode(req).hex()}



class ProtocolTests(unittest.TestCase):
    def test_one_bridge_mixes_historical_walt_and_npc(self):
        with tempfile.TemporaryDirectory(prefix='rs-mixed-') as d:
            # Fiche de Walt installée comme le fait le serveur (plus de prompt de secours depuis E05-T10).
            (Path(d) / 'personas').mkdir()
            (Path(d) / 'personas/walt.txt').write_bytes((bridge_module.BUNDLED_PERSONAS / 'walt.txt').read_bytes())
            worker = bridge_module.Bridge({'OFFLINE': '1'}, Path(d))
            req = request()
            walt = {'id': 'walt-1', 'sent': str(int(time.time() * 1000)), 'caller': 'alice',
                'name': 'Alice', 'date': '1993-07-09', 'days': '1', 'radio': 'Radio', 'text': 'Allo Walt'}
            try:
                worker._sync('historical-world', [envelope(req), walt])
                self.assertTrue(pump(lambda: req['id'] in worker.answers and walt['id'] in worker.answers, [], timeout=3))
                self.assertEqual(worker.answers[req['id']]['kind'], 'npc_reply')
                self.assertIsInstance(worker.answers[walt['id']], list)
                text = (Path(d) / 'responses.txt').read_text(encoding='utf-8')
                self.assertIn('resp=walt-1\nline=', text)
                self.assertIn('resp=' + req['id'] + '\npayload=', text)
                worker._sync('historical-world', [envelope(ack(req))])
                self.assertEqual(len(worker.npcs.load(req)['messages']), 2)
                self.assertEqual(len(list(Path(d).glob('history_*.json'))), 1)
            finally:
                worker.pool.shutdown(wait=True)

    def test_ack_reply_requires_durable_memory(self):
        with tempfile.TemporaryDirectory(prefix='rs-ack-') as d:
            worker = bridge_module.Bridge({'OFFLINE': '1'}, Path(d))
            req = request()
            worker.npcs.propose({'OFFLINE': '1'}, req)
            try:
                with patch.object(bridge_module, 'atomic_json', side_effect=OSError('disk failure')):
                    worker._sync('legacy', [envelope(ack(req))])
                self.assertNotIn(req['id'] + '-ack', worker.answers, 'failed memory write was acknowledged')
                self.assertEqual(len(worker.npcs.load(req)['messages']), 0)
                worker._sync('legacy', [envelope(ack(req))])
                self.assertEqual(worker.answers[req['id'] + '-ack']['kind'], 'ack_reply')
                self.assertEqual(len(worker.npcs.load(req)['messages']), 2)
                self.assertFalse(worker.npcs.acknowledge(ack(request(order=2))), 'unknown accepted fact acknowledged')
                self.assertTrue(worker.npcs.acknowledge(ack(request(order=2), False)))
            finally:
                worker.pool.shutdown(wait=True)

    def test_codec_lua_python_and_incomplete_files(self):
        import lupa.lua51 as lua
        runtime = lua.LuaRuntime(unpack_returned_tuples=True)
        codec = runtime.execute((LUA / 'shared/RadioSurvivor/RS_Codec.lua').read_text(encoding='utf-8'))
        value = {'nested': {1: 'é=漢字\nend', 'false': False}, 'number': 1790959902158, 'empty': {}}
        raw = protocol.encode(value)
        self.assertEqual(convert(codec.decode(raw.decode('utf-8'))), value)
        luavalue = runtime.table_from({'text': 'é=漢字\nend', 'enabled': True})
        self.assertEqual(protocol.decode(codec.encode(luavalue).encode('utf-8')), {'text': 'é=漢字\nend', 'enabled': True})
        for bad in (b't1:s1:x', b's9:a', b't2:s1:xb0s1:xb1', b'n3:nan'):
            with self.assertRaises(ValueError): protocol.decode(bad)
            self.assertIsNone(codec.decode(bad.decode('utf-8')))
        self.assertIsNone(bridge_module.parse_requests('session=x\nreq=a\ntext=hello\n'))
        self.assertIsNone(bridge_module.parse_requests('protocol=2\ngeneration=1\ncommit=2\nend\n'))
        self.assertIsNotNone(bridge_module.parse_requests('session=legacy\nreq=a\ntext=hello\nend\n'))
        req = request()
        self.assertEqual(protocol.unpack_request(envelope(req)), req)
        for change in ({'channel': 'general'}, {'language': 'x1'}, {'text': 'x' * 801}, {'order': -1}):
            with self.assertRaises(ValueError): protocol.unpack_request(envelope({**req, **change}))
        for bad in ({'text': 'hack', 'intent': 'give_reward'}, {'text': 'hack', 'intent': 'offer', 'offer': 'invented'},
                    {'text': 'hack', 'intent': 'none', 'quantity': 1000}):
            with self.assertRaises(ValueError): protocol.bounded_reply(req, bad)

    def test_memories_world_npc_ack_restart_and_bounded_history(self):
        with tempfile.TemporaryDirectory(prefix='rs-memory-') as d:
            store = bridge_module.NpcConversations(Path(d))
            a, b, other = request(), request(npc='npc-b'), request(world='world-b')
            for req in (a, b, other): store.propose({'OFFLINE': '1'}, req)
            self.assertEqual(len(store.load(a)['messages']), 0, 'proposal prematurely memorized')
            store.acknowledge(ack(a, False))
            self.assertEqual(len(store.load(a)['messages']), 0, 'rejected effect memorized')
            store.acknowledge(ack(b)); store.acknowledge(ack(other))
            self.assertEqual(len(store.load(b)['messages']), 2)
            self.assertEqual(len(store.load(other)['messages']), 2)
            cached = request(order=2)
            proposed = store.propose({'OFFLINE': '1'}, cached)
            restart = bridge_module.NpcConversations(Path(d))
            with patch.object(bridge_module, 'call_llm', side_effect=AssertionError('must reuse durable proposal')):
                self.assertEqual(restart.propose({}, cached), proposed)
            wrong = ack(cached); wrong['run'] = 'old'
            restart.acknowledge(wrong)
            self.assertEqual(len(restart.load(a)['messages']), 0)
            restart.acknowledge(ack(cached)); restart.acknowledge(ack(cached))
            self.assertEqual(len(restart.load(a)['messages']), 2)
            for order in range(3, 30):
                req = request(order=order)
                restart.propose({'OFFLINE': '1'}, req); restart.acknowledge(ack(req))
            self.assertEqual(len(restart.load(a)['messages']), 40)
            self.assertEqual(len(list(Path(d).glob('npc_*.json'))), 3)

    def test_bridge_orders_whole_turn_and_parallel_npcs(self):
        with tempfile.TemporaryDirectory(prefix='rs-order-') as d:
            worker = bridge_module.Bridge({'OFFLINE': '1'}, Path(d))
            a1, a2, b = request(order=1), request(order=2), request(npc='npc-b')
            entered, released = threading.Event(), threading.Event()
            original = worker.npcs.propose
            calls = []
            def delayed(config, req):
                calls.append((req['npc'], req['order']))
                if req['id'] == a1['id']:
                    entered.set(); released.wait(3)
                return original(config, req)
            worker.npcs.propose = delayed
            records = [envelope(a2), envelope(a1), envelope(b)]
            try:
                worker._sync('legacy', records)
                self.assertTrue(entered.wait(2))
                self.assertTrue(pump(lambda: b['id'] in worker.answers, [], timeout=2))
                self.assertNotIn(('npc-a', 2), calls, 'same NPC calls overlapped')
                released.set()
                self.assertTrue(pump(lambda: a1['id'] in worker.answers, [], timeout=2))
                worker._sync('legacy', records)
                self.assertNotIn(('npc-a', 2), calls, 'next turn started before ack')
                worker._sync('legacy', [envelope(ack(a1)), envelope(a2), envelope(b)])
                self.assertTrue(pump(lambda: a2['id'] in worker.answers, [], timeout=2))
                self.assertEqual([x for x in calls if x[0] == 'npc-a'], [('npc-a', 1), ('npc-a', 2)])
                self.assertEqual(len(worker.npcs.load(a1)['messages']), 2)
            finally:
                released.set(); worker.pool.shutdown(wait=True)


# Writer side of RS_Codec before E00-T08 (hex per string unit, lengths and checksum per unit), kept verbatim to
# prove that the states it wrote are still read.
LEGACY_CODEC = rb'''
local C = {}
function C.hex(s)
    return (s:gsub('.', function(c) return string.format('%02x', string.byte(c)) end))
end
local function pack(value, depth)
    local kind = type(value)
    if kind == 'boolean' then return value and 'b1' or 'b0' end
    if kind == 'string' or kind == 'number' then
        local s = tostring(value)
        return (kind == 'string' and 's' or 'n') .. #s .. ':' .. s
    end
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return type(a) .. tostring(a) < type(b) .. tostring(b) end)
    local out = {'t' .. #keys .. ':'}
    for _, k in ipairs(keys) do
        out[#out + 1] = pack(k, depth + 1)
        out[#out + 1] = pack(value[k], depth + 1)
    end
    return table.concat(out)
end
function C.encode(value) return pack(value, 0) end
function C.checksum(s)
    local a, b = 1, 0
    for i = 1, #s do a = (a + s:byte(i)) % 65521; b = (b + a) % 65521 end
    return string.format('%.0f', b * 65536 + a)
end
return C
'''

# "é ’ € œ" and U+1F4FB (outside the BMP).
ACCENTED = 'Été : l’abri coûte 5 €, œuvre \U0001F4FB.'


def adler(raw: bytes) -> str:
    a, b = 1, 0
    for x in raw:
        a = (a + x) % 65521
        b = (b + a) % 65521
    return str(b * 65536 + a)


class CodecUtf8Tests(unittest.TestCase):
    """E00-T08: RSV2 strings are UTF-8 bytes in both runtimes; old saved states stay readable."""

    def setUp(self):
        import lupa.lua51 as lua
        self.lua = lua
        self.source = (LUA / 'shared/RadioSurvivor/RS_Codec.lua').read_bytes()

    def byte_runtime(self, utf16=None):
        """Runtime without string conversion (Lua strings <-> bytes), optionally forcing the UTF-16 branch."""
        rt = self.lua.LuaRuntime(encoding=None, unpack_returned_tuples=True)
        codec = rt.execute(self.source)
        codec[b'_utf16'] = utf16
        return rt, codec

    def test_lupa_branch_round_trips_utf8_text(self):
        rt = self.lua.LuaRuntime(unpack_returned_tuples=True)
        codec = rt.execute(self.source.decode('utf-8'))
        self.assertEqual(rt.eval('#"\\195\\169"'), 2, 'lupa must see UTF-8 bytes')
        self.assertEqual(codec.toUtf8(ACCENTED), ACCENTED)
        self.assertEqual(codec.decode(codec.encode(ACCENTED)), ACCENTED)
        self.assertEqual(codec.unhex(codec.hex(ACCENTED)), ACCENTED)
        self.assertEqual(codec.hex(ACCENTED), ACCENTED.encode('utf-8').hex())
        self.assertEqual(codec.checksum(ACCENTED), adler(ACCENTED.encode('utf-8')))
        payload = codec.hexBytes(codec.encodeBytes(rt.table_from({'text': ACCENTED, 'n': 2})))
        self.assertEqual(protocol.decode(bytes.fromhex(payload)), {'text': ACCENTED, 'n': 2})
        self.assertEqual(payload, protocol.encode({'text': ACCENTED, 'n': 2}).hex())
        back = codec.decodeBytes(codec.unhexBytes(protocol.encode({'text': ACCENTED}).hex()))
        self.assertEqual(back['text'], ACCENTED)

    def test_forced_utf16_branch_converts_units_and_tolerates_latin1(self):
        # Under lupa the forced branch sees each byte as one UTF-16 unit (U+0000-U+00FF); units above U+00FF and
        # surrogate pairs are covered by the real Kahlua VM (tests/test_kahlua.py, suite rs.codec).
        _rt, C = self.byte_runtime(True)
        self.assertEqual(C.toUtf8(b'caf\xe9 \xff'), 'café ÿ'.encode('utf-8'))
        self.assertEqual(C.fromUtf8('café ÿ'.encode('utf-8')), b'caf\xe9 \xff')
        self.assertEqual(C.toUtf8(b'plain ascii'), b'plain ascii')
        # Invalid UTF-8: every byte that does not start a valid sequence is kept as the same code.
        for raw in (b'caf\xe9', b'\xc3(', b'\xc0\xaf', b'\xe2\x82', b'x\x80y', b'\xed\xa0\x80', b'\xf5\x80\x80\x80'):
            self.assertEqual(C.fromUtf8(raw), raw, raw)
        self.assertEqual(C.hex(b'caf\xe9'), '636166c3a9'.encode())
        self.assertEqual(C.unhex(b'636166c3a9'), b'caf\xe9')
        self.assertEqual(C.encodeBytes(b'\xe9t\xe9'), b's5:\xc3\xa9t\xc3\xa9')
        self.assertEqual(C.encode(b'\xe9t\xe9'), b's5:\xe9t\xe9', 'text layer: Lua string, length in bytes')
        self.assertEqual(C.decode(C.encode(b'\xe9t\xe9')), b'\xe9t\xe9')
        self.assertEqual(C.checksum(b'caf\xe9'), adler('café'.encode('utf-8')).encode())
        self.assertIsNone(C.decode(b's1:\xe9'), 'length counted in units instead of bytes')

    def test_old_states_are_read_unchanged(self):
        rt, C = self.byte_runtime(True)
        old = rt.execute(LEGACY_CODEC)
        ascii_state = rt.eval(b'{schema = 2, world = "world-1", npcs = {a = {name = "Walt", order = 3, ok = true}}}')
        body = old.encode(ascii_state)
        # Same bytes, same hex, same checksum as the old writer, in both branches.
        for utf16 in (True, None):
            C[b'_utf16'] = utf16
            self.assertEqual(C.encodeBytes(ascii_state), body)
            self.assertEqual(C.hex(C.encode(ascii_state)), old.hex(body))
            self.assertEqual(C.checksumBytes(C.unhexBytes(old.hex(body))), old.checksum(body))
            self.assertEqual(C.hexBytes(C.encodeBytes(C.decodeBytes(C.unhexBytes(old.hex(body))))), old.hex(body))
        C[b'_utf16'] = True
        # Old game state with Latin-1 units: "é" written as e9 with a length of 1 unit.
        latin = rt.eval(b'{name = "caf\\233"}')
        hexed, checksum = old.hex(old.encode(latin)), old.checksum(old.encode(latin))
        self.assertEqual(hexed, b'74313a73343a6e616d6573343a636166e9')
        raw = C.unhexBytes(hexed)
        self.assertEqual(C.checksumBytes(raw), checksum)
        self.assertEqual(C.decodeBytes(raw)[b'name'], b'caf\xe9')
        # Old game state holding a bridge reply read by the old codec: UTF-8 bytes stored as units (mojibake),
        # repaired on reading.
        mojibake = rt.eval(b'{name = "caf\\195\\169"}')
        raw = C.unhexBytes(old.hex(old.encode(mojibake)))
        self.assertEqual(C.checksumBytes(raw), old.checksum(old.encode(mojibake)))
        self.assertEqual(C.decodeBytes(raw)[b'name'], b'caf\xe9')

    def test_state_file_matches_the_old_writer(self):
        with tempfile.TemporaryDirectory(prefix='rs-state-') as d:
            sim = Simulation(Path(d))
            sim.add_client('alice')
            rt, C = self.byte_runtime()
            old = rt.execute(LEGACY_CODEC)
            files = sorted(Path(d).glob('state-*.txt'))
            self.assertTrue(files)
            for path in files:
                # Historical file name: per-unit hex of "Multiplayer/test", unchanged.
                self.assertTrue(path.name.startswith('state-' + 'Multiplayer/test'.encode().hex() + '-'), path.name)
                _header, hexed, checksum, end = path.read_text(encoding='utf-8').splitlines()
                self.assertEqual(end, 'end')
                body = bytes.fromhex(hexed)
                # The old writer gives the same bytes and checksum for this (ASCII) state.
                self.assertEqual(old.encode(C.decodeBytes(body)), body)
                self.assertEqual(old.checksum(body), checksum.encode())
            # A world reopened by the new code reads the files it wrote.
            again = Simulation(Path(d))
            self.assertFalse(again.server.g.RS_CarnetServer.store.blocked)
            self.assertIsNotNone(again.state())


class CollectiveLeaderTests(unittest.TestCase):
    """E10-T02 : chef du groupe et intentions collectives. Le chef est celui du registre Living Knox ; seule une phrase
    dite au chef peut proposer une mission de groupe (offre `supply`) ou en conclure l'acceptation ; un autre membre en
    parle mais renvoie au chef (`context.collective`) ; la réponse est revalidée sur la composition du groupe
    (`LivingKnox.API.composition`) et rejetée après une mort ou une succession ; la décision entre au journal du groupe
    (kind `decision`, fait seulement) et dans le contexte des membres. Vrai moteur Living Knox, vrai pont hors ligne."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='rs-collective-')
        self.path = Path(self.tmp.name)
        self.process = None

    def tearDown(self):
        if self.process:
            self.process.terminate()
            self.process.communicate(timeout=10)
        self.tmp.cleanup()

    def world(self, name, intent=''):
        sim = Simulation(self.path / name, living_knox=True)
        sim.server.rt.execute(LK_WORLD)
        sim.add_client('alice')
        self.sim, self.g, self.rt = sim, sim.server.g, sim.server.rt
        self.server, self.api = self.g.RS_CarnetServer, self.rt.eval('LivingKnox.API')
        self.G = self.rt.eval('LivingKnox.Groups')
        # Both bodies next to alice: she may select either.
        for npc in (self.g.LK_LEADER, self.g.LK_MATE):
            self.g.LivingKnox.Bodies.bound[npc].x = 12
        self.process = start_bridge(sim.path, intent)
        return sim

    def member(self, npc):
        return self.G.findNpc(npc)[1]

    def talk(self, npc, text, before_reply=None):
        """One sentence of alice to this NPC (selected and acquainted). before_reply runs between the request and
        the reply. Returns the request (dict) once the server handled the reply."""
        sim = self.sim
        sim.command('alice', 'select', incarnation=npc)
        sim.acquaint('alice')
        self.server.lastTalk[sim.character('alice')] = None
        sim.command('alice', 'talk', channel='say', text=text, language='FR')
        [req] = talk_requests(self.g)
        rid = req.id
        bound = convert(self.server.collectives[rid]) if self.server.collectives[rid] else None
        if before_reply:
            before_reply()
        self.assertTrue(pump(lambda: not any(r.id == rid for r in self.server.pending.values()), [sim.tick]),
                        'no reply: ' + text)
        self.assertEqual(count(self.server.collectives), 0, 'binding kept after the reply')
        out = convert(req)
        out['bound'] = bound
        return out

    def decisions(self):
        return [e.text for e in lua_list(self.G.get(self.g.LK_GROUP).log) if e.kind == 'decision']

    def logs(self):
        return [self.g.LOGS[i] for i in range(1, len(self.g.LOGS) + 1)]

    def spoken(self, npc):
        """Lines of this NPC said to alice (contact history, filled only for an accepted reply)."""
        fiche = self.server.ensure(npc)
        known = self.sim.state().characters[self.sim.character('alice')].contacts[fiche.id]
        return [h.text for h in lua_list(known.history) if h.author == fiche.name] if known else []

    def kept(self, req, effect, reason):
        """E09-T09: the effect proposed in req was refused by the server: the reply is kept, the refusal logged."""
        fiche = self.server.ensure(self.g.LK_LEADER)
        line = (f"{effect} of {fiche.id} toward {self.sim.character('alice')} in {req['id']} ignored, reply kept: "
                + reason)
        self.assertIn(line, [x.partition('[RS_Carnet] ')[2] for x in self.logs()], self.logs())
        self.assertFalse(any(req['id'] + ' refused' in x for x in self.logs()), 'whole reply refused')
        self.assertIsNone(self.sim.clients['alice'].g.RS_CarnetClient.lastError, 'the player sees NoAnswer')

    def test_composition_fingerprint_follows_deaths_arrivals_and_successions(self):
        self.world('composition')
        gid = self.g.LK_GROUP
        c = self.api.composition(gid)
        leader, mate = self.member(self.g.LK_LEADER), self.member(self.g.LK_MATE)
        self.assertEqual((c.group, c.leader, c.leaderNpc, c.alive), (gid, leader, self.g.LK_LEADER, 2))
        self.assertEqual(c.key, leader + '|' + ','.join(sorted([leader, mate], key=lambda m: int(m[2:]))))
        self.assertEqual(self.api.composition(gid).key, c.key, 'computed twice: same fingerprint')
        self.assertEqual(self.api.composition('grp-99'), (None, 'unknown group grp-99'))
        self.assertIsNone(self.G.get(gid).composition, 'no stored field')
        self.rt.execute(f'assert(LivingKnox.Groups.setLeader("{gid}", "{mate}"))')
        succession = self.api.composition(gid).key
        self.assertNotEqual(succession, c.key)
        self.rt.execute(f'assert(LivingKnox.Groups.markDead("{gid}", "{leader}"))')
        death = self.api.composition(gid)
        self.assertEqual((death.alive, death.leader), (1, mate))
        self.assertNotEqual(death.key, succession)
        self.rt.execute(f'assert(LivingKnox.Groups.addMember("{gid}", {{role = "worker"}}))')
        self.assertEqual(self.api.composition(gid).alive, 2)
        self.assertNotEqual(self.api.composition(gid).key, death.key, 'arrival changes the fingerprint')

    def test_only_the_leader_offers_a_group_mission_and_members_learn_the_decision(self):
        sim = self.world('leader')
        leader_name = self.server.ensure(self.g.LK_LEADER).name
        # A member: no group mission in the catalogue, told who decides; the offline reply offers nothing.
        req = self.talk(self.g.LK_MATE, "Vous avez besoin d'aide ?")
        self.assertNotIn('first_aid_v1', req['offers'])
        self.assertEqual(req['context']['collective'], {'speaker': 'member', 'leaderName': leader_name})
        # E10-T04: a member's request is bound only for its own departure (context.leave), never with a team.
        self.assertTrue(req['bound'] is None or ('leave' in req['context'] and 'team' not in req['bound']),
                        'a member request bound to a collective intention')
        system = protocol.prompt(req, [])[0]['content']
        self.assertIn('you are not the leader of your group', system)
        self.assertIn('refer the character to them', system)
        self.assertEqual(count(sim.state().missions), 0)
        self.assertEqual(self.decisions(), [])
        # The leader: the group mission is offered, bound to the composition, then logged as a decision.
        req = self.talk(self.g.LK_LEADER, "Vous avez besoin d'aide ?")
        self.assertIn('first_aid_v1', req['offers'])
        self.assertEqual(req['context']['collective'], {'speaker': 'leader'})
        # E09-T05: alice (personal team) may also conclude an agreement: the binding then names her team.
        self.assertEqual({k: req['bound'][k] for k in ('ref', 'key')},
                         {'ref': self.g.LK_GROUP, 'key': self.api.composition(self.g.LK_GROUP).key})
        self.assertIn('you lead your group', protocol.prompt(req, [])[0]['content'])
        m = sim.mission()
        self.assertEqual((m.npc, m.state, m.supply.need), (self.server.find(self.g.LK_LEADER).id, 'offer', 'food'))
        [decision] = self.decisions()
        alice = sim.state().characters[sim.character('alice')].name
        self.assertEqual(decision, f'The leader asked {alice} to bring food for the group.')
        speech = [h.text for h in lua_list(sim.state().characters[sim.character('alice')]
                                          .contacts[m.npc].history) if h.author == leader_name]
        self.assertTrue(speech and speech[-1] not in decision, 'reply text in the group journal')
        # The member's next request carries the decision (fact only) and still no collective intention.
        req = self.talk(self.g.LK_MATE, 'Votre chef a dit quoi ?')
        self.assertEqual([d['text'] for d in req['context']['group']['decisions'].values()], [decision])
        self.assertNotIn('acceptable', req['context'], 'a member may conclude the leader offer')
        self.assertNotIn('first_aid_v1', req['offers'])
        self.assertEqual(m.state, 'offer')

    def test_reply_after_a_death_or_a_succession_is_rejected(self):
        sim = self.world('stale')
        gid, mate = self.g.LK_GROUP, self.member(self.g.LK_MATE)
        client = sim.clients['alice'].g.RS_CarnetClient
        # Death of a member between the request and the reply: the group mission is refused, nothing logged.
        # E09-T09: the line of the leader is still said (kept in the history), only the offer is ignored.
        before = self.spoken(self.g.LK_LEADER)
        req = self.talk(self.g.LK_LEADER, "Vous avez besoin d'aide ?",
                        lambda: self.rt.execute(f'assert(LivingKnox.Groups.markDead("{gid}", "{mate}"))'))
        self.assertEqual((count(sim.state().missions), self.decisions(), client.lastError), (0, [], None))
        self.kept(req, 'collective offer', 'group composition changed')
        self.assertEqual(len(self.spoken(self.g.LK_LEADER)), len(before) + 1, 'reply of the leader not said')
        # Same leader, current composition: accepted.
        self.talk(self.g.LK_LEADER, "Vous avez besoin d'aide ?")
        self.assertEqual(count(sim.state().missions), 1)
        self.assertEqual(len(self.decisions()), 1)

    def test_succession_rejects_the_offer_and_the_spoken_acceptance(self):
        sim = self.world('succession', 'accept')
        gid, leader, mate = self.g.LK_GROUP, self.member(self.g.LK_LEADER), self.member(self.g.LK_MATE)
        # Offer made by the leader, then the spoken yes; a succession before the reply: refused, offer still open.
        self.talk(self.g.LK_LEADER, "Vous avez besoin d'aide ?")
        m = sim.mission()
        before = self.spoken(self.g.LK_LEADER)
        req = self.talk(self.g.LK_LEADER, "D'accord, je m'en occupe.",
                        lambda: self.rt.execute(f'assert(LivingKnox.Groups.setLeader("{gid}", "{mate}"))'))
        self.assertEqual(req['context']['acceptable']['mission'], m.id)
        self.assertEqual((m.state, count(m.participants)), ('offer', 0))
        self.assertEqual(len(self.decisions()), 1, 'refused acceptance logged')
        # E09-T09: the yes of the former leader is said, only the acceptance is ignored (no NoAnswer).
        self.kept(req, 'collective acceptance', 'NPC no longer the group leader')
        self.assertEqual(len(self.spoken(self.g.LK_LEADER)), len(before) + 1, 'reply of the former leader not said')
        # The former leader is now a member: neither a group mission nor its acceptance any more.
        req = self.talk(self.g.LK_LEADER, "D'accord, je m'en occupe.")
        self.assertEqual(req['context']['collective']['speaker'], 'member')
        self.assertNotIn('acceptable', req['context'])
        self.assertEqual(m.state, 'offer')
        # Back to the original leader (registry): the yes is concluded and logged.
        self.rt.execute(f'assert(LivingKnox.Groups.setLeader("{gid}", "{leader}"))')
        self.talk(self.g.LK_LEADER, "D'accord, je m'en occupe.")
        self.assertEqual(m.state, 'active')
        alice = sim.state().characters[sim.character('alice')].name
        self.assertEqual(self.decisions()[-1], f'{alice} agreed to bring food for the group.')

    def test_bridge_prompt_for_collective_context(self):
        base = {'kind': 'npc_talk', 'id': 'r-1-npc-1', 'world': 'w', 'run': 'r', 'npc': 'npc-1', 'order': 1,
                'revision': 1, 'language': 'FR', 'character': 'c-1', 'personality': {}, 'offers': {}, 'text': 'Ok',
                'context': {'stage': 'acquainted'}}
        self.assertEqual(protocol.collective_prompt(base), '')
        self.assertEqual(protocol.collective_prompt(dict(base, context={'collective': {'speaker': 'boss'}})), '')
        self.assertEqual(protocol.collective_prompt(dict(base, kind='npc_enrich',
                                                         context={'collective': {'speaker': 'leader'}})), '')
        member = dict(base, context={'collective': {'speaker': 'member', 'leaderName': 'Ann'}})
        self.assertIn('never propose or accept one yourself', protocol.prompt(member, [])[0]['content'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
