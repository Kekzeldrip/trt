----------------------------------------------------------------------
-- TRT: Rotation Helper – Core
-- Central addon object, event bus, and initialization.
----------------------------------------------------------------------
local addonName, TRT = ...
_G.TRT = TRT

TRT.version   = "0.1.0"
TRT.enabled   = false
TRT.inCombat  = false
TRT.playerClass   = nil
TRT.playerSpec    = nil
TRT.playerSpecID  = nil

-- Saved‑variables defaults
local defaults = {
    enabled       = true,
    scale         = 1.0,
    alpha         = 1.0,
    locked        = false,
    showRange     = true,
    showCooldown  = true,
    queueDepth    = 2,        -- how many upcoming abilities to show
}

----------------------------------------------------------------------
-- Event frame
----------------------------------------------------------------------
local frame = CreateFrame("Frame", "TRTEventFrame", UIParent)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("PLAYER_TALENT_UPDATE")

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
function TRT:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[TRT]|r " .. tostring(msg))
end

function TRT:Debug(msg)
    if TRTDB and TRTDB.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff888888[TRT-D]|r " .. tostring(msg))
    end
end

----------------------------------------------------------------------
-- Detect class / spec
----------------------------------------------------------------------
local function DetectSpec()
    local _, class = UnitClass("player")
    TRT.playerClass = class

    local specIndex = GetSpecialization()
    if specIndex then
        local specID, specName = GetSpecializationInfo(specIndex)
        TRT.playerSpecID  = specID
        TRT.playerSpec    = specName
    end
end

----------------------------------------------------------------------
-- Load / reload rotation for the current spec
----------------------------------------------------------------------
function TRT:LoadRotation()
    DetectSpec()
    if not TRT.playerClass or not TRT.playerSpecID then return end

    local key = TRT.playerClass .. "_" .. TRT.playerSpecID
    local rot = TRT.Rotations and TRT.Rotations[key]
    if rot then
        TRT.activeRotation = rot
        TRT:Print("Loaded rotation: " .. (rot.name or key))
    else
        TRT.activeRotation = nil
        TRT:Print("No rotation found for " .. key)
    end
end

----------------------------------------------------------------------
-- Event dispatcher
----------------------------------------------------------------------
frame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Merge saved variables with defaults
        if not TRTDB then TRTDB = {} end
        for k, v in pairs(defaults) do
            if TRTDB[k] == nil then TRTDB[k] = v end
        end
        TRT.db = TRTDB

    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        TRT:LoadRotation()
        if TRT.db.enabled then
            TRT:Enable()
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        TRT.inCombat = true

    elseif event == "PLAYER_REGEN_ENABLED" then
        TRT.inCombat = false

    elseif event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE" then
        TRT:LoadRotation()
    end
end)

----------------------------------------------------------------------
-- Enable / Disable the helper
----------------------------------------------------------------------
function TRT:Enable()
    TRT.enabled = true
    if TRT.UI then TRT.UI:Show() end
    TRT:Print("Enabled (v" .. TRT.version .. ")")
end

function TRT:Disable()
    TRT.enabled = false
    if TRT.UI then TRT.UI:Hide() end
    TRT:Print("Disabled")
end

function TRT:Toggle()
    if TRT.enabled then TRT:Disable() else TRT:Enable() end
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
SLASH_TRT1 = "/trt"
SlashCmdList["TRT"] = function(msg)
    msg = strtrim(msg):lower()
    if msg == "toggle" or msg == "" then
        TRT:Toggle()
    elseif msg == "on" or msg == "enable" then
        TRT:Enable()
    elseif msg == "off" or msg == "disable" then
        TRT:Disable()
    elseif msg == "lock" then
        TRT.db.locked = not TRT.db.locked
        TRT:Print("Frame " .. (TRT.db.locked and "locked" or "unlocked"))
        if TRT.UI then TRT.UI:SetMovable(not TRT.db.locked) end
    elseif msg == "debug" then
        TRT.db.debug = not TRT.db.debug
        TRT:Print("Debug " .. (TRT.db.debug and "ON" or "OFF"))
    elseif msg == "reset" then
        if TRT.UI and TRT.UI.frame then
            TRT.UI.frame:ClearAllPoints()
            TRT.UI.frame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
            TRT:Print("Position reset")
        end
    else
        TRT:Print("Commands: /trt [toggle|on|off|lock|debug|reset]")
    end
end
