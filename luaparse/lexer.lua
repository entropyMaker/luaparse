local byte = string.byte
local chr = string.char
local sub = string.sub
local gsub = string.gsub
local format = string.format
local table_concat = table.concat
local tonumber = tonumber

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

local escaped2char = {
  [97] = "\a",
  [98] = "\b",
  [102] = "\f",
  [110] = "\n",
  [114] = "\r",
  [116] = "\t",
  [118] = "\v",
  [92] = "\\",
  [39] = "'",
  [34] = '"',
}

local function is_identifier_start(c)
  return c == 95 -- _
    or (65 <= c and c <= 90) -- A-Z
    or (97 <= c and c <= 122) -- a-z
end

local function is_digit(c)
  return 48 <= c and c <= 57 -- 0-9
end

local function is_identifier_part(c)
  return is_digit(c) or is_identifier_start(c)
end

local function scan_identifier_keyword(input, index)
  for i = index + 1, #input do
    if not is_identifier_part(byte(input, i)) then return i end
  end
  return #input + 1
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

  return index, "malformed long string"
end

local function long_string_value(input, index, end_ind)
  local content_start = scan_long_string_opener(input, index)
  local level = content_start - index - 2
  local content = sub(input, content_start, end_ind - level - 3)

  local first = byte(content, 1)
  if first == 10 or first == 13 then -- newline or carriage return
    local second = byte(content, 2)
    local another = first == 10 and 13 or 10
    content = sub(content, second == another and 3 or 2)
  end

  -- Lua normalizes LF, CR, CRLF and LFCR to a single LF.
  content = gsub(content, "\r\n", "\n")
  content = gsub(content, "\n\r", "\n")
  return gsub(content, "\r", "\n")
end

-- in a quoted string, a character is used as-is if it is not
-- corresponding quote, backslash, newline, and carriage return
local function is_as_is_char(char, quote)
  return char ~= quote and char ~= 92 and char ~= 10 and char ~= 13
end

-- there are 3 cases:
-- 1. invalid quoted string literal, return index, reason
-- 2. need_value is true,
--   return index after close quote character, string value of the quoted string
-- 3. need_value is false,
--   return index after close quote character and empty string (for consistency)
local function scan_quote_string(input, index, need_value)
  local quote = byte(input, index)
  local length = #input
  local bytes = need_value and {} or nil
  local i = index + 1

  while i <= length do
    local char = byte(input, i)
    if char == quote then
      return i + 1, (bytes and table_concat(bytes) or "")
    elseif char == 92 then -- the escape character
      i = i + 1
      if i > length then return index, "escape character at end of input" end
      local escaped = byte(input, i)
      local single_escaped = escaped2char[escaped]
      if single_escaped ~= nil then
        if bytes then bytes[#bytes + 1] = single_escaped end
        i = i + 1
      elseif escaped == 10 or escaped == 13 then -- newline or carriage return
        if i >= length then break end
        -- lua normalizes LF, CR, CRLF and LFCR to a single LF
        if bytes then bytes[#bytes + 1] = "\n" end
        local another = escaped == 10 and 13 or 10
        i = i + (byte(input, i + 1) == another and 2 or 1)
      elseif is_digit(escaped) then
        -- scan digits but at most 3 characters
        local j = i + 1
        local value = escaped - 48
        while j <= length and j < i + 3 do
          local j_char = byte(input, j)
          if not is_digit(j_char) then break end
          value = value * 10 + j_char - 48
          j = j + 1
        end
        if value > 255 then return index, "decimal escape too large" end
        if bytes then bytes[#bytes + 1] = chr(value) end
        i = j
      else
        -- TODO in lua5.1, unknown escape sequences are treated as itself
        -- this behavior changed in newer version
        if bytes then bytes[#bytes + 1] = chr(escaped) end
        i = i + 1
      end
    elseif char == 10 or char == 13 then -- newline or carriage return
      break
    else
      if bytes then
        local j = i + 1
        while j <= length and is_as_is_char(byte(input, j), quote) do
          j = j + 1
        end
        if j > length then break end
        bytes[#bytes + 1] = sub(input, i, j - 1)
        i = j
      else
        i = i + 1
      end
    end
  end

  return index, "unfinished string"
end

-- based on regexp '(\d+(\.\d*)?|\.\d+)([eE][-+]?\d+)?'
local function scan_decimal(input, index)
  local length = #input
  local i = index

  if byte(input, i) == 46 then -- leading "."
    i = i + 1
    if i > length or not is_digit(byte(input, i)) then return index end
    repeat
      i = i + 1
    until i > length or not is_digit(byte(input, i))
  else
    if i > length or not is_digit(byte(input, i)) then return index end
    repeat
      i = i + 1
    until i > length or not is_digit(byte(input, i))

    if i <= length and byte(input, i) == 46 then -- optional "."
      i = i + 1
      while i <= length and is_digit(byte(input, i)) do
        i = i + 1
      end
    end
  end

  local mantissa_end = i
  if i <= length then
    local char = byte(input, i)
    if char == 69 or char == 101 then -- "E" or "e"
      i = i + 1
      if i <= length then
        char = byte(input, i)
        if char == 43 or char == 45 then i = i + 1 end -- "+" or "-"
      end

      -- Preserve the longest accepted prefix when the exponent is unfinished.
      if i > length or not is_digit(byte(input, i)) then return mantissa_end end
      repeat
        i = i + 1
      until i > length or not is_digit(byte(input, i))
    end
  end

  return i
end

local function starts_with_0x(input, index)
  if index >= #input or byte(input, index) ~= 48 then -- "."
    return false
  end

  local second = byte(input, index + 1)
  return second == 88 or second == 120 -- "x" or "X"
end

local function is_hex_char(char)
  return (65 <= char and char <= 70) -- A-F
    or (97 <= char and char <= 102) -- a-f
    or is_digit(char)
end

local function is_number_continuation(s, index)
  if index > #s then return false end
  local char = byte(s, index)
  -- . or identifier part (digit or letter or underscore)
  return char == 46 or is_identifier_part(char)
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

  return scan_decimal(input, index)
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

  local comment_start = index + 2
  local long_comment_end, long_string_error =
    scan_long_string(input, comment_start)
  if long_string_error ~= nil then return index, "malformed long comment" end
  if long_comment_end > comment_start then return long_comment_end end

  for i = comment_start, length do
    local char = byte(input, i)
    -- \n or \r
    if char == 10 or char == 13 then return i end
  end
  return length + 1
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
  return (
    index + 2 <= #input
    and byte(input, index) == 46 -- "."
    and byte(input, index + 1) == 46
    and byte(input, index + 2) == 46
  )
      and index + 3
    or index
end

local keyword_max_length = 0
for keyword in pairs(keywords) do
  keyword_max_length = math.max(keyword_max_length, #keyword)
end
assert(keyword_max_length <= 8)

local function scan_token(input, index)
  local length = #input
  if index > length then return "EOF", index end
  local first = byte(input, index)
  if (9 <= first and first <= 13) or first == 32 then
    index = skip_whitespaces(input, index + 1)
    if index > length then return "EOF", index end
    first = byte(input, index)
  end

  -- dispatch based on first character
  if is_identifier_start(first) then
    local end_ind = scan_identifier_keyword(input, index)
    if end_ind - index > 8 then return "Identifier", end_ind end
    local id = sub(input, index, end_ind - 1)
    local t = keywords[id]
    if t == nil then t = "Identifier" end
    return t, end_ind
  elseif is_digit(first) then
    local end_ind = scan_number(input, index)
    if end_ind > index and not is_number_continuation(input, end_ind) then
      return "NumberLiteral", end_ind
    end
    return format("malformed number near %d", index), index
  elseif first == 46 then -- .
    local end_ind = scan_vararg(input, index)
    if end_ind > index then return "VarargLiteral", end_ind end
    end_ind = scan_number(input, index)
    if end_ind > index then
      if not is_number_continuation(input, end_ind) then
        return "NumberLiteral", end_ind
      end
      return format("malformed number near %d", index), index
    end
    end_ind = scan_punctuator(input, index)
    if end_ind > index then return "Punctuator", end_ind end
    return format("unknown token after . near %d", index), index
  elseif first == 45 then -- -
    local end_ind, comment_error = scan_comment(input, index)
    if comment_error ~= nil then
      return format("%s near %d", comment_error, index), index
    end
    if end_ind > index then return "Comment", end_ind end
    end_ind = scan_punctuator(input, index)
    if end_ind > index then return "Punctuator", end_ind end
    return format("unknown token after - near %d", index), index
  elseif first == 91 then -- [
    local end_ind, long_string_error = scan_long_string(input, index)
    if long_string_error ~= nil then
      return format("%s near %d", long_string_error, index), index
    end
    if end_ind > index then return "StringLiteral", end_ind end
    end_ind = scan_punctuator(input, index)
    if end_ind > index then return "Punctuator", end_ind end
    return format("unknown token after [ near %d", index), index
  elseif first == 34 or first == 39 then -- " or '
    local end_ind = scan_quote_string(input, index, false)
    if end_ind > index then return "StringLiteral", end_ind end
    return format("malformed string near %d", index), index
  else
    local end_ind = scan_punctuator(input, index)
    if end_ind > index then return "Punctuator", end_ind end
    return format("unknown token near %d", index), index
  end
end

local function scan_token_value(input, index)
  local length = #input
  if index > length then return "EOF", index end
  local first = byte(input, index)
  if (9 <= first and first <= 13) or first == 32 then
    index = skip_whitespaces(input, index + 1)
    if index > length then return "EOF", index end
    first = byte(input, index)
  end

  if first == 34 or first == 39 then -- " or '
    local end_ind, value = scan_quote_string(input, index, true)
    if end_ind > index then return "StringLiteral", end_ind, value end
    return format("malformed string near %d", index), index
  elseif first == 91 then -- [
    local end_ind, long_string_error = scan_long_string(input, index)
    if long_string_error ~= nil then
      return format("%s near %d", long_string_error, index), index
    end
    if end_ind > index then
      return "StringLiteral", end_ind, long_string_value(input, index, end_ind)
    end
  end

  local t, end_ind = scan_token(input, index)
  if not token_types[t] or t == "EOF" then return t, end_ind end

  local value = sub(input, index, end_ind - 1)
  if t == "NumberLiteral" then
    value = tonumber(value)
  elseif t == "BooleanLiteral" then
    value = first == 116 -- true starts with "t"
  end
  return t, end_ind, value
end

return {
  token_types = token_types,
  scan_token = scan_token,
  scan_token_value = scan_token_value,
}
