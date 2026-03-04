----------------------------------------------------------------------
-- TRT: Rotation Helper – Spell Registry
-- Central registry mapping SimC spell names → WoW spell IDs + metadata.
----------------------------------------------------------------------
local _, TRT = ...
TRT.SpellRegistry = {}
TRT.Rotations     = {}

----------------------------------------------------------------------
-- Register a spell entry
-- @param simcName  string   SimC action name (e.g. "stormstrike")
-- @param data      table    { id=<spellID>, [cd], [charges], [maxStacks], [gcd] }
----------------------------------------------------------------------
function TRT:RegisterSpell(simcName, data)
    if not data or not data.id then
        TRT:Debug("RegisterSpell: missing id for " .. tostring(simcName))
        return
    end
    data.simcName = simcName
    TRT.SpellRegistry[simcName] = data
    TRT.SpellRegistry[data.id]  = data
end

----------------------------------------------------------------------
-- Look up spell by SimC name or spell ID
----------------------------------------------------------------------
function TRT:GetSpell(nameOrID)
    return TRT.SpellRegistry[nameOrID]
end

----------------------------------------------------------------------
-- Register a rotation (called by spec modules)
-- @param classToken  string  e.g. "SHAMAN"
-- @param specID      number  e.g. 263
-- @param rotation    table   { name, spells, apl }
----------------------------------------------------------------------
function TRT:RegisterRotation(classToken, specID, rotation)
    local key = classToken .. "_" .. specID
    TRT.Rotations[key] = rotation
    TRT:Debug("Registered rotation: " .. key .. " (" .. (rotation.name or "?") .. ")")
end
