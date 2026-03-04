----------------------------------------------------------------------
-- TRT: Rotation Helper – SimC APL Parser
-- Parses SimulationCraft action priority list text into a table of
-- action entries with parsed condition trees.
----------------------------------------------------------------------
local _, TRT = ...
TRT.APLParser = {}
local P = TRT.APLParser

----------------------------------------------------------------------
-- Tokeniser
----------------------------------------------------------------------
local TOKEN = {
    NUMBER   = "NUMBER",
    IDENT    = "IDENT",
    DOT      = "DOT",
    AND      = "AND",
    OR       = "OR",
    NOT      = "NOT",
    EQ       = "EQ",
    NEQ      = "NEQ",
    LT       = "LT",
    LE       = "LE",
    GT       = "GT",
    GE       = "GE",
    PLUS     = "PLUS",
    MINUS    = "MINUS",
    MUL      = "MUL",
    DIV      = "DIV",
    MOD      = "MOD",
    LPAREN   = "LPAREN",
    RPAREN   = "RPAREN",
    EOF      = "EOF",
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
            table.insert(tokens, {type = TOKEN.AND})
            i = i + 1
        elseif c == "|" then
            table.insert(tokens, {type = TOKEN.OR})
            i = i + 1
        elseif c == "!" then
            if expr:sub(i + 1, i + 1) == "=" then
                table.insert(tokens, {type = TOKEN.NEQ})
                i = i + 2
            else
                table.insert(tokens, {type = TOKEN.NOT})
                i = i + 1
            end
        elseif c == "=" then
            table.insert(tokens, {type = TOKEN.EQ})
            i = i + 1
        elseif c == "<" then
            if expr:sub(i + 1, i + 1) == "=" then
                table.insert(tokens, {type = TOKEN.LE})
                i = i + 2
            else
                table.insert(tokens, {type = TOKEN.LT})
                i = i + 1
            end
        elseif c == ">" then
            if expr:sub(i + 1, i + 1) == "=" then
                table.insert(tokens, {type = TOKEN.GE})
                i = i + 2
            else
                table.insert(tokens, {type = TOKEN.GT})
                i = i + 1
            end
        elseif c == "+" then
            table.insert(tokens, {type = TOKEN.PLUS})
            i = i + 1
        elseif c == "-" then
            table.insert(tokens, {type = TOKEN.MINUS})
            i = i + 1
        elseif c == "*" then
            table.insert(tokens, {type = TOKEN.MUL})
            i = i + 1
        elseif c == "/" then
            table.insert(tokens, {type = TOKEN.DIV})
            i = i + 1
        elseif c == "%" then
            -- SimC uses %% for modulo
            if expr:sub(i + 1, i + 1) == "%" then
                table.insert(tokens, {type = TOKEN.MOD})
                i = i + 2
            else
                table.insert(tokens, {type = TOKEN.MOD})
                i = i + 1
            end
        elseif c == "(" then
            table.insert(tokens, {type = TOKEN.LPAREN})
            i = i + 1
        elseif c == ")" then
            table.insert(tokens, {type = TOKEN.RPAREN})
            i = i + 1
        elseif c == "." then
            table.insert(tokens, {type = TOKEN.DOT})
            i = i + 1
        elseif c:match("[0-9]") then
            local j = i
            while j <= len and expr:sub(j, j):match("[0-9.]") do
                j = j + 1
            end
            table.insert(tokens, {type = TOKEN.NUMBER, value = tonumber(expr:sub(i, j - 1))})
            i = j
        elseif c:match("[a-zA-Z_]") then
            local j = i
            while j <= len and expr:sub(j, j):match("[a-zA-Z0-9_]") do
                j = j + 1
            end
            table.insert(tokens, {type = TOKEN.IDENT, value = expr:sub(i, j - 1)})
            i = j
        else
            -- Skip unknown characters
            i = i + 1
        end
    end
    table.insert(tokens, {type = TOKEN.EOF})
    return tokens
end

----------------------------------------------------------------------
-- Recursive‑descent expression parser
-- Produces an AST (Abstract Syntax Tree) for SimC conditions.
--
-- Grammar (simplified):
--   expr       → or_expr
--   or_expr    → and_expr ("|" and_expr)*
--   and_expr   → cmp_expr ("&" cmp_expr)*
--   cmp_expr   → add_expr (("=" | "!=" | "<" | "<=" | ">" | ">=") add_expr)?
--   add_expr   → mul_expr (("+" | "-") mul_expr)*
--   mul_expr   → unary_expr (("*" | "/" | "%%") unary_expr)*
--   unary_expr → "!" unary_expr | primary
--   primary    → NUMBER | ref_chain | "(" expr ")"
--   ref_chain  → IDENT ("." IDENT)*
----------------------------------------------------------------------
local function CreateParser(tokens)
    local pos = 1

    local function peek()  return tokens[pos] end
    local function advance()
        local t = tokens[pos]
        pos = pos + 1
        return t
    end
    local function match(ttype)
        if peek().type == ttype then return advance() end
        return nil
    end

    -- Forward declarations
    local parseExpr

    local function parsePrimary()
        local t = peek()
        if t.type == TOKEN.NUMBER then
            advance()
            return {op = "number", value = t.value}
        elseif t.type == TOKEN.LPAREN then
            advance()
            local node = parseExpr()
            match(TOKEN.RPAREN)  -- consume ")"
            return node
        elseif t.type == TOKEN.IDENT then
            -- ref chain: ident.ident.ident…
            local parts = {advance().value}
            while match(TOKEN.DOT) do
                local id = match(TOKEN.IDENT)
                if id then
                    table.insert(parts, id.value)
                else
                    -- Could be a number after dot (e.g. remains=3.5 handled by tokenizer)
                    local num = match(TOKEN.NUMBER)
                    if num then
                        table.insert(parts, tostring(num.value))
                    end
                end
            end
            return {op = "ref", parts = parts}
        elseif t.type == TOKEN.MINUS then
            -- Negative number
            advance()
            local node = parsePrimary()
            return {op = "neg", child = node}
        else
            -- Unexpected token; return 0 to be safe
            advance()
            return {op = "number", value = 0}
        end
    end

    local function parseUnary()
        if match(TOKEN.NOT) then
            return {op = "not", child = parseUnary()}
        end
        return parsePrimary()
    end

    local function parseMul()
        local node = parseUnary()
        while true do
            local t = peek()
            if t.type == TOKEN.MUL then
                advance(); node = {op = "*", left = node, right = parseUnary()}
            elseif t.type == TOKEN.DIV then
                advance(); node = {op = "/", left = node, right = parseUnary()}
            elseif t.type == TOKEN.MOD then
                advance(); node = {op = "%%", left = node, right = parseUnary()}
            else
                break
            end
        end
        return node
    end

    local function parseAdd()
        local node = parseMul()
        while true do
            local t = peek()
            if t.type == TOKEN.PLUS then
                advance(); node = {op = "+", left = node, right = parseMul()}
            elseif t.type == TOKEN.MINUS then
                advance(); node = {op = "-", left = node, right = parseMul()}
            else
                break
            end
        end
        return node
    end

    local function parseCmp()
        local node = parseAdd()
        local t = peek()
        if t.type == TOKEN.EQ then
            advance(); node = {op = "==", left = node, right = parseAdd()}
        elseif t.type == TOKEN.NEQ then
            advance(); node = {op = "!=", left = node, right = parseAdd()}
        elseif t.type == TOKEN.LT then
            advance(); node = {op = "<",  left = node, right = parseAdd()}
        elseif t.type == TOKEN.LE then
            advance(); node = {op = "<=", left = node, right = parseAdd()}
        elseif t.type == TOKEN.GT then
            advance(); node = {op = ">",  left = node, right = parseAdd()}
        elseif t.type == TOKEN.GE then
            advance(); node = {op = ">=", left = node, right = parseAdd()}
        end
        return node
    end

    local function parseAnd()
        local node = parseCmp()
        while match(TOKEN.AND) do
            node = {op = "and", left = node, right = parseCmp()}
        end
        return node
    end

    local function parseOr()
        local node = parseAnd()
        while match(TOKEN.OR) do
            node = {op = "or", left = node, right = parseAnd()}
        end
        return node
    end

    parseExpr = parseOr

    return {parse = parseExpr}
end

----------------------------------------------------------------------
-- Public: Parse a SimC condition expression string into an AST
----------------------------------------------------------------------
function P:ParseExpression(expr)
    if not expr or expr == "" then return nil end
    local tokens = Tokenize(expr)
    local parser = CreateParser(tokens)
    return parser.parse()
end

----------------------------------------------------------------------
-- Parse key=value pairs from a SimC action line
-- e.g. "stormstrike,if=buff.doom_winds.up&talent.thorims_invocation.enabled"
-- Returns: { action="stormstrike", if="buff.doom_winds.up&...", ... }
----------------------------------------------------------------------
local function ParseActionParams(line)
    local result = {}
    -- First comma-separated token is the action name
    local parts = {}
    for part in line:gmatch("[^,]+") do
        table.insert(parts, part)
    end
    if #parts == 0 then return nil end

    result.action = strtrim(parts[1])
    for i = 2, #parts do
        local k, v = parts[i]:match("^([^=]+)=(.+)$")
        if k then
            result[strtrim(k)] = strtrim(v)
        end
    end
    return result
end

----------------------------------------------------------------------
-- Public: Parse a full SimC APL text blob into a structured table
-- Returns: { precombat = {actions...}, default = {actions...}, <list_name> = {actions...} }
----------------------------------------------------------------------
function P:ParseAPL(text)
    local lists = {}

    for line in text:gmatch("[^\r\n]+") do
        line = strtrim(line)
        -- Skip comments and empty lines
        if line ~= "" and line:sub(1, 1) ~= "#" then
            -- Format: actions.listname+=/action  OR  actions.listname=action (first entry)
            local listName, actionStr = line:match("^actions%.([%w_]+)%+?=/?(.+)$")
            if not listName then
                -- Default list: actions+=/action  or  actions=action
                actionStr = line:match("^actions%+?=/?(.+)$")
                listName = "default"
            end

            if actionStr and listName then
                local entry = ParseActionParams(actionStr)
                if entry then
                    entry.listName = listName
                    -- Parse the condition expression into an AST
                    if entry["if"] then
                        entry.conditionAST = P:ParseExpression(entry["if"])
                    end
                    -- Parse variable value expression
                    if entry.action == "variable" and entry.value then
                        entry.valueAST = P:ParseExpression(entry.value)
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
-- Utility: Dump AST for debugging
----------------------------------------------------------------------
function P:DumpAST(node, indent)
    indent = indent or 0
    local pad = string.rep("  ", indent)
    if not node then return pad .. "(nil)" end
    if node.op == "number" then
        return pad .. "NUM(" .. tostring(node.value) .. ")"
    elseif node.op == "ref" then
        return pad .. "REF(" .. table.concat(node.parts, ".") .. ")"
    elseif node.op == "not" then
        return pad .. "NOT\n" .. P:DumpAST(node.child, indent + 1)
    elseif node.op == "neg" then
        return pad .. "NEG\n" .. P:DumpAST(node.child, indent + 1)
    else
        return pad .. "(" .. node.op .. ")\n"
            .. P:DumpAST(node.left, indent + 1) .. "\n"
            .. P:DumpAST(node.right, indent + 1)
    end
end
