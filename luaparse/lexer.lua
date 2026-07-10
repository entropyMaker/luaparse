local lexer = {}
local byte = string.byte
local sub = string.sub
local format = string.format

-- Token types: EOF, BooleanLiteral, NumberLiteral, StringLiteral, NilLiteral,
-- VarargLiteral, Keyword, Identifier, Punctuator, Comment.
local token_types = {
  ["EOF"] = true,
  ["BooleanLiteral"] = true,
  ["NumberLiteral"] = true,
  ["StringLiteral"] = true,
  ["NilLiteral"] = true,
  ["VarargLiteral"] = true,
  ["Keyword"] = true,
  ["Identifier"] = true,
  ["Punctuator"] = true,
  ["Comment"] = true,
}

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

local function skip_whitespaces(input, index)
  for i = index, #input do
    local char = byte(input, i)
    -- tab, LF, vertical tab, form feed, CR and space
    if not (9 <= char and char <= 13) and char ~= 32 then return i end
  end
  return #input + 1
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

local function decimal_alphabet(b)
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

local function is_number_continuation(char)
  return char ~= nil
    and (
      (48 <= char and char <= 57) -- 0-9
      or is_identifier_start(char)
      or char == 46 -- .
    )
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
    decimal_alphabet,
    5
  )
end

-- alphabet 1: the quote (single or double but must be consistent when matching)
-- alphabet 2: digits [0-9]
-- alphabet 3: a, b, f, n, r, t, v
--   and another quote (double quote if the quote is single and vice versa)
-- alphabet 4: the escape character "\\" (ascii 92)
-- alphabet 5: a real newline (ascii 10)
-- alphabet 6: a real return (ascii 13)
-- alphabet 7: other byte value
local quote_string_trans_table = {
  { 2, 0, 0, 0, 0, 0, 0 }, -- 1. start
  { 7, 2, 2, 3, 0, 0, 2 }, -- 2. seen one quote and several (or 0) valid characters
  { 2, 4, 2, 2, 2, 6, 0 }, -- 3. just seen "\\"
  { 7, 5, 2, 3, 0, 0, 2 }, -- 4. just seen "\\" and 1 digit
  { 7, 2, 2, 3, 0, 0, 2 }, -- 5. just seen "\\" and 2 digits
  { 7, 2, 2, 3, 2, 0, 2 }, -- 6. just seen "\\" and "\r"
  { 0, 0, 0, 0, 0, 0, 0 }, -- 7. seen the close quote, the only accept state
}

local function quote_string_alphabet(del)
  return function(char)
    if char == del then return 1 end
    if 48 <= char and char <= 57 then return 2 end
    if
      char == 97
      or char == 98
      or char == 102
      or char == 110
      or char == 114
      or char == 116
      or char == 118
      or char == 34
      or char == 39
    then
      return 3
    end

    if char == 92 then return 4 end
    if char == 10 then return 5 end
    if char == 13 then return 6 end
    return 7
  end
end

local single_quote_string_alphabet = quote_string_alphabet(39)
local double_quote_string_alphabet = quote_string_alphabet(34)

local function scan_quote_string(input, index)
  local length = #input
  if index > length then return index end
  local del = byte(input, index)
  if del ~= 34 and del ~= 39 then return index end
  return execute_state_machine(
    input,
    index,
    quote_string_trans_table,
    del == 39 and single_quote_string_alphabet or double_quote_string_alphabet,
    7
  )
end

local function scan_comment(input, index)
  local length = #input
  if
    index >= length
    or byte(input, index) ~= 45 -- -
    or byte(input, index + 1) ~= 45 -- -
  then
    return index
  end

  local long_comment_end = scan_long_string(input, index + 2)
  if long_comment_end > index + 2 then return long_comment_end end

  local i = index + 2
  while i <= length do
    local char = byte(input, i)
    if char == 10 or char == 13 then break end
    i = i + 1
  end

  return i
end

local function scan_punctuator(input, index)
  local length = #input
  if index > length then return index end

  local first = byte(input, index)
  local second = index < length and byte(input, index + 1) or -1
  if
    (first == 61 and second == 61) -- ==
    or (first == 126 and second == 61) -- ~=
    or (first == 60 and second == 61) -- <=
    or (first == 62 and second == 61) -- >=
    or (first == 46 and second == 46) -- ..
  then
    return index + 2
  end

  if
    first == 43 -- +
    or first == 45 -- -
    or first == 42 -- *
    or first == 47 -- /
    or first == 37 -- %
    or first == 94 -- ^
    or first == 35 -- #
    or first == 60 -- <
    or first == 62 -- >
    or first == 61 -- =
    or first == 40 -- (
    or first == 41 -- )
    or first == 123 -- {
    or first == 125 -- }
    or first == 91 -- [
    or first == 93 -- ]
    or first == 59 -- ;
    or first == 58 -- :
    or first == 44 -- ,
    or first == 46 -- .
  then
    return index + 1
  end

  return index
end

local function scan_vararg(input, index)
  local length = #input
  if
    index + 2 > length
    or byte(input, index) ~= 46
    or byte(input, index + 1) ~= 46
    or byte(input, index + 2) ~= 46
  then
    return index
  end
  return index + 3
end

local function scan_token(input, index)
  index = skip_whitespaces(input, index)
  local length = #input
  if index > length then return "EOF", index end

  -- dispatch based on first character
  local first = byte(input, index)
  if is_identifier_start(first) then
    local end_ind = scan_identifier_keyword(input, index)
    local t = keywords[sub(input, index, end_ind - 1)]
    if t == nil then t = "Identifier" end
    return t, end_ind
  elseif 48 <= first and first <= 57 then
    local end_ind = scan_number(input, index)
    if end_ind > index and not is_number_continuation(byte(input, end_ind)) then
      return "NumberLiteral", end_ind
    end
    return format("malformed number near %d", index), index
  elseif first == 46 then -- .
    local end_ind = scan_vararg(input, index)
    if end_ind > index then return "VarargLiteral", end_ind end
    end_ind = scan_number(input, index)
    if end_ind > index then
      if not is_number_continuation(byte(input, end_ind)) then
        return "NumberLiteral", end_ind
      end
      return format("malformed number near %d", index), index
    end
    end_ind = scan_punctuator(input, index)
    if end_ind > index then return "Punctuator", end_ind end
    return format("unknown token after . near %d", index), index
  elseif first == 45 then -- -
    local comment_start = index + 2
    if
      index < length
      and byte(input, index + 1) == 45 -- -
      and scan_long_string_opener(input, comment_start) > comment_start
    then
      local end_ind = scan_long_string(input, comment_start)
      if end_ind > comment_start then return "Comment", end_ind end
      return format("malformed long comment near %d", index), index
    end

    local end_ind = scan_comment(input, index)
    if end_ind > index then return "Comment", end_ind end
    end_ind = scan_punctuator(input, index)
    if end_ind > index then return "Punctuator", end_ind end
    return format("unknown token after - near %d", index), index
  elseif first == 91 then -- [
    if scan_long_string_opener(input, index) > index then
      local end_ind = scan_long_string(input, index)
      if end_ind > index then return "StringLiteral", end_ind end
      return format("malformed long string near %d", index), index
    end

    local end_ind = scan_long_string(input, index)
    if end_ind > index then return "StringLiteral", end_ind end
    end_ind = scan_punctuator(input, index)
    if end_ind > index then return "Punctuator", end_ind end
    return format("unknown token after [ near %d", index), index
  elseif first == 34 or first == 39 then -- " or '
    local end_ind = scan_quote_string(input, index)
    if end_ind > index then return "StringLiteral", end_ind end
    return format("malformed string near %d", index), index
  else
    local end_ind = scan_punctuator(input, index)
    if end_ind > index then return "Punctuator", end_ind end
    return format("unknown token near %d", index), index
  end
end

return lexer
