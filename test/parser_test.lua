local luaunit = require("luaunit")
local lexer = require("luaparse.lexer")
local parser = require("luaparse.parser")

local function parse(source) return parser.parse(source).ast end

local function parse_version(source, lua_version)
  return parser.parse(source, { lua_version = lua_version }).ast
end

local function assert_error(source, message)
  luaunit.assertErrorMsgContains(message, function() parser.parse(source) end)
end

local function assert_version_error(source, lua_version, message)
  luaunit.assertErrorMsgContains(
    message,
    function() parser.parse(source, { lua_version = lua_version }) end
  )
end

local function assert_lexically_valid_parse_error(source, message)
  local scanner = lexer.from_string(source)
  while scanner:next().type ~= "EOF" do
  end
  assert_error(source, message)
end

TestParser = {}

function TestParser:testDeclarationsAssignmentsAndReturns()
  local ast = parse([[
    local a, b = 1, "two"
    a, obj.x, obj[key] = b, 3, nil
    return a, b;
  ]])
  -- there are 3 statements
  luaunit.assertEquals(#ast.body, 3)
  -- the first statement declares local variables
  luaunit.assertEquals(ast.body[1].type, "VariableDeclaration")
  -- declaration names are wrapped in VariableDeclarator nodes
  luaunit.assertEquals(ast.body[1].variables[2].identifier.name, "b")
  -- dotted assignment targets retain member-access syntax
  luaunit.assertEquals(ast.body[2].variables[2].type, "MemberExpression")
  -- bracketed assignment targets retain index syntax
  luaunit.assertEquals(ast.body[2].variables[3].type, "IndexExpression")
  -- return arguments retain their source order
  luaunit.assertEquals(ast.body[3].arguments[2].name, "b")
end

function TestParser:testFunctionFormsAndCalls()
  local ast = parse([[
    local function local_name(x, ...) return x, ... end
    function module.object:method(value) return value end
    callback = function() return 42 end
    module.object:method "value"
  ]])
  local local_function = ast.body[1]
  -- local function syntax sets the explicit local scope
  luaunit.assertEquals(local_function.scope, "local")
  -- a trailing ellipsis becomes a parameter rather than an expression
  luaunit.assertEquals(local_function.parameters[2].type, "VarargParameter")
  local method = ast.body[2]
  -- the final component of a method declaration uses a colon
  luaunit.assertEquals(method.identifier.indexer, ":")
  -- preceding components retain their dotted access
  luaunit.assertEquals(method.identifier.base.indexer, ".")
  -- an anonymous function has no identifier
  luaunit.assertNil(ast.body[3].init[1].identifier)
  local call = ast.body[4].expression
  -- method calls preserve their colon member expression
  luaunit.assertEquals(call.base.indexer, ":")
  -- shorthand string arguments are decoded normally
  luaunit.assertEquals(call.arguments[1].value, "value")
end

function TestParser:testFunctionParameterLists()
  local ast = parse([[
    empty = function() end
    vararg_only = function(...) return ... end
    named = function(first, second) end
    named_vararg = function(first, second, ...) return ... end
  ]])
  -- an empty parameter list produces no parameter nodes
  luaunit.assertEquals(#ast.body[1].init[1].parameters, 0)
  -- a standalone ellipsis produces one VarargParameter
  luaunit.assertEquals(
    ast.body[2].init[1].parameters[1].type,
    "VarargParameter"
  )
  -- ordinary names retain their order
  luaunit.assertEquals(ast.body[3].init[1].parameters[2].name, "second")
  -- a trailing ellipsis follows all named parameters
  luaunit.assertEquals(
    ast.body[4].init[1].parameters[3].type,
    "VarargParameter"
  )

  -- a comma must be followed by another name or an ellipsis
  assert_error("function invalid(a,) end", "expected token type 'Identifier'")
  -- no parameter may follow an ellipsis
  assert_error("function invalid(..., a) end", "expected ')'")
  -- a trailing ellipsis must be the final parameter
  assert_error("function invalid(a, ..., b) end", "expected ')'")
  -- consecutive commas do not form a parameter
  assert_error("function invalid(a,,b) end", "expected token type 'Identifier'")
end

function TestParser:testControlFlow()
  local ast = parse([[
    if ready then work() elseif waiting then pause() else stop() end
    while running do break end
    repeat running = step() until not running
    for i = 1, 10, 2 do work(i) end
    for key, value in pairs(items) do work(key, value) end
    do local scoped end
  ]])
  -- the first control-flow construct is the if statement
  luaunit.assertEquals(ast.body[1].type, "IfStatement")
  -- if, elseif, and else each produce a clause
  luaunit.assertEquals(#ast.body[1].clauses, 3)
  -- while loops produce their dedicated statement node
  luaunit.assertEquals(ast.body[2].type, "WhileStatement")
  -- nested body fields directly contain their statement arrays
  luaunit.assertEquals(ast.body[2].body[1].type, "BreakStatement")
  luaunit.assertNil(ast.body[2].body.type)
  -- the numeric for limit is distinct from its start and step
  luaunit.assertEquals(ast.body[4].limit.value, 10)
  -- generic for iterator expressions can be function calls
  luaunit.assertEquals(ast.body[5].iterators[1].type, "CallExpression")
  -- explicit do blocks produce their dedicated statement node
  luaunit.assertEquals(ast.body[6].type, "DoStatement")
end

function TestParser:testExpressionsAndPrefixChains()
  local ast = parse([[
    result = -2^2 + a.b[c]:method().x(y)[z] .. "!" and true or false
    one = f()
    single = (f())
  ]])
  -- logical operators form the outermost, lowest-precedence expression
  luaunit.assertEquals(ast.body[1].init[1].type, "LogicalExpression")
  -- an ordinary call is retained as a call expression
  luaunit.assertEquals(ast.body[2].init[1].type, "CallExpression")
  -- explicit parentheses are retained around the call
  luaunit.assertEquals(ast.body[3].init[1].type, "ParenthesizedExpression")
end

function TestParser:testOperatorPrecedenceAndAssociativity()
  -- left-associative multiplication binds more tightly than addition
  local expression = parse("value = 1 + 2 * 3").body[1].init[1]
  luaunit.assertEquals(expression.operator, "+")
  luaunit.assertEquals(expression.right.operator, "*")

  -- exponentiation binds more tightly than a preceding unary operator
  expression = parse("value = -2 ^ 3").body[1].init[1]
  luaunit.assertEquals(expression.type, "UnaryExpression")
  luaunit.assertEquals(expression.operator, "-")
  luaunit.assertEquals(expression.argument.operator, "^")

  -- a unary operator binds more tightly than binary operators other than power
  expression = parse("value = -2 * 3").body[1].init[1]
  luaunit.assertEquals(expression.operator, "*")
  luaunit.assertEquals(expression.left.type, "UnaryExpression")
  luaunit.assertEquals(expression.left.operator, "-")

  -- left-associative addition binds more tightly than right-associative concat
  expression = parse("value = 1 + 2 .. 3").body[1].init[1]
  luaunit.assertEquals(expression.operator, "..")
  luaunit.assertEquals(expression.left.operator, "+")

  -- power binds before concat, while repeated concatenation groups to the right
  expression = parse("value = 1 ^ 2 .. 3 .. 4").body[1].init[1]
  luaunit.assertEquals(expression.operator, "..")
  luaunit.assertEquals(expression.left.operator, "^")
  luaunit.assertEquals(expression.right.operator, "..")
end

function TestParser:testTableFieldKinds()
  local ast = parse([[value = { [key] = 1, name = 2; value, trailing = f(), }]])
  local fields = ast.body[1].init[1].fields
  -- bracketed keys use TableKey
  luaunit.assertEquals(fields[1].type, "TableKey")
  -- identifier keys use TableKeyString
  luaunit.assertEquals(fields[2].type, "TableKeyString")
  -- positional fields use TableValue
  luaunit.assertEquals(fields[3].type, "TableValue")
  -- a keyed call value remains an identifier-key field
  luaunit.assertEquals(fields[4].type, "TableKeyString")
end

function TestParser:testCommentsTokensAndSourceGaps()
  local result =
    parser.parse("-- lead\nlocal x = 1 -- trailing\n-- next\nreturn x")
  -- all 3 comments are collected in source order
  luaunit.assertEquals(#result.ast.comments, 3)
  -- a leading comment has no preceding significant token
  luaunit.assertNil(result.ast.comments[1].previous_token)
  -- the leading comment is anchored to the following local keyword
  luaunit.assertNotNil(result.ast.comments[1].next_token)
  -- the inline comment is anchored after the preceding numeral
  luaunit.assertNotNil(result.ast.comments[2].previous_token)
  -- the inline comment is also anchored before the following return
  luaunit.assertNotNil(result.ast.comments[2].next_token)
  -- comments remain in the complete token stream
  luaunit.assertEquals(result.tokens[1].type, "Comment")

  local trailing = parser.parse("return 1\n-- final")
  -- a final comment has no following significant token
  luaunit.assertNil(trailing.ast.comments[1].next_token)
  -- a line comment beginning with a bracket is not a long comment
  luaunit.assertFalse(
    parser.parse("--[not long\nreturn").ast.comments[1].multiline
  )
  -- a matching long-bracket opener marks a multiline comment
  luaunit.assertTrue(
    parser.parse("--[=[long]=]\nreturn").ast.comments[1].multiline
  )
end

function TestParser:testLua51Grammar()
  -- Context restrictions are semantic, so a standalone break is accepted.
  luaunit.assertEquals(parse("break").body[1].type, "BreakStatement")
  -- break must be the final statement of a Lua 5.1 block
  assert_error("while true do break work() end", "statement must be last")
  -- return must be the final statement of its block
  assert_error("return 1; work()", "statement must be last")
  -- Lua 5.1 does not allow a standalone semicolon
  assert_error("; local x", "expected prefix expression")
  -- Lua 5.1 allows only one optional separator after a statement
  assert_error("local x;;", "expected prefix expression")
  -- parenthesized expressions are not assignment targets
  assert_error("(x) = 1", "invalid assignment target")
  -- Vararg context is semantic rather than part of the grammar production.
  parse("function f() return ... end")
  -- colon member syntax must be followed by call arguments
  assert_error("a:x", "expected function arguments")
  -- a completed function call cannot be assigned to
  assert_error("f() = 1", "expected prefix expression")
  -- a completed function call cannot begin an assignment target list
  assert_error("f(), x = 1, 2", "expected prefix expression")
end

function TestParser:testLua51ParenthesizedCallLineBreak()
  -- Lua 5.1 forbids a line break immediately before parenthesized call
  -- arguments. (https://www.lua.org/manual/5.1/manual.html#2.5.8)
  assert_error("f\n(x)", "ambiguous syntax")
  assert_error("return f -- comment\n(x)", "ambiguous syntax")
  assert_error("f --[[\ncomment\n]] (x)", "ambiguous syntax")

  -- The restriction applies only before parenthesized call arguments.
  local table_call = parse("f\n{ value }").body[1].expression
  luaunit.assertEquals(table_call.type, "CallExpression")

  local string_call = parse('f\n"value"').body[1].expression
  luaunit.assertEquals(string_call.type, "CallExpression")

  -- Newlines inside the argument list remain valid.
  local multiline_call = parse("f(\nvalue\n)").body[1].expression
  luaunit.assertEquals(multiline_call.type, "CallExpression")
end

function TestParser:testLexicallyValidButAlwaysInvalidLua()
  -- a literal expression cannot be used as a statement
  assert_lexically_valid_parse_error(
    '"standalone"',
    "expected prefix expression"
  )
  -- a binary expression cannot be used as a statement
  assert_lexically_valid_parse_error("a + b", "expected '='")
  -- a local declaration requires an identifier
  assert_lexically_valid_parse_error(
    "local 1",
    "expected token type 'Identifier'"
  )
  -- an if condition must be followed by then rather than do
  assert_lexically_valid_parse_error("if true do end", "expected 'then'")
  -- an argument list cannot begin with a comma
  assert_lexically_valid_parse_error("f(, value)", "expected prefix expression")
  -- adjacent table fields require a comma or semicolon
  assert_lexically_valid_parse_error("value = { key value }", "expected '}'")
  -- dotted expressions require brackets when used as table keys
  assert_lexically_valid_parse_error(
    "value = { object.key = 1 }",
    "expected identifier table key"
  )
  -- parenthesized expressions cannot use identifier-key shorthand
  assert_lexically_valid_parse_error(
    "value = { (key) = 1 }",
    "expected identifier table key"
  )
  -- bracket indexing is not allowed in a named function declaration
  assert_lexically_valid_parse_error(
    "function object[index]() end",
    "expected '('"
  )
end

function TestParser:testLuaJITDefaultGrammar()
  local ast = parse_version("goto target ::target:: goto = 1 goto()", "LuaJIT")
  luaunit.assertEquals(ast.body[1].type, "GotoStatement")
  luaunit.assertEquals(ast.body[2].type, "LabelStatement")
  luaunit.assertEquals(ast.body[3].variables[1].name, "goto")
  luaunit.assertEquals(ast.body[4].type, "FunctionCallStatement")

  assert_version_error("; local x", "LuaJIT", "expected prefix expression")
  assert_version_error("f\n(x)", "LuaJIT", "ambiguous syntax")
  assert_version_error("goto goto", "LuaJIT", "expected '='")
end

function TestParser:testLua52Statements()
  local ast = parse_version("; goto missing ::label:: ; break; work()", "5.2")
  luaunit.assertEquals(ast.body[1].type, "EmptyStatement")
  luaunit.assertEquals(ast.body[2].type, "GotoStatement")
  luaunit.assertEquals(ast.body[3].type, "LabelStatement")
  luaunit.assertEquals(ast.body[4].type, "EmptyStatement")
  luaunit.assertEquals(ast.body[5].type, "BreakStatement")
  luaunit.assertEquals(ast.body[6].type, "EmptyStatement")
  luaunit.assertEquals(ast.body[7].type, "FunctionCallStatement")

  -- Label visibility and resolution are semantic checks.
  parse_version("goto missing ::same:: ::same::", "5.2")
end

function TestParser:testLua53Operators()
  local expression = parse_version("value = 1 // 2 | 3", "5.3").body[1].init[1]
  luaunit.assertEquals(expression.operator, "|")
  luaunit.assertEquals(expression.left.operator, "//")
end

function TestParser:testLua54Attributes()
  local ast = parse_version(
    "local first <const>, second <unknown> = 1, 2; first = 3",
    "5.4"
  )
  local declaration = ast.body[1]
  luaunit.assertEquals(declaration.variables[1].attribute.name, "const")
  luaunit.assertEquals(declaration.variables[2].attribute.name, "unknown")
  luaunit.assertEquals(ast.body[3].type, "AssignmentStatement")
end

function TestParser:testLua55DeclarationsAndNamedVarargs()
  local ast = parse_version(
    [[
      global exposed <const> = 1
      global<const> *
      global function declared(... args) args = {} end
      local <close> first, second <const> = nil, 2
    ]],
    "5.5"
  )
  luaunit.assertEquals(ast.body[1].scope, "global")
  luaunit.assertEquals(ast.body[2].type, "GlobalWildcardDeclaration")
  luaunit.assertEquals(ast.body[3].scope, "global")
  luaunit.assertEquals(ast.body[3].parameters[1].identifier.name, "args")
  luaunit.assertEquals(ast.body[4].attribute.name, "close")
  luaunit.assertEquals(ast.body[4].variables[2].attribute.name, "const")
end

os.exit(luaunit.LuaUnit.run())
