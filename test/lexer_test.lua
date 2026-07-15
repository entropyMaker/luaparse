local luaunit = require("luaunit")
local lexer = require("luaparse.lexer")
local lua51 = lexer.new({ lua_version = "5.1" })

local function lex(source, scanner)
  scanner = scanner or lua51
  local tokens = {}
  local index = 1

  while true do
    local token_type, next_index, value =
      scanner:scan_token_value(source, index)
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

local function assert_lex_error(source, expected_error, scanner)
  scanner = scanner or lua51
  local index = 1

  while true do
    local token_type, next_index = scanner:scan_token(source, index)
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
  local token_type, next_index, value = lua51:scan_token("  true", 1)
  luaunit.assertEquals(token_type, "BooleanLiteral")
  luaunit.assertEquals(next_index, 7)
  luaunit.assertNil(value)

  token_type, next_index = lua51:scan_token("   ", 1)
  luaunit.assertEquals(token_type, "EOF")
  luaunit.assertEquals(next_index, 4)

  token_type, next_index = lua51:scan_token("", 1)
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

TestLexerVersions = {}

function TestLexerVersions:testConstructorAndProfileIsolation()
  local default_lexer = lexer.new()
  local luajit = lexer.new({ lua_version = "LuaJIT" })
  local lua52 = lexer.new({ lua_version = "5.2" })
  local lua55 = lexer.new({ lua_version = "5.5" })

  luaunit.assertEquals(default_lexer.lua_version, "5.1")
  luaunit.assertNil(lexer.scan_token)
  luaunit.assertErrorMsgContains(
    "unsupported Lua version",
    function() lexer.new({ lua_version = "5.6" }) end
  )

  luaunit.assertEquals(lex("goto global", default_lexer), {
    { "Identifier", "goto" },
    { "Identifier", "global" },
    { "EOF" },
  })
  luaunit.assertEquals(lex("goto global", luajit), {
    { "Identifier", "goto" },
    { "Identifier", "global" },
    { "EOF" },
  })
  luaunit.assertEquals(lex("goto global", lua52), {
    { "Keyword", "goto" },
    { "Identifier", "global" },
    { "EOF" },
  })
  luaunit.assertEquals(lex("goto global", lua55), {
    { "Keyword", "goto" },
    { "Keyword", "global" },
    { "EOF" },
  })
end

function TestLexerVersions:testPunctuatorProfiles()
  local lua52 = lexer.new({ lua_version = "5.2" })
  local lua53 = lexer.new({ lua_version = "5.3" })

  luaunit.assertEquals(lex("::", lua51), {
    { "Punctuator", ":" },
    { "Punctuator", ":" },
    { "EOF" },
  })
  luaunit.assertEquals(lex("::", lua52), {
    { "Punctuator", "::" },
    { "EOF" },
  })
  luaunit.assertEquals(lex("& ~ | << >> // ~=", lua53), {
    { "Punctuator", "&" },
    { "Punctuator", "~" },
    { "Punctuator", "|" },
    { "Punctuator", "<<" },
    { "Punctuator", ">>" },
    { "Punctuator", "//" },
    { "Punctuator", "~=" },
    { "EOF" },
  })
  assert_lex_error("&", "unknown token near 1", lua52)
end

function TestLexerVersions:testStandardNumberProfiles()
  local lua52 = lexer.new({ lua_version = "5.2" })
  luaunit.assertEquals(
    lex("0x0.1E 0xA23p-4 0X1.921FB54442D18P+1 0x.8p0 0x1.", lua52),
    {
      { "NumberLiteral", 0.1171875 },
      { "NumberLiteral", 162.1875 },
      { "NumberLiteral", math.pi },
      { "NumberLiteral", 0.5 },
      { "NumberLiteral", 1 },
      { "EOF" },
    }
  )
  assert_lex_error("0x1p2", "malformed number near 1", lua51)
  assert_lex_error("0x1p", "malformed number near 1", lua52)
  assert_lex_error("0x.p1", "malformed number near 1", lua52)

  local empty_hex_mantissas = { "0x", "0x,", "0x ", "0xp1" }
  for _, version in ipairs({ "5.2", "5.3", "5.4", "5.5" }) do
    local scanner = lexer.new({ lua_version = version })
    for _, source in ipairs(empty_hex_mantissas) do
      assert_lex_error(source, "malformed number near 1", scanner)
    end
  end
end

function TestLexerVersions:testLuaJITNumberForms()
  local luajit_lexer = lexer.new({ lua_version = "LuaJIT" })
  local forms = { "0b101", "123LL", "123ULL", "2i", "0x1.5p-3" }

  for _, source in ipairs(forms) do
    local token_type, next_index = luajit_lexer:scan_token(source, 1)
    luaunit.assertEquals(token_type, "NumberLiteral")
    luaunit.assertEquals(next_index, #source + 1)
  end

  local token_type, next_index, value =
    luajit_lexer:scan_token_value("0b101", 1)
  if tonumber("0b101") == nil then
    luaunit.assertEquals(token_type, "unsupported number value near 1")
    luaunit.assertEquals(next_index, 1)
    luaunit.assertNil(value)
  else
    luaunit.assertEquals(token_type, "NumberLiteral")
    luaunit.assertEquals(value, 5)
  end

  token_type, next_index = luajit_lexer:scan_token_value("123LL", 1)
  luaunit.assertEquals(token_type, "unsupported number value near 1")
  luaunit.assertEquals(next_index, 1)
end

function TestLexerVersions:testStringEscapeProfiles()
  local lua52 = lexer.new({ lua_version = "5.2" })
  local lua53 = lexer.new({ lua_version = "5.3" })

  luaunit.assertEquals(lex('"\\x41\\z  \n\tB"', lua52), {
    { "StringLiteral", "AB" },
    { "EOF" },
  })
  luaunit.assertEquals(lex([["\u{41}\u{1F600}"]], lua53), {
    { "StringLiteral", "A" .. string.char(0xf0, 0x9f, 0x98, 0x80) },
    { "EOF" },
  })
  luaunit.assertEquals(lex([["\y"]], lua51), {
    { "StringLiteral", "y" },
    { "EOF" },
  })
  assert_lex_error([["\y"]], "malformed string near 1", lua52)
  assert_lex_error([["\u{41}"]], "malformed string near 1", lua52)
  assert_lex_error([["\x4G"]], "malformed string near 1", lua52)
  assert_lex_error([["\u{}"]], "malformed string near 1", lua53)
end

function TestLexerVersions:testLuaJITIdentifiers()
  local luajit_lexer = lexer.new({ lua_version = "LuaJIT" })
  local utf8_name = "caf" .. string.char(0xc3, 0xa9)

  luaunit.assertEquals(lex("local " .. utf8_name, luajit_lexer), {
    { "Keyword", "local" },
    { "Identifier", utf8_name },
    { "EOF" },
  })
  assert_lex_error(
    utf8_name,
    "unknown token near 4",
    lexer.new({ lua_version = "5.2" })
  )
end

function TestLexerVersions:testLua51LocaleIdentifiersWhenAvailable()
  local original_locale = os.setlocale(nil, "ctype")
  local locales = {
    original_locale,
    "en_US.ISO8859-1",
    "en_SG.ISO8859-1",
    "fr_FR.ISO8859-1",
    "de_DE.ISO8859-15",
  }
  local locale_letter

  for _, locale in ipairs(locales) do
    if locale ~= nil and os.setlocale(locale, "ctype") ~= nil then
      for value = 128, 255 do
        local character = string.char(value)
        if string.match(character, "%a") ~= nil then
          locale_letter = character
          break
        end
      end
    end
    if locale_letter ~= nil then break end
  end

  if locale_letter == nil then
    os.setlocale(original_locale, "ctype")
    return
  end

  local ok, tokens =
    pcall(lex, locale_letter .. "name name" .. locale_letter .. "2")
  os.setlocale(original_locale, "ctype")
  luaunit.assertTrue(ok, tokens)
  luaunit.assertEquals(tokens, {
    { "Identifier", locale_letter .. "name" },
    { "Identifier", "name" .. locale_letter .. "2" },
    { "EOF" },
  })
end

os.exit(luaunit.LuaUnit.run())
