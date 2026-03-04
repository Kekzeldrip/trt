#!/usr/bin/env lua
----------------------------------------------------------------------
-- TRT: Offline APL Parser Tests
-- Run with: lua Tests/test_parser.lua
-- Tests the tokenizer, expression parser, and APL parser without WoW.
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Minimal WoW API stubs for loading outside of WoW
----------------------------------------------------------------------
function strtrim(s)
    return s:match("^%s*(.-)%s*$")
end
function CreateFrame() return {
    RegisterEvent = function() end,
    SetScript = function() end,
    SetSize = function() end,
    SetPoint = function() end,
    SetMovable = function() end,
    EnableMouse = function() end,
    SetClampedToScreen = function() end,
    RegisterForDrag = function() end,
    SetBackdrop = function() end,
    SetBackdropColor = function() end,
    SetBackdropBorderColor = function() end,
    SetFrameStrata = function() end,
    CreateTexture = function() return {
        SetAllPoints = function() end,
        SetTexCoord = function() end,
        SetTexture = function() end,
        SetBlendMode = function() end,
        SetVertexColor = function() end,
    } end,
    CreateFontString = function() return {
        SetPoint = function() end,
        SetTextColor = function() end,
        SetText = function() end,
    } end,
    Show = function() end,
    Hide = function() end,
} end
DEFAULT_CHAT_FRAME = { AddMessage = function(self, msg) print(msg) end }
UIParent = {}

----------------------------------------------------------------------
-- Load the addon core stubs
----------------------------------------------------------------------
local TRT = {}
_G.TRT = TRT
TRT.SpellRegistry = {}
TRT.Rotations = {}
function TRT:Print(msg) print("[TRT] " .. tostring(msg)) end
function TRT:Debug(msg) end
function TRT:RegisterSpell(name, data)
    data.simcName = name
    TRT.SpellRegistry[name] = data
    TRT.SpellRegistry[data.id] = data
end
function TRT:RegisterRotation(cls, specID, rot)
    TRT.Rotations[cls .. "_" .. specID] = rot
end

----------------------------------------------------------------------
-- Load APL Parser
----------------------------------------------------------------------
TRT.APLParser = {}
local P = TRT.APLParser

-- Copy the parser code inline for testing (we load via dofile below)
-- We'll use dofile to load the actual parser file

-- Helper to load a Lua file as if it were a WoW addon file
local function loadAddonFile(path)
    local fn, err = loadfile(path)
    if not fn then
        error("Failed to load " .. path .. ": " .. tostring(err))
    end
    -- WoW addon files receive (addonName, addonTable) as ...
    -- We simulate this by setting the upvalues
    local env = setmetatable({}, {__index = _G})
    -- The file uses: local _, TRT = ...
    -- We need to make ... return ("TRT", TRT)
    -- Use a wrapper function
    local wrapper = load(
        "local addonName, addon = ...\n" ..
        "local _, TRT = addonName, addon\n" ..
        -- Read the file content and embed it
        "-- loaded via wrapper",
        path, "t", env
    )
    -- Actually, let's just directly execute with the right environment
    -- Simpler approach: modify the global TRT and use dofile-style
end

----------------------------------------------------------------------
-- Inline the tokenizer and parser for testing
----------------------------------------------------------------------

local TOKEN = {
    NUMBER="NUMBER", IDENT="IDENT", DOT="DOT", AND="AND", OR="OR",
    NOT="NOT", EQ="EQ", NEQ="NEQ", LT="LT", LE="LE", GT="GT", GE="GE",
    PLUS="PLUS", MINUS="MINUS", MUL="MUL", DIV="DIV", MOD="MOD",
    LPAREN="LPAREN", RPAREN="RPAREN", EOF="EOF",
}

local function Tokenize(expr)
    local tokens = {}
    local i = 1
    local len = #expr
    while i <= len do
        local c = expr:sub(i, i)
        if c == " " or c == "\t" then
            i = i + 1
        elseif c == "&" then
            table.insert(tokens, {type = TOKEN.AND}); i = i + 1
        elseif c == "|" then
            table.insert(tokens, {type = TOKEN.OR}); i = i + 1
        elseif c == "!" then
            if expr:sub(i+1,i+1) == "=" then
                table.insert(tokens, {type = TOKEN.NEQ}); i = i + 2
            else
                table.insert(tokens, {type = TOKEN.NOT}); i = i + 1
            end
        elseif c == "=" then
            table.insert(tokens, {type = TOKEN.EQ}); i = i + 1
        elseif c == "<" then
            if expr:sub(i+1,i+1) == "=" then
                table.insert(tokens, {type = TOKEN.LE}); i = i + 2
            else
                table.insert(tokens, {type = TOKEN.LT}); i = i + 1
            end
        elseif c == ">" then
            if expr:sub(i+1,i+1) == "=" then
                table.insert(tokens, {type = TOKEN.GE}); i = i + 2
            else
                table.insert(tokens, {type = TOKEN.GT}); i = i + 1
            end
        elseif c == "+" then
            table.insert(tokens, {type = TOKEN.PLUS}); i = i + 1
        elseif c == "-" then
            table.insert(tokens, {type = TOKEN.MINUS}); i = i + 1
        elseif c == "*" then
            table.insert(tokens, {type = TOKEN.MUL}); i = i + 1
        elseif c == "/" then
            table.insert(tokens, {type = TOKEN.DIV}); i = i + 1
        elseif c == "%" then
            if expr:sub(i+1,i+1) == "%" then
                table.insert(tokens, {type = TOKEN.MOD}); i = i + 2
            else
                table.insert(tokens, {type = TOKEN.MOD}); i = i + 1
            end
        elseif c == "(" then
            table.insert(tokens, {type = TOKEN.LPAREN}); i = i + 1
        elseif c == ")" then
            table.insert(tokens, {type = TOKEN.RPAREN}); i = i + 1
        elseif c == "." then
            table.insert(tokens, {type = TOKEN.DOT}); i = i + 1
        elseif c:match("[0-9]") then
            local j = i
            while j <= len and expr:sub(j,j):match("[0-9.]") do j = j + 1 end
            table.insert(tokens, {type = TOKEN.NUMBER, value = tonumber(expr:sub(i, j-1))})
            i = j
        elseif c:match("[a-zA-Z_]") then
            local j = i
            while j <= len and expr:sub(j,j):match("[a-zA-Z0-9_]") do j = j + 1 end
            table.insert(tokens, {type = TOKEN.IDENT, value = expr:sub(i, j-1)})
            i = j
        else
            i = i + 1
        end
    end
    table.insert(tokens, {type = TOKEN.EOF})
    return tokens
end

local function CreateParser(tokens)
    local pos = 1
    local function peek() return tokens[pos] end
    local function advance() local t = tokens[pos]; pos = pos + 1; return t end
    local function match(ttype) if peek().type == ttype then return advance() end return nil end

    local parseExpr

    local function parsePrimary()
        local t = peek()
        if t.type == TOKEN.NUMBER then
            advance(); return {op="number", value=t.value}
        elseif t.type == TOKEN.LPAREN then
            advance(); local node = parseExpr(); match(TOKEN.RPAREN); return node
        elseif t.type == TOKEN.IDENT then
            local parts = {advance().value}
            while match(TOKEN.DOT) do
                local id = match(TOKEN.IDENT)
                if id then table.insert(parts, id.value)
                else
                    local num = match(TOKEN.NUMBER)
                    if num then table.insert(parts, tostring(num.value)) end
                end
            end
            return {op="ref", parts=parts}
        elseif t.type == TOKEN.MINUS then
            advance(); return {op="neg", child=parsePrimary()}
        else
            advance(); return {op="number", value=0}
        end
    end

    local function parseUnary()
        if match(TOKEN.NOT) then return {op="not", child=parseUnary()} end
        return parsePrimary()
    end

    local function parseMul()
        local node = parseUnary()
        while true do
            local t = peek()
            if t.type == TOKEN.MUL then advance(); node = {op="*", left=node, right=parseUnary()}
            elseif t.type == TOKEN.DIV then advance(); node = {op="/", left=node, right=parseUnary()}
            elseif t.type == TOKEN.MOD then advance(); node = {op="%%", left=node, right=parseUnary()}
            else break end
        end
        return node
    end

    local function parseAdd()
        local node = parseMul()
        while true do
            local t = peek()
            if t.type == TOKEN.PLUS then advance(); node = {op="+", left=node, right=parseMul()}
            elseif t.type == TOKEN.MINUS then advance(); node = {op="-", left=node, right=parseMul()}
            else break end
        end
        return node
    end

    local function parseCmp()
        local node = parseAdd()
        local t = peek()
        if t.type == TOKEN.EQ then advance(); node = {op="==", left=node, right=parseAdd()}
        elseif t.type == TOKEN.NEQ then advance(); node = {op="!=", left=node, right=parseAdd()}
        elseif t.type == TOKEN.LT then advance(); node = {op="<", left=node, right=parseAdd()}
        elseif t.type == TOKEN.LE then advance(); node = {op="<=", left=node, right=parseAdd()}
        elseif t.type == TOKEN.GT then advance(); node = {op=">", left=node, right=parseAdd()}
        elseif t.type == TOKEN.GE then advance(); node = {op=">=", left=node, right=parseAdd()}
        end
        return node
    end

    local function parseAnd()
        local node = parseCmp()
        while match(TOKEN.AND) do node = {op="and", left=node, right=parseCmp()} end
        return node
    end

    local function parseOr()
        local node = parseAnd()
        while match(TOKEN.OR) do node = {op="or", left=node, right=parseAnd()} end
        return node
    end

    parseExpr = parseOr
    return {parse = parseExpr}
end

local function ParseExpression(expr)
    if not expr or expr == "" then return nil end
    local tokens = Tokenize(expr)
    local parser = CreateParser(tokens)
    return parser.parse()
end

local function ParseActionParams(line)
    local result = {}
    local parts = {}
    for part in line:gmatch("[^,]+") do table.insert(parts, part) end
    if #parts == 0 then return nil end
    result.action = strtrim(parts[1])
    for i = 2, #parts do
        local k, v = parts[i]:match("^([^=]+)=(.+)$")
        if k then result[strtrim(k)] = strtrim(v) end
    end
    return result
end

local function ParseAPL(text)
    local lists = {}
    for line in text:gmatch("[^\r\n]+") do
        line = strtrim(line)
        if line ~= "" and line:sub(1,1) ~= "#" then
            local listName, actionStr = line:match("^actions%.([%w_]+)%+?=/?(.+)$")
            if not listName then
                actionStr = line:match("^actions%+?=/?(.+)$")
                listName = "default"
            end
            if actionStr and listName then
                local entry = ParseActionParams(actionStr)
                if entry then
                    entry.listName = listName
                    if entry["if"] then
                        entry.conditionAST = ParseExpression(entry["if"])
                    end
                    if entry.action == "variable" and entry.value then
                        entry.valueAST = ParseExpression(entry.value)
                    end
                    if not lists[listName] then lists[listName] = {} end
                    table.insert(lists[listName], entry)
                end
            end
        end
    end
    return lists
end

----------------------------------------------------------------------
-- Simple assertion helper
----------------------------------------------------------------------
local tests_run = 0
local tests_passed = 0
local tests_failed = 0

local function assert_eq(got, expected, msg)
    tests_run = tests_run + 1
    if got == expected then
        tests_passed = tests_passed + 1
    else
        tests_failed = tests_failed + 1
        print(string.format("  FAIL: %s — expected %s, got %s",
            msg or "?", tostring(expected), tostring(got)))
    end
end

local function assert_true(val, msg)
    assert_eq(not not val, true, msg)
end

local function assert_not_nil(val, msg)
    tests_run = tests_run + 1
    if val ~= nil then
        tests_passed = tests_passed + 1
    else
        tests_failed = tests_failed + 1
        print(string.format("  FAIL: %s — expected non-nil", msg or "?"))
    end
end

----------------------------------------------------------------------
-- Test: Tokenizer
----------------------------------------------------------------------
print("=== Tokenizer Tests ===")

do
    local tokens = Tokenize("buff.doom_winds.up")
    assert_eq(tokens[1].type, "IDENT", "tok1 is IDENT")
    assert_eq(tokens[1].value, "buff", "tok1 value")
    assert_eq(tokens[2].type, "DOT", "tok2 is DOT")
    assert_eq(tokens[3].type, "IDENT", "tok3 is IDENT")
    assert_eq(tokens[3].value, "doom_winds", "tok3 value")
    assert_eq(tokens[4].type, "DOT", "tok4 is DOT")
    assert_eq(tokens[5].type, "IDENT", "tok5 is IDENT")
    assert_eq(tokens[5].value, "up", "tok5 value")
    assert_eq(tokens[6].type, "EOF", "tok6 is EOF")
end

do
    local tokens = Tokenize("active_enemies>=2&!talent.surging_totem.enabled")
    assert_eq(tokens[1].type, "IDENT", "compound tok1")
    assert_eq(tokens[1].value, "active_enemies", "compound tok1 val")
    assert_eq(tokens[2].type, "GE", "compound tok2 GE")
    assert_eq(tokens[3].type, "NUMBER", "compound tok3 NUM")
    assert_eq(tokens[3].value, 2, "compound tok3 val")
    assert_eq(tokens[4].type, "AND", "compound tok4 AND")
    assert_eq(tokens[5].type, "NOT", "compound tok5 NOT")
end

do
    local tokens = Tokenize("fight_remains%%120<=20")
    assert_eq(tokens[1].type, "IDENT", "mod tok1")
    assert_eq(tokens[2].type, "MOD", "mod tok2")
    assert_eq(tokens[3].type, "NUMBER", "mod tok3")
    assert_eq(tokens[3].value, 120, "mod tok3 val")
    assert_eq(tokens[4].type, "LE", "mod tok4")
    assert_eq(tokens[5].type, "NUMBER", "mod tok5")
    assert_eq(tokens[5].value, 20, "mod tok5 val")
end

----------------------------------------------------------------------
-- Test: Expression Parser
----------------------------------------------------------------------
print("\n=== Expression Parser Tests ===")

do
    local ast = ParseExpression("buff.doom_winds.up")
    assert_not_nil(ast, "simple ref parsed")
    assert_eq(ast.op, "ref", "simple ref op")
    assert_eq(#ast.parts, 3, "simple ref 3 parts")
    assert_eq(ast.parts[1], "buff", "ref part1")
    assert_eq(ast.parts[2], "doom_winds", "ref part2")
    assert_eq(ast.parts[3], "up", "ref part3")
end

do
    local ast = ParseExpression("active_enemies=1")
    assert_not_nil(ast, "comparison parsed")
    assert_eq(ast.op, "==", "comparison op")
    assert_eq(ast.left.op, "ref", "cmp left is ref")
    assert_eq(ast.right.op, "number", "cmp right is number")
    assert_eq(ast.right.value, 1, "cmp right value")
end

do
    local ast = ParseExpression("!talent.surging_totem.enabled")
    assert_not_nil(ast, "NOT parsed")
    assert_eq(ast.op, "not", "NOT op")
    assert_eq(ast.child.op, "ref", "NOT child is ref")
end

do
    local ast = ParseExpression("active_enemies=1&!talent.surging_totem.enabled")
    assert_not_nil(ast, "AND parsed")
    assert_eq(ast.op, "and", "AND op")
    assert_eq(ast.left.op, "==", "AND left is cmp")
    assert_eq(ast.right.op, "not", "AND right is NOT")
end

do
    local ast = ParseExpression("buff.maelstrom_weapon.stack>=10&(!buff.ascendance.up|!buff.doom_winds.up)")
    assert_not_nil(ast, "complex AND+OR parsed")
    assert_eq(ast.op, "and", "complex top is AND")
    assert_eq(ast.left.op, ">=", "complex left is GE")
    assert_eq(ast.right.op, "or", "complex right paren is OR")
end

do
    local ast = ParseExpression("9+1*talent.surging_totem.enabled")
    assert_not_nil(ast, "arithmetic parsed")
    assert_eq(ast.op, "+", "arith top is PLUS")
    assert_eq(ast.left.value, 9, "arith left is 9")
    assert_eq(ast.right.op, "*", "arith right is MUL")
end

do
    local ast = ParseExpression("charges_fractional>=1.8")
    assert_not_nil(ast, "decimal parsed")
    assert_eq(ast.op, ">=", "decimal cmp")
    assert_eq(ast.right.value, 1.8, "decimal value")
end

do
    local ast = ParseExpression("fight_remains%%120<=20")
    assert_not_nil(ast, "modulo parsed")
    assert_eq(ast.op, "<=", "mod cmp op")
    assert_eq(ast.left.op, "%%", "mod left is MOD")
end

----------------------------------------------------------------------
-- Test: APL Parser
----------------------------------------------------------------------
print("\n=== APL Parser Tests ===")

do
    local apl_text = [[
actions.precombat=windfury_weapon
actions.precombat+=/flametongue_weapon
actions=auto_attack
actions+=/call_action_list,name=single_sb,if=active_enemies=1&!talent.surging_totem.enabled
actions+=/call_action_list,name=aoe,if=active_enemies>1
actions.single_sb=stormstrike,if=buff.doom_winds.up
actions.single_sb+=/lava_lash
actions.aoe=crash_lightning
actions.aoe+=/chain_lightning,if=buff.maelstrom_weapon.stack>=5
]]

    local lists = ParseAPL(apl_text)
    assert_not_nil(lists, "APL parsed")
    assert_not_nil(lists["precombat"], "precombat list exists")
    assert_eq(#lists["precombat"], 2, "precombat has 2 entries")
    assert_eq(lists["precombat"][1].action, "windfury_weapon", "precombat action 1")

    assert_not_nil(lists["default"], "default list exists")
    assert_eq(lists["default"][1].action, "auto_attack", "default action 1")
    assert_eq(lists["default"][2].action, "call_action_list", "default action 2 is call")
    assert_eq(lists["default"][2].name, "single_sb", "call target is single_sb")
    assert_not_nil(lists["default"][2].conditionAST, "call has condition AST")

    assert_not_nil(lists["single_sb"], "single_sb list exists")
    assert_eq(#lists["single_sb"], 2, "single_sb has 2 entries")
    assert_eq(lists["single_sb"][1].action, "stormstrike", "single_sb action 1")
    assert_not_nil(lists["single_sb"][1].conditionAST, "stormstrike has condition")
    assert_eq(lists["single_sb"][2].action, "lava_lash", "single_sb action 2")

    assert_not_nil(lists["aoe"], "aoe list exists")
    assert_eq(#lists["aoe"], 2, "aoe has 2 entries")
end

-- Test with full Enhancement Shaman APL
do
    local full_apl = [[
actions.precombat=windfury_weapon
actions.precombat+=/flametongue_weapon
actions.precombat+=/lightning_shield
actions=variable,name=flame_shock_saturated,value=((active_dot.flame_shock=active_enemies)|(active_dot.flame_shock=6))
actions+=/auto_attack
actions+=/call_action_list,name=single_sb,if=active_enemies=1&!talent.surging_totem.enabled
actions+=/call_action_list,name=single_totemic,if=active_enemies=1&talent.surging_totem.enabled
actions+=/call_action_list,name=aoe,if=active_enemies>1
actions.aoe=voltaic_blaze,if=talent.surging_totem.enabled&dot.flame_shock.remains=0
actions.aoe+=/surging_totem
actions.aoe+=/crash_lightning
actions.single_sb=stormstrike
actions.single_sb+=/lava_lash
actions.single_totemic=lava_lash,if=buff.whirling_fire.up|buff.hot_hand.up
actions.single_totemic+=/stormstrike
actions.buffs=potion
]]

    local lists = ParseAPL(full_apl)
    assert_not_nil(lists["precombat"], "full: precombat")
    assert_eq(#lists["precombat"], 3, "full: precombat count")
    assert_not_nil(lists["default"], "full: default")
    assert_not_nil(lists["aoe"], "full: aoe")
    assert_not_nil(lists["single_sb"], "full: single_sb")
    assert_not_nil(lists["single_totemic"], "full: single_totemic")
    assert_not_nil(lists["buffs"], "full: buffs")

    -- Check variable parsing
    local varEntry = lists["default"][1]
    assert_eq(varEntry.action, "variable", "full: first default is variable")
    assert_eq(varEntry.name, "flame_shock_saturated", "full: variable name")
    assert_not_nil(varEntry.valueAST, "full: variable has value AST")
end

----------------------------------------------------------------------
-- Test: Condition Evaluator (with mock state)
----------------------------------------------------------------------
print("\n=== Condition Evaluator Tests ===")

do
    -- Simple number evaluation
    local ast = ParseExpression("10")
    assert_not_nil(ast, "number AST")

    -- Simple arithmetic
    local ast2 = ParseExpression("9+1")
    assert_eq(ast2.op, "+", "arithmetic op")

    -- NOT of a number
    local ast3 = ParseExpression("!0")
    assert_eq(ast3.op, "not", "NOT op")
    assert_eq(ast3.child.value, 0, "NOT child is 0")

    -- Complex nested
    local ast4 = ParseExpression("(1+2)*3")
    assert_eq(ast4.op, "*", "nested mul")
    assert_eq(ast4.left.op, "+", "nested inner plus")
end

----------------------------------------------------------------------
-- Summary
----------------------------------------------------------------------
print(string.format("\n=== Results: %d/%d passed, %d failed ===",
    tests_passed, tests_run, tests_failed))

if tests_failed > 0 then
    os.exit(1)
else
    print("All tests passed!")
    os.exit(0)
end
