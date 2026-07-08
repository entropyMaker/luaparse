# luaparse

A pure Lua lexer and parser for the Lua programming language.

Repository: https://github.com/entropyMaker/luaparse

The current target is Lua 5.1, following the syntax described in the
[Lua 5.1 reference manual](https://www.lua.org/manual/5.1/manual.html#8).

## Goals

- Pure Lua implementation
- No third-party runtime dependencies
- Lexer and parser for Lua 5.1 source code
- Small, embeddable library interface

## Modules

```lua
local lexer = require("luaparse.lexer")
local parser = require("luaparse.parser")
```

## Status

Early development. The public API and AST format are not finalized yet.
