# luaparse

A pure Lua lexer and parser for the Lua programming language.

Repository: https://github.com/entropyMaker/luaparse

The lexer supports Lua 5.1 through Lua 5.5 and LuaJIT 2.1.

## Goals

- Pure Lua implementation
- No third-party runtime dependencies
- Version-configurable lexer for Lua 5.1 through Lua 5.5 and LuaJIT
- Small, embeddable library interface

## Modules

```lua
local lexer = require("luaparse.lexer")
local parser = require("luaparse.parser")

local lua54 = lexer.new({ lua_version = "5.4" })
local token_type, next_index = lua54:scan_token("local x = 1", 1)

local result = parser.parse("local x = 1")
local chunk = result.ast
```

Supported `lua_version` values are `"5.1"`, `"LuaJIT"`, `"5.2"`, `"5.3"`,
`"5.4"`, and `"5.5"`. The default is `"5.1"`. The `"LuaJIT"` profile models
a build with `LUAJIT_ENABLE_LUA52COMPAT`, so `goto` is a keyword.

`scan_token_value` converts numerals with the host runtime's `tonumber`. It
returns an `unsupported number value` lexer error when the selected profile
accepts a numeral that the host cannot convert.

## Choosing a scanning method

Both scanning methods validate the same version-specific lexical syntax and
return the token type and exclusive end index. They differ in whether they
decode the token value.

Use `scan_token(input, index)` for parsers, formatters, and other source tools
that need to preserve the original spelling. It finds the token boundary
without converting numerals or building decoded string values, so forms such
as `1e2`, `0x64`, `"\x41"`, and long-bracket strings remain available in the
original source.

Use `scan_token_value(input, index)` when semantic values are needed. It
converts numerals with the host's `tonumber`, decodes quoted and long strings,
and converts boolean literals. This is useful for evaluation, constant
analysis, and AST consumers that prefer decoded values, but the result does not
retain the original literal spelling.

```lua
local source = "1e2"

local token_type, end_index = lua54:scan_token(source, 1)
local raw = source:sub(1, end_index - 1)
-- token_type == "NumberLiteral"
-- raw == "1e2"

local value_type, value_end, value = lua54:scan_token_value(source, 1)
-- value_type == "NumberLiteral"
-- value_end == end_index
-- value == 100
```

Both methods skip leading whitespace. The substring example is exact because
the supplied index points directly at the token. A formatter that preserves
trivia should retain whitespace between tokens separately instead of assuming
that every supplied index is the token's first byte.

## Stateful scanning

For sequential scanning, `from_string` stores the input and current position:

```lua
local scanner = lexer.from_string("local answer = 0x2a", {
  lua_version = "5.4",
})

local token = scanner:peek()              -- does not consume "local"
token = scanner:next()                    -- consumes "local"
token = scanner:typed_next("Identifier") -- consumes "answer"
```

Stateful methods return a token table with `type`, `raw`, `value`, `start`, and
`finish` fields. Ranges are one-based, half-open byte offsets around the actual
token and exclude preceding whitespace. `peek()` caches its result, so a
following `peek()`, `next()`, or `typed_next()` does not scan the token again.
`typed_next()` raises an error without consuming the token when its type does
not match. Lexical errors are also raised without advancing.

Every token retains its exact spelling in `raw` and its decoded representation
in `value`. A syntactically valid numeral has a nil value if the host runtime's
`tonumber` cannot convert it. Source tools should treat `raw` as authoritative.
Comments are returned as tokens. EOF has an empty raw spelling and a nil value.

## Parsing

The parser currently implements the Lua 5.1 grammar. Its AST and internal
feature profiles are designed to accommodate later Lua versions, but requesting
a later parser profile currently raises an explicit not-implemented error.

```lua
local result = parser.parse([[
  -- answer
  local value = (compute())
  return value
]], { lua_version = "5.1" })

local chunk = result.ast
local tokens = result.tokens
```

Parsing returns the AST and every significant token and comment in source
order. Comments are also collected in `Chunk.comments` and anchored to
neighboring token indices. Token ranges refer to the source string supplied by
the caller; those ranges and source gaps allow a formatter to preserve comment
placement, literal spelling, parentheses, table separators, shorthand calls,
and optional semicolons without placing source locations on every AST node.

The parser validates contextual Lua 5.1 rules, including assignment targets,
loop-scoped `break`, final-statement placement, and use of `...` only in a
variadic function.

## Caveats

LuaJIT and Lua 5.3 interpreters may impose different limits on the value of a
Unicode escape such as `\u{XXX}`. This lexer consistently accepts values below
2^31 for every profile that supports Unicode escapes and rejects values greater
than or equal to 2^31.

LuaJIT documents that its loader
[skips a UTF-8 BOM](https://luajit.org/extensions.html) at the start of
source code. The lexer does not skip the BOM automatically. Callers that want
the same behavior can detect the leading bytes `EF BB BF` and start the first
scan at byte index `4`; otherwise, start at byte index `1`. Subsequent scans use
the index returned by the previous scan.

## Status

Early development. The public API and AST format are not finalized yet.
