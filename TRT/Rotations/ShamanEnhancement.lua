----------------------------------------------------------------------
-- TRT: Rotation Helper – Enhancement Shaman Rotation
-- SimC APL for Enhancement Shaman, parsed and registered.
-- Spec ID: 263
----------------------------------------------------------------------
local _, TRT = ...

----------------------------------------------------------------------
-- Spell IDs (Retail 11.1.x / The War Within)
----------------------------------------------------------------------
local SPELLS = {
    -- Core abilities
    stormstrike          = 17364,
    windstrike           = 115356,
    lava_lash            = 60103,
    crash_lightning       = 187874,
    chain_lightning       = 188443,
    lightning_bolt        = 188196,
    flame_shock           = 188389,
    frost_shock           = 196840,
    sundering             = 197214,

    -- Cooldowns / Talents
    feral_spirit          = 51533,
    ascendance            = 114051,
    doom_winds            = 384352,
    surging_totem         = 444995,
    primordial_storm      = 375982,
    tempest               = 454009,
    voltaic_blaze         = 470053,

    -- Weapon enchants
    windfury_weapon       = 33757,
    flametongue_weapon    = 318038,

    -- Shields
    lightning_shield      = 192106,

    -- Passive / Talent checks
    thorims_invocation    = 384444,
    storm_unleashed       = 470490,
    deeply_rooted_elements = 378270,
    surging_elements      = 453839,
    splitstream           = 453843,
    fire_nova             = 333974,
    converging_storms     = 384363,
    lashing_flames        = 334046,
    elemental_tempo       = 441385,
}

----------------------------------------------------------------------
-- Buff IDs
----------------------------------------------------------------------
local BUFFS = {
    maelstrom_weapon      = 344179,
    doom_winds            = 384352,
    ascendance            = 114051,
    crash_lightning       = 187874,
    hot_hand              = 215785,
    whirling_fire         = 453843,   -- Totemic buff
    whirling_earth        = 453844,   -- Totemic buff
    whirling_air          = 453845,   -- Totemic buff
    converging_storms     = 384363,
    primordial_storm      = 375982,
    -- Thorim's Invocation procs
    ti_chain_lightning    = 384444,   -- placeholder; same talent spell
    ti_lightning_bolt     = 384444,   -- placeholder; same talent spell
}

----------------------------------------------------------------------
-- Debuff IDs
----------------------------------------------------------------------
local DEBUFFS = {
    flame_shock           = 188389,
    lashing_flames        = 334046,
    lightning_rod          = 197209,
    chaos_brand           = 1490,
    hunters_mark          = 257284,
}

----------------------------------------------------------------------
-- Dot → debuff mapping for active_dot queries
----------------------------------------------------------------------
local DOTS = {
    flame_shock = 188389,
}

----------------------------------------------------------------------
-- Debuff values (percent modifiers used in SimC expressions)
----------------------------------------------------------------------
local DEBUFF_VALUES = {
    chaos_brand  = 0.05,   -- 5% magic damage increase
    hunters_mark = 0.05,
    lightning_rod = 0.20,
}

----------------------------------------------------------------------
-- Build spell/buff/debuff/talent maps for the condition resolver
----------------------------------------------------------------------
local spellMap  = {}
local buffMap   = {}
local debuffMap = {}
local talentMap = {}
local dotMap    = {}

for name, id in pairs(SPELLS) do
    spellMap[name] = id
end
for name, id in pairs(BUFFS) do
    buffMap[name] = id
end
for name, id in pairs(DEBUFFS) do
    debuffMap[name] = id
end
for name, id in pairs(DOTS) do
    dotMap[name] = id
end

-- Talents are abilities that may or may not be selected
talentMap = {
    surging_totem           = SPELLS.surging_totem,
    thorims_invocation      = SPELLS.thorims_invocation,
    storm_unleashed         = SPELLS.storm_unleashed,
    ascendance              = SPELLS.ascendance,
    doom_winds              = SPELLS.doom_winds,
    deeply_rooted_elements  = SPELLS.deeply_rooted_elements,
    surging_elements        = SPELLS.surging_elements,
    feral_spirit            = SPELLS.feral_spirit,
    splitstream             = SPELLS.splitstream,
    fire_nova               = SPELLS.fire_nova,
    converging_storms       = SPELLS.converging_storms,
    lashing_flames          = SPELLS.lashing_flames,
    elemental_tempo         = SPELLS.elemental_tempo,
}

----------------------------------------------------------------------
-- Full SimC APL text (from simc midnight branch)
----------------------------------------------------------------------
local APL_TEXT = [[
actions.precombat=windfury_weapon
actions.precombat+=/flametongue_weapon
actions.precombat+=/lightning_shield

actions=variable,name=target_nature_mod,value=(1+debuff.chaos_brand.up*debuff.chaos_brand.value)*(1+(debuff.hunters_mark.up*target.health.pct>=80)*debuff.hunters_mark.value)
actions+=/variable,name=expected_lb_funnel,value=action.lightning_bolt.damage*(1+debuff.lightning_rod.up*variable.target_nature_mod*(1+active_dot.flame_shock)*debuff.lightning_rod.value)
actions+=/variable,name=expected_cl_funnel,value=action.chain_lightning.damage*(1+debuff.lightning_rod.up*variable.target_nature_mod*active_enemies*debuff.lightning_rod.value)
actions+=/variable,name=flame_shock_saturated,value=((active_dot.flame_shock=active_enemies)|(active_dot.flame_shock=6))
actions+=/auto_attack
actions+=/call_action_list,name=single_sb,if=active_enemies=1&!talent.surging_totem.enabled
actions+=/call_action_list,name=single_totemic,if=active_enemies=1&talent.surging_totem.enabled
actions+=/call_action_list,name=aoe,if=active_enemies>1

actions.aoe=voltaic_blaze,if=talent.surging_totem.enabled&dot.flame_shock.remains=0
actions.aoe+=/surging_totem
actions.aoe+=/ascendance,if=ti_chain_lightning
actions.aoe+=/call_action_list,name=buffs
actions.aoe+=/sundering,if=talent.surging_elements.enabled|buff.whirling_earth.up
actions.aoe+=/lava_lash,if=buff.whirling_fire.up
actions.aoe+=/doom_winds
actions.aoe+=/crash_lightning,if=talent.thorims_invocation.enabled&buff.whirling_air.up&(buff.doom_winds.up|buff.ascendance.up)
actions.aoe+=/windstrike,if=talent.thorims_invocation.enabled&buff.whirling_air.up&(buff.ascendance.up)
actions.aoe+=/stormstrike,if=talent.thorims_invocation.enabled&buff.whirling_air.up&(buff.doom_winds.up)
actions.aoe+=/lava_lash,if=talent.splitstream.enabled&buff.hot_hand.up
actions.aoe+=/tempest,if=buff.maelstrom_weapon.stack>=10&(!buff.ascendance.up|!buff.doom_winds.up)
actions.aoe+=/primordial_storm,if=buff.maelstrom_weapon.stack>=10
actions.aoe+=/voltaic_blaze,if=talent.fire_nova.enabled
actions.aoe+=/crash_lightning
actions.aoe+=/windstrike
actions.aoe+=/stormstrike,if=buff.doom_winds.up
actions.aoe+=/chain_lightning,if=buff.maelstrom_weapon.stack>=(9+1*talent.surging_totem.enabled)
actions.aoe+=/sundering,if=talent.feral_spirit.enabled
actions.aoe+=/voltaic_blaze
actions.aoe+=/lava_lash,if=pet.searing_totem.active
actions.aoe+=/stormstrike,if=charges_fractional>=1.8|buff.converging_storms.stack=buff.converging_storms.max_stack
actions.aoe+=/sundering,if=cooldown.surging_totem.remains>25
actions.aoe+=/stormstrike,if=!talent.surging_totem.enabled
actions.aoe+=/lava_lash
actions.aoe+=/stormstrike
actions.aoe+=/chain_lightning,if=buff.maelstrom_weapon.stack>=5

actions.buffs=potion,if=(buff.ascendance.up|buff.doom_winds.up|pet.surging_totem.active|(fight_remains%%300<=30)|(!talent.ascendance.enabled&!talent.doom_winds.enabled&!talent.surging_totem.enabled))

actions.single_sb=primordial_storm,if=(buff.maelstrom_weapon.stack>=9|buff.primordial_storm.remains<=4&buff.maelstrom_weapon.stack>=5)
actions.single_sb+=/voltaic_blaze,if=dot.flame_shock.remains=0&time<5
actions.single_sb+=/lava_lash,if=!debuff.lashing_flames.up&time<5
actions.single_sb+=/call_action_list,name=buffs
actions.single_sb+=/sundering,if=talent.surging_elements.enabled|talent.feral_spirit.enabled
actions.single_sb+=/doom_winds
actions.single_sb+=/crash_lightning,if=!buff.crash_lightning.up|talent.storm_unleashed.enabled
actions.single_sb+=/voltaic_blaze,if=(buff.doom_winds.up&buff.maelstrom_weapon.stack>=10-(1+2*talent.fire_nova.enabled)&!buff.maelstrom_weapon.stack=10)&talent.thorims_invocation.enabled
actions.single_sb+=/windstrike,if=buff.maelstrom_weapon.stack>0&talent.thorims_invocation.enabled
actions.single_sb+=/ascendance
actions.single_sb+=/stormstrike,if=buff.doom_winds.up&talent.thorims_invocation.enabled
actions.single_sb+=/crash_lightning,if=buff.doom_winds.up&talent.thorims_invocation.enabled
actions.single_sb+=/tempest,if=buff.maelstrom_weapon.stack=10
actions.single_sb+=/lightning_bolt,if=buff.maelstrom_weapon.stack=10
actions.single_sb+=/stormstrike,if=charges_fractional>=1.8
actions.single_sb+=/lava_lash
actions.single_sb+=/stormstrike
actions.single_sb+=/voltaic_blaze
actions.single_sb+=/sundering
actions.single_sb+=/lightning_bolt,if=buff.maelstrom_weapon.stack>=8
actions.single_sb+=/crash_lightning
actions.single_sb+=/lightning_bolt,if=buff.maelstrom_weapon.stack>=5

actions.single_totemic=voltaic_blaze,if=dot.flame_shock.remains=0
actions.single_totemic+=/surging_totem
actions.single_totemic+=/call_action_list,name=buffs
actions.single_totemic+=/lava_lash,if=buff.whirling_fire.up|buff.hot_hand.up
actions.single_totemic+=/sundering,if=talent.surging_elements.enabled|buff.whirling_earth.up|talent.feral_spirit.enabled
actions.single_totemic+=/doom_winds
actions.single_totemic+=/crash_lightning,if=!buff.crash_lightning.up|talent.storm_unleashed.enabled
actions.single_totemic+=/primordial_storm,if=(buff.maelstrom_weapon.stack>=10|buff.primordial_storm.remains<3.5&buff.maelstrom_weapon.stack>=5)
actions.single_totemic+=/windstrike,if=talent.thorims_invocation.enabled&buff.ascendance.up
actions.single_totemic+=/ascendance,if=ti_lightning_bolt
actions.single_totemic+=/crash_lightning,if=talent.thorims_invocation.enabled&buff.doom_winds.up|buff.ascendance.up
actions.single_totemic+=/stormstrike,if=talent.thorims_invocation.enabled&buff.doom_winds.up
actions.single_totemic+=/lightning_bolt,if=talent.elemental_tempo.enabled&(buff.maelstrom_weapon.stack>=5&(cooldown.lava_lash.remains>gcd.max)&(cooldown.lava_lash.remains<=buff.maelstrom_weapon.stack*0.3)|buff.maelstrom_weapon.stack>=10)
actions.single_totemic+=/crash_lightning,if=!buff.crash_lightning.up
actions.single_totemic+=/lava_lash
actions.single_totemic+=/sundering,if=cooldown.surging_totem.remains>25
actions.single_totemic+=/stormstrike
actions.single_totemic+=/voltaic_blaze
actions.single_totemic+=/crash_lightning
actions.single_totemic+=/lightning_bolt,if=buff.maelstrom_weapon.stack>=5
]]

----------------------------------------------------------------------
-- Parse and register
----------------------------------------------------------------------
local function Init()
    local apl = TRT.APLParser:ParseAPL(APL_TEXT)

    -- Register all spells
    for name, id in pairs(SPELLS) do
        TRT:RegisterSpell(name, {
            id = id,
            maxStacks = (name == "maelstrom_weapon" and 10) or nil,
        })
    end

    -- Register the rotation
    TRT:RegisterRotation("SHAMAN", 263, {
        name        = "Enhancement Shaman (SimC)",
        class       = "SHAMAN",
        specID      = 263,
        apl         = apl,
        spellMap    = spellMap,
        buffMap     = buffMap,
        debuffMap   = debuffMap,
        talentMap   = talentMap,
        dotMap      = dotMap,
        debuffValues = DEBUFF_VALUES,
    })
end

-- Run init when file loads
Init()
