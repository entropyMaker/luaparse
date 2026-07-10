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

function TestLexerValid:testAllKeywordsAndKeywordLikeIdentifiers()
  local source = table.concat({
    "and",
    "break",
    "do",
    "else",
    "elseif",
    "end",
    "false",
    "for",
    "function",
    "if",
    "in",
    "local",
    "nil",
    "not",
    "or",
    "repeat",
    "return",
    "then",
    "true",
    "until",
    "while",
    "android",
    "True",
    "local_",
    "abcdefgh",
    "abcdefghi",
    "_name",
    "name2",
  }, " ")

  local tokens = lex(source)
  local expected_types = {
    "Keyword",
    "Keyword",
    "Keyword",
    "Keyword",
    "Keyword",
    "Keyword",
    "BooleanLiteral",
    "Keyword",
    "Keyword",
    "Keyword",
    "Keyword",
    "Keyword",
    "NilLiteral",
    "Keyword",
    "Keyword",
    "Keyword",
    "Keyword",
    "Keyword",
    "BooleanLiteral",
    "Keyword",
    "Keyword",
    "Identifier",
    "Identifier",
    "Identifier",
    "Identifier",
    "Identifier",
    "Identifier",
    "Identifier",
  }

  for i, expected_type in ipairs(expected_types) do
    luaunit.assertEquals(tokens[i][1], expected_type)
  end
  luaunit.assertEquals(tokens[#tokens], { "EOF" })
end

function TestLexerValid:testPunctuatorsAndDotPrefixes()
  luaunit.assertEquals(
    lex("+ - * / % ^ # == ~= <= >= < > = ( ) { } [ ] ; : , . .. ..."),
    {
      { "Punctuator", "+" },
      { "Punctuator", "-" },
      { "Punctuator", "*" },
      { "Punctuator", "/" },
      { "Punctuator", "%" },
      { "Punctuator", "^" },
      { "Punctuator", "#" },
      { "Punctuator", "==" },
      { "Punctuator", "~=" },
      { "Punctuator", "<=" },
      { "Punctuator", ">=" },
      { "Punctuator", "<" },
      { "Punctuator", ">" },
      { "Punctuator", "=" },
      { "Punctuator", "(" },
      { "Punctuator", ")" },
      { "Punctuator", "{" },
      { "Punctuator", "}" },
      { "Punctuator", "[" },
      { "Punctuator", "]" },
      { "Punctuator", ";" },
      { "Punctuator", ":" },
      { "Punctuator", "," },
      { "Punctuator", "." },
      { "Punctuator", ".." },
      { "VarargLiteral", "..." },
      { "EOF" },
    }
  )
end

function TestLexerValid:testQuotedStringEscapes()
  local source = [==['\a\b\f\n\r\t\v\\\'\"' "\065\66\067\0\255\q"]==]
  luaunit.assertEquals(lex(source), {
    { "StringLiteral", "\a\b\f\n\r\t\v\\'\"" },
    { "StringLiteral", "ABC" .. string.char(0, 255) .. "q" },
    { "EOF" },
  })
end

function TestLexerValid:testEscapedAndLongStringNewlinesAreNormalized()
  luaunit.assertEquals(lex('"a\\\r\nb\\\n\rc\\\rd"'), {
    { "StringLiteral", "a\nb\nc\nd" },
    { "EOF" },
  })

  luaunit.assertEquals(lex("[=[\r\nfirst\rsecond\n\rthird]=]"), {
    { "StringLiteral", "first\nsecond\nthird" },
    { "EOF" },
  })
end

function TestLexerValid:testNumberFormsAndBoundaries()
  luaunit.assertEquals(lex("0 00 123. .25 2e3 2E-3 2e+3 0XfF"), {
    { "NumberLiteral", 0 },
    { "NumberLiteral", 0 },
    { "NumberLiteral", 123 },
    { "NumberLiteral", 0.25 },
    { "NumberLiteral", 2000 },
    { "NumberLiteral", 0.002 },
    { "NumberLiteral", 2000 },
    { "NumberLiteral", 255 },
    { "EOF" },
  })
end

function TestLexerValid:testWhitespaceAndCommentBoundaries()
  luaunit.assertEquals(lex("\t\v\f\r\n -- one\r-- two\n-- final"), {
    { "Comment", "-- one" },
    { "Comment", "-- two" },
    { "Comment", "-- final" },
    { "EOF" },
  })
end

function TestLexerValid:testLongStringUsesMatchingDelimiterLevel()
  luaunit.assertEquals(lex("[==[left ]=] right ]==]"), {
    { "StringLiteral", "left ]=] right " },
    { "EOF" },
  })
end

function TestLexerValid:testScanTokenWithoutValues()
  local token_type, next_index, value = lexer.scan_token("  true", 1)
  luaunit.assertEquals(token_type, "BooleanLiteral")
  luaunit.assertEquals(next_index, 7)
  luaunit.assertNil(value)

  token_type, next_index = lexer.scan_token("   ", 1)
  luaunit.assertEquals(token_type, "EOF")
  luaunit.assertEquals(next_index, 4)

  token_type, next_index = lexer.scan_token("", 1)
  luaunit.assertEquals(token_type, "EOF")
  luaunit.assertEquals(next_index, 1)
end

TestLexerInvalid = {}

function TestLexerInvalid:testMalformedNumbers()
  assert_lex_error("local x = 0x", "malformed number near 11")
  assert_lex_error("return 1e+", "malformed number near 8")
  assert_lex_error("return 123abc", "malformed number near 8")
  assert_lex_error("1.2.3", "malformed number near 1")
  assert_lex_error("0xg", "malformed number near 1")
  assert_lex_error("0xffz", "malformed number near 1")
  assert_lex_error("1e", "malformed number near 1")
end

function TestLexerInvalid:testMalformedQuotedStrings()
  assert_lex_error('local x = "unterminated', "malformed string near 11")
  assert_lex_error("return 'line\nbreak'", "malformed string near 8")
  assert_lex_error('return "\\999"', "malformed string near 8")
  assert_lex_error('"ends with \\', "malformed string near 1")
  assert_lex_error("'carriage\rreturn'", "malformed string near 1")
end

function TestLexerInvalid:testMalformedLongStringsAndComments()
  assert_lex_error("local x = [[unterminated", "malformed long string near 11")
  assert_lex_error("--[=[unterminated", "malformed long comment near 1")
end

function TestLexerInvalid:testUnknownCharacter()
  assert_lex_error("local x = @", "unknown token near 11")
end

function TestLexerInvalid:testLongStringLikeBracketIsStillPunctuation()
  luaunit.assertEquals(lex("[=x"), {
    { "Punctuator", "[" },
    { "Punctuator", "=" },
    { "Identifier", "x" },
    { "EOF" },
  })
end

os.exit(luaunit.LuaUnit.run())
