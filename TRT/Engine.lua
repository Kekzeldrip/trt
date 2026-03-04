----------------------------------------------------------------------
-- TRT: Rotation Helper – Rotation Engine
-- Evaluates the active APL each tick to determine recommended abilities.
----------------------------------------------------------------------
local _, TRT = ...
TRT.Engine = {}
local E = TRT.Engine

local UPDATE_INTERVAL = 0.1   -- seconds between ticks
local elapsed = 0

----------------------------------------------------------------------
-- Result cache for the current tick
----------------------------------------------------------------------
E.recommended = {}     -- list of {spellID, spellName, icon}
E.lastUpdate  = 0

----------------------------------------------------------------------
-- Evaluate a single action list and return the first matching action
----------------------------------------------------------------------
local function EvaluateList(listName, rot, depth)
    depth = depth or 0
    if depth > 10 then return nil end  -- prevent infinite recursion

    local list = rot.apl[listName]
    if not list then return nil end

    for _, entry in ipairs(list) do
        local action = entry.action

        -- Skip non-ability actions
        if action == "snapshot_stats" or action == "auto_attack"
           or action == "use_item" or action == "potion"
           or action == "blood_fury" or action == "berserking"
           or action == "fireblood" or action == "ancestral_call"
           or action == "invoke_external_buff" or action == "bloodlust" then
            goto continue
        end

        -- Handle variable assignments
        if action == "variable" then
            if entry.name and entry.valueAST then
                TRT.Conditions.vars[entry.name] = TRT.Conditions:Eval(entry.valueAST, rot)
            end
            goto continue
        end

        -- Handle call_action_list
        if action == "call_action_list" then
            local targetList = entry.name
            if targetList then
                -- Check the if-condition for the call itself
                local callCondOk = true
                if entry.conditionAST then
                    callCondOk = TRT.Conditions:Check(entry.conditionAST, rot)
                end
                if callCondOk then
                    local result = EvaluateList(targetList, rot, depth + 1)
                    if result then return result end
                end
            end
            goto continue
        end

        -- Handle run_action_list (like call, but stops further processing)
        if action == "run_action_list" then
            local targetList = entry.name
            if targetList then
                local callCondOk = true
                if entry.conditionAST then
                    callCondOk = TRT.Conditions:Check(entry.conditionAST, rot)
                end
                if callCondOk then
                    return EvaluateList(targetList, rot, depth + 1)
                end
            end
            goto continue
        end

        -- Regular ability: check condition
        local condOk = true
        if entry.conditionAST then
            condOk = TRT.Conditions:Check(entry.conditionAST, rot)
        end

        if condOk then
            -- Look up spell data
            local spellID = rot.spellMap and rot.spellMap[action]
            if spellID then
                -- Set context for charges_fractional resolution
                TRT.Conditions._currentActionCharges = TRT.State:ChargesFractional(spellID)

                -- Re-check condition with charges context if needed
                if entry.conditionAST then
                    condOk = TRT.Conditions:Check(entry.conditionAST, rot)
                end

                if condOk then
                    -- Check if spell is usable and off cooldown
                    local usable = TRT.State:IsUsable(spellID)
                    local ready  = TRT.State:CooldownReady(spellID)
                    if usable and ready then
                        local name = C_Spell.GetSpellName(spellID)
                        local icon = C_Spell.GetSpellTexture(spellID)
                        return {
                            spellID   = spellID,
                            spellName = name or action,
                            icon      = icon,
                            action    = action,
                        }
                    end
                end
            end
        end

        ::continue::
    end
    return nil
end

----------------------------------------------------------------------
-- Main engine tick: evaluate the full APL
----------------------------------------------------------------------
function E:Tick()
    local rot = TRT.activeRotation
    if not rot or not rot.apl then return end

    -- Reset per-tick state
    TRT.State:Reset()
    TRT.Conditions.vars = {}
    TRT.Conditions._currentActionCharges = 0
    wipe(self.recommended)

    -- Evaluate precombat list if not yet in combat
    if not TRT.State:InCombat() then
        -- Don't show recommendations out of combat (optional)
        return
    end

    -- Process default-list variables first
    local defaultList = rot.apl["default"]
    if defaultList then
        for _, entry in ipairs(defaultList) do
            if entry.action == "variable" and entry.name and entry.valueAST then
                TRT.Conditions.vars[entry.name] = TRT.Conditions:Eval(entry.valueAST, rot)
            end
        end
    end

    -- Find the top recommended ability
    local primary = EvaluateList("default", rot, 0)
    if primary then
        table.insert(self.recommended, primary)
    end

    -- Optionally find a second recommendation (queue depth)
    -- This is a simplified approach – skip the matched action and continue
    -- For a proper queue we'd need to simulate a state change, which is complex.
end

----------------------------------------------------------------------
-- OnUpdate driver
----------------------------------------------------------------------
local engineFrame = CreateFrame("Frame", "TRTEngineFrame", UIParent)
engineFrame:SetScript("OnUpdate", function(self, dt)
    if not TRT.enabled then return end
    elapsed = elapsed + dt
    if elapsed < UPDATE_INTERVAL then return end
    elapsed = 0

    E:Tick()

    -- Update UI
    if TRT.UI and TRT.UI.UpdateIcons then
        TRT.UI:UpdateIcons(E.recommended)
    end
end)
