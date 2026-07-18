# luaparse

A pure Lua lexer and parser for the Lua programming language.

Repository: https://github.com/entropyMaker/luaparse

The lexer and parser support Lua 5.1 through Lua 5.5 and LuaJIT 2.1.

## Goals

- Pure Lua implementation
- No third-party runtime dependencies
- Version-configurable lexer and parser for Lua 5.1 through Lua 5.5 and LuaJIT
- Small, embeddable library interface

## Installation

The alpha release can be installed from LuaRocks:

```sh
luarocks install luaparse 0.1.0-1
```

To install directly from a source checkout instead:

```sh
luarocks make luaparse-0.1.0-1.rockspec
```

The package has no third-party runtime dependencies and supports Lua 5.1
through Lua 5.5 and LuaJIT 2.1.

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
the default mode without `LUAJIT_ENABLE_LUA52COMPAT`, where `goto` is a
contextual keyword and standalone semicolons are not accepted.

`scan_token_value` converts numerals with the host runtime's `tonumber`. It
returns an `unsupported number value` lexer error when the selected profile
accepts a numeral that the host cannot convert.

## Public API and complexity

The complexity bounds below use `n` for the source byte length or AST node
count, `k` for the bytes in one token plus its leading whitespace, `d` for the
maximum active semantic-scope depth, and `h` for syntactic or AST nesting
depth. Space bounds exclude caller-owned input but include returned and cached
values. Table access is expected O(1).

### `luaparse.lexer`

| API | Behavior | Worst case |
| --- | --- | --- |
| `lexer.token_types` | Set of token type names returned by scanners. Treat it as read-only. | O(1) expected lookup. |
| `lexer.new([options])` | Creates a stateless lexer. `options.lua_version` defaults to `"5.1"`. | O(1) time and space. |
| `scanner:scan_token(input, index)` | Skips whitespace at the one-based byte index and returns a token type and exclusive end index. A lexical failure returns an error string and the original index. | O(k) time and O(1) auxiliary space. |
| `scanner:scan_token_value(input, index)` | Scans as above and also returns the decoded token value. | O(k) time and O(k) space for decoded strings. |
| `lexer.from_string(input[, options])` | Creates a stateful lexer at byte one and retains the input. | O(1) construction time and space. |
| `scanner:peek()` | Returns the next token without consuming it and raises on lexical failure. | First peek is O(k) time and O(k) cache/output space; repeated peeks are O(1). |
| `scanner:next()` | Returns and consumes the next token and raises on lexical failure. | O(k) time and O(k) output space. |
| `scanner:typed_next(expected_type)` | Acts like `next`, but raises without consuming when the type differs. | Same as `next`. |

A complete sequential scan is O(n) time. The stateful scanner retains only the
input, its position, and at most one cached token, so its auxiliary space is
O(k) beyond returned tokens.

### `luaparse.parser`

| API | Behavior | Worst case |
| --- | --- | --- |
| `parser.node_fields` | Maps every AST node type to all fields it can contain across supported profiles. Treat it as read-only. | O(1) expected lookup. |
| `parser.parse(source[, options])` | Returns `{ ast = chunk, tokens = tokens }`; `options.lua_version` defaults to `"5.1"`. Lexical and syntax failures raise errors. | O(n) time and O(n) space, including the AST and retained tokens; O(h) recursive stack space. |

### `luaparse.semantic`

| API | Behavior | Worst case |
| --- | --- | --- |
| `semantic.check(ast[, options])` | Checks a parser-produced `Chunk` without modifying it and returns source-ordered `{ message, line }` diagnostics. `options.lua_version` defaults to `"5.1"`. Invalid arguments raise errors; semantic violations do not. | O(n²) time and O(n) space, with O(h) recursive stack space. |

The ordinary semantic traversal is O(n*d), because resolving an identifier can
walk every active scope. It reaches O(n²) with both linearly deep scope nesting
and linearly many references at the deepest point. Goto and label validation
also has an O(n²) worst case when many gotos repeatedly scan a long interval or
walk a deep block ancestry. With bounded scope depth and sparse, nearby gotos,
semantic checking is effectively O(n).

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

Every token retains its exact spelling in `raw`, its decoded representation in
`value`, and its one-based source line in `line`. A syntactically valid numeral
has a nil value if the host runtime's `tonumber` cannot convert it. Source tools
should treat `raw` as authoritative. Comments are returned as tokens. EOF has
an empty raw spelling and a nil value.

## Parsing

The parser implements the Lua 5.1 through Lua 5.5 grammars and the default
LuaJIT 2.1 grammar.

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

The parser validates grammar only. Semantic checking is a separate, optional
pass over the returned AST:

```lua
local semantic = require("luaparse.semantic")

local diagnostics = semantic.check(chunk, { lua_version = "5.4" })
for _, diagnostic in ipairs(diagnostics) do
  print(diagnostic.line, diagnostic.message)
end
```

`semantic.check` supports the same version profiles and defaults to Lua 5.1.
It returns all manual-defined semantic violations in source order as tables
with `line` and `message` fields; an empty list means the AST passed the check.
It does not mutate the AST or raise errors for semantic violations.

The checker covers loop-scoped `break`, variadic-expression context, labels and
gotos, Lua 5.4 attributes and read-only variables, and Lua 5.5 global
declarations and additional read-only bindings. LuaJIT uses Lua 5.1 semantics
plus its Lua 5.2-style goto extension. Diagnostic-bearing AST nodes retain a
one-based `line`; other AST nodes remain location-free.

Runtime failures are deliberately outside the checker. For example, a zero
numeric-for step, a non-closable value assigned to a `close` variable, invalid
operand types, and a Lua 5.5 initialized global that already has a value are
accepted by this pass. Implementation resource limits are likewise excluded.

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

The lexer and parser also do not automatically skip a shebang line at the start
of source code. Callers that want to parse files beginning with `#!` should
detect and remove or skip that line before passing the source to this library.

## Status

Alpha. The public API and AST format are not finalized yet. See the
[changelog](CHANGELOG.md) for release notes.
