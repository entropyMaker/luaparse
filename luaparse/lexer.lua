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

  return i
end

-- based on regexp '(\d+(\.\d*)?|\.\d+)([eE][-+]?\d+)?'
-- \d (i.e. [0-9]) is alphabet 1
-- \. (i.e. the literal ".") is alphabet 2
-- [eE] (i.e. "e" or "E" for exponent) is alphabet 3
-- [-+] (i.e. the positive or negative sign "+" or "-") is alphabet 4
-- accept states: 2, 4, 6, 7
local decimal_trans_table = {
  { 2, 3, 0, 0 },
  { 2, 4, 5, 0 },
  { 6, 0, 0, 0 },
  { 4, 0, 5, 0 },
  { 7, 0, 0, 8 },
  { 6, 0, 5, 0 },
  { 7, 0, 0, 0 },
  { 7, 0, 0, 0 },
}

local function starts_with_0x(input, index)
  if index >= #input or byte(input, index) ~= 48 then -- "."
    return false
  end

  local second = byte(input, index + 1)
  return second == 88 or second == 120 -- "x" or "X"
end

local function is_hex_char(char)
  return (48 <= char and char <= 57) -- 0-9
    or (65 <= char and char <= 70) -- A-F
    or (97 <= char and char <= 102) -- a-f
end

local function scan_number(input, index)
  local length = #input

  if starts_with_0x(input, index) then
    local i = index + 2
    while i <= length and is_hex_char(byte(input, i)) do
      i = i + 1
    end
    return i > index + 2 and i or index
  end

  local state = 1
  local last_accept = index
  for i = index, length do
    local alphabet = 0
    local b = byte(input, i)
    if 48 <= b and b <= 57 then -- 0-9
      alphabet = 1
    elseif b == 46 then -- "."
      alphabet = 2
    elseif b == 69 or b == 101 then -- "E" or "e"
      alphabet = 3
    elseif b == 43 or b == 45 then -- "+" or "-"
      alphabet = 4
    end

    if alphabet == 0 then break end

    state = decimal_trans_table[state][alphabet]
    if state == 0 then break end

    if state == 2 or state == 4 or state == 6 or state == 7 then
      last_accept = i + 1
    end
  end

  return last_accept
end

return lexer
