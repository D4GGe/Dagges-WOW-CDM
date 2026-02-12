----------------------------------------------------------------------
-- Dagge's Buff Tracker  —  WoW 12.0
-- Hooks the Blizzard BuffIconCooldownViewer (Tracked Buffs section
-- of the Cooldown Manager) and mirrors its visible entries into a
-- custom movable window.
----------------------------------------------------------------------

local ADDON_NAME, ns = ...

-- ── Defaults ─────────────────────────────────────────────────────────
local DEFAULTS = {
    buffCount = 5,
    locked    = false,
    visible   = true,   -- Legacy toggle, will migrate
    showBuffs = true,
    showTotems = true,
    totemCount = 4,
    showSecondaryBuffs = true,
    secondaryBuffCount = 10,
    hideBackground = true,
    primaryIconSize = 38,
    primaryIconPad  = 3,
    secondaryIconSize = 38,
    secondaryIconPad  = 3,
    totemIconSize = 38,
    totemIconPad  = 3,
    point     = "CENTER",
    relPoint  = "CENTER",
    x         = 0,
    y         = 0,
    secondaryPoint = "CENTER",
    secondaryRelPoint = "CENTER",
    secondaryX = 0,
    secondaryY = -150,
    hideBlizzardCDM = true,
    
    -- CDM Categories
    showEssential = true,
    essentialCount = 10,
    showUtility = true,
    utilityCount = 10,
    
    essentialPoint = "CENTER",
    essentialRelPoint = "CENTER",
    essentialX = 0,
    essentialY = 50,
    essentialIconSize = 38,
    essentialIconPad  = 3,
    
    utilityPoint = "CENTER",
    utilityRelPoint = "CENTER",
    utilityX = 0,
    utilityY = 100,
    utilityIconSize = 38,
    utilityIconPad  = 3,
}

-- ── Profile Management ───────────────────────────────────────────────
local function GetCharKey()
    return (UnitFullName("player") or "Unknown") .. " - " .. (GetRealmName() or "Unknown")
end

local function GetCurrentProfile()
    if not DaggesAddonDB then return DEFAULTS end
    if not DaggesAddonDB.profiles then return DEFAULTS end
    
    local charKey = GetCharKey()
    local pName = (DaggesAddonDB.charProfiles and DaggesAddonDB.charProfiles[charKey]) or "Default"
    
    if not DaggesAddonDB.profiles[pName] then
        pName = "Default"
    end
    
    if not DaggesAddonDB.profiles[pName] then
        DaggesAddonDB.profiles["Default"] = CopyTable(DEFAULTS)
        pName = "Default"
    end
    
    return DaggesAddonDB.profiles[pName]
end

local SetProfile, CopyProfile, DeleteProfile, CopyFromProfile



-- Sample icons for config preview (common WoW spell icon IDs)
local SAMPLE_ICONS = {
    136101, -- spell_holy_divineshield (Divine Shield)
    135981, -- spell_fire_flamebolt (Fireball)
    136085, -- spell_holy_flashheal (Flash Heal)
    132292, -- ability_thunderbolt (Thunder Clap)
    136075, -- spell_holy_devotionaura (Devotion Aura)
    135932, -- spell_nature_lightning (Lightning Bolt)
    136105, -- spell_holy_holybolt (Holy Light)
    132369, -- ability_warrior_shieldwall (Shield Wall)
    135991, -- spell_frost_frostbolt (Frostbolt)
    136048, -- spell_holy_innerfire (Inner Fire)
    135753, -- spell_nature_abolishmagic (Abolish Magic)
    135913, -- spell_nature_healingtouch (Healing Touch)
    136034, -- spell_holy_greaterheal (Greater Heal)
    135879, -- spell_nature_earthbind (Earthbind)
    136096, -- spell_holy_powerwordshield (Power Word: Shield)
    136197, -- spell_shadow_shadowwordpain (Shadow Word: Pain)
}
local SAMPLE_TOTEM_ICONS = {
    136098, -- spell_nature_stoneskintotem
    136040, -- spell_fire_sealoffire
    136114, -- spell_nature_windfury
    136052, -- spell_nature_healingwavelesser
}

-- ── Constants & Shared State ─────────────────────────────────────────
local ICON_SIZE   = 38
local ICON_PAD    = 3
local HEADER_H    = 14
local FRAME_PAD   = 4
local UPDATE_HZ   = 0.25

local CLR = {
    bg        = { 0.08, 0.08, 0.12, 0.92 },
    border    = { 0.40, 0.35, 0.55, 0.70 },
    title     = { 0.90, 0.80, 0.50 },
    accent    = { 0.55, 0.45, 0.80, 1.00 },
    iconBord  = { 0.25, 0.22, 0.35, 1.00 },
    highlight = { 0.70, 0.60, 1.00, 0.25 },
    duration  = { 1, 1, 1 },
    stacks    = { 1, 0.85, 0.40 },
}

local BACKDROP_CONFIG = {
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile     = true, tileSize = 16, edgeSize = 16,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- Forward declare frames for functions
local frame, secondaryFrame, totemFrame, essentialFrame, utilityFrame

-- ── UI Styling Helpers ──────────────────────────────────────────────

local function UpdateFrameStyles(forceClosed)
    local configOpen = not forceClosed and _G["DaggesConfigFrame"] and _G["DaggesConfigFrame"]:IsShown()
    local db = GetCurrentProfile()
    local hide = db.hideBackground and not configOpen -- Force show if config is open
    
    local targetFrames = { 
        frame, 
        totemFrame,
        secondaryFrame,
        essentialFrame,
        utilityFrame
    }
    
    for _, f in ipairs(targetFrames) do
        if f then
            if hide then
                f:SetBackdrop(nil)
                if f.accent then f.accent:Hide() end
                if f.title then f.title:Hide() end
            else
                f:SetBackdrop(BACKDROP_CONFIG)
                f:SetBackdropColor(unpack(CLR.bg))
                f:SetBackdropBorderColor(unpack(CLR.border))
                if f.accent then f.accent:Show() end
                if f.title then f.title:Show() end
            end
        end
    end
end

-- ── Main Frame ───────────────────────────────────────────────────────
frame = CreateFrame("Frame", "DaggesBuffTrackerFrame", UIParent, "BackdropTemplate")
frame:SetFrameStrata("MEDIUM")
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")

    UpdateFrameStyles()


-- Accent line
local accentTop = frame:CreateTexture(nil, "OVERLAY")
accentTop:SetHeight(1)
accentTop:SetPoint("TOPLEFT", 2, -1)
accentTop:SetPoint("TOPRIGHT", -2, -1)
accentTop:SetColorTexture(unpack(CLR.accent))
frame.accent = accentTop

-- Title
local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
titleText:SetPoint("TOP", 0, -2)
titleText:SetTextColor(unpack(CLR.title))
titleText:SetText("Buff Tracker")
frame.title = titleText

-- Drag
frame:SetScript("OnDragStart", function(self)
    local db = GetCurrentProfile()
    if not db.locked then self:StartMoving() end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, px, py = self:GetPoint()
    local db = GetCurrentProfile()
    db.point    = p
    db.relPoint = rp
    db.x        = px
    db.y        = py
end)

-- ── Icon Pool ────────────────────────────────────────────────────────
local icons = {}

local function GetIcon(index)
    if icons[index] then return icons[index] end

    local btn = CreateFrame("Frame", nil, frame)
    local db = GetCurrentProfile()
    local size = (db and db.primaryIconSize) or DEFAULTS.primaryIconSize or ICON_SIZE
    btn:SetSize(size, size)

    -- Background
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, 1)

    -- Icon texture
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", -1, 1)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = tex

    -- Border lines
    for _, setup in ipairs({
        {"TOPLEFT", "TOPRIGHT", true},
        {"BOTTOMLEFT", "BOTTOMRIGHT", true},
        {"TOPLEFT", "BOTTOMLEFT", false},
        {"TOPRIGHT", "BOTTOMRIGHT", false},
    }) do
        local line = btn:CreateTexture(nil, "OVERLAY")
        if setup[3] then
            line:SetHeight(1)
        else
            line:SetWidth(1)
        end
        line:SetPoint(setup[1])
        line:SetPoint(setup[2])
        line:SetColorTexture(unpack(CLR.iconBord))
    end

    -- Highlight
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(unpack(CLR.highlight))

    -- Cooldown sweep
    local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cd:SetAllPoints(btn.icon)
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetHideCountdownNumbers(false)
    btn.cooldown = cd

    -- Stack count (Parented to a high-level overlay frame to stay above cooldown sweep)
    local countFrame = CreateFrame("Frame", nil, btn)
    countFrame:SetAllPoints()
    countFrame:SetFrameLevel(btn:GetFrameLevel() + 10)
    
    local count = countFrame:CreateFontString(nil, "OVERLAY")
    count:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", -1, 2)
    count:SetTextColor(unpack(CLR.stacks))
    btn.count = count

    -- Tooltip
    btn:EnableMouse(true)
    btn:SetScript("OnEnter", function(self)
        if self.sourceFrame then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            
            if self.sourceFrame.isVirtualTotem then
                GameTooltip:SetTotem(self.sourceFrame.slot)
            
            -- Try to show the same tooltip the original frame would
            elseif self.sourceFrame.GetTooltipInfo then
                local info = self.sourceFrame:GetTooltipInfo()
                if info then
                    GameTooltip:ProcessInfo(info)
                end
            end
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)


    icons[index] = btn
    return btn
end

-- ── Secondary Buff Frame (The 'Rest') ──────────────────────────────
secondaryFrame = CreateFrame("Frame", "DaggesSecondaryTrackerFrame", UIParent, "BackdropTemplate")
secondaryFrame:SetFrameStrata("MEDIUM")
secondaryFrame:SetClampedToScreen(true)
secondaryFrame:EnableMouse(true)
secondaryFrame:SetMovable(true)
secondaryFrame:RegisterForDrag("LeftButton")

UpdateFrameStyles()

-- Accent line (Secondary)
local secondaryAccent = secondaryFrame:CreateTexture(nil, "OVERLAY")
secondaryAccent:SetHeight(1)
secondaryAccent:SetPoint("TOPLEFT", 2, -1)
secondaryAccent:SetPoint("TOPRIGHT", -2, -1)
secondaryAccent:SetColorTexture(unpack(CLR.accent))
secondaryFrame.accent = secondaryAccent

-- Center line (Secondary)
local centerLine = secondaryFrame:CreateTexture(nil, "OVERLAY", nil, 7)
centerLine:SetWidth(1)
centerLine:SetPoint("TOP", secondaryFrame, "TOP", 0, -HEADER_H)
centerLine:SetPoint("BOTTOM", secondaryFrame, "BOTTOM", 0, 2)
centerLine:SetColorTexture(1, 0.2, 0.2, 0.8)
secondaryFrame.centerLine = centerLine
centerLine:Hide()

-- Title (Secondary)
local secondaryTitle = secondaryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
secondaryTitle:SetPoint("TOP", 0, -2)
secondaryTitle:SetTextColor(unpack(CLR.title))
secondaryTitle:SetText("Secondary Buffs")
secondaryFrame.title = secondaryTitle

-- Drag (Secondary)
secondaryFrame:SetScript("OnDragStart", function(self)
    local db = GetCurrentProfile()
    if not db.locked then self:StartMoving() end
end)
secondaryFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, px, py = self:GetPoint()
    local db = GetCurrentProfile()
    db.secondaryPoint    = p
    db.secondaryRelPoint = rp
    db.secondaryX        = px
    db.secondaryY        = py
end)

local secondaryIcons = {}

local function CreateSecondaryIcon(index)
    local btn = CreateFrame("Frame", nil, secondaryFrame)
    local db = GetCurrentProfile()
    local size = (db and db.secondaryIconSize) or DEFAULTS.secondaryIconSize or ICON_SIZE
    btn:SetSize(size, size)
    
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, 1)

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", -1, 1)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = tex
    
    for _, setup in ipairs({
        {"TOPLEFT", "TOPRIGHT", true},
        {"BOTTOMLEFT", "BOTTOMRIGHT", true},
        {"TOPLEFT", "BOTTOMLEFT", false},
        {"TOPRIGHT", "BOTTOMRIGHT", false},
    }) do
        local line = btn:CreateTexture(nil, "OVERLAY")
        if setup[3] then line:SetHeight(1) else line:SetWidth(1) end
        line:SetPoint(setup[1])
        line:SetPoint(setup[2])
        line:SetColorTexture(unpack(CLR.iconBord))
    end

    local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cd:SetAllPoints(btn.icon)
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetHideCountdownNumbers(false)
    btn.cooldown = cd

    -- Stack count (High-level frame)
    local countFrame = CreateFrame("Frame", nil, btn)
    countFrame:SetAllPoints()
    countFrame:SetFrameLevel(btn:GetFrameLevel() + 10)

    local count = countFrame:CreateFontString(nil, "OVERLAY")
    count:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", -1, 2)
    count:SetTextColor(unpack(CLR.stacks))
    btn.count = count

    btn:EnableMouse(true)
    btn:SetScript("OnEnter", function(self)
        if self.sourceFrame then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.sourceFrame.GetTooltipInfo then
                local info = self.sourceFrame:GetTooltipInfo()
                if info then GameTooltip:ProcessInfo(info) end
            end
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)


    secondaryIcons[index] = btn
    return btn
end

local function GetSecondaryIcon(index)
    if secondaryIcons[index] then return secondaryIcons[index] end
    return CreateSecondaryIcon(index)
end

-- ── Safe value helpers (for Secret Values) ───────────────────────────
local function SafeGet(tbl, key)
    if not tbl then return nil end
    local ok, val = pcall(function() return tbl[key] end)
    return ok and val or nil
end

local function SafeSub(a, b)
    local ok, val = pcall(function() return a - b end)
    return ok and val or nil
end

local function SafeGT(a, b)
    local ok, val = pcall(function() return a > b end)
    return ok and val or nil
end

local function SafeNE(a, b)
    if a == nil and b == nil then return false end
    if a == nil or b == nil then return true end
    local ok, val = pcall(function() return a ~= b end)
    return ok and val or false
end

local function SafeBool(val)
    if val == nil then return false end
    -- If we can read it, return it. If it errors (Secret), assume true (it exists).
    local ok, res = pcall(function() return not not val end)
    if not ok then return true end
    return res
end

-- ── Essential Tracker Frame ──────────────────────────────────────────
essentialFrame = CreateFrame("Frame", "DaggesEssentialTrackerFrame", UIParent, "BackdropTemplate")
essentialFrame:SetFrameStrata("MEDIUM")
essentialFrame:SetClampedToScreen(true)
essentialFrame:EnableMouse(true)
essentialFrame:SetMovable(true)
essentialFrame:RegisterForDrag("LeftButton")

    UpdateFrameStyles()

local eAccent = essentialFrame:CreateTexture(nil, "OVERLAY")
eAccent:SetHeight(1)
eAccent:SetPoint("TOPLEFT", 2, -1)
eAccent:SetPoint("TOPRIGHT", -2, -1)
eAccent:SetColorTexture(unpack(CLR.accent))
essentialFrame.accent = eAccent

local eTitle = essentialFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
eTitle:SetPoint("TOP", 0, -2)
eTitle:SetTextColor(unpack(CLR.title))
eTitle:SetText("Essential")
essentialFrame.title = eTitle

essentialFrame:SetScript("OnDragStart", function(self)
    local db = GetCurrentProfile()
    if not db.locked then self:StartMoving() end
end)
essentialFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, px, py = self:GetPoint()
    local db = GetCurrentProfile()
    db.essentialPoint    = p
    db.essentialRelPoint = rp
    db.essentialX        = px
    db.essentialY        = py
end)

-- ── Utility Tracker Frame ────────────────────────────────────────────
utilityFrame = CreateFrame("Frame", "DaggesUtilityTrackerFrame", UIParent, "BackdropTemplate")
utilityFrame:SetFrameStrata("MEDIUM")
utilityFrame:SetClampedToScreen(true)
utilityFrame:EnableMouse(true)
utilityFrame:SetMovable(true)
utilityFrame:RegisterForDrag("LeftButton")

    UpdateFrameStyles()

local uAccent = utilityFrame:CreateTexture(nil, "OVERLAY")
uAccent:SetHeight(1)
uAccent:SetPoint("TOPLEFT", 2, -1)
uAccent:SetPoint("TOPRIGHT", -2, -1)
uAccent:SetColorTexture(unpack(CLR.accent))
utilityFrame.accent = uAccent

local uTitle = utilityFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
uTitle:SetPoint("TOP", 0, -2)
uTitle:SetTextColor(unpack(CLR.title))
uTitle:SetText("Utility")
utilityFrame.title = uTitle

utilityFrame:SetScript("OnDragStart", function(self)
    local db = GetCurrentProfile()
    if not db.locked then self:StartMoving() end
end)
utilityFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, px, py = self:GetPoint()
    local db = GetCurrentProfile()
    db.utilityPoint    = p
    db.utilityRelPoint = rp
    db.utilityX        = px
    db.utilityY        = py
end)

-- ── Icon Pools ───────────────────────────────────────────────────────
local essentialIcons = {}
local utilityIcons = {}

local function CreateGenericIcon(index, pool, parent, sizeKey)
    if pool[index] then return pool[index] end

    local btn = CreateFrame("Frame", nil, parent)
    local db = GetCurrentProfile()
    local size = (db and db[sizeKey]) or DEFAULTS[sizeKey] or ICON_SIZE
    btn:SetSize(size, size)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.08, 1)

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 1, -1); tex:SetPoint("BOTTOMRIGHT", -1, 1)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = tex

    for _, setup in ipairs({
        {"TOPLEFT", "TOPRIGHT", true}, {"BOTTOMLEFT", "BOTTOMRIGHT", true},
        {"TOPLEFT", "BOTTOMLEFT", false}, {"TOPRIGHT", "BOTTOMRIGHT", false},
    }) do
        local line = btn:CreateTexture(nil, "OVERLAY")
        if setup[3] then line:SetHeight(1) else line:SetWidth(1) end
        line:SetPoint(setup[1]); line:SetPoint(setup[2]); line:SetColorTexture(unpack(CLR.iconBord))
    end

    local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cd:SetAllPoints(btn.icon); cd:SetDrawEdge(false); cd:SetDrawSwipe(true); cd:SetHideCountdownNumbers(false)
    btn.cooldown = cd

    local countFrame = CreateFrame("Frame", nil, btn)
    countFrame:SetAllPoints(); countFrame:SetFrameLevel(btn:GetFrameLevel() + 10)
    local count = countFrame:CreateFontString(nil, "OVERLAY")
    count:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE"); count:SetPoint("BOTTOMRIGHT", -1, 2)
    count:SetTextColor(unpack(CLR.stacks))
    btn.count = count

    btn:EnableMouse(true)
    btn:SetScript("OnEnter", function(self)
        if self.sourceFrame then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.sourceFrame.GetTooltipInfo then
                local info = self.sourceFrame:GetTooltipInfo()
                if info then GameTooltip:ProcessInfo(info) end
            end
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    pool[index] = btn
    return btn
end

local function GetEssentialIcon(index)
    return CreateGenericIcon(index, essentialIcons, essentialFrame, "essentialIconSize")
end

local function GetUtilityIcon(index)
    return CreateGenericIcon(index, utilityIcons, utilityFrame, "utilityIconSize")
end

-- ── Totem Logic Refactored: Separate Bar ───────────────────────────────
totemFrame = CreateFrame("Frame", "DaggesTotemFrame", UIParent, "BackdropTemplate")
totemFrame:SetSize(4 * (ICON_SIZE + ICON_PAD) + FRAME_PAD*2 - ICON_PAD, ICON_SIZE + FRAME_PAD*2 + HEADER_H)
totemFrame:SetFrameStrata("MEDIUM")
totemFrame:SetClampedToScreen(true)
totemFrame:EnableMouse(true)
totemFrame:SetMovable(true)
totemFrame:RegisterForDrag("LeftButton")

    UpdateFrameStyles()

-- Accent line (Totem)
local tfAccent = totemFrame:CreateTexture(nil, "OVERLAY")
tfAccent:SetHeight(1)
tfAccent:SetPoint("TOPLEFT", 2, -1)
tfAccent:SetPoint("TOPRIGHT", -2, -1)
tfAccent:SetColorTexture(unpack(CLR.accent))
totemFrame.accent = tfAccent

-- Title (Totem)
local tfTitle = totemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
tfTitle:SetPoint("TOP", 0, -2)
tfTitle:SetTextColor(unpack(CLR.title))
tfTitle:SetText("Totems")
totemFrame.title = tfTitle

-- Drag (Totem)
totemFrame:SetScript("OnDragStart", function(self)
    if not GetCurrentProfile().locked then self:StartMoving() end
end)
totemFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, px, py = self:GetPoint()
    local db = GetCurrentProfile()
    db.totemPoint    = p
    db.totemRelPoint = rp
    db.totemX        = px
    db.totemY        = py
end)

local totemIcons = {}

local function GetTotemIcon(index)
    if totemIcons[index] then return totemIcons[index] end
    
    local btn = CreateFrame("Frame", nil, totemFrame)
    local db = GetCurrentProfile()
    local size = (db and db.totemIconSize) or DEFAULTS.totemIconSize or ICON_SIZE
    btn:SetSize(size, size)
    
    -- Background
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, 1)

    -- Icon texture
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", -1, 1)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = tex
    
    -- Border
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetColorTexture(0,0,0,0) -- Placeholder if we want borders
    
    local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cd:SetAllPoints(btn.icon)
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetHideCountdownNumbers(false) 
    btn.cooldown = cd

    -- Tooltip
    btn:EnableMouse(true)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetTotem(index) -- index corresponds to slot 1-4
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- Position
    local col = index - 1
    btn:SetPoint("TOPLEFT", totemFrame, "TOPLEFT", 
        FRAME_PAD + col * (ICON_SIZE + ICON_PAD), 
        -(HEADER_H + FRAME_PAD))
        

    totemIcons[index] = btn
    return btn
end

-- Initialize 4 totem slots
for i=1,4 do GetTotemIcon(i) end

-- ── Resize all icons when size/spacing changes ──────────────────────
local function ResizeAllIcons()
    local db = GetCurrentProfile()
    local pSize = db.primaryIconSize or DEFAULTS.primaryIconSize
    local sSize = db.secondaryIconSize or DEFAULTS.secondaryIconSize
    local tSize = db.totemIconSize or DEFAULTS.totemIconSize
    local tPad  = db.totemIconPad or DEFAULTS.totemIconPad
    local eSize = db.essentialIconSize or DEFAULTS.essentialIconSize
    local uSize = db.utilityIconSize or DEFAULTS.utilityIconSize

    -- Resize primary icons
    for _, btn in ipairs(icons) do
        btn:SetSize(pSize, pSize)
        btn.icon:SetPoint("TOPLEFT", 1, -1)
        btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    -- Resize secondary icons
    for _, btn in ipairs(secondaryIcons) do
        btn:SetSize(sSize, sSize)
        btn.icon:SetPoint("TOPLEFT", 1, -1)
        btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    -- Resize and reposition totem icons
    for i, btn in ipairs(totemIcons) do
        btn:SetSize(tSize, tSize)
        btn.icon:SetPoint("TOPLEFT", 1, -1)
        btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", totemFrame, "TOPLEFT",
            FRAME_PAD + (i-1) * (tSize + tPad),
            -(HEADER_H + FRAME_PAD))
    end
    -- Resize essential/utility icons
    for _, btn in ipairs(essentialIcons) do
        btn:SetSize(eSize, eSize)
        btn.icon:SetPoint("TOPLEFT", 1, -1)
        btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    for _, btn in ipairs(utilityIcons) do
        btn:SetSize(uSize, uSize)
        btn.icon:SetPoint("TOPLEFT", 1, -1)
        btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    -- Update totem frame size
    local maxTotems = db.totemCount or 4
    totemFrame:SetSize(maxTotems * (tSize + tPad) + FRAME_PAD*2 - tPad, tSize + FRAME_PAD*2 + HEADER_H)
end

local function UpdateTotemBar(forceClosed)
    local activeCount = 0
    local db = GetCurrentProfile()
    local maxTotems = db.totemCount or 4
    
    for i = 1, 4 do
        -- Respect user setting for max totems displayed
        if i > maxTotems then
            totemIcons[i]:Hide()
        else
            local haveTotem, name, start, duration, icon = GetTotemInfo(i)
            
            -- Use SafeBool to detect if a totem is present (handles Secret Values)
            local isActive = SafeBool(haveTotem)
            local btn = totemIcons[i]
            
            if isActive then
                -- Pass values directly to UI functions
                pcall(function() btn.icon:SetTexture(icon) end)
                pcall(function() btn.cooldown:SetCooldown(start, duration) end)
                
                btn:Show()
                activeCount = activeCount + 1
            else
                btn:Hide()
            end
        end
    end
    
    local configOpen = not forceClosed and _G["DaggesConfigFrame"] and _G["DaggesConfigFrame"]:IsShown()

    -- Show sample totem icons when config is open and slots are empty
    if configOpen then
        for i = 1, maxTotems do
            local btn = totemIcons[i]
            if not btn:IsShown() then
                btn.icon:SetTexture(SAMPLE_TOTEM_ICONS[((i - 1) % #SAMPLE_TOTEM_ICONS) + 1])
                btn.icon:SetDesaturated(true)
                btn.icon:SetAlpha(0.5)
                btn.cooldown:SetCooldown(0, 0)
                btn:Show()
                activeCount = activeCount + 1
            end
        end
    end

    if activeCount > 0 or configOpen then
        if db.showTotems then
             totemFrame:Show()
        else
             totemFrame:Hide()
        end
    else
        totemFrame:Hide()
    end
end



-- ── Stack Count Helper ──────────────────────────────────────────────
-- Uses hooked data first, then FontString mirroring, then aura API.
-- Handles WoW 12.0 Secret Values via SafeGT/SafeNE.
local function FindStacksFromChild(child)
    if not child then return nil end

    -- Method 0: Use cached stack text from our SetText hook (most reliable)
    if child._daggesStackText then
        local txt = child._daggesStackText
        if SafeNE(txt, nil) and SafeNE(txt, "") and SafeNE(txt, "1") then
            return txt
        end
    end

    -- Method 1: Mirror the Blizzard frame's count text directly
    local function FindCount(f)
        if not f then return nil end
        if f.Count then return f.Count end
        local regions = { f:GetRegions() }
        for _, reg in ipairs(regions) do
            if reg:IsObjectType("FontString") then
                local n = reg:GetName()
                if n and n:find("Count") then return reg end
                if not n and #regions == 1 then return reg end
            end
        end
        return nil
    end

    local sourceCount = FindCount(child)
    if not sourceCount and child.Applications then
        sourceCount = FindCount(child.Applications)
    end

    if sourceCount then
        local txt = sourceCount:GetText()
        local isVisible = sourceCount:IsShown()
        if SafeNE(txt, nil) and SafeNE(txt, "") and SafeNE(txt, "1") and isVisible then
            return txt
        end
    end

    -- Method 2: Fallback to Aura Data
    local aura = nil
    pcall(function()
        aura = C_UnitAuras.GetAuraDataByAuraInstanceID(
            child.auraDataUnit or "player",
            child.auraInstanceID
        )
    end)
    if not aura and child.auraSpellID then
        pcall(function()
            aura = C_UnitAuras.GetPlayerAuraBySpellID(child.auraSpellID)
        end)
    end
    if aura and aura.applications and SafeGT(aura.applications, 1) then
        return tostring(aura.applications)
    end

    return nil
end

-- ── Refresh: read from CDM viewers ──────────────────────────────────
local function PopulateFromViewer(viewer, getIconFunc, pool, maxCount, trackerFrame, onlyActive, configOpen)
    if not trackerFrame then return 0 end
    local itemFrames = {}
    if viewer then
        itemFrames = viewer.GetItemFrames and viewer:GetItemFrames() or { viewer:GetChildren() }
    end
    local currentIdx = 0
    
    -- Hide all in pool first
    for _, b in ipairs(pool) do b:Hide() end
    
    local db = GetCurrentProfile()

    for _, child in ipairs(itemFrames) do
        if child.Icon and currentIdx < maxCount then
            local isActive = child:IsShown()
            local texFile = child.Icon:GetTexture()

            if not texFile and child.cooldownInfo then
                pcall(function()
                    local sid = child.cooldownInfo.overrideSpellID or child.cooldownInfo.spellID
                    if sid then
                        local info = C_Spell.GetSpellInfo(sid)
                        if info then texFile = info.iconID end
                    end
                end)
            end

            if texFile and (not onlyActive or isActive) then
                currentIdx = currentIdx + 1
                local btn = getIconFunc(currentIdx)
                if btn then
                    btn.sourceFrame = child
                    btn.icon:SetTexture(texFile)
                    
                    if isActive then
                        btn.icon:SetDesaturated(false); btn.icon:SetAlpha(1.0)
                    else
                        btn.icon:SetDesaturated(true); btn.icon:SetAlpha(0.45)
                    end

                    -- Mirror Count
                    btn.count:Hide()
                    if isActive then
                        local stackTxt = FindStacksFromChild(child)
                        if stackTxt then
                            btn.count:SetText(stackTxt)
                            btn.count:Show()
                        end
                    end

                    -- Mirror Cooldown
                    pcall(function()
                        if isActive then
                            btn.cooldown:SetCooldown(child._daggesCDStart, child._daggesCDDuration)
                        else
                            btn.cooldown:SetCooldown(0, 0)
                        end
                    end)

                    btn:Show()
                end
            end
        end
    end

    -- Sample icons if config open
    if configOpen then
        for j = currentIdx + 1, maxCount do
            local btn = getIconFunc(j)
            if btn then
                btn.sourceFrame = nil
                btn.icon:SetTexture(SAMPLE_ICONS[((j + 2) % #SAMPLE_ICONS) + 1])
                btn.icon:SetDesaturated(true); btn.icon:SetAlpha(0.5)
                btn.cooldown:SetCooldown(0, 0); btn.count:Hide(); btn:Show()
            end
        end
        currentIdx = math.max(currentIdx, maxCount)
    end
    
    local size, pad
    if trackerFrame == frame then
        size = db.primaryIconSize or DEFAULTS.primaryIconSize
        pad = db.primaryIconPad or DEFAULTS.primaryIconPad
    elseif trackerFrame == essentialFrame then
        size = db.essentialIconSize or DEFAULTS.essentialIconSize
        pad = db.essentialIconPad or DEFAULTS.essentialIconPad
    elseif trackerFrame == utilityFrame then
        size = db.utilityIconSize or DEFAULTS.utilityIconSize
        pad = db.utilityIconPad or DEFAULTS.utilityIconPad
    else
        -- Secondary/Fallback
        size = db.secondaryIconSize or DEFAULTS.secondaryIconSize
        pad = db.secondaryIconPad or DEFAULTS.secondaryIconPad
    end
    
    if currentIdx > 0 or configOpen then
        trackerFrame:SetSize(currentIdx * (size + pad) + FRAME_PAD*2 - pad, size + FRAME_PAD*2 + HEADER_H)
        trackerFrame:Show()
        -- Reposition icons
        for j = 1, currentIdx do
            local b = pool[j]
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", trackerFrame, "TOPLEFT", FRAME_PAD + (j-1)*(size+pad), -(HEADER_H + FRAME_PAD))
        end
    else
        trackerFrame:Hide()
    end
    
    return currentIdx
end

-- ── Refresh: read from BuffIconCooldownViewer ────────────────────────
local function RefreshBuffs(forceClosed)
    UpdateFrameStyles(forceClosed)
    local db = GetCurrentProfile()
    local configOpen = not forceClosed and _G["DaggesConfigFrame"] and _G["DaggesConfigFrame"]:IsShown()
    
    -- Essential
    if db.showEssential then
        PopulateFromViewer(_G.EssentialCooldownViewer, GetEssentialIcon, essentialIcons, db.essentialCount or 10, essentialFrame, false, configOpen)
    else
        essentialFrame:Hide()
    end

    -- Utility
    if db.showUtility then
        PopulateFromViewer(_G.UtilityCooldownViewer, GetUtilityIcon, utilityIcons, db.utilityCount or 10, utilityFrame, false, configOpen)
    else
        utilityFrame:Hide()
    end

    -- Buffs (Primary/Secondary logic)
    local viewer = _G.BuffIconCooldownViewer
    local itemFrames = {}
    if viewer then
        itemFrames = viewer.GetItemFrames and viewer:GetItemFrames() or { viewer:GetChildren() }
    end

    local primaryIdx = 0
    local secondaryIdx = 0
    local maxPrimary = db.buffCount or 5
    local maxSecondary = db.secondaryBuffCount or 10

    -- Hide all first
    for _, b in ipairs(icons) do b:Hide() end
    for _, b in ipairs(secondaryIcons) do b:Hide() end

    for _, child in ipairs(itemFrames) do
        if child.Icon then
            local isActive = child:IsShown()
            local texFile = child.Icon:GetTexture()
            if texFile then
                local isPrimary = (primaryIdx < maxPrimary)
                if isPrimary or isActive then
                    local btn = nil
                    if isPrimary then
                        primaryIdx = primaryIdx + 1; btn = GetIcon(primaryIdx)
                    elseif secondaryIdx < maxSecondary then
                        secondaryIdx = secondaryIdx + 1; btn = GetSecondaryIcon(secondaryIdx)
                    end

                    if btn then
                        btn.sourceFrame = child
                        btn.icon:SetTexture(texFile)
                        btn.icon:SetDesaturated(not isActive); btn.icon:SetAlpha(isActive and 1.0 or 0.45)
                        
                        -- Count/CD logic for Buffs
                        btn.count:Hide()
                        if isActive then
                            local stackTxt = FindStacksFromChild(child)
                            if stackTxt then
                                btn.count:SetText(stackTxt)
                                btn.count:Show()
                            end
                        end
                        pcall(function()
                            if isActive then
                                btn.cooldown:SetCooldown(child._daggesCDStart, child._daggesCDDuration)
                            else
                                btn.cooldown:SetCooldown(0, 0)
                            end
                        end)
                        
                        btn:Show()
                    end
                end
            end
        end
    end

    -- Sample icons for Buffs if config open
    if configOpen then
        for j = primaryIdx + 1, maxPrimary do
            local btn = GetIcon(j)
            if btn then
                btn.sourceFrame = nil
                btn.icon:SetTexture(SAMPLE_ICONS[((j - 1) % #SAMPLE_ICONS) + 1])
                btn.icon:SetDesaturated(true); btn.icon:SetAlpha(0.5)
                btn.cooldown:SetCooldown(0, 0); btn.count:Hide(); btn:Show()
            end
        end
        primaryIdx = math.max(primaryIdx, maxPrimary)
        
        if db.showSecondaryBuffs then
            for j = secondaryIdx + 1, maxSecondary do
                local btn = GetSecondaryIcon(j)
                if btn then
                    btn.sourceFrame = nil
                    btn.icon:SetTexture(SAMPLE_ICONS[((j + 4) % #SAMPLE_ICONS) + 1])
                    btn.icon:SetDesaturated(true); btn.icon:SetAlpha(0.5)
                    btn.cooldown:SetCooldown(0, 0); btn.count:Hide(); btn:Show()
                end
            end
            secondaryIdx = math.max(secondaryIdx, maxSecondary)
        end
    end

    -- Frame Sizing & Positioning
    if primaryIdx > 0 or configOpen then
        local pSize = db.primaryIconSize or DEFAULTS.primaryIconSize
        local pPad = db.primaryIconPad or DEFAULTS.primaryIconPad
        frame:SetSize(primaryIdx * (pSize + pPad) + FRAME_PAD*2 - pPad, pSize + FRAME_PAD*2 + HEADER_H)
        if db.showBuffs then frame:Show() else frame:Hide() end
        for j = 1, primaryIdx do
            local b = icons[j]
            if b then
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", frame, "TOPLEFT", FRAME_PAD + (j-1)*(pSize+pPad), -(HEADER_H + FRAME_PAD))
            end
        end
    else
        frame:Hide()
    end
    
    if secondaryIdx > 0 or (configOpen and db.showSecondaryBuffs) then
        local sSize = db.secondaryIconSize or DEFAULTS.secondaryIconSize
        local sPad = db.secondaryIconPad or DEFAULTS.secondaryIconPad
        local w = secondaryIdx * (sSize + sPad) + FRAME_PAD*2 - sPad
        secondaryFrame:SetSize(w, sSize + FRAME_PAD*2 + HEADER_H)
        if db.showSecondaryBuffs then secondaryFrame:Show() else secondaryFrame:Hide() end
        local startX = (w - (secondaryIdx*(sSize+sPad)-sPad))/2
        for j = 1, secondaryIdx do
            local b = secondaryIcons[j]
            if b then
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", secondaryFrame, "TOPLEFT", startX + (j-1)*(sSize+sPad), -(HEADER_H + FRAME_PAD))
            end
        end
    else
        secondaryFrame:Hide()
    end
end

-- ── Hook the Blizzard CooldownViewer ─────────────────────────────────
local hooked = false

local function HookViewer()
    local viewers = {
        _G.BuffIconCooldownViewer,
        _G.EssentialCooldownViewer,
        _G.UtilityCooldownViewer
    }
    
    local anyAvailable = false
    for _, v in ipairs(viewers) do
        if v then anyAvailable = true break end
    end
    
    if not anyAvailable or hooked then return end
    hooked = true

    -- Hook child show/hide to catch individual buff changes
    local function HookChild(child)
        if not child or child.daggesHooked then return end
        child.daggesHooked = true
        child:HookScript("OnShow", function() C_Timer.After(0.05, RefreshBuffs) end)
        child:HookScript("OnHide", function() C_Timer.After(0.05, RefreshBuffs) end)

        pcall(function()
            local cdFrame = child.Cooldown
            if not cdFrame then
                local kids = { child:GetChildren() }
                for _, kid in ipairs(kids) do
                    if kid.SetCooldown and kid.GetCooldownTimes then
                        cdFrame = kid
                        break
                    end
                end
            end
            if cdFrame and cdFrame.SetCooldown then
                hooksecurefunc(cdFrame, "SetCooldown", function(_, start, duration)
                    child._daggesCDStart = start
                    child._daggesCDDuration = duration
                    C_Timer.After(0.05, RefreshBuffs)
                end)
            end
        end)

        -- Hook Applications FontString to capture stack count text
        -- (same pattern as the SetCooldown hook above)
        pcall(function()
            if child.Applications then
                local regions = { child.Applications:GetRegions() }
                for _, reg in ipairs(regions) do
                    if reg:IsObjectType("FontString") then
                        hooksecurefunc(reg, "SetText", function(_, text)
                            child._daggesStackText = text
                            C_Timer.After(0.05, RefreshBuffs)
                        end)
                        -- Also hook Show/Hide to track visibility
                        reg:HookScript("OnShow", function()
                            child._daggesStackShown = true
                            C_Timer.After(0.05, RefreshBuffs)
                        end)
                        reg:HookScript("OnHide", function()
                            child._daggesStackShown = false
                            C_Timer.After(0.05, RefreshBuffs)
                        end)
                    end
                end
            end
            -- Also hook child.Count if it exists
            if child.Count and child.Count.SetText then
                hooksecurefunc(child.Count, "SetText", function(_, text)
                    child._daggesStackText = text
                    C_Timer.After(0.05, RefreshBuffs)
                end)
            end
        end)
    end

    for _, viewer in ipairs(viewers) do
        if viewer then
            -- Hook Layout
            if viewer.Layout then
                hooksecurefunc(viewer, "Layout", function()
                    C_Timer.After(0.05, RefreshBuffs)
                end)
            end

            -- Hook existing children
            local children = { viewer:GetChildren() }
            for _, child in ipairs(children) do
                HookChild(child)
            end

            -- Monitor new children
            viewer:HookScript("OnUpdate", function(self)
                local currentChildren = { self:GetChildren() }
                for _, child in ipairs(currentChildren) do
                    if not child.daggesHooked then
                        HookChild(child)
                        C_Timer.After(0.05, RefreshBuffs)
                    end
                end
            end)

            -- Hide Blizzard CDM if requested
            if GetCurrentProfile().hideBlizzardCDM then
                if viewer.SetAlpha then viewer:SetAlpha(0) end
                viewer:HookScript("OnShow", function(self)
                    if GetCurrentProfile().hideBlizzardCDM and self.SetAlpha then self:SetAlpha(0) end
                end)
            end
        end
    end

    RefreshBuffs()
end

-- ── Update Timer ─────────────────────────────────────────────────────
local elapsed = 0
frame:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed >= UPDATE_HZ then
        elapsed = 0
        -- Try to hook if not yet done (viewer loads late)
        if not hooked then HookViewer() end
        RefreshBuffs()
    end
end)

-- ── Events ───────────────────────────────────────────────────────────
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_TOTEM_UPDATE")

frame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "PLAYER_LOGIN" then
        -- Init saved vars (PROFILE SYSTEM)
        if not DaggesAddonDB then 
            DaggesAddonDB = { profiles = {}, charProfiles = {} }
        end
        
        -- Migration/Cleanup
        if not DaggesAddonDB.profiles then
            DaggesAddonDB.profiles = {}
        end
        if not DaggesAddonDB.charProfiles then
            DaggesAddonDB.charProfiles = {}
        end
        
        if not DaggesAddonDB.profiles["Default"] then
            DaggesAddonDB.profiles["Default"] = CopyTable(DEFAULTS)
        end
        
        -- Set current character to Default if not set
        local charKey = GetCharKey()
        if not DaggesAddonDB.charProfiles[charKey] then
            DaggesAddonDB.charProfiles[charKey] = "Default"
        end

        ResizeAllIcons()
        UpdateFrameStyles()

        local db = GetCurrentProfile()

        -- Restore position (Main Frame)
        frame:ClearAllPoints()
        frame:SetPoint(
            db.point    or "CENTER",
            UIParent,
            db.relPoint or "CENTER",
            db.x        or 0,
            db.y        or 0
        )
        
        -- Restore position (Totem Frame)
        totemFrame:ClearAllPoints()
        totemFrame:SetPoint(
            db.totemPoint    or "CENTER",
            UIParent,
            db.totemRelPoint or "CENTER",
            db.totemX        or 0,
            db.totemY        or -100
        )

        -- Restore position (Secondary Frame)
        secondaryFrame:ClearAllPoints()
        secondaryFrame:SetPoint(
            db.secondaryPoint or "CENTER",
            UIParent,
            db.secondaryRelPoint or "CENTER",
            db.secondaryX or 0,
            db.secondaryY or -150
        )

        -- Restore position (Essential Frame)
        essentialFrame:ClearAllPoints()
        essentialFrame:SetPoint(
            db.essentialPoint or "CENTER",
            UIParent,
            db.essentialRelPoint or "CENTER",
            db.essentialX or 0,
            db.essentialY or 50
        )

        -- Restore position (Utility Frame)
        utilityFrame:ClearAllPoints()
        utilityFrame:SetPoint(
            db.utilityPoint or "CENTER",
            UIParent,
            db.utilityRelPoint or "CENTER",
            db.utilityX or 0,
            db.utilityY or 100
        )

        if db.showBuffs then
            frame:Show()
            RefreshBuffs()
        else
            frame:Hide()
        end
        
        -- totemFrame managed by UpdateTotemBar which calls Show/Hide based on content + setting

        -- Try to hook immediately, but viewer may not exist yet
        C_Timer.After(0.5, HookViewer)
        C_Timer.After(2.0, HookViewer) -- fallback retry
        
        -- Initial Totem Update
        UpdateTotemBar()

        print("|cff8878cc[Dagge's Buff Tracker]|r loaded \226\128\148 /dagge for options")

    elseif event == "ADDON_LOADED" and arg1 == "Blizzard_CooldownManager" then
        -- CooldownManager just loaded, hook the viewer
        C_Timer.After(0.5, HookViewer)

    elseif event == "PLAYER_LOGOUT" then
        local db = GetCurrentProfile()
        local p, _, rp, px, py = frame:GetPoint()
        db.point    = p
        db.relPoint = rp
        db.x        = px
        db.y        = py
        
        local tp, _, trp, tpx, tpy = totemFrame:GetPoint()
        db.totemPoint    = tp
        db.totemRelPoint = trp
        db.totemX        = tpx
        db.totemY        = tpy

        local sp, _, srp, spx, spy = secondaryFrame:GetPoint()
        db.secondaryPoint    = sp
        db.secondaryRelPoint = srp
        db.secondaryX        = spx
        db.secondaryY        = spy

        -- Save Essential position
        local ep, _, erp, epx, epy = essentialFrame:GetPoint()
        db.essentialPoint    = ep
        db.essentialRelPoint = erp
        db.essentialX        = epx
        db.essentialY        = epy

        -- Save Utility position
        local up, _, urp, upx, upy = utilityFrame:GetPoint()
        db.utilityPoint    = up
        db.utilityRelPoint = urp
        db.utilityX        = upx
        db.utilityY        = upy

        db.visible = frame:IsShown()
        
    elseif event == "PLAYER_TOTEM_UPDATE" then
        UpdateTotemBar()
    end
end)

-- ── Game Menu Shortcuts (Toolbelt) ─────────────────────────────────────
local sideButtons = {}

local function RunSlashCommand(cmd)
    local cmdLower = cmd:lower()
    for key, value in pairs(_G) do
        if type(key) == "string" and key:sub(1,6) == "SLASH_" then
            if type(value) == "string" and value:lower() == cmdLower then
                local tag = key:match("^SLASH_(.-)%d+$") or key:match("^SLASH_(.+)$")
                if tag and SlashCmdList[tag] then
                    SlashCmdList[tag]("")
                    return true
                end
            end
        end
    end
    -- Fallback: some addons don't use the standard numbering?
    return false
end

local function AddGameMenuButtons()
    if #sideButtons > 0 then return end

    local buttons = {
        {
            text = "Cooldowns",
            onClick = function()
                if not _G.CooldownViewerSettings then C_AddOns.LoadAddOn("Blizzard_CooldownViewer") end
                local frame = _G.CooldownViewerSettings
                if frame then frame:SetShown(not frame:IsShown()) HideUIPanel(GameMenuFrame) end
            end
        },
        {
            text = "Dominos",
            onClick = function()
                if RunSlashCommand("/dominos") then HideUIPanel(GameMenuFrame) else print("Dominos not found.") end
            end
        },
        {
            text = "Danders",
            onClick = function()
                if RunSlashCommand("/df") then HideUIPanel(GameMenuFrame) else print("Danders Frames not found.") end
            end
        },
        {
            text = "Unhalted",
            onClick = function()
                if RunSlashCommand("/uuf") then HideUIPanel(GameMenuFrame) else print("Unhalted Unitframes not found.") end
            end
        },
        {
            text = "Dagge's",
            onClick = function()
                SlashCmdList["DAGGE"]("config")
                HideUIPanel(GameMenuFrame)
            end
        },
    }

    local function PositionButtons()
        for i, btn in ipairs(sideButtons) do
            btn:ClearAllPoints()
            if i == 1 then
                btn:SetPoint("TOPLEFT", GameMenuFrame, "TOPRIGHT", 10, -15)
            else
                btn:SetPoint("TOPLEFT", sideButtons[i-1], "BOTTOMLEFT", 0, -1)
            end
        end
    end

    for i, cfg in ipairs(buttons) do
        local b = CreateFrame("Button", "DaggesSideBtn"..i, GameMenuFrame, "GameMenuButtonTemplate")
        b:SetText(cfg.text)
        b:SetScript("OnClick", cfg.onClick)
        tinsert(sideButtons, b)
    end

    hooksecurefunc(GameMenuFrame, "Layout", function() pcall(PositionButtons) end)
    GameMenuFrame:HookScript("OnShow", function() pcall(PositionButtons) end)
    
    if GameMenuFrame:IsShown() then pcall(PositionButtons) end
end

-- Hook into startup to create button
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    C_Timer.After(1, AddGameMenuButtons)
end)

-- ── Settings UI ────────────────────────────────────────────────────────
local configFrame = nil

local function CreateConfigFrame()
    if configFrame then return end
    
    local f = CreateFrame("Frame", "DaggesConfigFrame", UIParent, "BackdropTemplate")
    f:SetSize(320, 500) -- Increased height to fit all settings comfortably
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 32,
        insets   = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    -- Title
    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("Dagge's Buff Tracker")

    -- Close Button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -8, -8)

    -- ── Tab System ──
    local tabs = {}
    local tabFrames = {}

    local function ShowTab(id)
        for i, frame in ipairs(tabFrames) do
            if i == id then frame:Show() else frame:Hide() end
        end
        for i, button in ipairs(tabs) do
            if i == id then 
                button:SetAlpha(1.0)
                button:GetFontString():SetTextColor(1, 0.8, 0)
            else 
                button:SetAlpha(0.7)
                button:GetFontString():SetTextColor(1, 1, 1)
            end
        end
    end

    local function CreateTab(id, text)
        local tab = CreateFrame("Button", nil, f)
        tab:SetSize(70, 25) -- Slightly narrower to fit 4 tabs
        tab:SetPoint("TOPLEFT", f, "TOPLEFT", 10 + (id-1) * 75, -45)
        
        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.2, 0.2, 0.2, 0.5)
        
        local highlight = tab:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0.5, 0.5, 0.5, 0.3)
        
        tab:SetFontString(tab:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall"))
        tab:SetText(text)
        
        tab:SetScript("OnClick", function() ShowTab(id) end)
        
        tabs[id] = tab
        
        local content = CreateFrame("Frame", nil, f)
        content:SetPoint("TOPLEFT", 0, -75)
        content:SetPoint("BOTTOMRIGHT", 0, 0)
        tabFrames[id] = content
        
        return content
    end

    local generalTab = CreateTab(1, "General")
    local buffsTab   = CreateTab(2, "Buffs")
    local totemsTab  = CreateTab(3, "Totems")
    local cdsTab     = CreateTab(4, "Cooldowns")

    -- ── Helpers (Updated for parenting) ──
    local function MakeHeader(parent, text, yOffset)
        local h = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        h:SetPoint("TOPLEFT", 24, yOffset)
        h:SetTextColor(0.9, 0.8, 0.5)
        h:SetText(text)
        return h
    end

    local function MakeCheck(parent, name, label, yOffset, xOffset, dbKey, defaultVal, callback)
        local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", xOffset, yOffset)
        _G[cb:GetName() .. "Text"]:SetText(label)
        local db = GetCurrentProfile()
        local val = db[dbKey]
        if val == nil then val = defaultVal end
        cb:SetChecked(val)
        cb:SetScript("OnClick", function(self)
            GetCurrentProfile()[dbKey] = self:GetChecked()
            if callback then callback() end
        end)
        return cb
    end

    local function MakeSlider(parent, name, label, yOffset, min, max, dbKey, defaultVal, callback)
        local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
        sl:SetPoint("TOPLEFT", 24, yOffset)
        sl:SetWidth(250)
        sl:SetMinMaxValues(min, max)
        sl:SetValueStep(1)
        sl:SetObeyStepOnDrag(true)
        _G[sl:GetName() .. "Low"]:SetText(tostring(min))
        _G[sl:GetName() .. "High"]:SetText(tostring(max))
        local db = GetCurrentProfile()
        _G[sl:GetName() .. "Text"]:SetText(label .. ": " .. (db[dbKey] or defaultVal))
        sl:SetScript("OnValueChanged", function(self, value)
            local val = math.floor(value + 0.5)
            GetCurrentProfile()[dbKey] = val
            _G[self:GetName() .. "Text"]:SetText(label .. ": " .. val)
            if callback then callback() end
        end)
        sl:SetValue(db[dbKey] or defaultVal)
        return sl
    end

    -- ════════════════════════════════════════════════════════════════
    -- TAB 1: GENERAL (Profiles & Global Settings)
    -- ════════════════════════════════════════════════════════════════
    local y = -10
    
    local profileLabel = generalTab:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    profileLabel:SetPoint("TOPLEFT", 24, y)
    profileLabel:SetText("Profile:")
    
    local ddown = CreateFrame("Frame", "DaggesProfileDropdown", generalTab, "UIDropDownMenuTemplate")
    ddown:SetPoint("TOPLEFT", 70, y + 2)
    UIDropDownMenu_SetWidth(ddown, 120)
    
    local function UpdateDropdownText()
        local charKey = GetCharKey()
        local pName = DaggesAddonDB.charProfiles[charKey] or "Default"
        UIDropDownMenu_SetText(ddown, pName)
    end
    
    UIDropDownMenu_Initialize(ddown, function(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        local charKey = GetCharKey()
        local currentCharProfile = DaggesAddonDB.charProfiles[charKey] or "Default"
        local names = {}
        for name in pairs(DaggesAddonDB.profiles) do table.insert(names, name) end
        table.sort(names, function(a, b)
            if a == "Default" then return true end
            if b == "Default" then return false end
            return a < b
        end)
        for _, name in ipairs(names) do
            info.text = name
            info.checked = (name == currentCharProfile)
            info.func = function(self) SetProfile(self:GetText()); UpdateDropdownText() end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UpdateDropdownText()
    
    -- New/Delete Buttons
    local newBtn = CreateFrame("Button", nil, generalTab, "GameMenuButtonTemplate")
    newBtn:SetSize(20, 20); newBtn:SetPoint("LEFT", ddown, "RIGHT", -10, 2); newBtn:SetText("+")
    newBtn:SetScript("OnClick", function()
        StaticPopupDialogs["DAGGES_NEW_PROFILE"] = {
            text = "Enter new profile name:", button1 = "Create", button2 = "Cancel", hasEditBox = true,
            OnAccept = function(self) CopyProfile(self.EditBox:GetText()); UpdateDropdownText() end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("DAGGES_NEW_PROFILE")
    end)
    
    local delBtn = CreateFrame("Button", nil, generalTab, "GameMenuButtonTemplate")
    delBtn:SetSize(20, 20); delBtn:SetPoint("LEFT", newBtn, "RIGHT", 5, 0); delBtn:SetText("-")
    delBtn:SetScript("OnClick", function()
        local charKey = GetCharKey()
        local pName = DaggesAddonDB.charProfiles[charKey] or "Default"
        if pName == "Default" then print("Cannot delete Default profile."); return end
        DeleteProfile(pName); UpdateDropdownText()
    end)

    y = y - 35
    local copyLabel = generalTab:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    copyLabel:SetPoint("TOPLEFT", 24, y); copyLabel:SetText("Copy From:")
    
    local copyDown = CreateFrame("Frame", "DaggesCopyFromDropdown", generalTab, "UIDropDownMenuTemplate")
    copyDown:SetPoint("TOPLEFT", 70, y + 2); UIDropDownMenu_SetWidth(copyDown, 120); UIDropDownMenu_SetText(copyDown, "Select...")
    UIDropDownMenu_Initialize(copyDown, function(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        local names = {}
        for name in pairs(DaggesAddonDB.profiles) do table.insert(names, name) end
        table.sort(names, function(a, b)
            if a == "Default" then return true end
            if b == "Default" then return false end
            return a < b
        end)
        for _, name in ipairs(names) do
            info.text = name; info.checked = false
            info.func = function(self)
                local src = self:GetText()
                StaticPopupDialogs["DAGGES_COPY_CONFIRM"] = {
                    text = "Copy settings from '" .. src .. "' to current?", button1 = "Yes", button2 = "No",
                    OnAccept = function() CopyFromProfile(src) end, timeout = 0, whileDead = true, hideOnEscape = true,
                }
                StaticPopup_Show("DAGGES_COPY_CONFIRM")
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    y = y - 45
    MakeCheck(generalTab, "DaggesLockCheck", "Lock Frames", y, 20, "locked", false, function()
        print("|cff8878cc[Buff Tracker]|r Frames " .. (GetCurrentProfile().locked and "Locked" or "Unlocked"))
    end)
    MakeCheck(generalTab, "DaggesHideBGCheck", "Hide Background", y, 160, "hideBackground", false, UpdateFrameStyles)
    
    y = y - 30
    MakeCheck(generalTab, "DaggesHideCDMCheck", "Hide Blizzard CDM", y, 20, "hideBlizzardCDM", true, function()
        if viewer and viewer.SetAlpha then viewer:SetAlpha(GetCurrentProfile().hideBlizzardCDM and 0 or 1) end
    end)

    y = y - 40
    local resetBtn = CreateFrame("Button", nil, generalTab, "GameMenuButtonTemplate")
    resetBtn:SetPoint("TOPLEFT", 20, y); resetBtn:SetSize(130, 25); resetBtn:SetText("Reset Positions")
    resetBtn:SetScript("OnClick", function() SlashCmdList["DAGGE"]("reset") end)

    -- ════════════════════════════════════════════════════════════════
    -- TAB 2: BUFFS (Primary & Secondary)
    -- ════════════════════════════════════════════════════════════════
    y = -10
    MakeHeader(buffsTab, "-- Primary Buffs --", y)
    y = y - 25
    MakeCheck(buffsTab, "DaggesShowBuffsCheck", "Show Primary", y, 20, "showBuffs", true, RefreshBuffs)
    
    y = y - 35
    MakeSlider(buffsTab, "DaggesBuffSlider", "Count", y, 0, 20, "buffCount", DEFAULTS.buffCount, RefreshBuffs)
    y = y - 45
    MakeSlider(buffsTab, "DaggesPrimarySizeSlider", "Size", y, 20, 60, "primaryIconSize", DEFAULTS.primaryIconSize, function() ResizeAllIcons(); RefreshBuffs() end)
    y = y - 45
    MakeSlider(buffsTab, "DaggesPrimaryPadSlider", "Spacing", y, 0, 15, "primaryIconPad", DEFAULTS.primaryIconPad, function() ResizeAllIcons(); RefreshBuffs() end)
    
    y = y - 55
    MakeHeader(buffsTab, "-- Secondary Buffs --", y)
    y = y - 25
    MakeCheck(buffsTab, "DaggesShowSecondaryCheck", "Show Secondary", y, 20, "showSecondaryBuffs", true, RefreshBuffs)
    
    y = y - 35
    MakeSlider(buffsTab, "DaggesSecondarySlider", "Count", y, 1, 25, "secondaryBuffCount", 10, RefreshBuffs)
    y = y - 45
    MakeSlider(buffsTab, "DaggesSecondarySizeSlider", "Size", y, 20, 60, "secondaryIconSize", DEFAULTS.secondaryIconSize, function() ResizeAllIcons(); RefreshBuffs() end)
    y = y - 45
    MakeSlider(buffsTab, "DaggesSecondaryPadSlider", "Spacing", y, 0, 15, "secondaryIconPad", DEFAULTS.secondaryIconPad, function() ResizeAllIcons(); RefreshBuffs() end)
    
    -- ════════════════════════════════════════════════════════════════
    -- TAB 3: TOTEMS
    -- ════════════════════════════════════════════════════════════════
    y = -10
    MakeHeader(totemsTab, "-- Totem Settings --", y)
    y = y - 25
    MakeCheck(totemsTab, "DaggesShowTotemsCheck", "Show Totems", y, 20, "showTotems", true, UpdateTotemBar)
    
    y = y - 35
    MakeSlider(totemsTab, "DaggesTotemSlider", "Max Totems", y, 1, 4, "totemCount", 4, UpdateTotemBar)
    y = y - 45
    MakeSlider(totemsTab, "DaggesTotemSizeSlider", "Size", y, 20, 60, "totemIconSize", DEFAULTS.totemIconSize, function() ResizeAllIcons(); UpdateTotemBar() end)
    y = y - 45
    MakeSlider(totemsTab, "DaggesTotemPadSlider", "Spacing", y, 0, 15, "totemIconPad", DEFAULTS.totemIconPad, function() ResizeAllIcons(); UpdateTotemBar() end)

    -- ════════════════════════════════════════════════════════════════
    -- TAB 4: COOLDOWNS (Essential & Utility)
    -- ════════════════════════════════════════════════════════════════
    y = -10
    MakeHeader(cdsTab, "-- Essential Cooldowns --", y)
    y = y - 25
    MakeCheck(cdsTab, "DaggesShowEssentialCheck", "Show Essential", y, 20, "showEssential", true, RefreshBuffs)
    
    y = y - 35
    MakeSlider(cdsTab, "DaggesEssentialSlider", "Max Icons", y, 1, 20, "essentialCount", 10, RefreshBuffs)
    y = y - 45
    MakeSlider(cdsTab, "DaggesEssentialSizeSlider", "Size", y, 20, 60, "essentialIconSize", DEFAULTS.essentialIconSize, function() ResizeAllIcons(); RefreshBuffs() end)
    y = y - 45
    MakeSlider(cdsTab, "DaggesEssentialPadSlider", "Spacing", y, 0, 15, "essentialIconPad", DEFAULTS.essentialIconPad, function() ResizeAllIcons(); RefreshBuffs() end)
    
    y = y - 55
    MakeHeader(cdsTab, "-- Utility Cooldowns --", y)
    y = y - 25
    MakeCheck(cdsTab, "DaggesShowUtilityCheck", "Show Utility", y, 20, "showUtility", true, RefreshBuffs)
    
    y = y - 35
    MakeSlider(cdsTab, "DaggesUtilitySlider", "Max Icons", y, 1, 20, "utilityCount", 10, RefreshBuffs)
    y = y - 45
    MakeSlider(cdsTab, "DaggesUtilitySizeSlider", "Size", y, 20, 60, "utilityIconSize", DEFAULTS.utilityIconSize, function() ResizeAllIcons(); RefreshBuffs() end)
    y = y - 45
    MakeSlider(cdsTab, "DaggesUtilityPadSlider", "Spacing", y, 0, 15, "utilityIconPad", DEFAULTS.utilityIconPad, function() ResizeAllIcons(); RefreshBuffs() end)

    -- Default Tab
    ShowTab(1)

    configFrame = f
    tinsert(UISpecialFrames, "DaggesConfigFrame")
    
    f:HookScript("OnShow", function()
        if secondaryFrame.centerLine then secondaryFrame.centerLine:Show() end
        UpdateFrameStyles(); UpdateTotemBar(); RefreshBuffs()
    end)
    f:HookScript("OnHide", function()
        if secondaryFrame.centerLine then secondaryFrame.centerLine:Hide() end
        UpdateFrameStyles(true); UpdateTotemBar(true); RefreshBuffs(true)
    end)
    
    f:Hide()
end


-- ── Profile Management (Defined late for dependencies) ───────────────


SetProfile = function(name)
    if not name or name == "" then return end
    if not DaggesAddonDB.profiles[name] then
        DaggesAddonDB.profiles[name] = CopyTable(DEFAULTS)
    end
    
    local charKey = GetCharKey()
    DaggesAddonDB.charProfiles[charKey] = name
    
    local db = GetCurrentProfile()
    UpdateFrameStyles()
    ResizeAllIcons()
    RefreshBuffs()
    UpdateTotemBar()
    
    local function ApplyPos(f, dbP, dbRP, dbX, dbY)
        if f then
            f:ClearAllPoints()
            f:SetPoint(dbP or "CENTER", UIParent, dbRP or "CENTER", dbX or 0, dbY or 0)
        end
    end

    ApplyPos(frame, db.point, db.relPoint, db.x, db.y)
    ApplyPos(_G["DaggesTotemFrame"], db.totemPoint, db.totemRelPoint, db.totemX, db.totemY)
    ApplyPos(secondaryFrame, db.secondaryPoint, db.secondaryRelPoint, db.secondaryX, db.secondaryY)
    ApplyPos(essentialFrame, db.essentialPoint, db.essentialRelPoint, db.essentialX, db.essentialY)
    ApplyPos(utilityFrame, db.utilityPoint, db.utilityRelPoint, db.utilityX, db.utilityY)

    if DaggesConfigFrame and DaggesConfigFrame:IsShown() then
        DaggesConfigFrame:Hide(); DaggesConfigFrame:Show()
    end
end

CopyFromProfile = function(sourceName)
    if not sourceName or sourceName == "" then return end
    local source = DaggesAddonDB.profiles[sourceName]
    if not source then return end
    
    local charKey = GetCharKey()
    local currentProfileName = DaggesAddonDB.charProfiles[charKey] or "Default"
    
    -- Overwrite current profile settings with source's settings
    -- We can't just overwrite the table reference because it's shared
    -- or because we might lose the reference. Overwriting the structure is safest.
    DaggesAddonDB.profiles[currentProfileName] = CopyTable(source)
    
    -- Refresh UI to reflect the new settings
    SetProfile(currentProfileName)
end

CopyProfile = function(name)
    if not name or name == "" then return end
    local current = GetCurrentProfile()
    DaggesAddonDB.profiles[name] = CopyTable(current)
    SetProfile(name)
end

DeleteProfile = function(name)
    if not name or name == "Default" then return end
    
    -- If any character uses this profile, switch them to Default
    for ck, pn in pairs(DaggesAddonDB.charProfiles or {}) do
        if pn == name then
            DaggesAddonDB.charProfiles[ck] = "Default"
        end
    end
    
    DaggesAddonDB.profiles[name] = nil
    
    -- Refresh UI if we just deleted the profile we were on
    local charKey = GetCharKey()
    if not DaggesAddonDB.profiles[DaggesAddonDB.charProfiles[charKey]] then
        SetProfile("Default")
    end

    if DaggesConfigFrame and DaggesConfigFrame:IsShown() then
        DaggesConfigFrame:Hide()
        DaggesConfigFrame:Show()
    end
end

-- ── Slash Commands ───────────────────────────────────────────────────
SLASH_DAGGE1 = "/dagge"
SlashCmdList["DAGGE"] = function(msg)
    local cmd, arg = strsplit(" ", msg, 2)
    cmd = (cmd or ""):lower():trim()

    if cmd == "config" or cmd == "" then
        CreateConfigFrame()
        if configFrame:IsShown() then
            configFrame:Hide()
        else
            configFrame:Show()
            -- Sync UI elements to DB
            local db = GetCurrentProfile()
            DaggesBuffSlider:SetValue(db.buffCount or DEFAULTS.buffCount)
            DaggesTotemSlider:SetValue(db.totemCount or 4)
            DaggesLockCheck:SetChecked(db.locked)
            DaggesShowBuffsCheck:SetChecked(db.showBuffs ~= false)
            DaggesShowTotemsCheck:SetChecked(db.showTotems ~= false)
            DaggesHideBGCheck:SetChecked(db.hideBackground)
            DaggesShowSecondaryCheck:SetChecked(db.showSecondaryBuffs ~= false)
            DaggesSecondarySlider:SetValue(db.secondaryBuffCount or 10)
            DaggesHideCDMCheck:SetChecked(db.hideBlizzardCDM)
            
            -- Essential Sync
            DaggesShowEssentialCheck:SetChecked(db.showEssential ~= false)
            DaggesEssentialSlider:SetValue(db.essentialCount or 10)
            DaggesEssentialSizeSlider:SetValue(db.essentialIconSize or DEFAULTS.essentialIconSize)
            DaggesEssentialPadSlider:SetValue(db.essentialIconPad or DEFAULTS.essentialIconPad)
            
            -- Utility Sync
            DaggesShowUtilityCheck:SetChecked(db.showUtility ~= false)
            DaggesUtilitySlider:SetValue(db.utilityCount or 10)
            DaggesUtilitySizeSlider:SetValue(db.utilityIconSize or DEFAULTS.utilityIconSize)
            DaggesUtilityPadSlider:SetValue(db.utilityIconPad or DEFAULTS.utilityIconPad)

            UpdateFrameStyles()
            RefreshBuffs()
        end
    
    elseif cmd == "count" then
        local n = tonumber(arg)
        if n and n >= 0 and n <= 40 then
            GetCurrentProfile().buffCount = n
            RefreshBuffs()
            print("|cff8878cc[Buff Tracker]|r Now showing " .. n .. " buffs.")
        else
            print("|cff8878cc[Buff Tracker]|r Usage: /dagge count <0-40>")
        end

    elseif cmd == "lock" then
        local db = GetCurrentProfile()
        db.locked = not db.locked
        if db.locked then
            print("|cff8878cc[Buff Tracker]|r Frame |cffff6666locked|r.")
        else
            print("|cff8878cc[Buff Tracker]|r Frame |cff66ff66unlocked|r.")
        end

    elseif cmd == "reset" then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        local db = GetCurrentProfile()
        db.point    = "CENTER"
        db.relPoint = "CENTER"
        db.x        = 0
        db.y        = 0
        
        totemFrame:ClearAllPoints()
        totemFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
        db.totemPoint    = "CENTER"
        db.totemRelPoint = "CENTER"
        db.totemX        = 0
        db.totemY        = -100
        
        print("|cff8878cc[Buff Tracker]|r Position reset to center.")


    elseif cmd == "reset" then
        print("|cff8878cc[Dagge's]|r Resetting frame positions to center.")
        local db = GetCurrentProfile()
        local frames = {
            {f=frame, x=0, y=0, pk="point", rpk="relPoint", xk="x", yk="y"},
            {f=secondaryFrame, x=0, y=-150, pk="secondaryPoint", rpk="secondaryRelPoint", xk="secondaryX", yk="secondaryY"},
            {f=essentialFrame, x=0, y=50, pk="essentialPoint", rpk="essentialRelPoint", xk="essentialX", yk="essentialY"},
            {f=utilityFrame, x=0, y=100, pk="utilityPoint", rpk="utilityRelPoint", xk="utilityX", yk="utilityY"},
            {f=totemFrame, x=0, y=-100, pk="totemPoint", rpk="totemRelPoint", xk="totemX", yk="totemY"},
        }
        for _, cfg in ipairs(frames) do
            cfg.f:ClearAllPoints()
            cfg.f:SetPoint("CENTER", UIParent, "CENTER", cfg.x, cfg.y)
            db[cfg.pk] = "CENTER"
            db[cfg.rpk] = "CENTER"
            db[cfg.xk] = cfg.x
            db[cfg.yk] = cfg.y
        end
        RefreshBuffs()
        UpdateTotemBar()

    elseif cmd == "stacks" then
        -- Stacks diagnostic: probe all available data on active CDM children
        print("|cff8878cc[Stacks Debug]|r Probing active CDM children for stack data...")
        
        -- Check what APIs exist
        print("  API Check:")
        print("    C_UnitAuras.GetPlayerAuraBySpellID: " .. (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and "EXISTS" or "MISSING"))
        print("    C_UnitAuras.GetAuraDataByAuraInstanceID: " .. (C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID and "EXISTS" or "MISSING"))
        print("    C_UnitAuras.GetBuffDataByIndex: " .. (C_UnitAuras and C_UnitAuras.GetBuffDataByIndex and "EXISTS" or "MISSING"))
        
        local viewers = {
            { name = "Buffs", v = _G.BuffIconCooldownViewer },
            { name = "Essential", v = _G.EssentialCooldownViewer },
            { name = "Utility", v = _G.UtilityCooldownViewer },
        }
        for _, vInfo in ipairs(viewers) do
            if not vInfo.v then
                print("  " .. vInfo.name .. ": viewer not found")
            else
                local items = vInfo.v.GetItemFrames and vInfo.v:GetItemFrames() or { vInfo.v:GetChildren() }
                for i, child in ipairs(items) do
                    if child.Icon and i <= 5 then
                        local shown = child:IsShown() and "YES" or "NO"
                        print(string.format("  %s [%d] (shown=%s):", vInfo.name, i, shown))
                        
                        -- cooldownInfo dump
                        pcall(function()
                            if child.cooldownInfo then
                                local ci = child.cooldownInfo
                                local sid = ci.overrideSpellID or ci.spellID
                                print(string.format("    cooldownInfo.spellID=%s", tostring(sid)))
                                print(string.format("    cooldownInfo.applications=%s", tostring(ci.applications)))
                                print(string.format("    cooldownInfo.charges=%s maxCharges=%s", tostring(ci.charges), tostring(ci.maxCharges)))
                            else
                                print("    cooldownInfo: NIL")
                            end
                        end)
                        
                        -- Try GetPlayerAuraBySpellID
                        pcall(function()
                            local sid = child.cooldownInfo and (child.cooldownInfo.overrideSpellID or child.cooldownInfo.spellID)
                            if sid and C_UnitAuras.GetPlayerAuraBySpellID then
                                local aura = C_UnitAuras.GetPlayerAuraBySpellID(sid)
                                if aura then
                                    print(string.format("    GetPlayerAuraBySpellID: apps=%s name=%s", tostring(aura.applications), tostring(aura.name)))
                                else
                                    print("    GetPlayerAuraBySpellID: returned nil")
                                end
                            end
                        end)
                        
                        -- Texture matching test (our actual stack detection approach)
                        pcall(function()
                            local tex = child.Icon and child.Icon:GetTexture()
                            print(string.format("    Icon texture: %s", tostring(tex)))
                            local result = FindStacksByTexture(tex)
                            print(string.format("    FindStacksByTexture: %s", tostring(result)))
                        end)
                        
                        -- Applications sub-frame
                        pcall(function()
                            if child.Applications then
                                local regions = { child.Applications:GetRegions() }
                                for _, reg in ipairs(regions) do
                                    if reg:IsObjectType("FontString") then
                                        print(string.format("    Apps FontString: text=%s shown=%s", tostring(reg:GetText()), tostring(reg:IsShown())))
                                    end
                                end
                            end
                        end)
                    end
                end
            end
        end
        
        -- Standalone dump: All player buffs
        print("|cff8878cc[Stacks Debug]|r Player Buffs (up to 15):")
        pcall(function()
            for i = 1, 15 do
                local aura = C_UnitAuras.GetBuffDataByIndex("player", i)
                if not aura then break end
                print(string.format("  [%d] icon=%s apps=%s name=%s spellId=%s",
                    i, tostring(aura.icon), tostring(aura.applications), tostring(aura.name), tostring(aura.spellId)))
            end
        end)
        print("|cff8878cc[Stacks Debug]|r Done.")

    elseif cmd == "debug" then
        -- CDM Debug
        print("|cff8878cc[Debug]|r CDM Viewers:")
        print("  Buffs: " .. (SafeBool(_G.BuffIconCooldownViewer) and "OK" or "NIL"))
        print("  Essential: " .. (SafeBool(_G.EssentialCooldownViewer) and "OK" or "NIL"))
        print("  Utility: " .. (SafeBool(_G.UtilityCooldownViewer) and "OK" or "NIL"))
        
        print("|cff8878cc[Debug]|r Tracker Frames:")
        local function DebugF(f, n)
            if not f then print("  " .. n .. ": MISSING") return end
            local p, _, rp, px, py = f:GetPoint()
            print(string.format("  %s: Shown=%s Pos=%s,%s Point=%s", n, f:IsShown() and "YES" or "NO", px or 0, py or 0, p or "nil"))
        end
        DebugF(frame, "Primary")
        DebugF(secondaryFrame, "Secondary")
        DebugF(essentialFrame, "Essential")
        DebugF(utilityFrame, "Utility")
        DebugF(totemFrame, "Totems")

        -- Essential/Utility viewer debug
        local function DebugViewer(viewerName, viewer)
            if not viewer then
                print("|cff8878cc[Debug]|r " .. viewerName .. ": NOT FOUND")
                return
            end
            local items = viewer.GetItemFrames and viewer:GetItemFrames() or { viewer:GetChildren() }
            print("|cff8878cc[Debug]|r " .. viewerName .. ": " .. #items .. " children")
            for i, child in ipairs(items) do
                if i > 3 then print("  ..."); break end
                local shown = child:IsShown() and "YES" or "NO"
                local tex = (child.Icon and child.Icon:GetTexture()) or "none"
                print(string.format("  [%d] Shown=%s Tex=%s", i, shown, tostring(tex)))
            end
        end
        DebugViewer("EssentialCooldownViewer", _G.EssentialCooldownViewer)
        DebugViewer("UtilityCooldownViewer", _G.UtilityCooldownViewer)
        DebugViewer("BuffIconCooldownViewer", _G.BuffIconCooldownViewer)

        -- Totem Debug
        print("|cff8878cc[Debug]|r Totem Bar Slots:")
        for i=1,4 do
             local haveTotem, name, start, duration, icon = GetTotemInfo(i)
             local hasTotem = SafeBool(haveTotem) and "YES" or "NO"
             local hasIcon = SafeBool(icon) and "YES" or "NO"
             local hasDur = SafeBool(duration) and "YES" or "NO"
             print(string.format("  Slot %d: Active=%s Icon=%s Dur=%s Name=%s", i, hasTotem, hasIcon, hasDur, name or "nil"))
        end
        
        local viewer = _G.BuffIconCooldownViewer
        if not viewer then
            print("|cff8878cc[Debug]|r BuffIconCooldownViewer not found!")
            return
        end
        local itemFrames = viewer.GetItemFrames and viewer:GetItemFrames() or { viewer:GetChildren() }
        print("|cff8878cc[Debug]|r Found " .. #itemFrames .. " item frames")
        for i, child in ipairs(itemFrames) do
            if i > 5 then break end
            local shown = child:IsShown() and "YES" or "NO"
            local sid = "nil"
            pcall(function() sid = tostring(child.auraSpellID) end)
            local iid = "nil"
            pcall(function() iid = tostring(child.auraInstanceID) end)
            local unit = "nil"
            pcall(function() unit = tostring(child.auraDataUnit) end)
            print(string.format("  [%d] shown=%s spellID=%s instID=%s unit=%s", i, shown, sid, iid, unit))

            if child.isVirtualTotem then
                print(string.format("    [Virtual Totem] Slot=%s Name=%s", child.slot, GetConcentrationTotemName() or "?"))
            end

            -- Try each aura API
            if child:IsShown() then
                local a1, a2, a3 = "FAIL", "FAIL", "FAIL"
                pcall(function()
                    local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(child.auraDataUnit or "player", child.auraInstanceID)
                    a1 = aura and "OK" or "nil"
                    if aura then
                        local apps = tostring(aura.applications or "1")
                        a1 = a1 .. " apps=" .. apps
                    end
                end)
                
                -- Check for Count FontStrings
                local fsInfo = ""
                local function CheckFS(f, prefix)
                    if not f then return end
                    local regions = { f:GetRegions() }
                    for _, r in ipairs(regions) do
                        if r:IsObjectType("FontString") then
                            local txt = r:GetText() or "nil"
                            local shown = r:IsShown() and "YES" or "NO"
                            fsInfo = fsInfo .. string.format("\n      %sFS: txt='%s' shown=%s", prefix, txt, shown)
                        end
                    end
                end
                CheckFS(child, "Main")
                if child.Applications then CheckFS(child.Applications, "Apps") end
                
                print(string.format("    AuraData=%s%s", a1, fsInfo))
            end
        end

    else
        print("|cff8878cc[Dagge's Buff Tracker]|r Commands:")
        print("  /dagge          \226\128\148 toggle window")
        print("  /dagge count N  \226\128\148 show N buffs (1-40)")
        print("  /dagge lock     \226\128\148 lock/unlock dragging")
        print("  /dagge reset    \226\128\148 reset position to center")
        print("  /dagge debug    \226\128\148 diagnostic info")
    end
end
