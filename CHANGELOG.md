# Changelog

Notable changes to luaparse are documented in this file.

## 0.1.0 - 2026-07-18

Initial alpha release.

### Added

- Pure Lua lexer with stateless and stateful scanning interfaces.
- Parser support for Lua 5.1 through Lua 5.5 and LuaJIT 2.1.
- Version-aware semantic checking for control flow, labels and gotos,
  read-only bindings, Lua 5.4 variable attributes, and Lua 5.5 global
  declarations.
- Source tokens, comments, byte ranges, and line information suitable for
  source-analysis and formatting tools.
- Automated tests across Lua 5.1, 5.2, 5.3, 5.4, 5.5, and LuaJIT.

### Alpha notice

The public API and AST format may change before the stable release. Runtime
errors and implementation resource limits are outside the semantic checker's
scope.
