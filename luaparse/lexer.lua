local lexer = {}
local byte = string.byte

-- Token types: EOF, BooleanLiteral, NumberLiteral, StringLiteral, NilLiteral,
-- VarargLiteral, Keyword, Identifier, Punctuator, Comment.

local keywords = {
  ["false"] = "BooleanLiteral",
  ["true"] = "BooleanLiteral",

  ["nil"] = "NilLiteral",

  ["and"] = "Keyword",
  ["break"] = "Keyword",
  ["do"] = "Keyword",
  ["else"] = "Keyword",
  ["elseif"] = "Keyword",
  ["end"] = "Keyword",
  ["for"] = "Keyword",
  ["function"] = "Keyword",
  ["if"] = "Keyword",
  ["in"] = "Keyword",
  ["local"] = "Keyword",
  ["not"] = "Keyword",
  ["or"] = "Keyword",
  ["repeat"] = "Keyword",
  ["return"] = "Keyword",
  ["then"] = "Keyword",
  ["until"] = "Keyword",
  ["while"] = "Keyword",
}

local function is_identifier_start(c)
  return c == 95 -- _
      or (65 <= c and c <= 90) -- A-Z
      or (97 <= c and c <= 122) -- a-z
end

local function is_identifier_part(c)
  return (48 <= c and c <= 57) -- 0-9
      or is_identifier_start(c)
end

local function scan_identifier(input, index)
  local length = #input
  local i = index + 1

  while i <= length and is_identifier_part(byte(input, i)) do
    i = i + 1
  end

  return i - 1
end

return lexer
