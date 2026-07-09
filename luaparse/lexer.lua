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

local function scan_identifier_keyword(input, index)
  local length = #input
  local i = index + 1

  while i <= length and is_identifier_part(byte(input, i)) do
    i = i + 1
  end

  return i
end

local function scan_long_string_opener(input, index)
  local length = #input
  if index > length or byte(input, index) ~= 91 then -- [
    return index
  end

  local i = index + 1
  while i <= length and byte(input, i) == 61 do -- =
    i = i + 1
  end

  return (i <= length and byte(input, i) == 91) and i + 1 or index
end

local function scan_long_string(input, index)
  local i = scan_long_string_opener(input, index)
  if i == index then return index end

  local length = #input
  local level = i - index - 2 -- level is the number of "=" in the opener

  while i <= length do
    if byte(input, i) == 93 then -- ]
      local j = i + 1
      local n = 0

      while n < level and j <= length and byte(input, j) == 61 do -- =
        j = j + 1
        n = n + 1
      end

      if n == level and j <= length and byte(input, j) == 93 then -- ]
        return j + 1
      end

      i = j
    else
      i = i + 1
    end
  end

  return index
end

-- requirements:
-- 1. start state must be 1
-- 2. accept states must be >= accept
-- 3. #alphabet_range == #trans[1] * 2
-- 4. invalid state is represented by 0
-- 5. alphabet_range is a function return alphabet by byte value
local function execute_state_machine(s, index, trans, alphabet_range, accept)
  local state = 1
  local last_accept = index

  for i = index, #s do
    local b = byte(s, i)
    local alphabet = alphabet_range(b)

    if alphabet == 0 then break end
    state = trans[state][alphabet]
    if state == 0 then break end
    if state >= accept then last_accept = i + 1 end
  end
  return last_accept
end

-- based on regexp '(\d+(\.\d*)?|\.\d+)([eE][-+]?\d+)?'
-- \d (i.e. [0-9]) is alphabet 1
-- \. (i.e. the literal ".") is alphabet 2
-- [eE] (i.e. "e" or "E" for exponent) is alphabet 3
-- [-+] (i.e. the positive or negative sign "+" or "-") is alphabet 4
-- accept states: 5, 6, 7, 8
local decimal_trans_table = {
  { 5, 2, 0, 0 }, -- 1 start
  { 7, 0, 0, 0 }, -- 2 leading dot
  { 8, 0, 0, 4 }, -- 3 exponent marker
  { 8, 0, 0, 0 }, -- 4 exponent sign
  { 5, 6, 3, 0 }, -- 5 digits
  { 6, 0, 3, 0 }, -- 6 digits dot
  { 7, 0, 3, 0 }, -- 7 dot digits
  { 8, 0, 0, 0 }, -- 8 exponent digits
}

local function decimal_alphabet_range(b)
  if 48 <= b and b <= 57 then -- 0-9
    return 1
  elseif b == 46 then -- "."
    return 2
  elseif b == 69 or b == 101 then -- "E" or "e"
    return 3
  elseif b == 43 or b == 45 then -- "+" or "-"
    return 4
  end
  return 0
end

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

  return execute_state_machine(
    input,
    index,
    decimal_trans_table,
    decimal_alphabet_range,
    5
  )
end

return lexer
