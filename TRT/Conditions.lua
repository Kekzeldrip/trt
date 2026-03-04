----------------------------------------------------------------------
-- TRT: Rotation Helper – Condition Evaluator
-- Evaluates parsed SimC AST expressions against live game state.
----------------------------------------------------------------------
local _, TRT = ...
TRT.Conditions = {}
local C = TRT.Conditions
local S -- TRT.State, assigned on first use

----------------------------------------------------------------------
-- Variables storage (SimC "variable,name=X,value=Y")
----------------------------------------------------------------------
C.vars = {}

----------------------------------------------------------------------
-- Resolve a SimC reference chain (e.g. {"buff","doom_winds","up"})
-- into a numeric value using the game state API.
----------------------------------------------------------------------
local resolvers = {}

-- buff.<name>.<property>
resolvers["buff"] = function(parts, rot)
    local name = parts[2]
    local prop = parts[3] or "up"
    local spellID = rot and rot.buffMap and rot.buffMap[name]
    if not spellID then return 0 end

    if prop == "up" then
        return S:BuffUp(spellID) and 1 or 0
    elseif prop == "down" then
        return S:BuffDown(spellID) and 1 or 0
    elseif prop == "remains" then
        return S:BuffRemains(spellID)
    elseif prop == "stack" or prop == "stacks" then
        return S:BuffStacks(spellID)
    elseif prop == "max_stack" then
        return S:BuffMaxStacks(spellID)
    elseif prop == "react" then
        return S:BuffStacks(spellID)
    end
    return 0
end

-- debuff.<name>.<property>
resolvers["debuff"] = function(parts, rot)
    local name = parts[2]
    local prop = parts[3] or "up"
    local spellID = rot and rot.debuffMap and rot.debuffMap[name]
    if not spellID then return 0 end

    if prop == "up" then
        return S:DebuffUp(spellID) and 1 or 0
    elseif prop == "down" then
        return S:DebuffDown(spellID) and 1 or 0
    elseif prop == "remains" then
        return S:DebuffRemains(spellID)
    elseif prop == "stack" or prop == "stacks" then
        return S:DebuffStacks(spellID)
    elseif prop == "value" then
        -- For things like debuff.chaos_brand.value — return a modifier %
        local spell = rot and rot.debuffValues and rot.debuffValues[name]
        return spell or 0
    end
    return 0
end

-- dot.<name>.<property>
resolvers["dot"] = function(parts, rot)
    local name = parts[2]
    local prop = parts[3] or "remains"
    local spellID = rot and rot.dotMap and rot.dotMap[name]
    if not spellID then return 0 end

    if prop == "remains" or prop == "ticking" then
        local rem = S:DotRemains(spellID)
        if prop == "ticking" then return rem > 0 and 1 or 0 end
        return rem
    elseif prop == "up" then
        return S:DotRemains(spellID) > 0 and 1 or 0
    end
    return 0
end

-- cooldown.<name>.<property>
resolvers["cooldown"] = function(parts, rot)
    local name = parts[2]
    local prop = parts[3] or "remains"
    local spellID = rot and rot.spellMap and rot.spellMap[name]
    if not spellID then return 0 end

    if prop == "remains" then
        return S:CooldownRemains(spellID)
    elseif prop == "ready" or prop == "up" then
        return S:CooldownReady(spellID) and 1 or 0
    elseif prop == "duration" then
        local _, dur = S:CooldownInfo(spellID)
        return dur or 0
    end
    return 0
end

-- talent.<name>.<property>
resolvers["talent"] = function(parts, rot)
    local name = parts[2]
    local prop = parts[3] or "enabled"
    local spellID = rot and rot.talentMap and rot.talentMap[name]
    if not spellID then return 0 end

    if prop == "enabled" then
        return S:HasTalent(spellID) and 1 or 0
    end
    return 0
end

-- action.<name>.<property>
resolvers["action"] = function(parts, rot)
    local name = parts[2]
    local prop = parts[3]
    local spellID = rot and rot.spellMap and rot.spellMap[name]
    if not spellID then return 0 end

    if prop == "cooldown" then
        local _, dur = S:CooldownInfo(spellID)
        return dur or 0
    elseif prop == "duration" then
        -- buff/effect duration; not directly available from API – use spell data
        local spell = TRT.SpellRegistry[spellID]
        return spell and spell.duration or 0
    elseif prop == "damage" then
        -- Can't easily compute; return 1 as placeholder for relative comparisons
        return 1
    end
    return 0
end

-- pet.<name>.<property>
resolvers["pet"] = function(parts, rot)
    local name = parts[2]
    local prop = parts[3] or "active"

    if prop == "active" then
        return S:PetActive(name) and 1 or 0
    end
    return 0
end

-- variable.<name>
resolvers["variable"] = function(parts)
    local name = parts[2]
    return C.vars[name] or 0
end

-- active_dot.<name>
resolvers["active_dot"] = function(parts, rot)
    local name = parts[2]
    local spellID = rot and rot.dotMap and rot.dotMap[name]
    if not spellID then return 0 end
    return S:ActiveDot(spellID)
end

-- target.<property>
resolvers["target"] = function(parts)
    local prop = parts[2]
    if prop == "health" then
        local sub = parts[3]
        if sub == "pct" then
            return S:HealthPct("target")
        end
        return S:Health("target")
    elseif prop == "time_to_die" then
        return S:TargetTimeToDie()
    end
    return 0
end

-- trinket.<slot>.<property>
resolvers["trinket"] = function(parts)
    -- Trinket evaluation is complex; simplified stub
    local slot = parts[2]
    local prop = parts[3]
    if prop == "is" then
        return 0  -- We don't track specific trinkets by name yet
    elseif prop == "has_use_buff" then
        return 0
    end
    return 0
end

----------------------------------------------------------------------
-- Resolve a reference node to a numeric value
----------------------------------------------------------------------
function C:ResolveRef(parts, rot)
    if not S then S = TRT.State end

    local first = parts[1]

    -- Check resolvers
    local resolver = resolvers[first]
    if resolver then
        return resolver(parts, rot)
    end

    -- Direct identifiers
    if first == "active_enemies" then
        return S:ActiveEnemies()
    elseif first == "fight_remains" then
        return S:FightRemains()
    elseif first == "time" then
        return S:Time()
    elseif first == "gcd" then
        local sub = parts[2]
        if sub == "max" then
            return S:GCD()
        end
        return S:GCD()
    elseif first == "charges_fractional" then
        -- This appears standalone in SimC for the current action being evaluated
        return C._currentActionCharges or 0
    elseif first == "true" then
        return 1
    elseif first == "false" then
        return 0
    end

    -- SimC special references like "ti_chain_lightning", "ti_lightning_bolt"
    -- These are shorthand for specific Thorim's Invocation conditions
    if first == "ti_chain_lightning" then
        local tiSpellID = rot and rot.buffMap and rot.buffMap["ti_chain_lightning"]
        if tiSpellID then return S:BuffUp(tiSpellID) and 1 or 0 end
        return 0
    elseif first == "ti_lightning_bolt" then
        local tiSpellID = rot and rot.buffMap and rot.buffMap["ti_lightning_bolt"]
        if tiSpellID then return S:BuffUp(tiSpellID) and 1 or 0 end
        return 0
    end

    return 0
end

----------------------------------------------------------------------
-- Evaluate an AST node → numeric value
-- SimC treats nonzero as true, 0 as false.
----------------------------------------------------------------------
function C:Eval(node, rot)
    if not S then S = TRT.State end
    if not node then return 1 end  -- nil condition = always true

    local op = node.op

    if op == "number" then
        return node.value

    elseif op == "ref" then
        return self:ResolveRef(node.parts, rot)

    elseif op == "not" then
        local v = self:Eval(node.child, rot)
        return (v == 0 or v == false) and 1 or 0

    elseif op == "neg" then
        return -self:Eval(node.child, rot)

    elseif op == "and" then
        local l = self:Eval(node.left, rot)
        if l == 0 or l == false then return 0 end
        local r = self:Eval(node.right, rot)
        return (r ~= 0 and r ~= false) and 1 or 0

    elseif op == "or" then
        local l = self:Eval(node.left, rot)
        if l ~= 0 and l ~= false then return 1 end
        local r = self:Eval(node.right, rot)
        return (r ~= 0 and r ~= false) and 1 or 0

    elseif op == "==" then
        return self:Eval(node.left, rot) == self:Eval(node.right, rot) and 1 or 0

    elseif op == "!=" then
        return self:Eval(node.left, rot) ~= self:Eval(node.right, rot) and 1 or 0

    elseif op == "<" then
        return self:Eval(node.left, rot) < self:Eval(node.right, rot) and 1 or 0

    elseif op == "<=" then
        return self:Eval(node.left, rot) <= self:Eval(node.right, rot) and 1 or 0

    elseif op == ">" then
        return self:Eval(node.left, rot) > self:Eval(node.right, rot) and 1 or 0

    elseif op == ">=" then
        return self:Eval(node.left, rot) >= self:Eval(node.right, rot) and 1 or 0

    elseif op == "+" then
        return self:Eval(node.left, rot) + self:Eval(node.right, rot)

    elseif op == "-" then
        return self:Eval(node.left, rot) - self:Eval(node.right, rot)

    elseif op == "*" then
        return self:Eval(node.left, rot) * self:Eval(node.right, rot)

    elseif op == "/" then
        local r = self:Eval(node.right, rot)
        if r == 0 then return 0 end
        return self:Eval(node.left, rot) / r

    elseif op == "%%" then
        local r = self:Eval(node.right, rot)
        if r == 0 then return 0 end
        return self:Eval(node.left, rot) % r
    end

    return 0
end

----------------------------------------------------------------------
-- Boolean helper: evaluate and return true/false
----------------------------------------------------------------------
function C:Check(node, rot)
    local v = self:Eval(node, rot)
    return v ~= 0 and v ~= false
end
