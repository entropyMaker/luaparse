local lexer = require("luaparse.lexer")

local function usage()
  io.write([[
Usage: lua benchmark/lexer_benchmark.lua PASSES [LUA_VERSION] FILE...

Arguments:
  PASSES       Number of times to scan the input files.
  LUA_VERSION  Lexer profile: 5.1, LuaJIT, 5.2, 5.3, 5.4, or 5.5.
               Omit it when FILE is the second argument to infer the profile
               from the current interpreter.
  FILE         One or more Lua source files.

The benchmark loads all input files before timing, so reported throughput
excludes file I/O.
]])
end

if arg[1] == "-h" or arg[1] == "--help" then
  usage()
  return
end

local passes = tonumber(arg[1])
if passes == nil or passes < 1 or passes ~= math.floor(passes) then
  io.stderr:write("error: PASSES must be a positive integer\n\n")
  usage()
  os.exit(1)
end

local has_jit, jit = pcall(require, "jit")
local default_version = has_jit and "LuaJIT" or _VERSION:match("Lua (%d+%.%d+)")
local first_file = 2
local lua_version = default_version
if arg[2] ~= nil and not arg[2]:match("%.lua$") then
  lua_version = arg[2]
  first_file = 3
end

if arg[first_file] == nil then
  io.stderr:write("error: at least one FILE is required\n\n")
  usage()
  os.exit(1)
end

local scanner = lexer.new({ lua_version = lua_version })
local files = {}
local bytes_per_pass = 0

for i = first_file, #arg do
  local path = arg[i]
  local file = assert(io.open(path, "rb"))
  local input = assert(file:read("*a"))
  file:close()
  files[#files + 1] = { path = path, input = input }
  bytes_per_pass = bytes_per_pass + #input
end

local token_count = 0
local started = os.clock()
for _ = 1, passes do
  for _, source in ipairs(files) do
    local index = 1
    while true do
      local token_type, next_index = scanner:scan_token(source.input, index)
      if not lexer.token_types[token_type] then
        error(string.format("%s:%d: %s", source.path, index, token_type))
      end
      token_count = token_count + 1
      if token_type == "EOF" then break end
      index = next_index
    end
  end
end
local elapsed = os.clock() - started
local total_bytes = bytes_per_pass * passes

io.write(string.format("Interpreter:  %s\n", _VERSION))
io.write(
  string.format("JIT:          %s\n", has_jit and jit.version or "disabled")
)
io.write(string.format("Lexer profile: %s\n", lua_version))
io.write(string.format("Input files:  %d\n", #files))
io.write(string.format("Passes:       %d\n", passes))
io.write(string.format("Bytes/pass:   %d\n", bytes_per_pass))
io.write(string.format("Total bytes:  %d\n", total_bytes))
io.write(string.format("Tokens:       %d\n", token_count))
io.write(string.format("Elapsed:      %.6f s\n", elapsed))
io.write(
  string.format(
    "Throughput:   %.2f MiB/s\n",
    total_bytes / elapsed / 1024 / 1024
  )
)
