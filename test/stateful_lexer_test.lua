local luaunit = require("luaunit")
local lexer = require("luaparse.lexer")

TestStatefulLexer = {}

function TestStatefulLexer:testPeekAndNextReturnTokenObjects()
  local scanner = lexer.from_string("  local value")
  local peeked = scanner:peek()
  luaunit.assertEquals(peeked, {
    type = "Keyword",
    raw = "local",
    value = "local",
    start = 3,
    finish = 8,
  })
  luaunit.assertIs(peeked, scanner:peek())
  luaunit.assertIs(peeked, scanner:next())
  luaunit.assertEquals(scanner:next().raw, "value")
  local eof = scanner:next()
  luaunit.assertEquals(eof.type, "EOF")
  luaunit.assertEquals(eof.start, 14)
  luaunit.assertIs(eof, scanner:peek())
end

function TestStatefulLexer:testTypedNextDoesNotConsumeMismatch()
  local scanner = lexer.from_string("name")
  luaunit.assertErrorMsgContains(
    "expected token type 'Keyword', got 'Identifier'",
    function() scanner:typed_next("Keyword") end
  )
  local token = scanner:typed_next("Identifier")
  luaunit.assertEquals(token.raw, "name")
end

function TestStatefulLexer:testRawAndDecodedValuesTogether()
  local scanner = lexer.from_string('  0x64 "\\x41" true nil', {
    lua_version = "5.2",
  })
  local number = scanner:next()
  luaunit.assertEquals(number.raw, "0x64")
  luaunit.assertEquals(number.value, 100)
  local string_token = scanner:next()
  luaunit.assertEquals(string_token.raw, '"\\x41"')
  luaunit.assertEquals(string_token.value, "A")
  luaunit.assertEquals(scanner:next().value, true)
  luaunit.assertNil(scanner:next().value)
end

function TestStatefulLexer:testCommentsAndRanges()
  local scanner = lexer.from_string("x -- note\ny")
  luaunit.assertEquals(scanner:next().start, 1)
  local comment = scanner:next()
  luaunit.assertEquals(comment.type, "Comment")
  luaunit.assertEquals(comment.raw, "-- note")
  luaunit.assertEquals(comment.start, 3)
  luaunit.assertEquals(comment.finish, 10)
  luaunit.assertEquals(scanner:next().start, 11)
end

function TestStatefulLexer:testLexicalErrorDoesNotAdvance()
  local scanner = lexer.from_string("@")
  luaunit.assertErrorMsgContains(
    "unknown token near 1",
    function() scanner:peek() end
  )
  luaunit.assertErrorMsgContains(
    "unknown token near 1",
    function() scanner:next() end
  )
end

function TestStatefulLexer:testStatelessApiStillCoexists()
  local scanner = lexer.from_string("goto", { lua_version = "5.2" })
  luaunit.assertEquals(scanner:next().type, "Keyword")

  local stateless = lexer.new({ lua_version = "5.1" })
  luaunit.assertEquals({ stateless:scan_token("goto", 1) }, { "Identifier", 5 })
end

os.exit(luaunit.LuaUnit.run())
