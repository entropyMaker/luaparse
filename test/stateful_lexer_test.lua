local luaunit = require("luaunit")
local lexer = require("luaparse.lexer")

TestStatefulLexer = {}

function TestStatefulLexer:testPeekAndNext()
  local scanner = lexer.from_string("  local value")
  luaunit.assertEquals({ scanner:peek() }, { "Keyword", "local" })
  luaunit.assertEquals({ scanner:peek() }, { "Keyword", "local" })
  luaunit.assertEquals({ scanner:next() }, { "Keyword", "local" })
  luaunit.assertEquals({ scanner:next() }, { "Identifier", "value" })
  luaunit.assertEquals({ scanner:next() }, { "EOF" })
  luaunit.assertEquals({ scanner:peek() }, { "EOF" })
end

function TestStatefulLexer:testTypedNextDoesNotConsumeMismatch()
  local scanner = lexer.from_string("name")
  luaunit.assertErrorMsgContains(
    "expected token type 'Keyword', got 'Identifier'",
    function() scanner:typed_next("Keyword") end
  )
  luaunit.assertEquals(scanner:typed_next("Identifier"), "name")
end

function TestStatefulLexer:testRawAndDecodedValues()
  local decoded = lexer.from_string('  0x64 "\\x41" true false', {
    lua_version = "5.2",
  })
  luaunit.assertEquals({ decoded:next() }, { "NumberLiteral", 100 })
  luaunit.assertEquals({ decoded:next() }, { "StringLiteral", "A" })
  luaunit.assertEquals({ decoded:next() }, { "BooleanLiteral", true })
  luaunit.assertEquals({ decoded:peek() }, { "BooleanLiteral", false })
  luaunit.assertEquals({ decoded:next() }, { "BooleanLiteral", false })

  local raw = lexer.from_string('  0x64 "\\x41" true', {
    lua_version = "5.2",
    raw = true,
  })
  luaunit.assertEquals({ raw:next() }, { "NumberLiteral", "0x64" })
  luaunit.assertEquals({ raw:next() }, { "StringLiteral", '"\\x41"' })
  luaunit.assertEquals({ raw:next() }, { "BooleanLiteral", "true" })
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

function TestStatefulLexer:testOptionsAndStatelessApiCoexist()
  local scanner = lexer.from_string("goto", { lua_version = "5.2" })
  luaunit.assertEquals(scanner.lua_version, "5.2")
  luaunit.assertFalse(scanner.raw)
  luaunit.assertEquals({ scanner:next() }, { "Keyword", "goto" })

  local stateless = lexer.new({ lua_version = "5.1" })
  luaunit.assertEquals({ stateless:scan_token("goto", 1) }, { "Identifier", 5 })
end

os.exit(luaunit.LuaUnit.run())
