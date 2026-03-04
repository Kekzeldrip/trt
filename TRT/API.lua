----------------------------------------------------------------------
-- TRT: Rotation Helper – Game‑State API
-- Thin abstraction over the WoW API so the engine can query state.
----------------------------------------------------------------------
local _, TRT = ...
TRT.State = {}
local S = TRT.State

----------------------------------------------------------------------
-- Caches (refreshed each engine tick)
----------------------------------------------------------------------
S.cache = {}

function S:Reset()
    wipe(self.cache)
end

----------------------------------------------------------------------
-- Unit helpers
----------------------------------------------------------------------
function S:Exists(unit)     return UnitExists(unit) end
function S:IsDead(unit)     return UnitIsDead(unit) end
function S:Health(unit)     return UnitHealth(unit) end
function S:HealthMax(unit)  return UnitHealthMax(unit) end
function S:HealthPct(unit)
    local max = self:HealthMax(unit)
    if max == 0 then return 100 end
    return 100 * self:Health(unit) / max
end
function S:Power(unit, ptype)   return UnitPower(unit, ptype) end
function S:PowerMax(unit, ptype) return UnitPowerMax(unit, ptype) end

----------------------------------------------------------------------
-- Buff / Debuff
----------------------------------------------------------------------
local function FindAura(unit, spellID, filter)
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
        if not aura then break end
        if aura.spellId == spellID then
            return aura
        end
    end
    return nil
end

function S:Buff(spellID, unit)
    unit = unit or "player"
    local key = "buff_" .. spellID .. "_" .. unit
    if self.cache[key] == nil then
        self.cache[key] = FindAura(unit, spellID, "HELPFUL") or false
    end
    return self.cache[key]
end

function S:Debuff(spellID, unit)
    unit = unit or "target"
    local key = "debuff_" .. spellID .. "_" .. unit
    if self.cache[key] == nil then
        self.cache[key] = FindAura(unit, spellID, "HARMFUL") or false
    end
    return self.cache[key]
end

function S:BuffUp(spellID, unit)
    return self:Buff(spellID, unit) and true or false
end

function S:BuffDown(spellID, unit)
    return not self:BuffUp(spellID, unit)
end

function S:BuffRemains(spellID, unit)
    local aura = self:Buff(spellID, unit)
    if aura and aura.expirationTime then
        local rem = aura.expirationTime - GetTime()
        return rem > 0 and rem or 0
    end
    return 0
end

function S:BuffStacks(spellID, unit)
    local aura = self:Buff(spellID, unit)
    return aura and aura.applications or 0
end

function S:BuffMaxStacks(spellID)
    -- Not directly available in API; rotations can override this in spell data
    local spell = TRT.SpellRegistry and TRT.SpellRegistry[spellID]
    return spell and spell.maxStacks or 1
end

function S:DebuffUp(spellID, unit)
    return self:Debuff(spellID, unit) and true or false
end

function S:DebuffDown(spellID, unit)
    return not self:DebuffUp(spellID, unit)
end

function S:DebuffRemains(spellID, unit)
    local aura = self:Debuff(spellID, unit)
    if aura and aura.expirationTime then
        local rem = aura.expirationTime - GetTime()
        return rem > 0 and rem or 0
    end
    return 0
end

function S:DebuffStacks(spellID, unit)
    local aura = self:Debuff(spellID, unit)
    return aura and aura.applications or 0
end

----------------------------------------------------------------------
-- Dot helpers (alias for debuff on target applied by player)
----------------------------------------------------------------------
function S:DotRemains(spellID, unit)
    unit = unit or "target"
    return self:DebuffRemains(spellID, unit)
end

function S:ActiveDot(spellID)
    -- Count targets with this debuff; uses nameplates as proxy
    local key = "activedot_" .. spellID
    if self.cache[key] then return self.cache[key] end
    local count = 0
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and self:DebuffUp(spellID, unit) then
            count = count + 1
        end
    end
    self.cache[key] = count
    return count
end

----------------------------------------------------------------------
-- Cooldown
----------------------------------------------------------------------
function S:CooldownInfo(spellID)
    local key = "cd_" .. spellID
    if self.cache[key] then return unpack(self.cache[key]) end
    local info = C_Spell.GetSpellCooldown(spellID)
    local start, dur
    if info then
        start = info.startTime or 0
        dur   = info.duration or 0
    else
        start, dur = 0, 0
    end
    self.cache[key] = {start, dur}
    return start, dur
end

function S:CooldownRemains(spellID)
    local start, dur = self:CooldownInfo(spellID)
    if dur == 0 then return 0 end
    local rem = start + dur - GetTime()
    return rem > 0 and rem or 0
end

function S:CooldownReady(spellID)
    return self:CooldownRemains(spellID) == 0
end

function S:CooldownCharges(spellID)
    local info = C_Spell.GetSpellCharges(spellID)
    if info then
        return info.currentCharges, info.maxCharges, info.cooldownStartTime, info.cooldownDuration
    end
    return 0, 0, 0, 0
end

function S:ChargesFractional(spellID)
    local cur, max, start, dur = self:CooldownCharges(spellID)
    if max == 0 then
        return self:CooldownReady(spellID) and 1 or 0
    end
    if cur == max then return max end
    if dur == 0 then return cur end
    local partial = (GetTime() - start) / dur
    return cur + partial
end

----------------------------------------------------------------------
-- GCD
----------------------------------------------------------------------
function S:GCD()
    local start, dur = GetSpellCooldown(61304) -- global GCD spell
    if dur and dur > 0 then
        return dur
    end
    -- Fallback: hasted 1.5 s
    local haste = UnitSpellHaste("player") or 0
    return max(0.75, 1.5 / (1 + haste / 100))
end

function S:GCDRemains()
    local start, dur = GetSpellCooldown(61304)
    if dur and dur > 0 then
        local rem = start + dur - GetTime()
        return rem > 0 and rem or 0
    end
    return 0
end

----------------------------------------------------------------------
-- Talent
----------------------------------------------------------------------
function S:HasTalent(spellID)
    local key = "talent_" .. spellID
    if self.cache[key] ~= nil then return self.cache[key] end

    local result = false
    -- Check via IsPlayerSpell (works for talented abilities)
    if IsPlayerSpell(spellID) then
        result = true
    else
        -- Check via IsSpellKnown
        if IsSpellKnown(spellID) then
            result = true
        end
    end
    self.cache[key] = result
    return result
end

----------------------------------------------------------------------
-- Spell usability / in range
----------------------------------------------------------------------
function S:IsUsable(spellID)
    local usable, noMana = C_Spell.IsSpellUsable(spellID)
    return usable
end

function S:InRange(spellID, unit)
    unit = unit or "target"
    local inRange = C_Spell.IsSpellInRange(spellID, unit)
    if inRange == nil then return true end  -- melee assumed
    return inRange
end

----------------------------------------------------------------------
-- Combat / target info
----------------------------------------------------------------------
function S:InCombat()
    return TRT.inCombat or UnitAffectingCombat("player")
end

function S:ActiveEnemies()
    local key = "active_enemies"
    if self.cache[key] then return self.cache[key] end
    local count = 0
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitCanAttack("player", unit)
           and not UnitIsDead(unit)
           and IsItemInRange(37727, unit) then  -- Ruby Acorn (40 yd range check item)
            count = count + 1
        end
    end
    count = max(count, UnitExists("target") and 1 or 0)
    self.cache[key] = count
    return count
end

function S:TargetTimeToDie()
    -- Rough estimate; proper implementation needs health tracking
    return 300
end

function S:FightRemains()
    return self:TargetTimeToDie()
end

----------------------------------------------------------------------
-- Pet helpers
----------------------------------------------------------------------
function S:PetActive(petName)
    -- Check if a specific totem / pet is active
    if not petName then return UnitExists("pet") end
    -- Check totems
    for slot = 1, 4 do
        local _, name, start, dur = GetTotemInfo(slot)
        if name and name ~= "" then
            local lname = name:lower()
            if lname:find(petName:lower()) then
                if dur > 0 and (start + dur) > GetTime() then
                    return true
                end
            end
        end
    end
    return false
end

----------------------------------------------------------------------
-- Time helpers
----------------------------------------------------------------------
function S:Time()
    -- Time in combat
    if TRT._combatStart then
        return GetTime() - TRT._combatStart
    end
    return 0
end

-- Track combat start
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        TRT._combatStart = GetTime()
    elseif event == "PLAYER_REGEN_ENABLED" then
        TRT._combatStart = nil
    end
end)
