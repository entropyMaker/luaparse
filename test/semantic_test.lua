local luaunit = require("luaunit")
local parser = require("luaparse.parser")
local semantic = require("luaparse.semantic")

local versions = { "5.1", "LuaJIT", "5.2", "5.3", "5.4", "5.5" }
local goto_versions = { "LuaJIT", "5.2", "5.3", "5.4", "5.5" }

local function check(source, lua_version)
  local ast = parser.parse(source, { lua_version = lua_version }).ast
  return semantic.check(ast, { lua_version = lua_version })
end

local function messages(source, lua_version)
  local result = {}
  for _, diagnostic in ipairs(check(source, lua_version)) do
    result[#result + 1] = diagnostic.message
  end
  return result
end

local function assert_valid(source, lua_version)
  luaunit.assertEquals(check(source, lua_version), {})
end

local function assert_messages(source, lua_version, expected)
  luaunit.assertEquals(messages(source, lua_version), expected)
end

TestSemantic = {}

function TestSemantic:testBreakAndVarargContexts()
  for _, version in ipairs(versions) do
    assert_messages("break", version, { "break outside loop near 'break'" })
    assert_valid("while true do break end", version)
    assert_messages(
      "while true do local f = function() break end end",
      version,
      { "break outside loop near 'break'" }
    )

    assert_valid("return ...", version)
    assert_messages(
      "function f() return ... end",
      version,
      { "cannot use '...' outside a vararg function near '...'" }
    )
    assert_valid("function f(...) return ... end", version)
    assert_messages(
      "function f(...) local g = function() return ... end end",
      version,
      { "cannot use '...' outside a vararg function near '...'" }
    )
  end
end

function TestSemantic:testGotoResolutionAndDeclarationScopes()
  for _, version in ipairs(goto_versions) do
    assert_messages(
      "goto missing",
      version,
      { "no visible label 'missing' for <goto> at line 1" }
    )
    assert_messages(
      "::same:: ::same::",
      version,
      { 'label "same" on line 1 already defined on line 1' }
    )
    assert_messages(
      [[
        local function use() end
        goto target
        local value
        ::target:: use(value)
      ]],
      version,
      { "<goto target> at line 2 jumps into the scope of 'value'" }
    )
    assert_valid("goto target; local value; ::target::", version)
    assert_valid("goto target; local value; ::target:: ::trailing::", version)
    assert_valid("::target:: local value; goto target", version)
    assert_valid("::outer:: do goto outer end", version)
    assert_valid("do goto outer end; ::outer::", version)
    assert_messages(
      "goto inner; do ::inner:: end",
      version,
      { "no visible label 'inner' for <goto> at line 1" }
    )
    assert_messages(
      "::outer:: local f = function() goto outer end",
      version,
      { "no visible label 'outer' for <goto> at line 1" }
    )
    assert_messages(
      "goto target; local function value() end; ::target:: value()",
      version,
      { "<goto target> at line 1 jumps into the scope of 'value'" }
    )
    assert_messages(
      "do goto target end; local value; ::target:: value = value",
      version,
      { "<goto target> at line 1 jumps into the scope of 'value'" }
    )
  end
end

function TestSemantic:testLabelShadowingChangedInLua54()
  local code = "::label:: do ::label:: goto label end"
  for _, version in ipairs({ "LuaJIT", "5.2", "5.3" }) do
    assert_valid(code, version)
  end
  for _, version in ipairs({ "5.4", "5.5" }) do
    assert_messages(
      code,
      version,
      { 'label "label" on line 1 already defined on line 1' }
    )
    assert_messages(
      "-- comment\n::label::\n::label::",
      version,
      { 'label "label" on line 3 already defined on line 2' }
    )
  end
end

function TestSemantic:testLaterOuterLabelAllowedInLua54and55()
  for _, version in ipairs({ "5.4", "5.5" }) do
    assert_valid("do ::label:: goto label end ::label::", version)
  end
end

local nearest_label_source = [[
  do
    goto label
    local value
    ::label:: value = value
  end
  ::label::
]]

function TestSemantic:testGotoChoosesNearestLabel()
  for _, version in ipairs({ "LuaJIT", "5.2", "5.3", "5.4", "5.5" }) do
    assert_messages(
      nearest_label_source,
      version,
      { "<goto label> at line 2 jumps into the scope of 'value'" }
    )
  end
end

function TestSemantic:testLabelsAreIndependentAcrossBlocksAndFunctions()
  for _, version in ipairs(goto_versions) do
    assert_valid("do ::label:: end do ::label:: end", version)
    assert_valid(
      "::label:: local f = function() ::label:: goto label end; goto label",
      version
    )
  end
end

function TestSemantic:testTrailingVoidStatementsEndLocalScope()
  for _, version in ipairs({ "5.2", "5.3", "5.4", "5.5" }) do
    assert_valid(
      "goto target; local value; ; ::target:: ; ::trailing:: ;",
      version
    )
  end
end

function TestSemantic:testLua54AttributesAndReadOnlyBindings()
  for _, version in ipairs({ "5.4", "5.5" }) do
    assert_messages(
      "local value<unknown>",
      version,
      { "unknown attribute 'unknown'" }
    )
    assert_messages(
      "local first<close>, second<close>",
      version,
      { "multiple to-be-closed variables in local list" }
    )
    assert_messages(
      "local value<const> = 1; value = 2",
      version,
      { "attempt to assign to const variable 'value'" }
    )
    assert_messages(
      "local value<close> = nil; value = nil",
      version,
      { "attempt to assign to const variable 'value'" }
    )
    assert_messages(
      "local value<const> = 1; local f = function() value = 2 end",
      version,
      { "attempt to assign to const variable 'value'" }
    )
    assert_valid("local value<const> = {}; value.field = 1", version)
    assert_valid(
      "local value<const> = 1; do local value; value = 2 end",
      version
    )
    assert_messages(
      "local f<const>; function f() end",
      version,
      { "attempt to assign to const variable 'f'" }
    )
    assert_valid("local f<const>; local function f() end", version)
  end
end

function TestSemantic:testLua55AttributeDefaults()
  assert_valid("local<close> first<const>, second = 1, nil", "5.5")
  assert_messages(
    "local<const> first<close>, second<close>",
    "5.5",
    { "multiple to-be-closed variables in local list" }
  )
  assert_messages(
    "global value<close>",
    "5.5",
    { "global variables cannot be to-be-closed" }
  )
  assert_messages(
    "global<close> value<const>",
    "5.5",
    { "global variables cannot be to-be-closed" }
  )
end

function TestSemantic:testLua55GlobalDeclarations()
  assert_messages(
    "global declared; declared = missing",
    "5.5",
    { "variable 'missing' not declared" }
  )
  assert_messages(
    "global declared; missing = declared",
    "5.5",
    { "variable 'missing' not declared" }
  )
  assert_valid("do global declared; declared = 1 end; implicit = 2", "5.5")
  assert_valid("global *; do global declared; implicit = 1 end", "5.5")
  assert_messages(
    "global<const> *; value = 1",
    "5.5",
    { "attempt to assign to const variable 'value'" }
  )
  assert_messages(
    "global mutable; global<const> *; mutable = 1; other = 2",
    "5.5",
    { "attempt to assign to const variable 'other'" }
  )
  assert_messages(
    "global existing; global new = new",
    "5.5",
    { "variable 'new' not declared" }
  )
  assert_valid("global function recursive() return recursive() end", "5.5")
  assert_valid(
    "global recursive<const>; global function recursive() end",
    "5.5"
  )
  assert_valid("global Table; function Table:method() self = self end", "5.5")
  assert_valid(
    "global source, result; result = { field = source, [source] = source }",
    "5.5"
  )
  assert_valid("global _ENV; _ENV = {}", "5.5")
end

function TestSemantic:testLua55ReadOnlyImplicitBindings()
  assert_messages(
    "for index = 1, 2 do index = 3 end",
    "5.5",
    { "attempt to assign to const variable 'index'" }
  )
  assert_messages(
    "for key, value in next, {} do key = value end",
    "5.5",
    { "attempt to assign to const variable 'key'" }
  )
  assert_valid("for key, value in next, {} do value = key end", "5.5")
  assert_messages(
    "function f(... arguments) arguments = {} end",
    "5.5",
    { "attempt to assign to const variable 'arguments'" }
  )
  assert_valid("function f(... arguments) arguments[1] = 1 end", "5.5")
  assert_valid("for index = 1, 2 do index = 3 end", "5.4")
end

function TestSemantic:testRepeatConditionSharesBodyScope()
  assert_valid("global<const> *; repeat local value = 1 until value", "5.5")
  for _, version in ipairs(goto_versions) do
    assert_messages(
      "repeat goto target; local value; ::target:: until true",
      version,
      { "<goto target> at line 1 jumps into the scope of 'value'" }
    )
  end
end

function TestSemantic:testLua55GotoIncludesGlobalDeclarations()
  assert_messages(
    [[
      global print
      goto target
      global value
      ::target:: print(value)
    ]],
    "5.5",
    { "<goto target> at line 2 jumps into the scope of 'value'" }
  )
  assert_valid("global print; goto target; global value; ::target::", "5.5")
  assert_messages(
    "goto target; global *; ::target:: value = 1",
    "5.5",
    { "<goto target> at line 1 jumps into the scope of '*'" }
  )
  assert_valid("goto target; global *; ::target::", "5.5")
  assert_messages(
    [[
      global result
      goto target
      global function value() end
      ::target:: result = value
    ]],
    "5.5",
    { "<goto target> at line 2 jumps into the scope of 'value'" }
  )
end

function TestSemantic:testCollectsDiagnosticsWithLogicalLines()
  local diagnostics = check(
    "global print\r\nbreak\n\rmissing = 1\r--[[line\nline]]\r\nlocal value<bad>",
    "5.5"
  )
  luaunit.assertEquals(diagnostics, {
    { message = "break outside loop near 'break'", line = 2 },
    { message = "variable 'missing' not declared", line = 3 },
    { message = "unknown attribute 'bad'", line = 6 },
  })
end

function TestSemantic:testRuntimeFailuresAreNotSemanticFailures()
  assert_valid(
    [[
      global resource, existing, value
      local closing<close> = 1
      for index = 1, 2, 0 do end
      global existing = 2
      value = nil + {}
    ]],
    "5.5"
  )
end

function TestSemantic:testApiValidation()
  luaunit.assertErrorMsgContains(
    "ast must be a Chunk node",
    function() semantic.check({ type = "Identifier", body = {} }) end
  )
  luaunit.assertErrorMsgContains(
    "unsupported Lua version",
    function()
      semantic.check({ type = "Chunk", body = {} }, { lua_version = "5.6" })
    end
  )
end

os.exit(luaunit.LuaUnit.run())
