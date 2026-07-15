package = "luaparse"
version = "dev-1"

source = {
  url = "git://github.com/entropyMaker/luaparse.git",
}

description = {
  summary = "Pure Lua lexer and parser for multiple Lua versions",
  detailed = [[
luaparse is a pure Lua lexer and parser for the Lua programming language,
with version-configurable support for Lua 5.1 through Lua 5.5 and LuaJIT.
]],
  homepage = "https://github.com/entropyMaker/luaparse",
  license = "MIT",
}

dependencies = {
  "lua >= 5.1",
}

build = {
  type = "builtin",
  modules = {
    ["luaparse.lexer"] = "luaparse/lexer.lua",
    ["luaparse.parser"] = "luaparse/parser.lua",
  },
}
