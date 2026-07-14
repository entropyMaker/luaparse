local lexer = require("luaparse.lexer")
local format = string.format
local error = error
local setmetatable = setmetatable
local type = type
local tostring = tostring

-- FOLLOW(block) is {end, else, elseif, until, EOF}
local function is_block_follow(token)
  if token.type == "Keyword" then
    local raw = token.raw
    return raw == "end" or raw == "else" or raw == "elseif" or raw == "until"
  end
  return token.type == "EOF"
end

local function node(node_type, fields)
  fields = fields or {}
  fields.type = node_type
  return fields
end

local function syntax_error(token, message)
  error(format("%s near byte %d", message, token.start), 0)
end

local parser_methods = {}
local parser_mt = {
  __index = parser_methods,
  __metatable = false,
}

-- read tokens until the next non-comment token, retaining every token in source
-- order and anchoring skipped comments to their neighboring significant tokens
function parser_methods:read_significant()
  while true do
    local token = self.scanner:next()
    local token_index = #self.tokens + 1
    self.tokens[token_index] = token
    if token.type ~= "Comment" then
      if token.type ~= "EOF" then
        local pending_comments = self.pending_comments
        local pending_count = #pending_comments
        if pending_count ~= 0 then
          for i = 1, pending_count do
            pending_comments[i].nextToken = token_index
          end
          self.pending_comments = {}
        end
        self.previous_significant = token_index
      end
      return token
    end

    local raw = token.raw
    local comment = node("Comment", {
      raw = raw,
      -- the pattern is lua version of '^--\[=*\[',
      -- which is beginning of a multiline comment
      multiline = raw:find("^%-%-%[=*%[") ~= nil,
      previousToken = self.previous_significant,
    })
    self.comments[#self.comments + 1] = comment
    self.pending_comments[#self.pending_comments + 1] = comment
  end
end

function parser_methods:peek()
  if self.current == nil then self.current = self:read_significant() end
  return self.current
end

function parser_methods:next()
  local token = self:peek()
  self.current = nil
  return token
end

function parser_methods:is_token(token_type, value)
  local token = self:peek()
  return token.type == token_type and (value == nil or token.raw == value)
end

-- consume the current token and return true when its type and optional raw
-- value match; otherwise leave the token unconsumed and return false
function parser_methods:consume(token_type, value)
  if not self:is_token(token_type, value) then return false end
  self:next()
  return true
end

-- consume and return a required token, raising a syntax error at the current
-- token without consuming it when its type or optional raw value does not match
function parser_methods:expect(token_type, value)
  local token = self:peek()
  if token.type ~= token_type or (value ~= nil and token.raw ~= value) then
    local expected = value and format("'%s'", value)
      or format("token type '%s'", token_type)
    syntax_error(token, format("expected %s, got '%s'", expected, token.raw))
  end
  return self:next()
end

function parser_methods:expect_identifier()
  local token = self:expect("Identifier")
  return node("Identifier", { name = token.raw })
end

-- expression parsing methods

-- explist ::= {exp ','} exp
function parser_methods:parse_expression_list()
  local expressions = { self:parse_expression() }
  while self:consume("Punctuator", ",") do
    expressions[#expressions + 1] = self:parse_expression()
  end
  return expressions
end

-- args ::= '(' [explist] ')' | tableconstructor | String
function parser_methods:parse_arguments()
  if self:consume("Punctuator", "(") then
    local arguments = {}
    if not self:is_token("Punctuator", ")") then
      arguments = self:parse_expression_list()
    end
    self:expect("Punctuator", ")")
    return arguments
  elseif self:is_token("Punctuator", "{") then
    return { self:parse_table() }
  elseif self:is_token("StringLiteral") then
    local token = self:next()
    return { node("StringLiteral", { raw = token.raw, value = token.value }) }
  end
  syntax_error(self:peek(), "expected function arguments")
end

local function is_arguments_begin(token)
  local token_type = token.type
  local raw = token.raw
  return token_type == "StringLiteral"
    or token_type == "Punctuator" and (raw == "(" or raw == "{")
end

-- prefixexp ::= var | functioncall | '(' exp ')'
-- var ::= Name | prefixexp '[' exp ']' | prefixexp '.' Name
-- functioncall ::= prefixexp args | prefixexp ':' Name args
--
-- after substituting var and functioncall:
-- prefixexp ::= Name
--             | '(' exp ')'
--             | prefixexp '[' exp ']'
--             | prefixexp '.' Name
--             | prefixexp args
--             | prefixexp ':' Name args
--
-- after eliminating direct left recursion:
-- prefixexp ::= (Name | '(' exp ')') {suffixexp}
-- suffixexp ::= '[' exp ']' | '.' Name | args | ':' Name args
function parser_methods:parse_prefix_expression()
  local base
  if self:is_token("Identifier") then
    base = self:expect_identifier()
  elseif self:consume("Punctuator", "(") then
    local expression = self:parse_expression()
    base = node("ParenthesizedExpression", { expression = expression })
    self:expect("Punctuator", ")")
  else
    syntax_error(self:peek(), "expected prefix expression")
  end

  -- suffixes
  while true do
    if self:consume("Punctuator", "[") then
      local index = self:parse_expression()
      self:expect("Punctuator", "]")
      base = node("IndexExpression", { base = base, index = index })
    elseif self:consume("Punctuator", ".") then
      local name = self:expect_identifier()
      base = node(
        "MemberExpression",
        { base = base, identifier = name, indexer = "." }
      )
    elseif self:consume("Punctuator", ":") then
      local name = self:expect_identifier()
      local member = node(
        "MemberExpression",
        { base = base, identifier = name, indexer = ":" }
      )
      local arguments = self:parse_arguments()
      base = node("CallExpression", { base = member, arguments = arguments })
    elseif is_arguments_begin(self:peek()) then
      local arguments = self:parse_arguments()
      base = node("CallExpression", { base = base, arguments = arguments })
    else
      return base
    end
  end
end

-- tableconstructor ::= '{' [fieldlist] '}'
-- fieldlist ::= field {fieldsep field} [fieldsep]
-- field ::= '[' exp ']' '=' exp | Name '=' exp | exp
-- fieldsep ::= ',' | ';'
function parser_methods:parse_table()
  self:expect("Punctuator", "{")
  local fields = {}
  while not self:is_token("Punctuator", "}") do
    local field
    if self:consume("Punctuator", "[") then
      -- field ::= '[' exp ']' '=' exp
      local key = self:parse_expression()
      self:expect("Punctuator", "]")
      self:expect("Punctuator", "=")
      local value = self:parse_expression()
      field = node("TableKey", { key = key, value = value })
    else
      -- field ::= Name '=' exp | exp
      -- because '=' is not in follow set of `field`,
      -- seeing a '=' unambiguously selects Name '=' exp
      local expression = self:parse_expression()
      if self:consume("Punctuator", "=") then
        if expression.type ~= "Identifier" then
          syntax_error(self:peek(), "expected identifier table key")
        end
        local value = self:parse_expression()
        field = node("TableKeyString", { key = expression, value = value })
      else
        field = node("TableValue", { value = expression })
      end
    end
    fields[#fields + 1] = field
    if
      not self:consume("Punctuator", ",")
      and not self:consume("Punctuator", ";")
    then
      break
    end
  end
  self:expect("Punctuator", "}")
  return node("TableConstructorExpression", { fields = fields })
end

-- funcbody ::= '(' [parlist] ')' block end
-- parlist ::= namelist [',' '...'] | '...'
function parser_methods:parse_function_body(identifier, scope)
  self:expect("Punctuator", "(")
  local parameters = {}
  if not self:is_token("Punctuator", ")") then
    repeat
      if self:consume("VarargLiteral") then
        parameters[#parameters + 1] = node("VarargParameter")
        break
      end
      parameters[#parameters + 1] = self:expect_identifier()
    until not self:consume("Punctuator", ",")
  end
  self:expect("Punctuator", ")")

  local old_vararg = self.in_vararg_function
  local old_loop_depth = self.loop_depth
  self.in_vararg_function = #parameters > 0
    and parameters[#parameters].type == "VarargParameter"
  self.loop_depth = 0
  local body = self:parse_block()
  self:expect("Keyword", "end")
  self.in_vararg_function = old_vararg
  self.loop_depth = old_loop_depth
  return node("FunctionDeclaration", {
    identifier = identifier,
    scope = scope,
    parameters = parameters,
    body = body,
  })
end

-- Atomic and prefix expression portion of:
-- exp ::= nil | false | true | Number | String | '...' | function |
--         prefixexp | tableconstructor | exp binop exp | unop exp
-- function ::= function funcbody
-- prefixexp ::= var | functioncall | '(' exp ')'
function parser_methods:parse_primary()
  local token = self:peek()
  local token_type = token.type
  if token_type == "NilLiteral" then
    self:next()
    return node("NilLiteral", { raw = token.raw })
  elseif token_type == "BooleanLiteral" then
    self:next()
    return node("BooleanLiteral", { raw = token.raw, value = token.value })
  elseif token_type == "NumberLiteral" then
    self:next()
    return node("NumberLiteral", { raw = token.raw, value = token.value })
  elseif token_type == "StringLiteral" then
    self:next()
    return node("StringLiteral", { raw = token.raw, value = token.value })
  elseif token_type == "VarargLiteral" then
    if not self.in_vararg_function then
      syntax_error(token, "cannot use '...' outside a vararg function")
    end
    self:next()
    return node("VarargLiteral", { raw = token.raw })
  elseif self:is_token("Punctuator", "{") then
    return self:parse_table()
  elseif self:consume("Keyword", "function") then
    return self:parse_function_body(nil, nil)
  else
    return self:parse_prefix_expression()
  end
end

-- used in parse_subexpression, put in module scope to avoid recreating
local binary_precedence = {
  ["or"] = 1,
  ["and"] = 2,

  ["<"] = 3,
  [">"] = 3,
  ["<="] = 3,
  [">="] = 3,
  ["~="] = 3,
  ["=="] = 3,

  ["|"] = 4,
  ["~"] = 5,
  ["&"] = 6,
  ["<<"] = 7,
  [">>"] = 7,

  [".."] = 8,

  ["+"] = 9,
  ["-"] = 9,

  ["*"] = 10,
  ["/"] = 10,
  ["//"] = 10,
  ["%"] = 10,
  -- precedence 11 is reserved for unary operators, below exponentiation "^"
  ["^"] = 12,
}
local right_associative = { ["^"] = true, [".."] = true }
local unary_operators = {
  ["-"] = true,
  ["#"] = true,
  ["not"] = true,
  ["~"] = true,
}

-- Precedence-aware implementation of:
-- exp ::= exp binop exp | unop exp
function parser_methods:parse_subexpression(minimum_precedence)
  local operator = self:peek().raw
  local left
  if unary_operators[operator] then
    self:next()
    -- Unary precedence is below exponentiation, so -2^2 parses as -(2^2).
    local argument = self:parse_subexpression(11)
    left = node("UnaryExpression", { operator = operator, argument = argument })
  else
    left = self:parse_primary()
  end

  while true do
    operator = self:peek().raw
    local precedence = binary_precedence[operator]
    -- stop combining if the next token is not a binary operator
    -- or its precedence is below the required minimum
    if precedence == nil or precedence < minimum_precedence then break end
    self:next()
    -- keep the same minimum for right-associative operators so an operator of
    -- equal precedence can be included in the right operand; increase it for
    -- left-associative operators to exclude equal precedence
    if not right_associative[operator] then precedence = precedence + 1 end
    local right = self:parse_subexpression(precedence)
    left = node(
      (operator == "and" or operator == "or") and "LogicalExpression"
        or "BinaryExpression",
      { operator = operator, left = left, right = right }
    )
  end
  return left
end

-- exp ::= nil | false | true | Number | String | '...' | function |
--         prefixexp | tableconstructor | exp binop exp | unop exp
function parser_methods:parse_expression() return self:parse_subexpression(1) end

-- end of expression parsing methods

local function is_assignable(expression)
  local expr_type = expression.type
  return expr_type == "Identifier"
    or expr_type == "MemberExpression"
    or expr_type == "IndexExpression"
end

-- statement parsing methods

-- stat ::= varlist '=' explist
--        | functioncall
--        | do block end
--        | while exp do block end
--        | repeat block until exp
--        | if exp then block {elseif exp then block} [else block] end
--        | for Name '=' exp ',' exp [',' exp] do block end
--        | for namelist in explist do block end
--        | function funcname funcbody
--        | local function Name funcbody
--        | local namelist ['=' explist]
function parser_methods:parse_statement()
  -- do block end
  if self:consume("Keyword", "do") then
    local body = self:parse_block()
    self:expect("Keyword", "end")
    return node("DoStatement", { body = body })
  -- while exp do block end
  elseif self:consume("Keyword", "while") then
    local condition = self:parse_expression()
    self:expect("Keyword", "do")
    self.loop_depth = self.loop_depth + 1
    local body = self:parse_block()
    self.loop_depth = self.loop_depth - 1
    self:expect("Keyword", "end")
    return node("WhileStatement", { condition = condition, body = body })
  -- repeat block until exp
  elseif self:consume("Keyword", "repeat") then
    self.loop_depth = self.loop_depth + 1
    local body = self:parse_block()
    self.loop_depth = self.loop_depth - 1
    self:expect("Keyword", "until")
    local condition = self:parse_expression()
    return node("RepeatStatement", { body = body, condition = condition })
  elseif self:consume("Keyword", "if") then
    return self:parse_if()
  elseif self:consume("Keyword", "for") then
    return self:parse_for()
  -- function funcname funcbody
  elseif self:consume("Keyword", "function") then
    local identifier = self:parse_function_name()
    return self:parse_function_body(identifier, nil)
  elseif self:consume("Keyword", "local") then
    return self:parse_local()
  elseif self:is_token("Keyword", "break") then
    local break_token = self:next()
    if self.loop_depth == 0 then
      syntax_error(break_token, "break outside loop")
    end
    return node("BreakStatement")
  end
  return self:parse_assignment_or_call()
end

-- funcname ::= Name {'.' Name} [':' Name]
function parser_methods:parse_function_name()
  local expression = self:expect_identifier()
  while self:consume("Punctuator", ".") do
    local name = self:expect_identifier()
    expression = node(
      "MemberExpression",
      { base = expression, identifier = name, indexer = "." }
    )
  end
  if self:consume("Punctuator", ":") then
    local method = self:expect_identifier()
    expression = node(
      "MemberExpression",
      { base = expression, identifier = method, indexer = ":" }
    )
  end
  return expression
end

-- stat ::= if exp then block {elseif exp then block} [else block] end
function parser_methods:parse_if()
  local condition = self:parse_expression()
  self:expect("Keyword", "then")
  local body = self:parse_block()
  local clauses = { node("IfClause", { condition = condition, body = body }) }
  while self:consume("Keyword", "elseif") do
    condition = self:parse_expression()
    self:expect("Keyword", "then")
    body = self:parse_block()
    clauses[#clauses + 1] =
      node("ElseifClause", { condition = condition, body = body })
  end
  if self:consume("Keyword", "else") then
    body = self:parse_block()
    clauses[#clauses + 1] = node("ElseClause", { body = body })
  end
  self:expect("Keyword", "end")
  return node("IfStatement", { clauses = clauses })
end

-- invoke after the `for` is already consumed
function parser_methods:parse_for()
  local variable = self:expect_identifier()
  -- stat ::= for Name '=' exp ',' exp [',' exp] do block end
  if self:consume("Punctuator", "=") then
    local start = self:parse_expression()
    self:expect("Punctuator", ",")
    local limit = self:parse_expression()
    local step
    if self:consume("Punctuator", ",") then step = self:parse_expression() end
    self:expect("Keyword", "do")
    self.loop_depth = self.loop_depth + 1
    local body = self:parse_block()
    self.loop_depth = self.loop_depth - 1
    self:expect("Keyword", "end")
    return node("NumericForStatement", {
      variable = variable,
      start = start,
      limit = limit,
      step = step,
      body = body,
    })
  end

  -- stat ::= for namelist in explist do block end
  local variables = { variable }
  while self:consume("Punctuator", ",") do
    variables[#variables + 1] = self:expect_identifier()
  end
  self:expect("Keyword", "in")
  local iterators = self:parse_expression_list()
  self:expect("Keyword", "do")
  self.loop_depth = self.loop_depth + 1
  local body = self:parse_block()
  self.loop_depth = self.loop_depth - 1
  self:expect("Keyword", "end")
  return node("GenericForStatement", {
    variables = variables,
    iterators = iterators,
    body = body,
  })
end

-- invoke after the `local` is already consumed
function parser_methods:parse_local()
  -- stat ::= local function Name funcbody
  if self:consume("Keyword", "function") then
    local identifier = self:expect_identifier()
    return self:parse_function_body(identifier, "local")
  end

  -- stat ::= local namelist ['=' explist]
  local name = self:expect_identifier()
  local variables = { node("VariableDeclarator", { identifier = name }) }
  while self:consume("Punctuator", ",") do
    name = self:expect_identifier()
    variables[#variables + 1] =
      node("VariableDeclarator", { identifier = name })
  end
  local init = {}
  if self:consume("Punctuator", "=") then
    init = self:parse_expression_list()
  end
  return node("VariableDeclaration", {
    scope = "local",
    variables = variables,
    init = init,
  })
end

-- stat ::= varlist '=' explist | functioncall
-- varlist ::= var {',' var}
function parser_methods:parse_assignment_or_call()
  local expression = self:parse_prefix_expression()
  -- return early here because functioncall is never assignable,
  -- if there is a ',' or '=' later, it will be caught in caller
  if expression.type == "CallExpression" then
    return node("FunctionCallStatement", { expression = expression })
  end

  local variables = {}
  while true do
    if not is_assignable(expression) then
      syntax_error(self:peek(), "invalid assignment target")
    end
    variables[#variables + 1] = expression
    if not self:consume("Punctuator", ",") then break end
    expression = self:parse_prefix_expression()
  end
  self:expect("Punctuator", "=")
  local init = self:parse_expression_list()
  return node("AssignmentStatement", { variables = variables, init = init })
end

-- chunk ::= {stat [';']} [laststat [';']]
-- block ::= chunk
-- laststat ::= return [explist] | break
function parser_methods:parse_block()
  local body = {}
  local final_statement = false
  while true do
    local token = self:peek()
    if is_block_follow(token) then break end
    if final_statement then
      syntax_error(token, "statement must be last in its block")
    end

    if self:consume("Keyword", "return") then
      local empty_return = is_block_follow(self:peek())
        or self:is_token("Punctuator", ";")
      local arguments = empty_return and {} or self:parse_expression_list()
      body[#body + 1] = node("ReturnStatement", { arguments = arguments })
      final_statement = true
    else
      local statement = self:parse_statement()
      body[#body + 1] = statement
      -- Lua 5.1 treats both return and break as final statements. Later
      -- profiles keep return final but allow break among ordinary statements.
      if
        statement.type == "BreakStatement" and self.features.break_must_be_last
      then
        final_statement = true
      end
    end

    self:consume("Punctuator", ";")
  end
  return node("Block", { body = body })
end

-- end of statement parsing methods

local feature_profiles = {
  ["5.1"] = {
    implemented = true,
    break_must_be_last = true,
  },
  ["LuaJIT"] = {
    implemented = false,
    labels_and_goto = true,
  },
  ["5.2"] = {
    implemented = false,
    labels_and_goto = true,
    empty_statements = true,
  },
  ["5.3"] = {
    implemented = false,
    labels_and_goto = true,
    empty_statements = true,
    bitwise_operators = true,
    integer_division = true,
  },
  ["5.4"] = {
    implemented = false,
    labels_and_goto = true,
    empty_statements = true,
    bitwise_operators = true,
    integer_division = true,
    variable_attributes = true,
  },
  ["5.5"] = {
    implemented = false,
    labels_and_goto = true,
    empty_statements = true,
    bitwise_operators = true,
    integer_division = true,
    variable_attributes = true,
    attribute_prefix = true,
    global_declarations = true,
    named_varargs = true,
  },
}

local function new_parser(source, options)
  options = options or {}
  local lua_version = options.lua_version or "5.1"
  local features = feature_profiles[lua_version]
  if features == nil then
    error(format("unsupported Lua version '%s'", tostring(lua_version)), 3)
  end
  if not features.implemented then
    error(
      format("parser support for Lua %s is not implemented", lua_version),
      3
    )
  end
  return setmetatable({
    scanner = lexer.from_string(source, { lua_version = lua_version }),
    features = features,
    tokens = {},
    comments = {},
    pending_comments = {},
    loop_depth = 0,
    in_vararg_function = true,
  }, parser_mt)
end

local function parse(source, options)
  if type(source) ~= "string" then error("source must be a string", 2) end
  local state = new_parser(source, options)
  local block = state:parse_block()
  state:expect("EOF")
  local ast = node("Chunk", { body = block.body, comments = state.comments })
  return { ast = ast, tokens = state.tokens }
end

-- possible fields for AST nodes across all planned Lua version profiles;
-- fields whose values are nil are absent from the actual Lua table
local node_fields = {
  ["Chunk"] = { "body", "comments" },
  ["Block"] = { "body" },
  ["BreakStatement"] = {},
  ["ReturnStatement"] = { "arguments" },
  ["IfStatement"] = { "clauses" },
  ["WhileStatement"] = { "condition", "body" },
  ["DoStatement"] = { "body" },
  ["RepeatStatement"] = { "body", "condition" },
  ["VariableDeclaration"] = { "scope", "attribute", "variables", "init" },
  ["GlobalWildcardDeclaration"] = { "attribute" },
  ["AssignmentStatement"] = { "variables", "init" },
  ["FunctionCallStatement"] = { "expression" },
  ["FunctionDeclaration"] = { "identifier", "scope", "parameters", "body" },
  ["NumericForStatement"] = { "variable", "start", "limit", "step", "body" },
  ["GenericForStatement"] = { "variables", "iterators", "body" },
  ["GotoStatement"] = { "label" },
  ["LabelStatement"] = { "label" },
  ["EmptyStatement"] = {},
  ["IfClause"] = { "condition", "body" },
  ["ElseifClause"] = { "condition", "body" },
  ["ElseClause"] = { "body" },
  ["VariableDeclarator"] = { "identifier", "attribute" },
  ["Attribute"] = { "name" },
  ["VarargParameter"] = { "identifier" },
  ["NilLiteral"] = { "raw" },
  ["BooleanLiteral"] = { "raw", "value" },
  ["NumberLiteral"] = { "raw", "value" },
  ["StringLiteral"] = { "raw", "value" },
  ["VarargLiteral"] = { "raw" },
  ["Identifier"] = { "name" },
  ["TableConstructorExpression"] = { "fields" },
  ["BinaryExpression"] = { "operator", "left", "right" },
  ["LogicalExpression"] = { "operator", "left", "right" },
  ["UnaryExpression"] = { "operator", "argument" },
  ["ParenthesizedExpression"] = { "expression" },
  ["MemberExpression"] = { "base", "identifier", "indexer" },
  ["IndexExpression"] = { "base", "index" },
  ["CallExpression"] = { "base", "arguments" },
  ["TableKey"] = { "key", "value" },
  ["TableKeyString"] = { "key", "value" },
  ["TableValue"] = { "value" },
  ["Comment"] = { "raw", "multiline", "previousToken", "nextToken" },
}

return {
  node_fields = node_fields,
  parse = parse,
}
