----------------------------------------------------------------------
-- TRT: Rotation Helper – UI Overlay
-- Displays recommended abilities as icon buttons on screen.
----------------------------------------------------------------------
local _, TRT = ...
TRT.UI = {}
local UI = TRT.UI

local ICON_SIZE     = 64
local ICON_SPACING  = 8
local QUEUE_ICONS   = 2      -- secondary (smaller) icons
local SMALL_SCALE   = 0.6

----------------------------------------------------------------------
-- Create the main frame and icons
----------------------------------------------------------------------
local mainFrame

local function CreateUI()
    if mainFrame then return end

    mainFrame = CreateFrame("Frame", "TRTFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(ICON_SIZE + (QUEUE_ICONS * (ICON_SIZE * SMALL_SCALE + ICON_SPACING)) + 20,
                      ICON_SIZE + 16)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(self)
        if not TRT.db or not TRT.db.locked then
            self:StartMoving()
        end
    end)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    -- Semi-transparent background
    mainFrame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 16, edgeSize = 12,
        insets   = {left = 2, right = 2, top = 2, bottom = 2},
    })
    mainFrame:SetBackdropColor(0, 0, 0, 0.5)
    mainFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    mainFrame:SetFrameStrata("HIGH")

    -- Primary icon (big)
    mainFrame.primary = CreateFrame("Frame", "TRTPrimary", mainFrame)
    mainFrame.primary:SetSize(ICON_SIZE, ICON_SIZE)
    mainFrame.primary:SetPoint("LEFT", mainFrame, "LEFT", 8, 0)

    mainFrame.primary.icon = mainFrame.primary:CreateTexture(nil, "ARTWORK")
    mainFrame.primary.icon:SetAllPoints()
    mainFrame.primary.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim edges

    mainFrame.primary.border = mainFrame.primary:CreateTexture(nil, "OVERLAY")
    mainFrame.primary.border:SetAllPoints()
    mainFrame.primary.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    mainFrame.primary.border:SetBlendMode("ADD")
    mainFrame.primary.border:SetVertexColor(1, 1, 0, 0.6)

    mainFrame.primary.text = mainFrame.primary:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mainFrame.primary.text:SetPoint("BOTTOM", mainFrame.primary, "BOTTOM", 0, -2)
    mainFrame.primary.text:SetTextColor(1, 1, 1, 0.9)

    -- Cooldown swipe on primary icon
    mainFrame.primary.cooldown = CreateFrame("Cooldown", "TRTPrimaryCD", mainFrame.primary, "CooldownFrameTemplate")
    mainFrame.primary.cooldown:SetAllPoints()

    -- Queue icons (smaller)
    mainFrame.queue = {}
    for i = 1, QUEUE_ICONS do
        local f = CreateFrame("Frame", "TRTQueue" .. i, mainFrame)
        local size = ICON_SIZE * SMALL_SCALE
        f:SetSize(size, size)
        local xOff = ICON_SIZE + ICON_SPACING + (i - 1) * (size + ICON_SPACING) + 8
        f:SetPoint("LEFT", mainFrame, "LEFT", xOff, 0)

        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetAllPoints()
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.text:SetPoint("BOTTOM", f, "BOTTOM", 0, -2)
        f.text:SetTextColor(0.8, 0.8, 0.8, 0.8)

        f:SetAlpha(0.65)
        mainFrame.queue[i] = f
    end

    mainFrame:Hide()  -- starts hidden until enabled
    UI.frame = mainFrame
end

----------------------------------------------------------------------
-- Show / Hide
----------------------------------------------------------------------
function UI:Show()
    CreateUI()
    mainFrame:Show()
end

function UI:Hide()
    if mainFrame then mainFrame:Hide() end
end

function UI:SetMovable(movable)
    if mainFrame then
        mainFrame:SetMovable(movable)
    end
end

----------------------------------------------------------------------
-- Update icon display from engine recommendations
----------------------------------------------------------------------
function UI:UpdateIcons(recommended)
    if not mainFrame or not mainFrame:IsShown() then return end

    -- Primary icon
    if recommended and recommended[1] then
        local rec = recommended[1]
        mainFrame.primary.icon:SetTexture(rec.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        mainFrame.primary.icon:Show()
        mainFrame.primary.text:SetText("")

        -- Show cooldown swipe if spell is on GCD
        local start, dur = TRT.State:CooldownInfo(rec.spellID)
        if dur and dur > 0 and dur <= 1.5 then
            mainFrame.primary.cooldown:SetCooldown(start, dur)
        else
            mainFrame.primary.cooldown:Clear()
        end
    else
        mainFrame.primary.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        mainFrame.primary.cooldown:Clear()
        mainFrame.primary.text:SetText("")
    end

    -- Queue icons
    for i, frame in ipairs(mainFrame.queue) do
        local rec = recommended and recommended[i + 1]
        if rec then
            frame.icon:SetTexture(rec.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            frame:SetAlpha(0.65)
            frame:Show()
        else
            frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            frame:SetAlpha(0.2)
            frame:Show()
        end
    end
end
