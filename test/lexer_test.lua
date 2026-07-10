local luaunit = require("luaunit")
local lexer = require("luaparse.lexer")

local function lex(source)
  local tokens = {}
  local index = 1

  while true do
    local token_type, next_index, value = lexer.scan_token_value(source, index)
    luaunit.assertTrue(
      lexer.token_types[token_type] == true,
      string.format("lexer error at byte %d: %s", index, token_type)
    )

    tokens[#tokens + 1] = { token_type, value }
    if token_type == "EOF" then return tokens end

    luaunit.assertTrue(next_index > index, "lexer did not advance")
    index = next_index
  end
end

local function assert_lex_error(source, expected_error)
  local index = 1

  while true do
    local token_type, next_index = lexer.scan_token(source, index)
    if lexer.token_types[token_type] ~= true then
      luaunit.assertEquals(token_type, expected_error)
      luaunit.assertTrue(next_index >= index)
      return
    end

    luaunit.assertNotEquals(token_type, "EOF", "expected a lexer error")
    luaunit.assertTrue(next_index > index, "lexer did not advance")
    index = next_index
  end
end

TestLexerValid = {}

function TestLexerValid:testFunctionWithControlFlow()
  local source = [[
local function max(a, b)
  if a >= b then
    return a
  else
    return b
  end
end
]]

  luaunit.assertEquals(lex(source), {
    { "Keyword", "local" },
    { "Keyword", "function" },
    { "Identifier", "max" },
    { "Punctuator", "(" },
    { "Identifier", "a" },
    { "Punctuator", "," },
    { "Identifier", "b" },
    { "Punctuator", ")" },
    { "Keyword", "if" },
    { "Identifier", "a" },
    { "Punctuator", ">=" },
    { "Identifier", "b" },
    { "Keyword", "then" },
    { "Keyword", "return" },
    { "Identifier", "a" },
    { "Keyword", "else" },
    { "Keyword", "return" },
    { "Identifier", "b" },
    { "Keyword", "end" },
    { "Keyword", "end" },
    { "EOF" },
  })
end

function TestLexerValid:testLiteralValuesAndComments()
  local source = [==[-- heading
local values = { true, false, nil, 42, 0x2a, .5, 1.25e2, "line\n", [=[long
text]=] }
]==]

  luaunit.assertEquals(lex(source), {
    { "Comment", "-- heading" },
    { "Keyword", "local" },
    { "Identifier", "values" },
    { "Punctuator", "=" },
    { "Punctuator", "{" },
    { "BooleanLiteral", true },
    { "Punctuator", "," },
    { "BooleanLiteral", false },
    { "Punctuator", "," },
    { "NilLiteral", "nil" },
    { "Punctuator", "," },
    { "NumberLiteral", 42 },
    { "Punctuator", "," },
    { "NumberLiteral", 42 },
    { "Punctuator", "," },
    { "NumberLiteral", 0.5 },
    { "Punctuator", "," },
    { "NumberLiteral", 125 },
    { "Punctuator", "," },
    { "StringLiteral", "line\n" },
    { "Punctuator", "," },
    { "StringLiteral", "long\ntext" },
    { "Punctuator", "}" },
    { "EOF" },
  })
end

function TestLexerValid:testVarargAndLongComment()
  local source = "--[=[ignored\ntext]=]\nreturn ..."

  luaunit.assertEquals(lex(source), {
    { "Comment", "--[=[ignored\ntext]=]" },
    { "Keyword", "return" },
    { "VarargLiteral", "..." },
    { "EOF" },
  })
end

TestLexerInvalid = {}

function TestLexerInvalid:testMalformedNumbers()
  assert_lex_error("local x = 0x", "malformed number near 11")
  assert_lex_error("return 1e+", "malformed number near 8")
  assert_lex_error("return 123abc", "malformed number near 8")
end

function TestLexerInvalid:testMalformedQuotedStrings()
  assert_lex_error('local x = "unterminated', "malformed string near 11")
  assert_lex_error("return 'line\nbreak'", "malformed string near 8")
  assert_lex_error('return "\\999"', "malformed string near 8")
end

function TestLexerInvalid:testMalformedLongStringsAndComments()
  assert_lex_error("local x = [[unterminated", "malformed long string near 11")
  assert_lex_error("--[=[unterminated", "malformed long comment near 1")
end

function TestLexerInvalid:testUnknownCharacter()
  assert_lex_error("local x = @", "unknown token near 11")
end

os.exit(luaunit.LuaUnit.run())
