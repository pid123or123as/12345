--[[
==================================================================
    DrawLib — Drawing-based UI library
    API-compatible re-implementation of MacLib_V2
    
    * Pure Drawing API (no ScreenGui / Frame), mobile-friendly
    * Same public methods: Window, TabGroup, Tab, Section, Toggle,
      Slider, Dropdown, Keybind, Colorpicker, Button, Input, Label,
      SubLabel, Paragraph, Header, Divider, Spacer, Notify, Dialog,
      Preloader, SaveConfig/LoadConfig, FAL*, custom elements, etc.
    * Different design: "neon glass" dark theme, FAB toggle button,
      bottom tab-bar layout (mobile-first), smooth animations
==================================================================
]]

local DrawLib = {
    Options    = {},
    Folder     = "DrawLib",
    Theme      = {
        Background     = Color3.fromRGB(10, 10, 15),
        Surface        = Color3.fromRGB(20, 22, 30),
        SurfaceHover   = Color3.fromRGB(30, 33, 44),
        SurfaceActive  = Color3.fromRGB(40, 44, 58),
        Border         = Color3.fromRGB(45, 48, 62),
        Accent         = Color3.fromRGB(0, 229, 255),
        AccentDim      = Color3.fromRGB(0, 140, 170),
        Text           = Color3.fromRGB(235, 240, 250),
        TextDim        = Color3.fromRGB(140, 148, 165),
        TextMuted      = Color3.fromRGB(95, 100, 115),
        Success        = Color3.fromRGB(80, 220, 120),
        Warning        = Color3.fromRGB(245, 175, 70),
        Danger         = Color3.fromRGB(235, 80, 95),
        Shadow         = Color3.fromRGB(0, 0, 0),
    },
    GetService = function(service)
        return cloneref and cloneref(game:GetService(service)) or game:GetService(service)
    end
}

--// Services
local RunService        = DrawLib.GetService("RunService")
local UserInputService  = DrawLib.GetService("UserInputService")
local HttpService       = DrawLib.GetService("HttpService")
local TweenService      = DrawLib.GetService("TweenService")
local Players           = DrawLib.GetService("Players")
local Workspace         = DrawLib.GetService("Workspace")

local isStudio   = RunService:IsStudio()
local LocalPlayer = Players.LocalPlayer

-- ====================================================================
-- POLYFILLS for non-exploit environments (so the script doesn't crash)
-- ====================================================================
local isfile    = isfile    or function() return false end
local readfile  = readfile  or function() return nil end
local writefile = writefile or function() end
local isfolder  = isfolder  or function() return false end
local makefolder= makefolder or function() end
local listfiles = listfiles or function() return {} end
local delfile   = delfile   or function() end

-- Drawing polyfill stub (lets the script load in Studio for testing)
if not Drawing then
    Drawing = {}
    Drawing.Fonts = { UI = 0, System = 1, Plex = 2, Monospace = 3 }
    function Drawing.new(class)
        local o = setmetatable({
            Visible=false, ZIndex=0, Transparency=1, Color=Color3.new(1,1,1),
            Position=Vector2.zero, Size=Vector2.zero, Thickness=1, Filled=true,
            Text="", TextBounds=Vector2.zero, Font=0, Center=false, Outline=false,
            OutlineColor=Color3.new(0,0,0), From=Vector2.zero, To=Vector2.zero,
            Radius=0, NumSides=0, PointA=Vector2.zero, PointB=Vector2.zero,
            PointC=Vector2.zero, PointD=Vector2.zero, Data="", Rounding=0,
        }, { __index = function() return function() end end })
        function o:Remove() end
        function o:Destroy() end
        return o
    end
end

-- ====================================================================
-- UTILITIES
-- ====================================================================
local function clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function lerpColor(a, b, t)
    return Color3.new(lerp(a.R,b.R,t), lerp(a.G,b.G,t), lerp(a.B,b.B,t))
end
local function pointInRect(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end
local function getViewport()
    local cam = Workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(1280, 720)
end
local function isMobile()
    local vp = getViewport()
    return UserInputService.TouchEnabled and (vp.X <= 1024 or not UserInputService.MouseEnabled)
end

-- Easing helpers (since we don't use TweenService on Drawing objects)
local Easing = {}
function Easing.outQuad(t) return 1 - (1 - t) * (1 - t) end
function Easing.outCubic(t) return 1 - math.pow(1 - t, 3) end
function Easing.outBack(t) local c1=1.70158; local c3=c1+1; return 1 + c3*math.pow(t-1,3) + c1*math.pow(t-1,2) end
function Easing.outSine(t) return math.sin((t * math.pi) / 2) end
function Easing.inOutQuad(t) return t < 0.5 and 2*t*t or 1 - math.pow(-2*t+2,2)/2 end
function Easing.linear(t) return t end

-- ====================================================================
-- ANIMATION ENGINE — tweens arbitrary numbers/colors/vectors via callback
-- ====================================================================
local Anim = { _active = {} }

function Anim.tween(duration, easing, onUpdate, onComplete)
    local t0 = tick()
    local ent = { t0=t0, dur=duration, easing=easing, onUpdate=onUpdate, onComplete=onComplete, alive=true }
    table.insert(Anim._active, ent)
    return ent
end

function Anim.cancel(ent) if ent then ent.alive = false end end

function Anim.step()
    local now = tick()
    for i = #Anim._active, 1, -1 do
        local e = Anim._active[i]
        if not e.alive then
            table.remove(Anim._active, i)
        else
            local t = (now - e.t0) / e.dur
            if t >= 1 then
                e.onUpdate(1)
                if e.onComplete then pcall(e.onComplete) end
                table.remove(Anim._active, i)
            else
                e.onUpdate(e.easing(t))
            end
        end
    end
end

-- Animate a number value with an updater callback
function Anim.number(from, to, dur, easing, onUpdate, onComplete)
    return Anim.tween(dur, easing or Easing.outCubic, function(t)
        onUpdate(from + (to - from) * t)
    end, onComplete)
end

function Anim.color(from, to, dur, easing, onUpdate, onComplete)
    return Anim.tween(dur, easing or Easing.outCubic, function(t)
        onUpdate(lerpColor(from, to, t))
    end, onComplete)
end

-- ====================================================================
-- DRAW PRIMITIVES — rounded rectangles via Square composition
-- ====================================================================
local Draw = {}

-- Filled rectangle
function Draw.rect(x, y, w, h, color, transparency, zIndex)
    local s = Drawing.new("Square")
    s.Position = Vector2.new(x, y)
    s.Size = Vector2.new(w, h)
    s.Color = color
    s.Filled = true
    s.Thickness = 0
    s.Transparency = 1 - (transparency or 0) -- Drawing.Transparency: 1=opaque, 0=invisible
    s.ZIndex = zIndex or 1
    s.Visible = true
    return s
end

-- Stroke rectangle
function Draw.stroke(x, y, w, h, color, thickness, transparency, zIndex)
    local s = Drawing.new("Square")
    s.Position = Vector2.new(x, y)
    s.Size = Vector2.new(w, h)
    s.Color = color
    s.Filled = false
    s.Thickness = thickness or 1
    s.Transparency = 1 - (transparency or 0)
    s.ZIndex = zIndex or 1
    s.Visible = true
    return s
end

-- Text label
function Draw.text(str, x, y, size, color, font, center, zIndex)
    local t = Drawing.new("Text")
    t.Text = str or ""
    t.Position = Vector2.new(x, y)
    t.Size = size or 14
    t.Color = color or Color3.new(1, 1, 1)
    t.Font = font or Drawing.Fonts.UI
    t.Center = center or false
    t.Outline = false
    t.Transparency = 1
    t.ZIndex = zIndex or 2
    t.Visible = true
    return t
end

-- Circle
function Draw.circle(cx, cy, radius, color, filled, transparency, zIndex)
    local c = Drawing.new("Circle")
    c.Position = Vector2.new(cx, cy)
    c.Radius = radius
    c.NumSides = math.max(16, math.floor(radius * 1.5))
    c.Color = color
    c.Filled = filled ~= false
    c.Thickness = 1
    c.Transparency = 1 - (transparency or 0)
    c.ZIndex = zIndex or 1
    c.Visible = true
    return c
end

-- Line
function Draw.line(x1, y1, x2, y2, color, thickness, transparency, zIndex)
    local l = Drawing.new("Line")
    l.From = Vector2.new(x1, y1)
    l.To   = Vector2.new(x2, y2)
    l.Color = color
    l.Thickness = thickness or 1
    l.Transparency = 1 - (transparency or 0)
    l.ZIndex = zIndex or 1
    l.Visible = true
    return l
end

-- Rounded rectangle approximation: center square + 4 edge squares + 4 corner circles
function Draw.roundedRect(x, y, w, h, radius, color, transparency, zIndex)
    radius = math.min(radius, math.floor(math.min(w, h) / 2))
    transparency = transparency or 0
    zIndex = zIndex or 1
    local parts = {}
    -- center cross
    parts[#parts+1] = Draw.rect(x + radius, y, w - 2*radius, h, color, transparency, zIndex)
    parts[#parts+1] = Draw.rect(x, y + radius, radius, h - 2*radius, color, transparency, zIndex)
    parts[#parts+1] = Draw.rect(x + w - radius, y + radius, radius, h - 2*radius, color, transparency, zIndex)
    -- 4 corner circles
    parts[#parts+1] = Draw.circle(x + radius,     y + radius,     radius, color, true, transparency, zIndex)
    parts[#parts+1] = Draw.circle(x + w - radius, y + radius,     radius, color, true, transparency, zIndex)
    parts[#parts+1] = Draw.circle(x + radius,     y + h - radius, radius, color, true, transparency, zIndex)
    parts[#parts+1] = Draw.circle(x + w - radius, y + h - radius, radius, color, true, transparency, zIndex)
    return parts
end

-- A grouped rounded rectangle object with helpful methods (move/resize/recolor/destroy)
function Draw.roundedGroup(x, y, w, h, radius, color, transparency, zIndex)
    local g = { x=x, y=y, w=w, h=h, r=radius, color=color, transp=transparency or 0, z=zIndex or 1 }
    g.parts = Draw.roundedRect(x, y, w, h, radius, color, g.transp, g.z)
    function g:SetPosition(nx, ny)
        local dx, dy = nx - self.x, ny - self.y
        self.x, self.y = nx, ny
        for _, p in ipairs(self.parts) do
            p.Position = p.Position + Vector2.new(dx, dy)
        end
    end
    function g:SetSize(nw, nh)
        for _, p in ipairs(self.parts) do p:Remove() end
        self.w, self.h = nw, nh
        self.parts = Draw.roundedRect(self.x, self.y, nw, nh, self.r, self.color, self.transp, self.z)
    end
    function g:SetColor(c)
        self.color = c
        for _, p in ipairs(self.parts) do p.Color = c end
    end
    function g:SetTransparency(t)
        self.transp = t
        for _, p in ipairs(self.parts) do p.Transparency = 1 - t end
    end
    function g:SetVisible(v)
        for _, p in ipairs(self.parts) do p.Visible = v end
    end
    function g:SetZIndex(z)
        self.z = z
        for _, p in ipairs(self.parts) do p.ZIndex = z end
    end
    function g:Destroy()
        for _, p in ipairs(self.parts) do p:Remove() end
        self.parts = {}
    end
    return g
end

-- Soft shadow (3 stacked semi-transparent rounded rects with growing radius)
function Draw.shadow(x, y, w, h, radius, zIndex)
    local layers = {}
    for i = 1, 3 do
        local off = i * 2
        local rg = Draw.roundedGroup(x - off, y - off + i*2, w + off*2, h + off*2, radius + off, DrawLib.Theme.Shadow, 0.18 - i*0.05, (zIndex or 1) - 1)
        layers[#layers+1] = rg
    end
    local s = { layers = layers }
    function s:Destroy() for _, l in ipairs(self.layers) do l:Destroy() end end
    function s:SetVisible(v) for _, l in ipairs(self.layers) do l:SetVisible(v) end end
    function s:SetPosition(nx, ny)
        local dx, dy = nx - layers[1].x - 2, ny - layers[1].y - 2
        for _, l in ipairs(self.layers) do l:SetPosition(l.x + dx, l.y + dy) end
    end
    return s
end

-- ====================================================================
-- INPUT MANAGER — handles touch + mouse, dispatches to interactive zones
-- ====================================================================
local Input = {
    zones = {},      -- {id, x, y, w, h, z, onPress, onRelease, onHover, onDrag, parentVisible, parentEnabled, data}
    nextId = 1,
    held = nil,      -- currently pressed zone
    holdStart = nil, -- {x,y,t}
    lastMouse = Vector2.zero,
}

function Input.register(zone)
    zone.id = Input.nextId
    Input.nextId = Input.nextId + 1
    table.insert(Input.zones, zone)
    return zone
end

function Input.unregister(zone)
    for i, z in ipairs(Input.zones) do
        if z == zone or z.id == (zone and zone.id) then
            table.remove(Input.zones, i)
            return
        end
    end
end

function Input.updateZone(zone, x, y, w, h)
    zone.x, zone.y, zone.w, zone.h = x, y, w, h
end

-- Find topmost zone at point
function Input.pick(x, y)
    local best, bestZ = nil, -math.huge
    for _, z in ipairs(Input.zones) do
        local visible = z.visible == nil or z.visible
        if type(z.visible) == "function" then visible = z.visible() end
        if visible and z.z and z.z > bestZ and pointInRect(x, y, z.x, z.y, z.w, z.h) then
            -- additional filter
            local enabled = z.enabled == nil or z.enabled
            if type(z.enabled) == "function" then enabled = z.enabled() end
            if enabled then
                best, bestZ = z, z.z
            end
        end
    end
    return best
end

-- Global input loop — to be installed once
function Input.install()
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            local pos = input.Position
            local zone = Input.pick(pos.X, pos.Y)
            if zone then
                Input.held = zone
                Input.holdStart = { x=pos.X, y=pos.Y, t=tick() }
                if zone.onPress then zone.onPress(pos.X, pos.Y, input) end
            end
        elseif input.UserInputType == Enum.UserInputType.Keyboard then
            -- broadcast to keybind listeners
            if DrawLib._keyListeners then
                for _, fn in pairs(DrawLib._keyListeners) do pcall(fn, input.KeyCode, true) end
            end
        end
    end)
    UserInputService.InputChanged:Connect(function(input, processed)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local pos = input.Position
            Input.lastMouse = Vector2.new(pos.X, pos.Y)
            if Input.held and Input.held.onDrag then
                Input.held.onDrag(pos.X, pos.Y, input)
            end
        end
    end)
    UserInputService.InputEnded:Connect(function(input, processed)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if Input.held then
                local pos = input.Position
                if Input.held.onRelease then
                    Input.held.onRelease(pos.X, pos.Y, input)
                end
                Input.held = nil
                Input.holdStart = nil
            end
        elseif input.UserInputType == Enum.UserInputType.Keyboard then
            if DrawLib._keyListeners then
                for _, fn in pairs(DrawLib._keyListeners) do pcall(fn, input.KeyCode, false) end
            end
        end
    end)
end

-- ====================================================================
-- GLOBAL FRAME LOOP
-- ====================================================================
DrawLib._loaded = false
DrawLib._keyListeners = {}
DrawLib._customData = {}
DrawLib._loadedModules = {}
DrawLib._onLoadCallbacks = {}
DrawLib._registeredElements = {}        -- via RegisterElement
DrawLib._sectionPatches = {}            -- via PatchSection
DrawLib._hooks = {}                     -- via Hook
DrawLib._extends = {}                   -- via Extend
DrawLib._optionWatchers = {}            -- via WatchOption
DrawLib._keybindBtnVisible = {}
DrawLib._mobileKeybindsHidden = {}
DrawLib._keybindPositions = {}
DrawLib._toggleBtnVisible = true

if not DrawLib._loaded then
    Input.install()
    RunService.RenderStepped:Connect(function()
        Anim.step()
        if DrawLib._renderHooks then
            for _, h in ipairs(DrawLib._renderHooks) do pcall(h) end
        end
    end)
    DrawLib._loaded = true
end

DrawLib._renderHooks = {}

-- ====================================================================
-- ELEMENT BASE — anything drawn on screen with show/hide/destroy
-- ====================================================================
local function newElement()
    local el = {
        _parts   = {},      -- Drawing primitives
        _groups  = {},      -- roundedGroup objects
        _zones   = {},      -- input zones
        _children= {},
        _visible = true,
        _z       = 1,
    }
    function el:track(part)
        self._parts[#self._parts+1] = part
        return part
    end
    function el:trackGroup(g) self._groups[#self._groups+1] = g; return g end
    function el:trackZone(z)  self._zones[#self._zones+1] = z; return z end
    function el:setVisible(v)
        self._visible = v
        for _, p in ipairs(self._parts) do p.Visible = v end
        for _, g in ipairs(self._groups) do g:SetVisible(v) end
        for _, c in ipairs(self._children) do
            if c.setVisible then c:setVisible(v) end
        end
    end
    function el:destroy()
        for _, p in ipairs(self._parts) do pcall(function() p:Remove() end) end
        for _, g in ipairs(self._groups) do g:Destroy() end
        for _, z in ipairs(self._zones) do Input.unregister(z) end
        for _, c in ipairs(self._children) do if c.destroy then c:destroy() end end
        self._parts, self._groups, self._zones, self._children = {}, {}, {}, {}
    end
    return el
end

-- ====================================================================
-- WINDOW
-- ====================================================================

function DrawLib:Window(Settings)
    Settings = Settings or {}
    local WindowFunctions = { Settings = Settings, _opened = true }
    local T = DrawLib.Theme

    local vp = getViewport()
    local mobile = isMobile()

    -- Compute window size: on mobile fill ~92% screen, on desktop respect Settings.Size or default
    local W, H
    if mobile then
        W = math.min(vp.X - 24, 520)
        H = math.min(vp.Y - 100, 720)
    else
        if Settings.Size then
            W = Settings.Size.X.Offset > 0 and Settings.Size.X.Offset or 720
            H = Settings.Size.Y.Offset > 0 and Settings.Size.Y.Offset or 520
        else
            W = 720
            H = 520
        end
    end

    local X = math.floor((vp.X - W) / 2)
    local Y = math.floor((vp.Y - H) / 2)

    WindowFunctions._x, WindowFunctions._y, WindowFunctions._w, WindowFunctions._h = X, Y, W, H

    -- z-index plan:
    --   1   = base shadow
    --   5   = window background
    --   10  = topbar / tab bar
    --   15  = section panel
    --   20  = elements
    --   25  = element interactive overlays (slider knobs etc.)
    --   100 = dropdowns / colorpicker popups
    --   150 = notifications
    --   200 = dialogs/modals
    --   250 = FAB toggle button (always on top)
    local Z = {
        shadow=2, bg=5, topbar=10, panel=14, element=20, overlay=24,
        popup=100, notif=150, dialog=200, fab=250,
    }

    local Win = newElement()
    WindowFunctions._el = Win

    -------------------------------------------------------------------
    -- SHADOW + BACKGROUND
    -------------------------------------------------------------------
    Win:trackGroup(Draw.shadow(X, Y, W, H, 14, Z.shadow))
    local bg     = Win:trackGroup(Draw.roundedGroup(X, Y, W, H, 14, T.Background, 0.04, Z.bg))
    local border = Win:trackGroup(Draw.roundedGroup(X-1, Y-1, W+2, H+2, 15, T.Border, 0.7, Z.bg-1))

    -- Header bar (gradient accent top)
    local headerH = mobile and 56 or 52
    local header = Win:trackGroup(Draw.roundedGroup(X, Y, W, headerH, 14, T.Surface, 0, Z.topbar))
    -- Hide bottom corners of header (overlay rect)
    Win:track(Draw.rect(X, Y + headerH - 14, W, 14, T.Surface, 0, Z.topbar))
    -- Accent thin line under header
    Win:track(Draw.rect(X + 14, Y + headerH - 1, W - 28, 1, T.Accent, 0.4, Z.topbar+1))

    -- Title + subtitle
    local title = Win:track(Draw.text(Settings.Title or "DrawLib", X + 18, Y + 10, mobile and 18 or 17, T.Text, Drawing.Fonts.UI, false, Z.topbar+2))
    local subtitle = Win:track(Draw.text(Settings.Subtitle or "", X + 18, Y + 30, mobile and 13 or 12, T.TextDim, Drawing.Fonts.UI, false, Z.topbar+2))

    WindowFunctions._title, WindowFunctions._subtitle = title, subtitle

    -------------------------------------------------------------------
    -- WINDOW CONTROLS (close / minimize)
    -------------------------------------------------------------------
    local controlsList = {}
    local function makeControl(label, color, callback, order)
        local size = 22
        local cx = X + W - 18 - (order-1) * (size + 8) - size
        local cy = Y + math.floor((headerH - size) / 2)
        local g = Win:trackGroup(Draw.roundedGroup(cx, cy, size, size, 6, color, 0, Z.topbar+2))
        local txt = Win:track(Draw.text(label, cx + size/2, cy + 2, 16, T.Text, Drawing.Fonts.UI, true, Z.topbar+3))
        local zone = Input.register({
            x=cx, y=cy, w=size, h=size, z=Z.topbar+2,
            onPress = function()
                Anim.color(color, T.Text, 0.12, Easing.outQuad, function(c) g:SetColor(c) end)
            end,
            onRelease = function(rx, ry)
                Anim.color(T.Text, color, 0.12, Easing.outQuad, function(c) g:SetColor(c) end)
                if pointInRect(rx, ry, cx, cy, size, size) then
                    if callback then pcall(callback) end
                end
            end,
            visible = function() return WindowFunctions._opened end,
        })
        Win:trackZone(zone)
        return { g=g, txt=txt, zone=zone }
    end

    local disabled = Settings.DisabledWindowControls or {}
    local function isDisabled(name)
        for _, n in ipairs(disabled) do if n == name then return true end end
        return false
    end

    if not isDisabled("Exit") then
        controlsList.exit = makeControl("×", T.Danger, function() WindowFunctions:Unload() end, 1)
    end
    if not isDisabled("Minimize") then
        controlsList.min = makeControl("–", T.Warning, function() WindowFunctions:SetState(false) end, 2)
    end

    -------------------------------------------------------------------
    -- TAB BAR — bottom on mobile, top-left on desktop
    -------------------------------------------------------------------
    local tabBarH = mobile and 60 or 44
    local tabBarY, tabBarX, tabBarW
    if mobile then
        tabBarY = Y + H - tabBarH
        tabBarX = X
        tabBarW = W
    else
        tabBarY = Y + headerH + 8
        tabBarX = X + 12
        tabBarW = W - 24
    end

    local tabBarBg = Win:trackGroup(Draw.roundedGroup(tabBarX, tabBarY, tabBarW, tabBarH, mobile and 0 or 10, T.Surface, 0, Z.topbar))
    -- Cover top corners if at the bottom edge of mobile window
    if mobile then
        Win:track(Draw.rect(tabBarX, tabBarY, tabBarW, 14, T.Surface, 0, Z.topbar))
    end
    -- Divider line
    if mobile then
        Win:track(Draw.rect(tabBarX, tabBarY, tabBarW, 1, T.Border, 0.5, Z.topbar+1))
    else
        Win:track(Draw.rect(tabBarX, tabBarY + tabBarH, tabBarW, 1, T.Border, 0.5, Z.topbar+1))
    end

    -------------------------------------------------------------------
    -- CONTENT AREA + SCROLL STATE
    -------------------------------------------------------------------
    local contentX, contentY, contentW, contentH
    if mobile then
        contentX = X + 8
        contentY = Y + headerH + 6
        contentW = W - 16
        contentH = (tabBarY) - contentY - 6
    else
        contentX = X + 12
        contentY = Y + headerH + 8 + tabBarH + 8
        contentW = W - 24
        contentH = (Y + H) - contentY - 12
    end

    WindowFunctions._content = { x=contentX, y=contentY, w=contentW, h=contentH }

    -------------------------------------------------------------------
    -- STATE
    -------------------------------------------------------------------
    local tabGroups = {}
    local allTabs = {}
    local activeTab = nil
    WindowFunctions._tabGroups = tabGroups
    WindowFunctions._tabs = allTabs

    -- Show / hide window contents (animated)
    function WindowFunctions:SetState(state)
        if state == self._opened then return end
        self._opened = state
        Win:setVisible(state)
        if state and activeTab then activeTab:_render() end
    end
    function WindowFunctions:GetState() return self._opened end

    -- ============================================================
    -- TAB GROUP / TAB / SECTION
    -- ============================================================
    function WindowFunctions:TabGroup()
        local SectionFunctions = {}
        local TabsInGroup = {}
        table.insert(tabGroups, { Tabs = TabsInGroup, _sectionFns = SectionFunctions })

        function SectionFunctions:Tab(TabSettings)
            TabSettings = TabSettings or {}
            local TabFunctions = { Settings = TabSettings, _sections = {} }

            -- Tab button geometry
            local btn = newElement()
            table.insert(TabsInGroup, TabFunctions)
            table.insert(allTabs, TabFunctions)

            TabFunctions._btn = btn

            -- Per-tab content area (split left/right on desktop, single column on mobile)
            local function getSides()
                if mobile then
                    return {
                        left  = { x=contentX, y=contentY, w=contentW, h=contentH },
                        right = { x=contentX, y=contentY, w=contentW, h=contentH },
                    }
                else
                    local halfW = math.floor((contentW - 10) / 2)
                    return {
                        left  = { x=contentX,             y=contentY, w=halfW, h=contentH },
                        right = { x=contentX+halfW+10,    y=contentY, w=halfW, h=contentH },
                    }
                end
            end
            TabFunctions._getSides = getSides

            -- Scroll offsets per side
            TabFunctions._scroll = { left=0, right=0 }
            TabFunctions._sectionsBySide = { Left = {}, Right = {} }

            -- Re-layout this tab
            function TabFunctions:_render()
                if activeTab ~= self then return end
                local sides = self:_getSides()
                for _, sideName in ipairs({"Left","Right"}) do
                    local sideKey = sideName:lower()
                    local box = sides[sideKey]
                    local list = self._sectionsBySide[sideName]
                    local cursorY = box.y - self._scroll[sideKey]
                    for _, sec in ipairs(list) do
                        sec:_layout(box.x, cursorY, box.w)
                        cursorY = cursorY + sec._height + 10
                    end
                    self._maxScroll = self._maxScroll or {}
                    self._maxScroll[sideKey] = math.max(0, (cursorY + self._scroll[sideKey] - box.y) - box.h)
                end
            end

            -- Scroll handler for this tab — registered when active
            TabFunctions._scrollZone = nil

            function TabFunctions:Section(SecSettings)
                SecSettings = SecSettings or {}
                local side = SecSettings.Side or "Left"
                if mobile then side = "Left" end

                local Sec = newElement()
                local SectionApi = { _el = Sec, _height = 0, _elements = {}, Settings = SecSettings }

                -- Title bar
                SectionApi._titleH = (SecSettings.Name and 28) or 0

                -- Layout method called by Tab._render
                function SectionApi:_layout(x, y, w)
                    self._x, self._y, self._w = x, y, w
                    -- destroy and rebuild on each layout (simpler & robust)
                    Sec:destroy()
                    Sec = newElement()
                    self._el = Sec

                    -- Section panel background
                    local titleH = self._titleH
                    local innerPad = 10
                    local cursorY = y + titleH + innerPad
                    local startY = y

                    -- Render elements (collect heights first)
                    local renderedHeights = {}
                    for i, item in ipairs(self._elements) do
                        local h = item:_estimateHeight(w - innerPad*2)
                        renderedHeights[i] = h
                    end
                    local totalH = titleH + innerPad
                    for i, h in ipairs(renderedHeights) do
                        totalH = totalH + h + (i < #renderedHeights and 6 or 0)
                    end
                    totalH = totalH + innerPad

                    -- Draw panel background
                    if totalH > 0 then
                        Sec:trackGroup(Draw.roundedGroup(x, startY, w, totalH, 12, T.Surface, 0, Z.panel))
                    end

                    if SecSettings.Name then
                        Sec:track(Draw.text(SecSettings.Name, x + innerPad, startY + 6, 14, T.Text, Drawing.Fonts.UI, false, Z.panel+2))
                        Sec:track(Draw.rect(x + innerPad, startY + titleH - 2, w - innerPad*2, 1, T.Border, 0.5, Z.panel+1))
                    end

                    -- Now layout each element
                    cursorY = startY + titleH + innerPad
                    for i, item in ipairs(self._elements) do
                        item:_render(x + innerPad, cursorY, w - innerPad*2, Sec)
                        cursorY = cursorY + renderedHeights[i] + 6
                    end

                    self._height = totalH
                end

                -- Clip elements outside content area
                function SectionApi:_addElement(elDef)
                    table.insert(self._elements, elDef)
                end

                -- =================================================
                -- ELEMENT FACTORY HELPERS
                -- =================================================
                local function defElement(typeName, settings, flag, makeRender, methods)
                    local item = {
                        Type = typeName, Settings = settings, Flag = flag,
                        _el = nil, _visible = true,
                    }
                    function item:_estimateHeight(w)
                        return (settings._heightHint or 36)
                    end
                    item._render = makeRender(item, settings, flag)
                    if methods then for k, v in pairs(methods) do item[k] = v end end
                    if flag then
                        item.Class = typeName
                        DrawLib.Options[flag] = item
                    end
                    self:_addElement(item)
                    return item
                end

                -- =================================================
                -- BUTTON
                -- =================================================
                function SectionApi:Button(s, flag)
                    s = s or {}
                    local descH = s.Description and 14 or 0
                    s._heightHint = 36 + descH
                    local item = {
                        Type="Button", Settings=s, Flag=flag, Class="Button"
                    }
                    function item:_estimateHeight(w)
                        return 36 + (self.Settings.Description and 14 or 0)
                    end
                    function item:_render(x, y, w, secEl)
                        if self._visible == false then return end
                        local h = 36
                        local g = secEl:trackGroup(Draw.roundedGroup(x, y, w, h, 8, T.SurfaceHover, 0, Z.element))
                        local name = secEl:track(Draw.text(self.Settings.Name or "Button", x + 12, y + (h-14)/2 - 1, 14, T.Text, Drawing.Fonts.UI, false, Z.element+2))
                        local chevron = secEl:track(Draw.text("›", x + w - 18, y + 6, 18, T.TextDim, Drawing.Fonts.UI, false, Z.element+2))
                        local zone = Input.register({
                            x=x, y=y, w=w, h=h, z=Z.element,
                            onPress = function() g:SetColor(T.SurfaceActive) end,
                            onRelease = function(rx, ry)
                                Anim.color(T.SurfaceActive, T.SurfaceHover, 0.18, Easing.outQuad, function(c) g:SetColor(c) end)
                                if pointInRect(rx, ry, x, y, w, h) and self.Settings.Callback then
                                    task.spawn(self.Settings.Callback)
                                end
                            end,
                            visible = function() return self._visible and WindowFunctions._opened and activeTab == TabFunctions end,
                        })
                        secEl:trackZone(zone)
                        if self.Settings.Description then
                            secEl:track(Draw.text(self.Settings.Description, x + 12, y + h + 2, 11, T.TextMuted, Drawing.Fonts.UI, false, Z.element+2))
                        end
                    end
                    function item:UpdateName(n) self.Settings.Name = n; TabFunctions:_render() end
                    function item:UpdateDescription(d) self.Settings.Description = d; TabFunctions:_render() end
                    function item:SetCallback(fn) self.Settings.Callback = fn end
                    function item:SetVisibility(v) self._visible = v; TabFunctions:_render() end
                    SectionApi:_addElement(item)
                    if flag then DrawLib.Options[flag] = item end
                    return item
                end

                -- =================================================
                -- TOGGLE
                -- =================================================
                function SectionApi:Toggle(s, flag)
                    s = s or {}
                    s._heightHint = 36
                    local item = { Type="Toggle", Settings=s, Flag=flag, Class="Toggle", State=s.Default and true or false }
                    function item:_estimateHeight() return 36 end
                    function item:_render(x, y, w, secEl)
                        if self._visible == false then return end
                        local h = 36
                        secEl:trackGroup(Draw.roundedGroup(x, y, w, h, 8, T.SurfaceHover, 0, Z.element))
                        secEl:track(Draw.text(self.Settings.Name or "Toggle", x + 12, y + (h-14)/2 - 1, 14, T.Text, Drawing.Fonts.UI, false, Z.element+2))

                        -- Toggle pill
                        local tw, th = 36, 20
                        local tx, ty = x + w - tw - 10, y + (h - th)/2
                        local pill = secEl:trackGroup(Draw.roundedGroup(tx, ty, tw, th, 10, self.State and T.Accent or T.Border, 0, Z.element+1))
                        local knobR = 7
                        local knobX = self.State and (tx + tw - knobR - 3) or (tx + knobR + 3)
                        local knob = secEl:track(Draw.circle(knobX, ty + th/2, knobR, T.Text, true, 0, Z.element+3))

                        local function setState(newState, fromUser)
                            self.State = newState
                            local targetColor = newState and T.Accent or T.Border
                            local targetX = newState and (tx + tw - knobR - 3) or (tx + knobR + 3)
                            local startColor = pill.color
                            local startX = knob.Position.X
                            Anim.tween(0.18, Easing.outCubic, function(t)
                                pill:SetColor(lerpColor(startColor, targetColor, t))
                                knob.Position = Vector2.new(startX + (targetX - startX) * t, ty + th/2)
                            end)
                            if fromUser and self.Settings.Callback then
                                task.spawn(self.Settings.Callback, newState)
                            end
                            if self.Flag and DrawLib._optionWatchers[self.Flag] then
                                for _, fn in ipairs(DrawLib._optionWatchers[self.Flag]) do
                                    pcall(fn, newState)
                                end
                            end
                            if self.Flag and self.Settings.ForceAutoLoad and fromUser then
                                DrawLib:FALSave(self.Flag, self)
                            end
                        end
                        self._setState = setState

                        local zone = Input.register({
                            x=x, y=y, w=w, h=h, z=Z.element,
                            onRelease = function(rx, ry)
                                if pointInRect(rx, ry, x, y, w, h) then
                                    setState(not self.State, true)
                                end
                            end,
                            visible = function() return self._visible and WindowFunctions._opened and activeTab == TabFunctions end,
                        })
                        secEl:trackZone(zone)
                    end
                    function item:Toggle() if self._setState then self._setState(not self.State, true) end end
                    function item:UpdateState(state) self.State = state and true or false; if self._setState then self._setState(self.State, true) else if self.Settings.Callback then task.spawn(self.Settings.Callback, self.State) end end end
                    function item:GetState() return self.State end
                    function item:UpdateName(n) self.Settings.Name = n; TabFunctions:_render() end
                    function item:SetCallback(fn) self.Settings.Callback = fn end
                    function item:SetVisibility(v) self._visible = v; TabFunctions:_render() end
                    function item:SetEnabledColor(c) self.Settings.EnabledColor = c end
                    function item:SetDisabledColor(c) self.Settings.DisabledColor = c end
                    function item:SetColor(c) self:SetEnabledColor(c) end
                    SectionApi:_addElement(item)
                    if flag then
                        DrawLib.Options[flag] = item
                        if s.ForceAutoLoad then task.delay(s.FALoadDelay or 0, function() DrawLib:FALLoad(flag, item) end) end
                    end
                    -- initial callback
                    if s.Default and s.Callback then task.spawn(s.Callback, true) end
                    return item
                end

                -- =================================================
                -- SLIDER
                -- =================================================
                function SectionApi:Slider(s, flag)
                    s = s or {}
                    s.Minimum = s.Minimum or s.Min or 0
                    s.Maximum = s.Maximum or s.Max or 100
                    s.Default = s.Default or s.Minimum
                    s.Precision = s.Precision or 0
                    s.DisplayMethod = s.DisplayMethod or "Value"
                    s._heightHint = 52
                    local item = { Type="Slider", Settings=s, Flag=flag, Class="Slider", Value = s.Default }

                    function item:_estimateHeight() return 52 end
                    function item:_render(x, y, w, secEl)
                        if self._visible == false then return end
                        local h = 52
                        secEl:trackGroup(Draw.roundedGroup(x, y, w, h, 8, T.SurfaceHover, 0, Z.element))
                        secEl:track(Draw.text(self.Settings.Name or "Slider", x + 12, y + 8, 14, T.Text, Drawing.Fonts.UI, false, Z.element+2))

                        local function fmt(v)
                            local p = self.Settings.Precision
                            local mult = 10^p
                            local rounded = math.floor(v * mult + 0.5) / mult
                            if self.Settings.DisplayMethod == "Percent" then
                                local pct = (rounded - self.Settings.Minimum) / (self.Settings.Maximum - self.Settings.Minimum) * 100
                                return string.format("%d%%", math.floor(pct + 0.5))
                            end
                            if p == 0 then return tostring(math.floor(rounded)) end
                            return string.format("%."..p.."f", rounded)
                        end
                        local valLabel = secEl:track(Draw.text(fmt(self.Value), x + w - 12, y + 8, 13, T.Accent, Drawing.Fonts.UI, false, Z.element+2))
                        valLabel.Position = Vector2.new(x + w - 12 - valLabel.TextBounds.X, y + 8)

                        -- Track bar
                        local trackY = y + 32
                        local trackH = 8
                        local trackX = x + 12
                        local trackW = w - 24
                        secEl:trackGroup(Draw.roundedGroup(trackX, trackY, trackW, trackH, 4, T.Border, 0, Z.element+1))

                        local function pctFromValue(v)
                            return (v - self.Settings.Minimum) / (self.Settings.Maximum - self.Settings.Minimum)
                        end
                        local pct = pctFromValue(self.Value)
                        local fillW = math.max(8, trackW * pct)
                        local fill = secEl:trackGroup(Draw.roundedGroup(trackX, trackY, fillW, trackH, 4, T.Accent, 0, Z.element+2))

                        local knobR = 9
                        local knobX = trackX + trackW * pct
                        local knobY = trackY + trackH/2
                        local knob = secEl:track(Draw.circle(knobX, knobY, knobR, T.Text, true, 0, Z.element+4))
                        local knobOutline = secEl:track(Draw.circle(knobX, knobY, knobR, T.Accent, false, 0, Z.element+5))
                        knobOutline.Thickness = 2

                        local function setValue(newVal, fromUser)
                            newVal = clamp(newVal, self.Settings.Minimum, self.Settings.Maximum)
                            local mult = 10^self.Settings.Precision
                            newVal = math.floor(newVal * mult + 0.5) / mult
                            self.Value = newVal
                            local np = pctFromValue(newVal)
                            local newFillW = math.max(8, trackW * np)
                            local newKnobX = trackX + trackW * np
                            fill:SetSize(newFillW, trackH)
                            knob.Position = Vector2.new(newKnobX, knobY)
                            knobOutline.Position = Vector2.new(newKnobX, knobY)
                            valLabel.Text = fmt(newVal)
                            valLabel.Position = Vector2.new(x + w - 12 - valLabel.TextBounds.X, y + 8)
                            if fromUser and self.Settings.Callback then task.spawn(self.Settings.Callback, newVal) end
                            if self.Flag and DrawLib._optionWatchers[self.Flag] then
                                for _, fn in ipairs(DrawLib._optionWatchers[self.Flag]) do pcall(fn, newVal) end
                            end
                            if self.Flag and self.Settings.ForceAutoLoad and fromUser then DrawLib:FALSave(self.Flag, self) end
                        end
                        self._setValue = setValue

                        local zone = Input.register({
                            x=trackX-6, y=trackY-12, w=trackW+12, h=trackH+24, z=Z.element+3,
                            onPress = function(px, py)
                                local p = (px - trackX) / trackW
                                setValue(self.Settings.Minimum + p * (self.Settings.Maximum - self.Settings.Minimum), true)
                            end,
                            onDrag = function(px, py)
                                local p = clamp((px - trackX) / trackW, 0, 1)
                                setValue(self.Settings.Minimum + p * (self.Settings.Maximum - self.Settings.Minimum), true)
                            end,
                            visible = function() return self._visible and WindowFunctions._opened and activeTab == TabFunctions end,
                        })
                        secEl:trackZone(zone)
                    end

                    function item:UpdateValue(v, fromConfig)
                        self.Value = tonumber(v) or self.Value
                        if self._setValue then self._setValue(self.Value, not fromConfig)
                        elseif (not fromConfig) and self.Settings.Callback then task.spawn(self.Settings.Callback, self.Value) end
                    end
                    function item:GetValue() return self.Value end
                    function item:UpdateName(n) self.Settings.Name = n; TabFunctions:_render() end
                    function item:SetCallback(fn) self.Settings.Callback = fn end
                    function item:SetVisibility(v) self._visible = v; TabFunctions:_render() end
                    SectionApi:_addElement(item)
                    if flag then
                        DrawLib.Options[flag] = item
                        if s.ForceAutoLoad then task.delay(s.FALoadDelay or 0, function() DrawLib:FALLoad(flag, item) end) end
                    end
                    return item
                end

                -- =================================================
                -- INPUT (textbox)
                -- =================================================
                function SectionApi:Input(s, flag)
                    s = s or {}
                    s._heightHint = 56
                    local item = { Type="Input", Settings=s, Flag=flag, Class="Input", Text = s.Default or "" }
                    function item:_estimateHeight() return 56 end
                    function item:_render(x, y, w, secEl)
                        if self._visible == false then return end
                        local h = 56
                        secEl:trackGroup(Draw.roundedGroup(x, y, w, h, 8, T.SurfaceHover, 0, Z.element))
                        secEl:track(Draw.text(self.Settings.Name or "Input", x + 12, y + 6, 13, T.TextDim, Drawing.Fonts.UI, false, Z.element+2))
                        local boxY = y + 24
                        local boxH = 26
                        local boxBg = secEl:trackGroup(Draw.roundedGroup(x + 10, boxY, w - 20, boxH, 6, T.Background, 0, Z.element+1))
                        local boxStroke = secEl:trackGroup(Draw.roundedGroup(x + 10, boxY, w - 20, boxH, 6, T.Border, 0, Z.element))
                        -- the bg over the stroke creates a 1px border illusion: simpler — just use one rect
                        local placeholder = self.Settings.Placeholder or "Type here..."
                        local displayText = (self.Text and self.Text ~= "") and self.Text or placeholder
                        local displayColor = (self.Text and self.Text ~= "") and T.Text or T.TextMuted
                        local txt = secEl:track(Draw.text(displayText, x + 18, boxY + 6, 13, displayColor, Drawing.Fonts.UI, false, Z.element+3))

                        local function startEdit()
                            -- Use UserInputService keyboard capture via TextChannel polling
                            -- Simpler: create a transparent TextBox via SetCore? Not available.
                            -- Fallback: build a hidden ScreenGui TextBox for editing.
                            local sg = Instance.new("ScreenGui")
                            sg.ResetOnSpawn = false
                            sg.IgnoreGuiInset = true
                            sg.DisplayOrder = 2147483646
                            local parent = (gethui and gethui()) or (RunService:IsStudio() and LocalPlayer:FindFirstChild("PlayerGui")) or DrawLib.GetService("CoreGui")
                            sg.Parent = parent
                            local tb = Instance.new("TextBox")
                            tb.Size = UDim2.new(0, w - 20, 0, boxH)
                            tb.Position = UDim2.new(0, x + 10, 0, boxY)
                            tb.BackgroundColor3 = T.Background
                            tb.BorderSizePixel = 0
                            tb.TextColor3 = T.Text
                            tb.TextSize = 13
                            tb.Font = Enum.Font.Gotham
                            tb.PlaceholderText = placeholder
                            tb.PlaceholderColor3 = T.TextMuted
                            tb.Text = self.Text or ""
                            tb.TextXAlignment = Enum.TextXAlignment.Left
                            tb.ClearTextOnFocus = false
                            tb.Parent = sg
                            local pad = Instance.new("UIPadding")
                            pad.PaddingLeft = UDim.new(0, 8); pad.Parent = tb
                            local cor = Instance.new("UICorner"); cor.CornerRadius = UDim.new(0,6); cor.Parent = tb
                            local str = Instance.new("UIStroke"); str.Color = T.Accent; str.Thickness = 1; str.Parent = tb
                            tb:CaptureFocus()
                            tb.FocusLost:Connect(function(enter)
                                self.Text = tb.Text
                                txt.Text = (self.Text and self.Text ~= "") and self.Text or placeholder
                                txt.Color = (self.Text and self.Text ~= "") and T.Text or T.TextMuted
                                if self.Settings.Callback then task.spawn(self.Settings.Callback, self.Text) end
                                if self.Settings.onChanged then task.spawn(self.Settings.onChanged, self.Text) end
                                if self.Flag and self.Settings.ForceAutoLoad then DrawLib:FALSave(self.Flag, self) end
                                sg:Destroy()
                            end)
                            tb:GetPropertyChangedSignal("Text"):Connect(function()
                                if self.Settings.onChanged then task.spawn(self.Settings.onChanged, tb.Text) end
                            end)
                        end

                        local zone = Input.register({
                            x=x+10, y=boxY, w=w-20, h=boxH, z=Z.element+1,
                            onRelease = function(rx, ry) if pointInRect(rx, ry, x+10, boxY, w-20, boxH) then startEdit() end end,
                            visible = function() return self._visible and WindowFunctions._opened and activeTab == TabFunctions end,
                        })
                        secEl:trackZone(zone)
                    end
                    function item:UpdateName(n) self.Settings.Name = n; TabFunctions:_render() end
                    function item:SetVisibility(v) self._visible = v; TabFunctions:_render() end
                    function item:GetInput() return self.Text end
                    function item:GetText() return self.Text end
                    function item:SetCallback(fn) self.Settings.Callback = fn end
                    function item:SetOnChanged(fn) self.Settings.onChanged = fn end
                    function item:UpdatePlaceholder(p) self.Settings.Placeholder = p; TabFunctions:_render() end
                    function item:Clear() self.Text = ""; TabFunctions:_render() end
                    function item:UpdateText(t) self.Text = t or ""; TabFunctions:_render() end
                    SectionApi:_addElement(item)
                    if flag then
                        DrawLib.Options[flag] = item
                        if s.ForceAutoLoad then task.delay(s.FALoadDelay or 0, function() DrawLib:FALLoad(flag, item) end) end
                    end
                    return item
                end

                -- =================================================
                -- KEYBIND
                -- =================================================
                function SectionApi:Keybind(s, flag)
                    s = s or {}
                    s._heightHint = 36
                    local item = { Type="Keybind", Settings=s, Flag=flag, Class="Keybind", Bind = s.Default }

                    function item:_estimateHeight() return 36 end
                    function item:_render(x, y, w, secEl)
                        if self._visible == false then return end
                        local h = 36
                        secEl:trackGroup(Draw.roundedGroup(x, y, w, h, 8, T.SurfaceHover, 0, Z.element))
                        secEl:track(Draw.text(self.Settings.Name or "Keybind", x + 12, y + (h-14)/2 - 1, 14, T.Text, Drawing.Fonts.UI, false, Z.element+2))

                        local pillW = 64
                        local pillH = 22
                        local pillX = x + w - pillW - 10
                        local pillY = y + (h - pillH)/2
                        local pill = secEl:trackGroup(Draw.roundedGroup(pillX, pillY, pillW, pillH, 6, T.Background, 0, Z.element+1))
                        local label = (self.Bind and self.Bind.Name) or "None"
                        local lbl = secEl:track(Draw.text(label, pillX + pillW/2, pillY + 3, 12, T.TextDim, Drawing.Fonts.UI, true, Z.element+3))

                        local listening = false
                        local function startListen()
                            listening = true
                            lbl.Text = "..."
                            lbl.Color = T.Accent
                        end
                        local function setBind(key)
                            self.Bind = key
                            lbl.Text = (key and key.Name) or "None"
                            lbl.Color = T.TextDim
                            if self.Settings.onBinded then task.spawn(self.Settings.onBinded, key) end
                            if self.Flag and self.Settings.ForceAutoLoad then DrawLib:FALSave(self.Flag, self) end
                        end
                        self._setBind = setBind

                        local listenerId = "kb_"..tostring(flag or math.random(1,1e9))
                        DrawLib._keyListeners[listenerId] = function(key, isDown)
                            if listening and isDown then
                                listening = false
                                setBind(key)
                            elseif (not listening) and isDown and self.Bind and key == self.Bind then
                                if self.Settings.Callback then task.spawn(self.Settings.Callback, key) end
                            end
                        end

                        local zone = Input.register({
                            x=pillX, y=pillY, w=pillW, h=pillH, z=Z.element+1,
                            onRelease = function(rx, ry) if pointInRect(rx, ry, pillX, pillY, pillW, pillH) then startListen() end end,
                            visible = function() return self._visible and WindowFunctions._opened and activeTab == TabFunctions end,
                        })
                        secEl:trackZone(zone)
                    end

                    function item:Bind(key) self.Bind = key; if self._setBind then self._setBind(key) end end
                    function item:Unbind() if self._setBind then self._setBind(nil) end end
                    function item:GetBind() return self.Bind end
                    function item:UpdateName(n) self.Settings.Name = n; TabFunctions:_render() end
                    function item:SetCallback(fn) self.Settings.Callback = fn end
                    function item:SetVisibility(v) self._visible = v; TabFunctions:_render() end
                    function item:SetMobileImage() end
                    function item:SetMobileButtonVisibility(state) DrawLib._keybindBtnVisible[flag] = state end
                    SectionApi:_addElement(item)
                    if flag then
                        DrawLib.Options[flag] = item
                        if s.ForceAutoLoad then task.delay(s.FALoadDelay or 0, function() DrawLib:FALLoad(flag, item) end) end
                    end
                    return item
                end

                -- =================================================
                -- DROPDOWN  (single + multi + search)
                -- =================================================
                function SectionApi:Dropdown(s, flag)
                    s = s or {}
                    s.Options = s.Options or {}
                    s.Multi = s.Multi or false
                    s._heightHint = 36
                    local item = { Type="Dropdown", Settings=s, Flag=flag, Class="Dropdown", Value = nil }

                    -- initialise default
                    if s.Multi then
                        item.Value = {}
                        if type(s.Default) == "table" then
                            for _, v in ipairs(s.Default) do item.Value[v] = true end
                        end
                    else
                        if type(s.Default) == "number" then item.Value = s.Options[s.Default]
                        elseif type(s.Default) == "string" then item.Value = s.Default end
                    end

                    function item:_estimateHeight() return 36 end

                    function item:_render(x, y, w, secEl)
                        if self._visible == false then return end
                        local h = 36
                        secEl:trackGroup(Draw.roundedGroup(x, y, w, h, 8, T.SurfaceHover, 0, Z.element))
                        secEl:track(Draw.text(self.Settings.Name or "Dropdown", x + 12, y + (h-14)/2 - 1, 14, T.Text, Drawing.Fonts.UI, false, Z.element+2))

                        local valueStr
                        if self.Settings.Multi then
                            local arr = {}
                            for k, _ in pairs(self.Value or {}) do arr[#arr+1] = k end
                            valueStr = #arr > 0 and table.concat(arr, ", ") or "..."
                        else
                            valueStr = (self.Value and tostring(self.Value)) or "..."
                        end
                        if #valueStr > 20 then valueStr = valueStr:sub(1, 20) .. ".." end
                        local valLbl = secEl:track(Draw.text(valueStr, x + w - 26, y + (h-13)/2 - 1, 13, T.Accent, Drawing.Fonts.UI, false, Z.element+2))
                        valLbl.Position = Vector2.new(x + w - 26 - valLbl.TextBounds.X, y + (h-13)/2 - 1)
                        secEl:track(Draw.text("▾", x + w - 18, y + (h-12)/2 - 1, 12, T.TextDim, Drawing.Fonts.UI, false, Z.element+2))

                        local popupOpen = false
                        local popupEl = nil

                        local function closePopup()
                            if popupEl then popupEl:destroy(); popupEl = nil end
                            popupOpen = false
                        end
                        local function openPopup()
                            if popupOpen then closePopup() return end
                            popupOpen = true
                            popupEl = newElement()
                            local optH = mobile and 36 or 28
                            local maxItems = math.min(8, #self.Settings.Options)
                            local popupH = optH * maxItems + 8
                            local popupW = w
                            local popupX = x
                            local popupY = y + h + 4
                            -- if popup goes off-screen vertically, place above
                            if popupY + popupH > Y + H - 8 then popupY = y - popupH - 4 end
                            popupEl:trackGroup(Draw.shadow(popupX, popupY, popupW, popupH, 8, Z.popup))
                            popupEl:trackGroup(Draw.roundedGroup(popupX, popupY, popupW, popupH, 8, T.Surface, 0, Z.popup))
                            popupEl:trackGroup(Draw.roundedGroup(popupX-1, popupY-1, popupW+2, popupH+2, 9, T.Border, 0.6, Z.popup-1))
                            for i, opt in ipairs(self.Settings.Options) do
                                if i > maxItems then break end
                                local oy = popupY + 4 + (i-1)*optH
                                local selected
                                if self.Settings.Multi then selected = self.Value[opt] else selected = self.Value == opt end
                                local bgC = selected and T.SurfaceActive or T.Surface
                                local rowG = popupEl:trackGroup(Draw.roundedGroup(popupX+4, oy, popupW-8, optH-2, 6, bgC, 0, Z.popup+1))
                                local tc = selected and T.Accent or T.Text
                                popupEl:track(Draw.text(opt, popupX + 14, oy + (optH-14)/2 - 1, 13, tc, Drawing.Fonts.UI, false, Z.popup+2))
                                if self.Settings.Multi then
                                    popupEl:track(Draw.text(selected and "✓" or "", popupX + popupW - 24, oy + (optH-14)/2 - 1, 14, T.Accent, Drawing.Fonts.UI, false, Z.popup+2))
                                end
                                local zone = Input.register({
                                    x=popupX+4, y=oy, w=popupW-8, h=optH-2, z=Z.popup+1,
                                    onRelease = function(rx, ry)
                                        if not pointInRect(rx, ry, popupX+4, oy, popupW-8, optH-2) then return end
                                        if self.Settings.Multi then
                                            self.Value[opt] = (not self.Value[opt]) and true or nil
                                            if self.Settings.Callback then task.spawn(self.Settings.Callback, self.Value) end
                                        else
                                            self.Value = opt
                                            if self.Settings.Callback then task.spawn(self.Settings.Callback, opt) end
                                            closePopup()
                                        end
                                        if self.Flag and self.Settings.ForceAutoLoad then DrawLib:FALSave(self.Flag, self) end
                                        if self.Flag and DrawLib._optionWatchers[self.Flag] then
                                            for _, fn in ipairs(DrawLib._optionWatchers[self.Flag]) do pcall(fn, self.Value) end
                                        end
                                        TabFunctions:_render()
                                    end,
                                    visible = function() return popupOpen end,
                                })
                                popupEl:trackZone(zone)
                            end
                            -- Backdrop click closes popup
                            local bd = Input.register({
                                x=0, y=0, w=vp.X, h=vp.Y, z=Z.popup-2,
                                onRelease = function() closePopup() end,
                                visible = function() return popupOpen end,
                            })
                            popupEl:trackZone(bd)
                        end
                        local zone = Input.register({
                            x=x, y=y, w=w, h=h, z=Z.element,
                            onRelease = function(rx, ry) if pointInRect(rx, ry, x, y, w, h) then openPopup() end end,
                            visible = function() return self._visible and WindowFunctions._opened and activeTab == TabFunctions end,
                        })
                        secEl:trackZone(zone)
                    end

                    function item:UpdateName(n) self.Settings.Name = n; TabFunctions:_render() end
                    function item:SetVisibility(v) self._visible = v; TabFunctions:_render() end
                    function item:UpdateSelection(sel)
                        if self.Settings.Multi then
                            if type(sel) == "table" then
                                self.Value = {}
                                for _, v in ipairs(sel) do self.Value[v] = true end
                            end
                        else
                            self.Value = sel
                        end
                        TabFunctions:_render()
                        if self.Settings.Callback then task.spawn(self.Settings.Callback, self.Value) end
                    end
                    function item:InsertOptions(newOpts)
                        for _, v in ipairs(newOpts) do table.insert(self.Settings.Options, v) end
                        TabFunctions:_render()
                    end
                    function item:ClearOptions() self.Settings.Options = {}; TabFunctions:_render() end
                    function item:GetOptions() return self.Settings.Options end
                    function item:RemoveOptions(remove)
                        local set = {}
                        for _, v in ipairs(remove) do set[v] = true end
                        local kept = {}
                        for _, v in ipairs(self.Settings.Options) do if not set[v] then kept[#kept+1] = v end end
                        self.Settings.Options = kept
                        TabFunctions:_render()
                    end
                    function item:IsOption(opt)
                        for _, v in ipairs(self.Settings.Options) do if v == opt then return true end end
                        return false
                    end
                    function item:SetCallback(fn) self.Settings.Callback = fn end
                    function item:GetValue() return self.Value end

                    SectionApi:_addElement(item)
                    if flag then
                        DrawLib.Options[flag] = item
                        if s.ForceAutoLoad then task.delay(s.FALoadDelay or 0, function() DrawLib:FALLoad(flag, item) end) end
                    end
                    return item
                end

                -- =================================================
                -- COLORPICKER (HSV wheel + brightness + alpha)
                -- =================================================
                function SectionApi:Colorpicker(s, flag)
                    s = s or {}
                    s.Default = s.Default or Color3.fromRGB(255, 255, 255)
                    s._heightHint = 36
                    local item = {
                        Type="Colorpicker", Settings=s, Flag=flag, Class="Colorpicker",
                        Color = s.Default, Alpha = s.Alpha or 1
                    }

                    function item:_estimateHeight() return 36 end
                    function item:_render(x, y, w, secEl)
                        if self._visible == false then return end
                        local h = 36
                        secEl:trackGroup(Draw.roundedGroup(x, y, w, h, 8, T.SurfaceHover, 0, Z.element))
                        secEl:track(Draw.text(self.Settings.Name or "Colorpicker", x + 12, y + (h-14)/2 - 1, 14, T.Text, Drawing.Fonts.UI, false, Z.element+2))

                        local swW, swH = 30, 20
                        local swX, swY = x + w - swW - 10, y + (h - swH)/2
                        local swatch = secEl:trackGroup(Draw.roundedGroup(swX, swY, swW, swH, 4, self.Color, 0, Z.element+1))
                        secEl:trackGroup(Draw.roundedGroup(swX-1, swY-1, swW+2, swH+2, 5, T.Border, 0.4, Z.element))

                        local popupOpen = false
                        local popupEl = nil

                        local function hsvFromColor(c)
                            return Color3.toHSV(c)
                        end
                        local function setColor(c, fromUser)
                            self.Color = c
                            swatch:SetColor(c)
                            if fromUser and self.Settings.Callback then
                                task.spawn(self.Settings.Callback, c, self.Alpha)
                            end
                            if self.Flag and self.Settings.ForceAutoLoad and fromUser then DrawLib:FALSave(self.Flag, self) end
                        end
                        self._setColor = setColor

                        local function closePopup()
                            if popupEl then popupEl:destroy(); popupEl = nil end
                            popupOpen = false
                        end
                        local function openPopup()
                            if popupOpen then closePopup() return end
                            popupOpen = true
                            popupEl = newElement()

                            local pW, pH = 220, 230
                            if self.Settings.Alpha ~= nil then pH = pH + 22 end
                            if mobile then pW, pH = math.min(280, W-32), pH + 30 end
                            local pX = math.min(x, X + W - pW - 8)
                            local pY = y + h + 4
                            if pY + pH > Y + H - 8 then pY = math.max(Y + 8, y - pH - 4) end

                            popupEl:trackGroup(Draw.shadow(pX, pY, pW, pH, 10, Z.popup))
                            popupEl:trackGroup(Draw.roundedGroup(pX, pY, pW, pH, 10, T.Surface, 0, Z.popup))
                            popupEl:trackGroup(Draw.roundedGroup(pX-1, pY-1, pW+2, pH+2, 11, T.Border, 0.6, Z.popup-1))

                            local h_, s_, v_ = hsvFromColor(self.Color)

                            -- SV square
                            local svPad = 12
                            local svSize = pW - svPad*2
                            local svX, svY = pX + svPad, pY + svPad
                            -- Render SV square via columns (32 steps) for performance
                            local svBgParts = {}
                            local cols = 16
                            for i = 0, cols-1 do
                                local cx0 = svX + (svSize/cols)*i
                                local cw  = math.ceil(svSize/cols) + 1
                                -- color gradient column: at this column, saturation is i/(cols-1), value goes 1->0
                                -- approximate with vertical strip of a single hue
                                local stripS = i/(cols-1)
                                -- 8 segments per column for value
                                local rows = 12
                                for j = 0, rows-1 do
                                    local cy0 = svY + (svSize/rows)*j
                                    local ch  = math.ceil(svSize/rows) + 1
                                    local stripV = 1 - j/(rows-1)
                                    local c = Color3.fromHSV(h_, stripS, stripV)
                                    svBgParts[#svBgParts+1] = popupEl:track(Draw.rect(cx0, cy0, cw, ch, c, 0, Z.popup+1))
                                end
                            end

                            -- SV cursor
                            local svCurX = svX + s_ * svSize
                            local svCurY = svY + (1 - v_) * svSize
                            local svCur1 = popupEl:track(Draw.circle(svCurX, svCurY, 6, Color3.new(1,1,1), false, 0, Z.popup+3))
                            svCur1.Thickness = 2
                            local svCur2 = popupEl:track(Draw.circle(svCurX, svCurY, 8, Color3.new(0,0,0), false, 0, Z.popup+3))
                            svCur2.Thickness = 1

                            -- Hue bar
                            local hueY = svY + svSize + 10
                            local hueH = 14
                            local hueSeg = 24
                            for i = 0, hueSeg-1 do
                                local cw = math.ceil(svSize / hueSeg) + 1
                                local cx0 = svX + (svSize/hueSeg)*i
                                local c = Color3.fromHSV(i/(hueSeg-1), 1, 1)
                                popupEl:track(Draw.rect(cx0, hueY, cw, hueH, c, 0, Z.popup+1))
                            end
                            local hueCurX = svX + h_ * svSize
                            local hueCur = popupEl:track(Draw.rect(hueCurX-1, hueY-2, 3, hueH+4, Color3.new(1,1,1), 0, Z.popup+3))

                            local function refreshSV()
                                -- rebuild SV strips for new hue
                                for _, p in ipairs(svBgParts) do p:Remove() end
                                svBgParts = {}
                                for i = 0, cols-1 do
                                    local cx0 = svX + (svSize/cols)*i
                                    local cw  = math.ceil(svSize/cols) + 1
                                    local stripS = i/(cols-1)
                                    local rows = 12
                                    for j = 0, rows-1 do
                                        local cy0 = svY + (svSize/rows)*j
                                        local ch  = math.ceil(svSize/rows) + 1
                                        local stripV = 1 - j/(rows-1)
                                        local c = Color3.fromHSV(h_, stripS, stripV)
                                        svBgParts[#svBgParts+1] = popupEl:track(Draw.rect(cx0, cy0, cw, ch, c, 0, Z.popup+1))
                                    end
                                end
                            end

                            local function commit()
                                local nc = Color3.fromHSV(h_, s_, v_)
                                setColor(nc, true)
                            end

                            -- SV zone
                            popupEl:trackZone(Input.register({
                                x=svX, y=svY, w=svSize, h=svSize, z=Z.popup+2,
                                onPress = function(px, py)
                                    s_ = clamp((px - svX)/svSize, 0, 1)
                                    v_ = 1 - clamp((py - svY)/svSize, 0, 1)
                                    svCur1.Position = Vector2.new(svX + s_*svSize, svY + (1-v_)*svSize)
                                    svCur2.Position = svCur1.Position
                                    commit()
                                end,
                                onDrag = function(px, py)
                                    s_ = clamp((px - svX)/svSize, 0, 1)
                                    v_ = 1 - clamp((py - svY)/svSize, 0, 1)
                                    svCur1.Position = Vector2.new(svX + s_*svSize, svY + (1-v_)*svSize)
                                    svCur2.Position = svCur1.Position
                                    commit()
                                end,
                                visible = function() return popupOpen end,
                            }))
                            -- Hue zone
                            popupEl:trackZone(Input.register({
                                x=svX, y=hueY-4, w=svSize, h=hueH+8, z=Z.popup+2,
                                onPress = function(px) h_ = clamp((px - svX)/svSize, 0, 1); hueCur.Position = Vector2.new(svX + h_*svSize - 1, hueY-2); refreshSV(); commit() end,
                                onDrag  = function(px) h_ = clamp((px - svX)/svSize, 0, 1); hueCur.Position = Vector2.new(svX + h_*svSize - 1, hueY-2); refreshSV(); commit() end,
                                visible = function() return popupOpen end,
                            }))

                            -- Alpha bar (optional)
                            if self.Settings.Alpha ~= nil then
                                local aY = hueY + hueH + 10
                                local aH = 12
                                -- Checker pattern background (simplified: 2 grays)
                                for i = 0, 11 do
                                    local cw = math.ceil(svSize/12) + 1
                                    local cx0 = svX + (svSize/12)*i
                                    popupEl:track(Draw.rect(cx0, aY, cw, aH, (i%2==0) and Color3.fromRGB(180,180,180) or Color3.fromRGB(120,120,120), 0, Z.popup+1))
                                end
                                local aFill = popupEl:track(Draw.rect(svX, aY, svSize * (self.Alpha or 1), aH, Color3.fromHSV(h_, s_, v_), 0.4, Z.popup+2))
                                local aCur = popupEl:track(Draw.rect(svX + svSize*(self.Alpha or 1) - 1, aY-2, 3, aH+4, Color3.new(1,1,1), 0, Z.popup+3))
                                popupEl:trackZone(Input.register({
                                    x=svX, y=aY-4, w=svSize, h=aH+8, z=Z.popup+2,
                                    onPress = function(px) self.Alpha = clamp((px-svX)/svSize, 0, 1); aFill.Size = Vector2.new(svSize*self.Alpha, aH); aCur.Position = Vector2.new(svX + svSize*self.Alpha - 1, aY-2); commit() end,
                                    onDrag  = function(px) self.Alpha = clamp((px-svX)/svSize, 0, 1); aFill.Size = Vector2.new(svSize*self.Alpha, aH); aCur.Position = Vector2.new(svX + svSize*self.Alpha - 1, aY-2); commit() end,
                                    visible = function() return popupOpen end,
                                }))
                            end

                            -- Backdrop
                            popupEl:trackZone(Input.register({
                                x=0, y=0, w=vp.X, h=vp.Y, z=Z.popup-2,
                                onRelease = function() closePopup() end,
                                visible = function() return popupOpen end,
                            }))
                        end

                        local zone = Input.register({
                            x=swX-4, y=swY-4, w=swW+8, h=swH+8, z=Z.element+1,
                            onRelease = function(rx, ry) if pointInRect(rx, ry, swX-4, swY-4, swW+8, swH+8) then openPopup() end end,
                            visible = function() return self._visible and WindowFunctions._opened and activeTab == TabFunctions end,
                        })
                        secEl:trackZone(zone)
                    end

                    function item:UpdateName(n) self.Settings.Name = n; TabFunctions:_render() end
                    function item:SetVisibility(v) self._visible = v; TabFunctions:_render() end
                    function item:SetColor(c)
                        self.Color = c
                        if self._setColor then self._setColor(c, true)
                        elseif self.Settings.Callback then task.spawn(self.Settings.Callback, c, self.Alpha) end
                    end
                    function item:SetAlpha(a) self.Alpha = a end
                    function item:GetColor() return self.Color end
                    function item:GetAlpha() return self.Alpha end
                    function item:SetCallback(fn) self.Settings.Callback = fn end

                    SectionApi:_addElement(item)
                    if flag then
                        DrawLib.Options[flag] = item
                        if s.ForceAutoLoad then task.delay(s.FALoadDelay or 0, function() DrawLib:FALLoad(flag, item) end) end
                    end
                    return item
                end

                -- =================================================
                -- HEADER / LABEL / SUBLABEL / PARAGRAPH / DIVIDER / SPACER
                -- =================================================
                function SectionApi:Header(s)
                    s = s or {}
                    local item = { Type="Header", Settings=s }
                    function item:_estimateHeight() return 24 end
                    function item:_render(x, y, w, secEl)
                        if self._visible == false then return end
                        local txt = self.Settings.Text or self.Settings.Name or "Header"
                        secEl:track(Draw.text(txt, x, y + 4, 15, T.Accent, Drawing.Fonts.UI, false, Z.element+2))
                        secEl:track(Draw.rect(x, y + 22, w, 1, T.Border, 0.5, Z.element+1))
                    end
                    function item:UpdateName(t) self.Settings.Text = t; TabFunctions:_render() end
                    function item:SetVisibility(v) self._visible = v; TabFunctions:_render() end
                    SectionApi:_addElement(item)
                    return item
                end

                function SectionApi:Label(s)
                    s = s or {}
                    local item = { Type="Label", Settings=s }
                    function item:_estimateHeight() return 18 end
                    function item:_render(x, y, w, secEl)
                        if self._visible == false then return end
                        local txt = self.Settings.Text or self.Settings.Name or ""
                        secEl:track(Draw.text(txt, x, y + 2, 13, T.Text, Drawing.Fonts.UI, false, Z.element+2))
                    end
                    function item:UpdateName(t) self.Settings.Text = t; TabFunctions:_render() end
                    function item:SetVisibility(v) self._visible = v; TabFunctions:_render() end
                    SectionApi:_addElement(item)
                    return item
                end

                function SectionApi:SubLabel(s)
                    s = s or {}
                    local item = { Type="SubLabel", Settings=s }
                    function item:_estimateHeight() return 16 end
                    function item:_render(x, y, w, secEl)
                        if self._visible == false then return end
                        local txt = self.Settings.Text or self.Settings.Name or ""
                        secEl:track(Draw.text(txt, x, y + 1, 12, T.TextDim, Drawing.Fonts.UI, false, Z.element+2))
                    end
                    function item:UpdateName(t) self.Settings.Text = t; TabFunctions:_render() end
                    function item:SetVisibility(v) self._visible = v; TabFunctions:_render() end
                    SectionApi:_addElement(item)
                    return item
                end

                function SectionApi:Paragraph(s)
                    s = s or {}
                    local item = { Type="Paragraph", Settings=s }
                    function item:_estimateHeight() return 44 end
                    function item:_render(x, y, w, secEl)
                        if self._visible == false then return end
                        secEl:track(Draw.text(self.Settings.Header or "", x, y + 2, 14, T.Text, Drawing.Fonts.UI, false, Z.element+2))
                        secEl:track(Draw.text(self.Settings.Body or "", x, y + 22, 12, T.TextDim, Drawing.Fonts.UI, false, Z.element+2))
                    end
                    function item:UpdateHeader(t) self.Settings.Header = t; TabFunctions:_render() end
                    function item:UpdateBody(t) self.Settings.Body = t; TabFunctions:_render() end
                    function item:SetVisibility(v) self._visible = v; TabFunctions:_render() end
                    SectionApi:_addElement(item)
                    return item
                end

                function SectionApi:Divider()
                    local item = { Type="Divider" }
                    function item:_estimateHeight() return 8 end
                    function item:_render(x, y, w, secEl)
                        if self._visible == false then return end
                        secEl:track(Draw.rect(x, y + 4, w, 1, T.Border, 0.5, Z.element+1))
                    end
                    function item:Remove() self._visible = false; TabFunctions:_render() end
                    function item:SetVisibility(v) self._visible = v; TabFunctions:_render() end
                    SectionApi:_addElement(item)
                    return item
                end

                function SectionApi:Spacer()
                    local item = { Type="Spacer" }
                    function item:_estimateHeight() return 8 end
                    function item:_render() end
                    function item:Remove() self._visible = false; TabFunctions:_render() end
                    function item:SetVisibility(v) self._visible = v; TabFunctions:_render() end
                    SectionApi:_addElement(item)
                    return item
                end

                function SectionApi:ReserveSlot(count)
                    for _ = 1, (count or 1) do SectionApi:Spacer() end
                end

                -- Apply patched custom methods
                DrawLib:_ApplySectionPatches(SectionApi)

                table.insert(TabFunctions._sectionsBySide[side], SectionApi)
                table.insert(TabFunctions._sections, SectionApi)
                TabFunctions:_render()
                return SectionApi
            end

            function TabFunctions:Select()
                if activeTab == self then return end
                if activeTab then
                    for _, sec in ipairs(activeTab._sections) do sec._el:setVisible(false) end
                end
                activeTab = self
                for _, sec in ipairs(self._sections) do sec._el:setVisible(true) end
                self:_render()
                if WindowFunctions._tabBarRender then WindowFunctions._tabBarRender() end
            end

            -- Config section insertion
            function TabFunctions:InsertConfigSection(side)
                local sec = self:Section({ Name = "Configuration", Side = side or "Left" })
                local cfgList = DrawLib:RefreshConfigList()
                local nameInput
                nameInput = sec:Input({ Name = "Config Name", Placeholder = "myconfig", Callback = function() end }, "_cfgName")
                local cfgDD = sec:Dropdown({ Name = "Config", Options = cfgList, Callback = function() end }, "_cfgPick")
                sec:Button({ Name = "Create", Callback = function()
                    local n = nameInput:GetText()
                    if not n or n == "" then return end
                    local ok, err = DrawLib:SaveConfig(n)
                    WindowFunctions:Notify({ Title = "Config", Description = ok and ("Created "..n) or ("Error: "..tostring(err)) })
                    cfgDD:ClearOptions()
                    for _, v in ipairs(DrawLib:RefreshConfigList()) do cfgDD:InsertOptions({v}) end
                end })
                sec:Button({ Name = "Load", Callback = function()
                    if cfgDD:GetValue() then
                        local ok, err = DrawLib:LoadConfig(cfgDD:GetValue())
                        WindowFunctions:Notify({ Title = "Config", Description = ok and "Loaded" or ("Error: "..tostring(err)) })
                    end
                end })
                sec:Button({ Name = "Save", Callback = function()
                    if cfgDD:GetValue() then
                        DrawLib:SaveConfig(cfgDD:GetValue())
                        WindowFunctions:Notify({ Title = "Config", Description = "Saved" })
                    end
                end })
                sec:Button({ Name = "Refresh", Callback = function()
                    cfgDD:ClearOptions()
                    for _, v in ipairs(DrawLib:RefreshConfigList()) do cfgDD:InsertOptions({v}) end
                end })
                sec:Button({ Name = "Set Autoload", Callback = function()
                    if cfgDD:GetValue() and writefile then
                        writefile(DrawLib.Folder.."/settings/autoload.txt", cfgDD:GetValue())
                        WindowFunctions:Notify({ Title = "Config", Description = "Autoload: "..cfgDD:GetValue() })
                    end
                end })
                return sec
            end

            function TabFunctions:InsertCustomisationSection(side)
                local sec = self:Section({ Name = "Customisation", Side = side or "Right" })
                sec:Toggle({ Name = "FAB Visible", Default = DrawLib._toggleBtnVisible,
                    Callback = function(v) DrawLib:SetToggleButtonVisible(v) end }, "Cust_TBVis")
                sec:Slider({ Name = "FAB Size", Default = 44, Minimum = 30, Maximum = 80,
                    Callback = function(v) DrawLib:StyleToggleButton({ Size = v }) end }, "Cust_TBSize")
                sec:Colorpicker({ Name = "FAB Color", Default = T.Accent,
                    Callback = function(c) DrawLib:StyleToggleButton({ Color = c }) end }, "Cust_TBColor")
                return sec
            end

            return TabFunctions
        end

        return SectionFunctions
    end

    -- ============================================================
    -- Tab bar rendering (placed after first TabGroup created)
    -- ============================================================
    function WindowFunctions._tabBarRender()
        -- destroy existing tab buttons (simple approach: collect all tabs across groups and re-render)
        if WindowFunctions._tabBtnEl then WindowFunctions._tabBtnEl:destroy() end
        local el = newElement()
        WindowFunctions._tabBtnEl = el

        local allTabsFlat = {}
        for _, g in ipairs(tabGroups) do
            for _, t in ipairs(g.Tabs) do table.insert(allTabsFlat, t) end
        end
        if #allTabsFlat == 0 then return end

        local btnW = math.floor(tabBarW / #allTabsFlat)
        for i, tab in ipairs(allTabsFlat) do
            local bx = tabBarX + (i-1)*btnW
            local by = tabBarY
            local bh = tabBarH
            local isActive = activeTab == tab
            local txtColor = isActive and T.Accent or T.TextDim
            local name = tab.Settings.Name or ("Tab "..i)
            local label = el:track(Draw.text(name, bx + btnW/2, by + (bh - 14)/2 - (mobile and 6 or 0), mobile and 12 or 13, txtColor, Drawing.Fonts.UI, true, Z.topbar+3))
            if mobile then
                -- icon area above text
                el:track(Draw.text("●", bx + btnW/2, by + 10, 14, txtColor, Drawing.Fonts.UI, true, Z.topbar+3))
            end
            -- active accent underline (or top stripe on mobile)
            if isActive then
                if mobile then
                    el:track(Draw.rect(bx + btnW/2 - 14, by + 4, 28, 3, T.Accent, 0.1, Z.topbar+4))
                else
                    el:track(Draw.rect(bx + 8, by + bh - 2, btnW - 16, 2, T.Accent, 0, Z.topbar+4))
                end
            end
            local zone = Input.register({
                x=bx, y=by, w=btnW, h=bh, z=Z.topbar+2,
                onRelease = function(rx, ry) if pointInRect(rx, ry, bx, by, btnW, bh) then tab:Select() end end,
                visible = function() return WindowFunctions._opened end,
            })
            el:trackZone(zone)
        end
    end

    -- ============================================================
    -- GLOBAL SETTING (simple toggle in topbar area or popover)
    -- ============================================================
    function WindowFunctions:GlobalSetting(s)
        s = s or {}
        local State = s.Default and true or false
        local api = { State = State }
        function api:UpdateName(n) s.Name = n end
        function api:UpdateState(state)
            api.State = state
            if s.Callback then task.spawn(s.Callback, state) end
        end
        if s.Callback and s.Default ~= nil then task.spawn(s.Callback, State) end
        return api
    end

    -- ============================================================
    -- NOTIFY
    -- ============================================================
    WindowFunctions._notifications = {}
    WindowFunctions._notifEnabled = true

    function WindowFunctions:Notify(s)
        if not self._notifEnabled then return end
        s = s or {}
        local lifetime = s.Lifetime or 4
        local nVp = getViewport()
        local nW = mobile and math.min(280, nVp.X - 24) or (s.SizeX or 280)
        local nH = 56 + (s.Description and 18 or 0)
        local margin = 12
        local baseX = nVp.X - nW - margin
        local baseY = nVp.Y - margin - nH

        -- Offset stacking for existing notifs
        local offset = 0
        for _, n in ipairs(self._notifications) do offset = offset + n._h + 8 end
        local nX = baseX
        local nY = baseY - offset

        local el = newElement()
        el:trackGroup(Draw.shadow(nX, nY, nW, nH, 10, Z.notif))
        local bgG = el:trackGroup(Draw.roundedGroup(nX, nY, nW, nH, 10, T.Surface, 0, Z.notif))
        el:trackGroup(Draw.roundedGroup(nX-1, nY-1, nW+2, nH+2, 11, T.Border, 0.6, Z.notif-1))
        el:track(Draw.rect(nX + 8, nY + 12, 3, nH - 24, T.Accent, 0, Z.notif+1))
        el:track(Draw.text(s.Title or "Notification", nX + 18, nY + 8, 13, T.Text, Drawing.Fonts.UI, false, Z.notif+2))
        if s.Description then
            el:track(Draw.text(s.Description, nX + 18, nY + 28, 12, T.TextDim, Drawing.Fonts.UI, false, Z.notif+2))
        end

        local notif = { _el=el, _h=nH }
        table.insert(self._notifications, notif)

        -- enter animation
        bgG:SetTransparency(0)
        task.delay(lifetime, function()
            -- fade out and remove
            Anim.tween(0.3, Easing.outCubic, function(t)
                for _, p in ipairs(el._parts) do p.Transparency = math.max(0, 1 - t) end
                for _, g in ipairs(el._groups) do g:SetTransparency(1 - t) end
            end, function()
                el:destroy()
                for i, n in ipairs(self._notifications) do if n == notif then table.remove(self._notifications, i) break end end
            end)
        end)
        return notif
    end

    function WindowFunctions:SetNotificationsState(state) self._notifEnabled = state end
    function WindowFunctions:GetNotificationsState() return self._notifEnabled end

    -- ============================================================
    -- DIALOG
    -- ============================================================
    function WindowFunctions:Dialog(s)
        s = s or {}
        local dVp = getViewport()
        local dW = math.min(440, dVp.X - 32)
        local dH = 160 + (s.Description and 20 or 0)
        local dX = math.floor((dVp.X - dW)/2)
        local dY = math.floor((dVp.Y - dH)/2)

        local el = newElement()
        -- backdrop
        local backdrop = el:track(Draw.rect(0, 0, dVp.X, dVp.Y, Color3.new(0,0,0), 0.5, Z.dialog-1))
        el:trackGroup(Draw.shadow(dX, dY, dW, dH, 14, Z.dialog))
        el:trackGroup(Draw.roundedGroup(dX, dY, dW, dH, 14, T.Surface, 0, Z.dialog))
        el:trackGroup(Draw.roundedGroup(dX-1, dY-1, dW+2, dH+2, 15, T.Border, 0.5, Z.dialog-1))
        el:track(Draw.text(s.Title or "Dialog", dX + 18, dY + 16, 16, T.Text, Drawing.Fonts.UI, false, Z.dialog+1))
        if s.Description then
            el:track(Draw.text(s.Description, dX + 18, dY + 44, 13, T.TextDim, Drawing.Fonts.UI, false, Z.dialog+1))
        end

        local buttons = s.Buttons or {}
        local btnW = math.floor((dW - 36 - 8*(#buttons-1)) / math.max(1, #buttons))
        local btnY = dY + dH - 50
        local btnH = 34
        for i, b in ipairs(buttons) do
            local bx = dX + 18 + (i-1)*(btnW+8)
            local primary = i == 1
            local col = primary and T.Accent or T.SurfaceHover
            local txC = primary and T.Background or T.Text
            local g = el:trackGroup(Draw.roundedGroup(bx, btnY, btnW, btnH, 8, col, 0, Z.dialog+1))
            el:track(Draw.text(b.Name or "OK", bx + btnW/2, btnY + (btnH-14)/2 - 1, 14, txC, Drawing.Fonts.UI, true, Z.dialog+2))
            el:trackZone(Input.register({
                x=bx, y=btnY, w=btnW, h=btnH, z=Z.dialog+1,
                onRelease = function(rx, ry)
                    if pointInRect(rx, ry, bx, btnY, btnW, btnH) then
                        el:destroy()
                        if b.Callback then task.spawn(b.Callback) end
                    end
                end,
            }))
        end
    end

    -- ============================================================
    -- ACRYLIC BLUR (Lighting blur effect, since true blur on Drawing isn't possible)
    -- ============================================================
    WindowFunctions._blurEnabled = Settings.AcrylicBlur ~= false
    WindowFunctions._blur = nil
    function WindowFunctions:SetAcrylicBlurState(state)
        self._blurEnabled = state
        if state and not self._blur then
            local b = Instance.new("BlurEffect")
            b.Size = 8
            b.Parent = DrawLib.GetService("Lighting")
            self._blur = b
        elseif (not state) and self._blur then
            self._blur:Destroy(); self._blur = nil
        end
    end
    function WindowFunctions:GetAcrylicBlurState() return self._blurEnabled end
    if WindowFunctions._blurEnabled then WindowFunctions:SetAcrylicBlurState(true) end

    WindowFunctions._userInfoState = Settings.ShowUserInfo and true or false
    function WindowFunctions:SetUserInfoState(state) self._userInfoState = state end
    function WindowFunctions:GetUserInfoState() return self._userInfoState end

    -- ============================================================
    -- WINDOW TITLE/SUBTITLE/UNLOAD
    -- ============================================================
    function WindowFunctions:UpdateTitle(t) self._title.Text = t; self.Settings.Title = t end
    function WindowFunctions:UpdateSubtitle(t) self._subtitle.Text = t; self.Settings.Subtitle = t end

    WindowFunctions._unloadCallbacks = {}
    function WindowFunctions.onUnloaded(cb) table.insert(WindowFunctions._unloadCallbacks, cb) end
    function WindowFunctions:Unload()
        for _, cb in ipairs(self._unloadCallbacks or {}) do pcall(cb) end
        Win:destroy()
        if WindowFunctions._fabEl then WindowFunctions._fabEl:destroy() end
        if self._blur then self._blur:Destroy() end
        DrawLib._unloaded = true
    end

    -- ============================================================
    -- FAB TOGGLE BUTTON  (always-on-top open/close)
    -- ============================================================
    local fabEl = newElement()
    WindowFunctions._fabEl = fabEl
    local fabSize = mobile and 48 or 42
    local fabX = Settings.ToggleBtnPosition and Settings.ToggleBtnPosition.X.Offset or (vp.X - fabSize - 20)
    local fabY = Settings.ToggleBtnPosition and Settings.ToggleBtnPosition.Y.Offset or (vp.Y - fabSize - 20)
    local fabColor = Settings.ToggleBtnColor or T.Accent
    local fabShadow = fabEl:trackGroup(Draw.shadow(fabX, fabY, fabSize, fabSize, fabSize/2, Z.fab))
    local fabBg = fabEl:trackGroup(Draw.roundedGroup(fabX, fabY, fabSize, fabSize, fabSize/2, fabColor, 0, Z.fab))
    local fabIcon = fabEl:track(Draw.text("✕", fabX + fabSize/2, fabY + (fabSize-18)/2, 18, T.Background, Drawing.Fonts.UI, true, Z.fab+1))

    local function setFabIcon()
        fabIcon.Text = WindowFunctions._opened and "✕" or "≡"
    end
    setFabIcon()

    -- FAB drag + click
    local fabDragStart, fabPosStart, fabMoved
    local fabZone = Input.register({
        x=fabX, y=fabY, w=fabSize, h=fabSize, z=Z.fab,
        onPress = function(px, py)
            fabDragStart = Vector2.new(px, py)
            fabPosStart = Vector2.new(fabX, fabY)
            fabMoved = false
            Anim.color(fabBg.color, T.AccentDim, 0.1, Easing.outQuad, function(c) fabBg:SetColor(c) end)
        end,
        onDrag = function(px, py)
            if not fabDragStart then return end
            local dx, dy = px - fabDragStart.X, py - fabDragStart.Y
            if math.abs(dx) > 4 or math.abs(dy) > 4 then fabMoved = true end
            if fabMoved then
                fabX = clamp(fabPosStart.X + dx, 0, vp.X - fabSize)
                fabY = clamp(fabPosStart.Y + dy, 0, vp.Y - fabSize)
                fabBg:SetPosition(fabX, fabY)
                fabShadow:SetPosition(fabX, fabY)
                fabIcon.Position = Vector2.new(fabX + fabSize/2, fabY + (fabSize-18)/2)
                Input.updateZone(fabZone, fabX, fabY, fabSize, fabSize)
                DrawLib._keybindPositions["__fab"] = { X = fabX/vp.X, Y = fabY/vp.Y }
            end
        end,
        onRelease = function()
            Anim.color(T.AccentDim, fabColor, 0.18, Easing.outCubic, function(c) fabBg:SetColor(c) end)
            if not fabMoved then
                WindowFunctions:SetState(not WindowFunctions._opened)
                setFabIcon()
                -- bounce icon
                local origPos = fabIcon.Position
                Anim.number(1, 0.7, 0.08, Easing.outQuad, function(s) end)
            end
            fabDragStart = nil
        end,
        visible = function() return DrawLib._toggleBtnVisible end,
    })
    fabEl:trackZone(fabZone)

    function DrawLib:SetToggleButtonVisible(state)
        DrawLib._toggleBtnVisible = state
        for _, p in ipairs(fabEl._parts) do p.Visible = state end
        for _, g in ipairs(fabEl._groups) do g:SetVisible(state) end
    end
    function DrawLib:StyleToggleButton(props)
        if props.Color then fabBg:SetColor(props.Color); fabColor = props.Color end
        if props.Size then
            fabSize = props.Size
            fabBg:SetSize(fabSize, fabSize)
            fabIcon.Position = Vector2.new(fabX + fabSize/2, fabY + (fabSize-18)/2)
            Input.updateZone(fabZone, fabX, fabY, fabSize, fabSize)
        end
    end

    -- Default keybind to toggle
    if Settings.Keybind then
        DrawLib._keyListeners["__windowToggle"] = function(key, isDown)
            if isDown and key == Settings.Keybind then
                WindowFunctions:SetState(not WindowFunctions._opened)
                setFabIcon()
            end
        end
    end

    -- Apply hooks
    if DrawLib._hooks["Window"] then
        for _, h in ipairs(DrawLib._hooks["Window"]) do pcall(h, WindowFunctions, Settings) end
    end

    return WindowFunctions
end

-- ====================================================================
-- CLASS PARSER (config save/load per element type)
-- ====================================================================
local ClassParser = {
    Toggle = {
        Save = function(flag, data) return { type="Toggle", flag=flag, state=data.State or false } end,
        Load = function(flag, data) if DrawLib.Options[flag] and data.state ~= nil then DrawLib.Options[flag]:UpdateState(data.state) end end,
    },
    Slider = {
        Save = function(flag, data) return { type="Slider", flag=flag, value=tostring(data.Value or 0) } end,
        Load = function(flag, data) if DrawLib.Options[flag] and data.value then DrawLib.Options[flag]:UpdateValue(tonumber(data.value) or 0, true) end end,
    },
    Input = {
        Save = function(flag, data) return { type="Input", flag=flag, text=data.Text or "" } end,
        Load = function(flag, data) if DrawLib.Options[flag] and data.text then DrawLib.Options[flag]:UpdateText(data.text) end end,
    },
    Keybind = {
        Save = function(flag, data) return { type="Keybind", flag=flag, bind = data.Bind and data.Bind.Name or nil } end,
        Load = function(flag, data) if DrawLib.Options[flag] and data.bind then DrawLib.Options[flag]:Bind(Enum.KeyCode[data.bind]) end end,
    },
    Dropdown = {
        Save = function(flag, data) return { type="Dropdown", flag=flag, value=data.Value } end,
        Load = function(flag, data) if DrawLib.Options[flag] and data.value ~= nil then DrawLib.Options[flag]:UpdateSelection(data.value) end end,
    },
    Colorpicker = {
        Save = function(flag, data)
            local c = data.Color
            local hex = c and string.format("#%02X%02X%02X", math.floor(c.R*255), math.floor(c.G*255), math.floor(c.B*255)) or "#FFFFFF"
            return { type="Colorpicker", flag=flag, color=hex, alpha=data.Alpha }
        end,
        Load = function(flag, data)
            if DrawLib.Options[flag] and data.color then
                local h = data.color
                local r,g,b = tonumber(h:sub(2,3),16)/255, tonumber(h:sub(4,5),16)/255, tonumber(h:sub(6,7),16)/255
                DrawLib.Options[flag]:SetColor(Color3.new(r,g,b))
                if data.alpha then DrawLib.Options[flag]:SetAlpha(data.alpha) end
            end
        end,
    },
}

-- ====================================================================
-- CONFIG SYSTEM
-- ====================================================================
local function BuildFolderTree()
    if isStudio then return end
    local paths = { DrawLib.Folder, DrawLib.Folder.."/settings" }
    for _, p in ipairs(paths) do if not isfolder(p) then makefolder(p) end end
end

function DrawLib:SetFolder(folder)
    DrawLib.Folder = folder
    BuildFolderTree()
    DrawLib:InitForceAutoLoad()
end

function DrawLib:GetFolder() return DrawLib.Folder end

function DrawLib:SaveConfig(Path)
    if isStudio or not writefile then return false, "Config system unavailable." end
    if not Path or Path == "" then return false, "Please select a config file." end
    local fullPath = DrawLib.Folder.."/settings/"..Path..".json"
    local data = {
        objects = {},
        custom = DrawLib._customData or {},
        keybind_positions = DrawLib._keybindPositions or {},
        toggle_btn_visible = DrawLib._toggleBtnVisible,
        mobile_keybinds_hidden = DrawLib._mobileKeybindsHidden or {},
        keybind_btn_visible = DrawLib._keybindBtnVisible or {},
    }
    for flag, opt in pairs(DrawLib.Options) do
        if ClassParser[opt.Class] and not opt.IgnoreConfig then
            table.insert(data.objects, ClassParser[opt.Class].Save(flag, opt))
        end
    end
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
    if not ok then return false, "Unable to encode JSON" end
    writefile(fullPath, encoded)
    return true
end

function DrawLib:LoadConfig(Path)
    if isStudio or not (isfile and readfile) then return false, "Config system unavailable." end
    if not Path or Path == "" then return false, "Please select a config file." end
    local file = DrawLib.Folder.."/settings/"..Path..".json"
    if not isfile(file) then return false, "Invalid file" end
    local raw = readfile(file)
    local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok then return false, "Unable to decode JSON" end
    for _, obj in ipairs(data.objects or {}) do
        if ClassParser[obj.type] then
            pcall(function() ClassParser[obj.type].Load(obj.flag, obj) end)
        end
    end
    if data.custom then DrawLib._customData = data.custom end
    if data.toggle_btn_visible ~= nil then DrawLib._toggleBtnVisible = data.toggle_btn_visible end
    return true
end

function DrawLib:LoadAutoLoadConfig()
    if isStudio or not (isfile and readfile) then return end
    local f = DrawLib.Folder.."/settings/autoload.txt"
    if isfile(f) then
        local name = readfile(f)
        DrawLib:LoadConfig(name)
    end
end

function DrawLib:RefreshConfigList()
    local list = {}
    if not isfolder or not listfiles then return list end
    local folder = DrawLib.Folder.."/settings"
    if not isfolder(folder) then return list end
    for _, f in ipairs(listfiles(folder)) do
        local name = f:match("([^/\\]+)%.json$")
        if name then table.insert(list, name) end
    end
    return list
end

-- ====================================================================
-- FORCE-AUTO-LOAD (FAL) per-flag persistence
-- ====================================================================
DrawLib._falFolder = nil

function DrawLib:InitForceAutoLoad()
    if isStudio or not makefolder then return end
    DrawLib._falFolder = DrawLib.Folder.."/FAutoLoad"
    if not isfolder(DrawLib._falFolder) then makefolder(DrawLib._falFolder) end
end

local function falPath(flag) return (DrawLib._falFolder or (DrawLib.Folder.."/FAutoLoad")).."/"..tostring(flag)..".json" end

function DrawLib:FALSave(flag, el)
    if not writefile or not el then return end
    DrawLib:InitForceAutoLoad()
    local payload
    if el.Class == "Toggle" then payload = { state = el.State }
    elseif el.Class == "Slider" then payload = { value = el.Value }
    elseif el.Class == "Input" then payload = { text = el.Text }
    elseif el.Class == "Keybind" then payload = { bind = el.Bind and el.Bind.Name or nil }
    elseif el.Class == "Dropdown" then payload = { value = el.Value }
    elseif el.Class == "Colorpicker" then
        local c = el.Color
        payload = { color = string.format("#%02X%02X%02X", math.floor(c.R*255), math.floor(c.G*255), math.floor(c.B*255)), alpha = el.Alpha }
    end
    if payload then
        local ok, enc = pcall(HttpService.JSONEncode, HttpService, payload)
        if ok then writefile(falPath(flag), enc) end
    end
end

function DrawLib:FALLoad(flag, el, delay)
    if not readfile or not el then return end
    local p = falPath(flag)
    if not isfile(p) then return end
    local ok, data = pcall(HttpService.JSONDecode, HttpService, readfile(p))
    if not ok then return end
    local apply = function()
        if el.Class == "Toggle" and data.state ~= nil then el:UpdateState(data.state)
        elseif el.Class == "Slider" and data.value then el:UpdateValue(data.value, true)
        elseif el.Class == "Input" and data.text then el:UpdateText(data.text)
        elseif el.Class == "Keybind" and data.bind then el:Bind(Enum.KeyCode[data.bind])
        elseif el.Class == "Dropdown" and data.value then el:UpdateSelection(data.value)
        elseif el.Class == "Colorpicker" and data.color then
            local h = data.color
            el:SetColor(Color3.new(tonumber(h:sub(2,3),16)/255, tonumber(h:sub(4,5),16)/255, tonumber(h:sub(6,7),16)/255))
            if data.alpha then el:SetAlpha(data.alpha) end
        end
    end
    if delay and delay > 0 then task.delay(delay, apply) else apply() end
end

function DrawLib:FALClear(flag) if delfile and isfile(falPath(flag)) then delfile(falPath(flag)) end end
function DrawLib:FALSetData(flag, val)
    if not writefile then return end
    DrawLib:InitForceAutoLoad()
    local ok, enc = pcall(HttpService.JSONEncode, HttpService, { value = val })
    if ok then writefile(falPath(flag), enc) end
end
function DrawLib:FALGetData(flag, default)
    if not readfile then return default end
    local p = falPath(flag)
    if not isfile(p) then return default end
    local ok, data = pcall(HttpService.JSONDecode, HttpService, readfile(p))
    if ok and data and data.value ~= nil then return data.value end
    return default
end
function DrawLib:FALLoadData(flag, callback, delay, default)
    local fn = function() if callback then pcall(callback, DrawLib:FALGetData(flag, default)) end end
    if delay and delay > 0 then task.delay(delay, fn) else fn() end
end

-- ====================================================================
-- DATA / OPTIONS API
-- ====================================================================
function DrawLib:SetData(key, value) DrawLib._customData[key] = value end
function DrawLib:GetData(key, default) local v = DrawLib._customData[key]; if v == nil then return default end; return v end
function DrawLib:OnDataLoad(cb) DrawLib._onDataLoadCbs = DrawLib._onDataLoadCbs or {}; table.insert(DrawLib._onDataLoadCbs, cb) end

function DrawLib:GetOption(flag) return DrawLib.Options[flag] end
function DrawLib:GetOptions() return DrawLib.Options end
function DrawLib:RemoveOption(flag) DrawLib.Options[flag] = nil end

function DrawLib:BatchSet(tbl, silent)
    for flag, val in pairs(tbl) do
        local opt = DrawLib.Options[flag]
        if opt then
            if opt.Class == "Toggle" then opt:UpdateState(val)
            elseif opt.Class == "Slider" then opt:UpdateValue(val, silent)
            elseif opt.Class == "Input" then opt:UpdateText(val)
            elseif opt.Class == "Dropdown" then opt:UpdateSelection(val)
            elseif opt.Class == "Keybind" then opt:Bind(val)
            elseif opt.Class == "Colorpicker" then opt:SetColor(val)
            end
        end
    end
end

function DrawLib:WatchOption(flag, fn)
    DrawLib._optionWatchers[flag] = DrawLib._optionWatchers[flag] or {}
    table.insert(DrawLib._optionWatchers[flag], fn)
end

function DrawLib:StyleElement(flag, props)
    -- minimal — DrawLib doesn't expose every prop, but we support common ones
    local opt = DrawLib.Options[flag]
    if not opt then return end
    if props.Visible ~= nil and opt.SetVisibility then opt:SetVisibility(props.Visible) end
end

function DrawLib:StyleKeybindButton(flag, props) end
function DrawLib:SetMobileKeybindVisible(flag, state) DrawLib._mobileKeybindsHidden[flag] = not state end
function DrawLib:ShowKeybindButton(flag, state) DrawLib._keybindBtnVisible[flag] = state end
function DrawLib:SimulateKeybindPress(flag)
    local opt = DrawLib.Options[flag]
    if opt and opt.Settings and opt.Settings.Callback then task.spawn(opt.Settings.Callback, opt.Bind) end
end

-- ====================================================================
-- CUSTOM ELEMENT API (RegisterElement / PatchSection / CreateCustomElement)
-- ====================================================================
function DrawLib:RegisterElement(typeName, classDef, builderFn)
    DrawLib._registeredElements[typeName] = { classDef = classDef, builder = builderFn }
    if classDef and classDef.Save and classDef.Load then ClassParser[typeName] = classDef end
end

function DrawLib:PatchSection(methodName, fn)
    DrawLib._sectionPatches[methodName] = fn
end

function DrawLib:_ApplySectionPatches(sectionFns)
    for name, fn in pairs(DrawLib._sectionPatches) do
        sectionFns[name] = function(self, ...) return fn(self, ...) end
    end
end

function DrawLib:CreateCustomElement(sectionObj, typeName, settings, flag)
    local reg = DrawLib._registeredElements[typeName]
    if reg and reg.builder then return reg.builder(sectionObj, settings, flag) end
end

-- ====================================================================
-- PRELOADER
-- ====================================================================
function DrawLib:Preloader(moduleResult, config)
    if type(config) == "function" then config = { onLoad = config } end
    config = config or {}
    task.spawn(function()
        local ok, result = pcall(function()
            local ctx = { MacLib = DrawLib, DrawLib = DrawLib, Options = DrawLib.Options, Window = config.Window, Name = config.Name }
            local mod = moduleResult
            if type(mod) == "function" then mod = mod(ctx) end
            if type(mod) == "function" then mod = mod(ctx) end
            return mod
        end)
        if ok then
            if type(config.onLoad) == "function" then pcall(config.onLoad, result) end
            if config.Name then
                DrawLib._loadedModules[config.Name] = true
                local cbs = DrawLib._onLoadCallbacks[config.Name]
                if cbs then for _, cb in ipairs(cbs) do task.spawn(cb) end; DrawLib._onLoadCallbacks[config.Name] = nil end
            end
        else
            warn("[DrawLib:Preloader] Error"..(config.Name and (" in '"..config.Name.."'") or "")..": "..tostring(result))
            if type(config.onError) == "function" then pcall(config.onError, result) end
        end
    end)
end

function DrawLib:OnLoad(name, cb)
    if DrawLib._loadedModules[name] then task.spawn(cb)
    else
        DrawLib._onLoadCallbacks[name] = DrawLib._onLoadCallbacks[name] or {}
        table.insert(DrawLib._onLoadCallbacks[name], cb)
    end
end
function DrawLib:IsLoaded(name) return DrawLib._loadedModules[name] == true end

-- ====================================================================
-- EXTEND / HOOK
-- ====================================================================
function DrawLib:Extend(name, fn) DrawLib[name] = fn end
function DrawLib:ExtendSection(name, fn) DrawLib:PatchSection(name, fn) end
function DrawLib:Hook(name, hookFn)
    DrawLib._hooks[name] = DrawLib._hooks[name] or {}
    table.insert(DrawLib._hooks[name], hookFn)
end

-- ====================================================================
-- DEMO
-- ====================================================================
function DrawLib:Demo()
    local Window = DrawLib:Window({
        Title = "DrawLib Demo",
        Subtitle = "Drawing-based UI",
        Size = UDim2.fromOffset(720, 520),
        AcrylicBlur = true,
        Keybind = Enum.KeyCode.RightControl,
    })
    local tg = Window:TabGroup()
    local tabMain = tg:Tab({ Name = "Main" })
    local tabSettings = tg:Tab({ Name = "Settings" })
    local sec = tabMain:Section({ Name = "Demo Section", Side = "Left" })
    sec:Header({ Text = "Quick Demo" })
    sec:Button({ Name = "Notify", Callback = function() Window:Notify({ Title = "Hello", Description = "From DrawLib" }) end })
    sec:Toggle({ Name = "Enable feature", Default = false, Callback = function(v) print("Toggle:", v) end }, "demoToggle")
    sec:Slider({ Name = "Speed", Default = 50, Minimum = 0, Maximum = 100, DisplayMethod = "Percent", Callback = function(v) print("Speed", v) end }, "demoSlider")
    sec:Dropdown({ Name = "Fruit", Options = {"Apple","Banana","Orange","Mango"}, Default = 1, Callback = function(v) print("Dropdown", v) end }, "demoDD")
    sec:Dropdown({ Name = "Multi", Multi = true, Options = {"A","B","C","D"}, Default = {"A"}, Callback = function(v) end }, "demoMulti")
    sec:Keybind({ Name = "Bind", Callback = function(k) print("Pressed", k.Name) end }, "demoKB")
    sec:Colorpicker({ Name = "Color", Default = Color3.fromRGB(0, 229, 255), Callback = function(c) print(c) end }, "demoColor")
    sec:Input({ Name = "Text", Placeholder = "type...", Callback = function(t) print("Input", t) end }, "demoInput")
    sec:Divider()
    sec:Label({ Text = "Built on Drawing API — mobile-friendly" })
    DrawLib:SetFolder("DrawLib")
    tabSettings:InsertConfigSection("Left")
    tabSettings:InsertCustomisationSection("Right")
    tabMain:Select()
    DrawLib:LoadAutoLoadConfig()
    return Window
end

return DrawLib
