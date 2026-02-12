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

-- ── UI Styling Helpers ──────────────────────────────────────────────
local BACKDROP_CONFIG = {
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile     = true, tileSize = 16, edgeSize = 16,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function UpdateFrameStyles(forceClosed)
    local configOpen = not forceClosed and _G["DaggesConfigFrame"] and _G["DaggesConfigFrame"]:IsShown()
    local db = GetCurrentProfile()
    local hide = db.hideBackground and not configOpen -- Force show if config is open
    
    local targetFrames = { 
        _G["DaggesBuffTrackerFrame"], 
        _G["DaggesTotemFrame"],
        _G["DaggesSecondaryTrackerFrame"]
    }
    
    for _, f in ipairs(targetFrames) do
        if f then
            if hide then
                f:SetBackdrop(nil)
                if f.accent then f.accent:Hide() end
                if f.title then f.title:Hide() end
            else
                f:SetBackdrop(BACKDROP_CONFIG)
                f:SetBackdropColor(0, 0, 0, 0.8)
                if f.accent then f.accent:Show() end
                if f.title then f.title:Show() end
            end
        end
    end
end

local ICON_SIZE   = 38
local ICON_PAD    = 3
local HEADER_H    = 14
local FRAME_PAD   = 4
local UPDATE_HZ   = 0.25

-- ── Colors ───────────────────────────────────────────────────────────
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

-- ── Main Frame ───────────────────────────────────────────────────────
local frame = CreateFrame("Frame", "DaggesBuffTrackerFrame", UIParent, "BackdropTemplate")
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
local secondaryFrame = CreateFrame("Frame", "DaggesSecondaryTrackerFrame", UIParent, "BackdropTemplate")
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



local function SafeBool(val)
    if val == nil then return false end
    -- If we can read it, return it. If it errors (Secret), assume true (it exists).
    local ok, res = pcall(function() return not not val end)
    if not ok then return true end
    return res
end

local function SafeNE(a, b)
    local ok, res = pcall(function() return a ~= b end)
    if not ok then return true end
    return res
end

-- ── Totem Logic Refactored: Separate Bar ───────────────────────────────
local totemFrame = CreateFrame("Frame", "DaggesTotemFrame", UIParent, "BackdropTemplate")
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




-- ── Refresh: read from BuffIconCooldownViewer ────────────────────────
local function RefreshBuffs(forceClosed)
    -- Visibility toggle
    local db = GetCurrentProfile()
    local configOpen = not forceClosed and _G["DaggesConfigFrame"] and _G["DaggesConfigFrame"]:IsShown()
    if not db.showBuffs and not db.showSecondaryBuffs then
        frame:Hide()
        secondaryFrame:Hide()
        return
    end

    local viewer = _G.BuffIconCooldownViewer
    local trackedIDs = {} -- Store what we track in the primary list
    if not viewer then return end

    local maxBuffs = db.buffCount or DEFAULTS.buffCount
    local now = GetTime()
    local idx = 0

    -- Get the item frames from the Blizzard CooldownViewer
    local itemFrames
    if viewer.GetItemFrames then
        itemFrames = viewer:GetItemFrames()
    end

    -- Fallback: get direct children
    if not itemFrames or #itemFrames == 0 then
        itemFrames = { viewer:GetChildren() }
    end

    -- Show ALL tracked buffs — split between primary and secondary
    local primaryIdx = 0
    local secondaryIdx = 0
    local maxPrimary = db.buffCount or DEFAULTS.buffCount
    local maxSecondary = db.secondaryBuffCount or 10

    for i, child in ipairs(itemFrames) do
        if child.Icon then
            local isActive = child:IsShown()
            local texFile = child.Icon:GetTexture()

            -- For hidden children, try to get the icon via cooldownInfo
            if not texFile and child.cooldownInfo then
                pcall(function()
                    local sid = child.cooldownInfo.overrideSpellID or child.cooldownInfo.spellID
                    if sid then
                        local info = C_Spell.GetSpellInfo(sid)
                        if info then texFile = info.iconID end
                    end
                end)
            end

            if texFile then
                local isPrimary = (primaryIdx < maxPrimary)
                
                -- Centering/Filtering for Secondary: only show active ones
                if not isPrimary and not isActive then
                    -- Skip inactive buffs for the secondary group
                else
                    local btn = nil
                    if isPrimary then
                        primaryIdx = primaryIdx + 1
                        btn = GetIcon(primaryIdx)
                    else
                        secondaryIdx = secondaryIdx + 1
                        btn = GetSecondaryIcon(secondaryIdx)
                    end

                    if btn then
                        btn.sourceFrame = child
                        btn.icon:SetTexture(texFile)

                        if isActive then
                            btn.icon:SetDesaturated(false)
                            btn.icon:SetAlpha(1.0)
                        else
                            btn.icon:SetDesaturated(true)
                            btn.icon:SetAlpha(0.45)
                        end

                        -- ── Stacks Logic ──
                        btn.count:Hide()
                        if isActive then
                            -- Method 1: Mirror the Blizzard frame's count text directly
                            -- This is safest for 12.0 Secret Values and combat updates.
                            local function FindCount(f)
                                if not f then return nil end
                                if f.Count then return f.Count end
                                local regions = { f:GetRegions() }
                                for _, reg in ipairs(regions) do
                                    if reg:IsObjectType("FontString") then
                                        local n = reg:GetName()
                                        if n and n:find("Count") then return reg end
                                        -- Sometimes it's just a FontString with no name but it's the only one
                                        if not n and #regions == 1 then return reg end
                                    end
                                end
                                return nil
                            end

                            local sourceCount = FindCount(child)
                            if not sourceCount and child.Applications then
                                sourceCount = FindCount(child.Applications)
                            end

                            local hasUIMirror = false
                            if sourceCount then
                                local txt = sourceCount:GetText()
                                -- Blizzard frames might show " " or other placeholders for 1
                                local isVisible = sourceCount:IsShown()
                                
                                -- Use SafeNE to avoid secret string comparison errors
                                if SafeNE(txt, nil) and SafeNE(txt, "") and SafeNE(txt, "1") and isVisible then
                                    pcall(function()
                                        btn.count:SetText(txt)
                                        btn.count:Show()
                                        hasUIMirror = true
                                    end)
                                end
                            end

                            -- Method 2: Fallback to Aura Data
                            if not hasUIMirror then
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
                                -- USE SafeGT to avoid "Secret Value" comparison errors
                                if aura and aura.applications and SafeGT(aura.applications, 1) then
                                    btn.count:SetText(aura.applications)
                                    btn.count:Show()
                                end
                            end
                        end

                        -- ── Cooldown Logic ──
                        -- Try to set cooldown from cached values (set by our SetCooldown hook)
                        -- This works for buffs gained in combat because Blizzard calls
                        -- SetCooldown with real numbers, and our hook captures them.
                        local cdCopied = false
                        if isActive then
                            -- Method 1: Use cached values from our SetCooldown hook
                            -- Values may be Secret — don't compare, just pass to SetCooldown
                            -- The C widget API handles Secret Values natively.
                            pcall(function()
                                btn.cooldown:SetCooldown(child._daggesCDStart, child._daggesCDDuration)
                                cdCopied = true
                            end)

                            -- Method 2: Try reading from source Cooldown frame directly
                            if not cdCopied then
                                pcall(function()
                                    local srcCD = child.Cooldown
                                    if not srcCD then
                                        local kids = { child:GetChildren() }
                                        for _, kid in ipairs(kids) do
                                            if kid.GetCooldownTimes then srcCD = kid; break end
                                        end
                                    end
                                    if srcCD and srcCD.GetCooldownTimes then
                                        local startMs, durMs = srcCD:GetCooldownTimes()
                                        if startMs and durMs and SafeGT(startMs, 0) and SafeGT(durMs, 0) then
                                            pcall(function()
                                                btn.cooldown:SetCooldown(startMs / 1000, durMs / 1000)
                                                cdCopied = true
                                            end)
                                        end
                                    end
                                end)
                            end

                            -- Method 3: Fallback to aura data (works out of combat)
                            if not cdCopied then
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
                                if aura then
                                    pcall(function()
                                        if aura.duration > 0 then
                                            btn.cooldown:SetCooldown(
                                                aura.expirationTime - aura.duration,
                                                aura.duration
                                            )
                                            cdCopied = true
                                        end
                                    end)
                                end
                            end
                        end
                        -- Only clear cooldown for inactive buffs.
                        -- For active buffs, leave existing cooldown running.
                        if not cdCopied and not isActive then
                            btn.cooldown:SetCooldown(0, 0)
                        end

                        btn:Show()
                        btn.isPrimary = isPrimary
                        btn.displayIdx = isPrimary and primaryIdx or secondaryIdx

                    end
                end
            end
        end
    end

    -- Hide unused primary icons
    for j = primaryIdx + 1, #icons do
        icons[j]:Hide()
    end
    -- Hide unused secondary icons
    for j = secondaryIdx + 1, #secondaryIcons do
        secondaryIcons[j]:Hide()
    end


    -- ── Sample Preview Icons (config open) ──────────────────────────
    local configOpen = _G["DaggesConfigFrame"] and _G["DaggesConfigFrame"]:IsShown()
    if configOpen then
        -- Fill remaining primary slots with samples
        local maxPrimarySample = db.buffCount or DEFAULTS.buffCount
        for j = primaryIdx + 1, maxPrimarySample do
            local btn = GetIcon(j)
            btn.sourceFrame = nil
            btn.icon:SetTexture(SAMPLE_ICONS[((j - 1) % #SAMPLE_ICONS) + 1])
            btn.icon:SetDesaturated(true)
            btn.icon:SetAlpha(0.5)
            btn.cooldown:SetCooldown(0, 0)
            btn.count:SetText("")
            btn.count:Hide()
            btn:Show()
        end
        if maxPrimarySample > primaryIdx then primaryIdx = maxPrimarySample end

        -- Fill remaining secondary slots with samples
        local maxSecondarySample = db.secondaryBuffCount or DEFAULTS.secondaryBuffCount
        for j = secondaryIdx + 1, maxSecondarySample do
            local btn = GetSecondaryIcon(j)
            btn.sourceFrame = nil
            btn.icon:SetTexture(SAMPLE_ICONS[((j + 4) % #SAMPLE_ICONS) + 1])
            btn.icon:SetDesaturated(true)
            btn.icon:SetAlpha(0.5)
            btn.cooldown:SetCooldown(0, 0)
            btn.count:SetText("")
            btn.count:Hide()
            btn:Show()
        end
        if maxSecondarySample > secondaryIdx then secondaryIdx = maxSecondarySample end
    end
    
    -- Primary Frame: Left-aligned as before
    if primaryIdx > 0 or configOpen then
        local pSize = db.primaryIconSize or DEFAULTS.primaryIconSize
        local pPad  = db.primaryIconPad or DEFAULTS.primaryIconPad
        local w = FRAME_PAD * 2 + primaryIdx * (pSize + pPad) - pPad
        local h = HEADER_H + FRAME_PAD * 2 + pSize
        frame:SetSize(math.max(w, 60), h)
        frame:Show()
        
        for j = 1, primaryIdx do
            local btn = icons[j]
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
                FRAME_PAD + (j-1) * (pSize + pPad),
                -(HEADER_H + FRAME_PAD))
        end
    else
        frame:Hide()
    end

    -- Secondary Frame: Centered growth
    if (secondaryIdx > 0 or configOpen) and db.showSecondaryBuffs then
        local sSize = db.secondaryIconSize or DEFAULTS.secondaryIconSize
        local sPad  = db.secondaryIconPad or DEFAULTS.secondaryIconPad
        local w = FRAME_PAD * 2 + secondaryIdx * (sSize + sPad) - sPad
        -- If config is open but no icons, show a minimum width
        local frameW = math.max(w, 60)
        local h = HEADER_H + FRAME_PAD * 2 + sSize
        secondaryFrame:SetSize(frameW, h)
        secondaryFrame:Show()
        
        -- Calculate centered start X for secondary icons
        local totalIconW = secondaryIdx * (sSize + sPad) - sPad
        local startX = (frameW - totalIconW) / 2
        
        for j = 1, secondaryIdx do
            local btn = secondaryIcons[j]
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", secondaryFrame, "TOPLEFT",
                startX + (j-1) * (sSize + sPad),
                -(HEADER_H + FRAME_PAD))
        end
    else
        secondaryFrame:Hide()
    end
end

-- ── Hook the Blizzard CooldownViewer ─────────────────────────────────
local hooked = false

local function HookViewer()
    local viewer = _G.BuffIconCooldownViewer
    if not viewer or hooked then return end
    hooked = true

    -- Hook Layout so we refresh when Blizzard rearranges icons
    if viewer.Layout then
        hooksecurefunc(viewer, "Layout", function()
            C_Timer.After(0.05, RefreshBuffs)
        end)
    end

    -- Hook child show/hide to catch individual buff changes
    local function HookChild(child)
        if child.daggesHooked then return end
        child.daggesHooked = true
        child:HookScript("OnShow", function() C_Timer.After(0.05, RefreshBuffs) end)
        child:HookScript("OnHide", function() C_Timer.After(0.05, RefreshBuffs) end)

        -- Hook SetCooldown on the child's Cooldown frame to capture start/duration
        -- This is the key to making durations work for buffs gained IN combat,
        -- because Blizzard calls SetCooldown with real numbers internally.
        pcall(function()
            local cdFrame = child.Cooldown
            if not cdFrame then
                -- Try to find it among children
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
    end

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

    RefreshBuffs()

    -- Hide Blizzard CDM if requested
    if GetCurrentProfile().hideBlizzardCDM then
        if viewer.SetAlpha then viewer:SetAlpha(0) end
        -- Avoid Hide() as it may stop OnUpdate or visibility events
        viewer:HookScript("OnShow", function(self)
            if GetCurrentProfile().hideBlizzardCDM and self.SetAlpha then self:SetAlpha(0) end
        end)
    end
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
    f:SetSize(300, 320)
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
    title:SetPoint("TOP", 0, -16)
    title:SetText("Dagge's Buff Tracker")

    -- Close Button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -8, -8)

    -- ── Helper: Section Header ──
    local function MakeHeader(text, yOffset)
        local h = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        h:SetPoint("TOPLEFT", 24, yOffset)
        h:SetTextColor(0.9, 0.8, 0.5)
        h:SetText(text)
        return h
    end

    -- ── Helper: Checkbox ──
    local function MakeCheck(name, label, yOffset, xOffset, dbKey, defaultVal, callback)
        local cb = CreateFrame("CheckButton", name, f, "UICheckButtonTemplate")
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

    -- ── Helper: Slider ──
    local function MakeSlider(name, label, yOffset, min, max, dbKey, defaultVal, callback)
        local sl = CreateFrame("Slider", name, f, "OptionsSliderTemplate")
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

    local y = -50  -- starting Y below title

    -- ════════════════════════════════════════════════════════════════
    -- DROPDOWN / PROFILE UI
    -- ════════════════════════════════════════════════════════════════
    local profileLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    profileLabel:SetPoint("TOPLEFT", 24, y)
    profileLabel:SetText("Profile:")
    
    local ddown = CreateFrame("Frame", "DaggesProfileDropdown", f, "UIDropDownMenuTemplate")
    ddown:SetPoint("TOPLEFT", 70, y + 2)
    UIDropDownMenu_SetWidth(ddown, 120)
    
    -- Function to refresh the dropdown text
    local function UpdateDropdownText()
        local charKey = GetCharKey()
        local pName = DaggesAddonDB.charProfiles[charKey] or "Default"
        UIDropDownMenu_SetText(ddown, pName)
    end
    
    UIDropDownMenu_Initialize(ddown, function(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        local charKey = GetCharKey()
        local currentCharProfile = DaggesAddonDB.charProfiles[charKey] or "Default"
        
        -- Sort names: Default first, then alphabetical
        local names = {}
        for name in pairs(DaggesAddonDB.profiles) do
            table.insert(names, name)
        end
        table.sort(names, function(a, b)
            if a == "Default" then return true end
            if b == "Default" then return false end
            return a < b
        end)
        
        for _, name in ipairs(names) do
            info.text = name
            info.checked = (name == currentCharProfile)
            info.func = function(self)
                SetProfile(self:GetText())
                UpdateDropdownText()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UpdateDropdownText()
    
    -- Copy From Dropdown
    y = y - 30
    local copyLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    copyLabel:SetPoint("TOPLEFT", 24, y)
    copyLabel:SetText("Copy From:")
    
    local copyDown = CreateFrame("Frame", "DaggesCopyFromDropdown", f, "UIDropDownMenuTemplate")
    copyDown:SetPoint("TOPLEFT", 70, y + 2)
    UIDropDownMenu_SetWidth(copyDown, 120)
    UIDropDownMenu_SetText(copyDown, "Select Source...")
    
    UIDropDownMenu_Initialize(copyDown, function(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        local names = {}
        for name in pairs(DaggesAddonDB.profiles) do
            table.insert(names, name)
        end
        table.sort(names, function(a, b)
            if a == "Default" then return true end
            if b == "Default" then return false end
            return a < b
        end)
        
        for _, name in ipairs(names) do
            info.text = name
            info.checked = false
            info.func = function(self)
                local targetName = self:GetText()
                StaticPopupDialogs["DAGGES_COPY_CONFIRM"] = {
                    text = "Are you sure you want to overwrite your current profile with settings from '" .. targetName .. "'?",
                    button1 = "Yes",
                    button2 = "No",
                    OnAccept = function()
                        CopyFromProfile(targetName)
                        print("|cff8878cc[Buff Tracker]|r Settings copied from " .. targetName)
                    end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                }
                StaticPopup_Show("DAGGES_COPY_CONFIRM")
                UIDropDownMenu_SetText(copyDown, "Select Source...")
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    
    -- New Profile
    local newBtn = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    newBtn:SetSize(20, 20)
    newBtn:SetPoint("LEFT", ddown, "RIGHT", -10, 2)
    newBtn:SetText("+")
    newBtn:SetScript("OnClick", function()
        StaticPopupDialogs["DAGGES_NEW_PROFILE"] = {
            text = "Enter new profile name:",
            button1 = "Create",
            button2 = "Cancel",
            hasEditBox = true,
            OnAccept = function(self)
                local text = self.EditBox:GetText()
                CopyProfile(text)
                UpdateDropdownText()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("DAGGES_NEW_PROFILE")
    end)
    
    -- Delete Profile
    local delBtn = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    delBtn:SetSize(20, 20)
    delBtn:SetPoint("LEFT", newBtn, "RIGHT", 5, 0)
    delBtn:SetText("-")
    delBtn:SetScript("OnClick", function()
        local charKey = GetCharKey()
        local pName = DaggesAddonDB.charProfiles[charKey] or "Default"
        if pName == "Default" then
            print("Cannot delete Default profile.")
            return
        end
        DeleteProfile(pName)
        UpdateDropdownText()
    end)

    y = y - 40

    -- ════════════════════════════════════════════════════════════════
    -- GENERAL
    -- ════════════════════════════════════════════════════════════════
    MakeHeader("-- General --", y)
    y = y - 20
    MakeCheck("DaggesLockCheck", "Lock Frames", y, 20, "locked", false, function()
        if GetCurrentProfile().locked then
            print("|cff8878cc[Buff Tracker]|r Frames Locked.")
        else
            print("|cff8878cc[Buff Tracker]|r Frames Unlocked.")
        end
    end)
    MakeCheck("DaggesHideBGCheck", "Hide Background", y, 160, "hideBackground", false, UpdateFrameStyles)
    y = y - 30
    MakeCheck("DaggesHideCDMCheck", "Hide Blizzard CDM", y, 20, "hideBlizzardCDM", true, function()
        if viewer then
            local db = GetCurrentProfile()
            if db.hideBlizzardCDM then
                if viewer.SetAlpha then viewer:SetAlpha(0) end
            else
                if viewer.SetAlpha then viewer:SetAlpha(1) end
            end
        end
    end)
    y = y - 50

    -- ════════════════════════════════════════════════════════════════
    -- PRIMARY BUFFS
    -- ════════════════════════════════════════════════════════════════
    MakeHeader("-- Primary Buffs --", y)
    y = y - 20
    MakeCheck("DaggesShowBuffsCheck", "Show", y, 20, "showBuffs", true, RefreshBuffs)
    y = y - 30
    MakeSlider("DaggesBuffSlider", "Count", y, 0, 20, "buffCount", DEFAULTS.buffCount, RefreshBuffs)
    y = y - 50
    MakeSlider("DaggesPrimarySizeSlider", "Size", y, 20, 60, "primaryIconSize", DEFAULTS.primaryIconSize, function() ResizeAllIcons() RefreshBuffs() end)
    y = y - 50
    MakeSlider("DaggesPrimaryPadSlider", "Spacing", y, 0, 15, "primaryIconPad", DEFAULTS.primaryIconPad, function() ResizeAllIcons() RefreshBuffs() end)
    y = y - 60

    -- ════════════════════════════════════════════════════════════════
    -- SECONDARY BUFFS
    -- ════════════════════════════════════════════════════════════════
    MakeHeader("-- Secondary Buffs --", y)
    y = y - 20
    MakeCheck("DaggesShowSecondaryCheck", "Show", y, 20, "showSecondaryBuffs", true, RefreshBuffs)
    y = y - 30
    MakeSlider("DaggesSecondarySlider", "Count", y, 1, 20, "secondaryBuffCount", DEFAULTS.secondaryBuffCount, RefreshBuffs)
    y = y - 50
    MakeSlider("DaggesSecondarySizeSlider", "Size", y, 20, 60, "secondaryIconSize", DEFAULTS.secondaryIconSize, function() ResizeAllIcons() RefreshBuffs() end)
    y = y - 50
    MakeSlider("DaggesSecondaryPadSlider", "Spacing", y, 0, 15, "secondaryIconPad", DEFAULTS.secondaryIconPad, function() ResizeAllIcons() RefreshBuffs() end)
    y = y - 60

    -- ════════════════════════════════════════════════════════════════
    -- TOTEMS
    -- ════════════════════════════════════════════════════════════════
    MakeHeader("-- Totems --", y)
    y = y - 20
    MakeCheck("DaggesShowTotemsCheck", "Show", y, 20, "showTotems", true, UpdateTotemBar)
    y = y - 30
    MakeSlider("DaggesTotemSlider", "Count", y, 1, 4, "totemCount", 4, UpdateTotemBar)
    y = y - 50
    MakeSlider("DaggesTotemSizeSlider", "Size", y, 20, 60, "totemIconSize", DEFAULTS.totemIconSize, function() ResizeAllIcons() UpdateTotemBar() end)
    y = y - 50
    MakeSlider("DaggesTotemPadSlider", "Spacing", y, 0, 15, "totemIconPad", DEFAULTS.totemIconPad, function() ResizeAllIcons() UpdateTotemBar() end)
    y = y - 45

    -- Reset Button
    local resetBtn = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    resetBtn:SetPoint("TOPLEFT", 20, y)
    resetBtn:SetSize(120, 25)
    resetBtn:SetText("Reset Positions")
    resetBtn:SetScript("OnClick", function()
        SlashCmdList["DAGGE"]("reset")
    end)
    y = y - 35

    f:SetSize(300, math.abs(y) + 20)
    configFrame = f
    tinsert(UISpecialFrames, "DaggesConfigFrame")
    
    f:HookScript("OnShow", function()
        if secondaryFrame.centerLine then secondaryFrame.centerLine:Show() end
        UpdateFrameStyles() UpdateTotemBar() RefreshBuffs()
    end)
    f:HookScript("OnHide", function()
        if secondaryFrame.centerLine then secondaryFrame.centerLine:Hide() end
        -- Force update styles with 'forceClosed' flag to avoid race conditions
        UpdateFrameStyles(true) 
        UpdateTotemBar(true) 
        RefreshBuffs(true)
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
    
    frame:ClearAllPoints()
    frame:SetPoint(db.point or "CENTER", UIParent, db.relPoint or "CENTER", db.x or 0, db.y or 0)
    
    local tf = _G["DaggesTotemFrame"]
    if tf then
        tf:ClearAllPoints()
        tf:SetPoint(db.totemPoint or "CENTER", UIParent, db.totemRelPoint or "CENTER", db.totemX or 0, db.totemY or -100)
    end
    
    local sf = _G["DaggesSecondaryTrackerFrame"]
    if sf then
        sf:ClearAllPoints()
        sf:SetPoint(db.secondaryPoint or "CENTER", UIParent, db.secondaryRelPoint or "CENTER", db.secondaryX or 0, db.secondaryY or -150)
    end

    if DaggesConfigFrame and DaggesConfigFrame:IsShown() then
        DaggesConfigFrame:Hide()
        DaggesConfigFrame:Show()
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


    elseif cmd == "debug" then
        -- Totem Debug
        print("|cff8878cc[Debug]|r Totem Bar Slots:")
        for i=1,4 do
             local _, name, start, duration, icon = GetTotemInfo(i)
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
