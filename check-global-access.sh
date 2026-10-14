#!/bin/sh

luac5.1 -p -l luaparse/*.lua | lua5.1 -e '
local funcline = ""
local visiting_global = {}

for line in io.lines() do
  if line == "" then
    funcline = ""
  elseif funcline == "" then
    funcline = line
  end

  local opcode = line:match("^%s*%S+%s+%S+%s+(%S+)")
  if opcode == "GETGLOBAL" or opcode == "SETGLOBAL" then
    visiting_global[funcline] = true
  end
end

local not_main = {}
for name in pairs(visiting_global) do
  if not name:match("^main ") then
    not_main[#not_main + 1] = name
  end
end

for i = 1, #not_main do
  print(not_main[i])
end
if #not_main > 0 then os.exit(1) end
'
