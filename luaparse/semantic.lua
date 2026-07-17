local error = error
local format = string.format
local ipairs = ipairs
local setmetatable = setmetatable
local type = type
local append = table.insert
local pop = table.remove

-- some features (for example `break statement must be in a loop`)
-- are enabled for every version, thus no need to specify them here
local feature_profiles = {
  ["5.1"] = {},
  ["LuaJIT"] = { gotos = true },
  ["5.2"] = { gotos = true, environment = true },
  ["5.3"] = { gotos = true, environment = true },
  ["5.4"] = {
    gotos = true,
    environment = true,
    attributes = true,
    forbid_visible_label_shadowing = true,
  },
  ["5.5"] = {
    gotos = true,
    environment = true,
    attributes = true,
    forbid_visible_label_shadowing = true,
    global_declarations = true,
    readonly_loop_variables = true,
    named_varargs = true,
  },
}

local checker_methods = {}
local checker_mt = { __index = checker_methods, __metatable = false }

function checker_methods:adjust_loop_depth(delta)
  self.current_function.loop_depth = self.current_function.loop_depth + delta
end

local function statement_has_body(statement_type)
  return statement_type == "DoStatement"
    or statement_type == "WhileStatement"
    or statement_type == "RepeatStatement"
    or statement_type == "NumericForStatement"
    or statement_type == "GenericForStatement"
end

-- returns nil if this goto does not jump into the scope of a declaration
-- otherwise a declaration string that the goto jump into its scope
local function jump_into_declaration(node, goto_index, label_index)
  if label_index < goto_index then return nil end
  local body = node.body

  local decl = ""
  for i = goto_index + 1, label_index do
    local statement = body[i]
    local state_type = statement.type
    if state_type == "VariableDeclaration" and #statement.variables > 0 then
      decl = statement.variables[1].identifier.name
    elseif state_type == "FunctionDeclaration" and statement.scope ~= nil then
      decl = statement.identifier.name
    elseif state_type == "GlobalWildcardDeclaration" then
      decl = "*"
    end
    if decl ~= "" then break end
  end
  if decl == "" then return nil end
  if node.type == "RepeatStatement" then return decl end

  for i = label_index, #body do
    local state_type = body[i].type
    if state_type ~= "LabelStatement" and state_type ~= "EmptyStatement" then
      return decl
    end
  end
  return nil
end

-- Validate goto and label statements within one function.
-- A goto must resolve to the nearest visible label in its block or an
-- outer block. Labels are visible throughout their block, including
-- before declaration and inner blocks, but never across function boundaries.
--
-- A goto cannot enter the scope of a variable declaration. In Lua 5.2-5.4
-- and LuaJIT this restriction applies to local variables; in Lua 5.5 it
-- also applies to global declarations. A variable's scope ends at the last
-- non-void statement of its block, so trailing labels are outside its scope.
-- The exception is a repeat body: its declarations remain in scope through
-- the until condition, so trailing labels are still inside their scope.
--
-- Two labels with the same name cannot be declared in the same block.
-- Lua 5.2, Lua 5.3, and LuaJIT allow a nested label to shadow an enclosing
-- label. Lua 5.4 and Lua 5.5 reject a label when a previously declared label
-- with the same name is visible at the point of declaration.
function checker_methods:validate_goto_and_label(func)
  if not self.features.gotos then return end

  local forbid_visible_label_shadowing =
    self.features.forbid_visible_label_shadowing
  local node2parent = {}
  -- node to dict of (label_name to index in the node body)
  local node2labels = {}

  local function find_label(name, node)
    while node ~= nil do
      local index = node2labels[node][name]
      if index then return node, index end
      node = node2parent[node]
    end
    return nil, 0
  end

  -- note, label's visibility never extends across function boundaries.
  -- so nested functions are ignored in DFS and will be check separately

  -- collect all node2labels and node2parent items via DFS
  local function collect_labels(has_body, parent)
    if parent then node2parent[has_body] = parent end
    -- from label name (string) to index in the node body (int)
    local label2index = {}
    node2labels[has_body] = label2index
    for i, statement in ipairs(has_body.body) do
      local state_type = statement.type
      if state_type == "LabelStatement" then
        local name = statement.label.name
        local index = label2index[name]
        local node_defined_name = index and has_body or nil
        if node_defined_name == nil and forbid_visible_label_shadowing then
          node_defined_name, index = find_label(name, parent)
        end
        if node_defined_name ~= nil then
          self:add_control_error(
            statement,
            'label "%s" on line %d already defined on line %d',
            name,
            statement.line,
            node_defined_name.body[index].line
          )
        else
          label2index[name] = i
        end
      elseif statement_has_body(state_type) then
        collect_labels(statement, has_body)
      elseif state_type == "IfStatement" then
        for _, clause in ipairs(statement.clauses) do
          collect_labels(clause, has_body)
        end
      end
    end
  end

  -- DFS to resolve goto statement in a `has_body`,
  -- stack_index records the index of each `has_body` in the stack
  local function resolve_gotos(has_body, stack_index)
    for i, statement in ipairs(has_body.body) do
      local state_type = statement.type
      stack_index[has_body] = i
      if state_type == "GotoStatement" then
        local name = statement.label.name
        local node, index = find_label(name, has_body)
        if node == nil then
          self:add_control_error(
            statement,
            "no visible label '%s' for <goto> at line %d",
            name,
            statement.line
          )
        else
          local decl = jump_into_declaration(node, stack_index[node], index)
          if decl then
            self:add_control_error(
              statement,
              "<goto %s> at line %d jumps into the scope of '%s'",
              name,
              statement.line,
              decl
            )
          end
        end
      elseif statement_has_body(state_type) then
        resolve_gotos(statement, stack_index)
      elseif state_type == "IfStatement" then
        for _, clause in ipairs(statement.clauses) do
          resolve_gotos(clause, stack_index)
        end
      end
    end
    stack_index[has_body] = nil
  end

  collect_labels(func)
  resolve_gotos(func, {})
end

-- Goto and label validation runs before the normal AST traversal. Defer its
-- errors by node so they are emitted in source order with other diagnostics.
function checker_methods:add_control_error(node, ...)
  local errors = self.control_errors[node]
  if errors == nil then
    errors = {}
    self.control_errors[node] = errors
  end
  append(errors, format(...))
end

function checker_methods:emit_control_errors(node)
  local errors = self.control_errors[node]
  if errors == nil then return end
  for i = 1, #errors do
    self:add_diagnostic(node, errors[i])
  end
end

function checker_methods:add_diagnostic(node, ...)
  append(self.diagnostics, { message = format(...), line = node.line })
end

function checker_methods:push_scope()
  append(self.scopes, { bindings = {}, global_declaration = false })
end

function checker_methods:pop_scope() pop(self.scopes) end

function checker_methods:declare(name, readonly)
  local scope = self.scopes[#self.scopes]
  scope.bindings[name] = { name = name, readonly = readonly or false }
end

function checker_methods:declare_global(name, readonly)
  local scope = self.scopes[#self.scopes]
  scope.global_declaration = true
  self:declare(name, readonly)
end

function checker_methods:declare_wildcard(readonly)
  local scope = self.scopes[#self.scopes]
  scope.global_declaration = true
  scope.wildcard = { readonly = readonly or false }
end

function checker_methods:resolve(name)
  -- Explicit declarations always take precedence over wildcard declarations,
  -- including an explicit declaration in an enclosing scope.
  for index = #self.scopes, 1, -1 do
    local binding = self.scopes[index].bindings[name]
    if binding ~= nil then return binding end
  end

  if self.features.global_declarations then
    for index = #self.scopes, 1, -1 do
      local wildcard = self.scopes[index].wildcard
      if wildcard ~= nil then return wildcard end
    end
    for index = #self.scopes, 1, -1 do
      if self.scopes[index].global_declaration then return nil end
    end
  end

  return { readonly = false }
end

function checker_methods:visit_identifier(identifier, assignment)
  local binding = self:resolve(identifier.name)
  if binding == nil then
    self:add_diagnostic(
      identifier,
      "variable '%s' not declared",
      identifier.name
    )
  elseif assignment and binding.readonly then
    self:add_diagnostic(
      identifier,
      "attempt to assign to const variable '%s'",
      identifier.name
    )
  end
end

function checker_methods:validate_attribute(attribute, is_global)
  if attribute == nil or not self.features.attributes then return nil end
  local name = attribute.name
  if name ~= "const" and name ~= "close" then
    self:add_diagnostic(attribute, "unknown attribute '%s'", name)
    return nil
  end
  if is_global and name == "close" then
    self:add_diagnostic(attribute, "global variables cannot be to-be-closed")
  end
  return name
end

function checker_methods:visit_variable_declaration(statement)
  local is_global = statement.scope == "global"
  local prefix = self:validate_attribute(statement.attribute, is_global)
  local effective = {}
  local close_count = 0

  for index, variable in ipairs(statement.variables) do
    local postfix = self:validate_attribute(variable.attribute, is_global)
    local attribute
    if variable.attribute ~= nil then
      attribute = postfix
    else
      attribute = prefix
    end
    effective[index] = attribute
    if attribute == "close" then
      close_count = close_count + 1
      if close_count > 1 then
        self:add_diagnostic(
          variable.attribute or variable.identifier,
          "multiple to-be-closed variables in local list"
        )
      end
    end
  end

  self:visit_expression_list(statement.init)

  for index, variable in ipairs(statement.variables) do
    local readonly = effective[index] == "const" or effective[index] == "close"
    if is_global and self.features.global_declarations then
      self:declare_global(variable.identifier.name, readonly)
    else
      self:declare(variable.identifier.name, readonly)
    end
  end
end

function checker_methods:visit_global_wildcard(statement)
  local attribute = self:validate_attribute(statement.attribute, true)
  self:declare_wildcard(attribute == "const" or attribute == "close")
end

function checker_methods:visit_assignment_target(expression)
  local expression_type = expression.type
  if expression_type == "Identifier" then
    self:visit_identifier(expression, true)
  elseif expression_type == "MemberExpression" then
    self:visit_expression(expression.base)
  elseif expression_type == "IndexExpression" then
    self:visit_expression(expression.base)
    self:visit_expression(expression.index)
  end
end

function checker_methods:visit_function(function_node)
  local previous_function = self.current_function
  local parameters = function_node.parameters
  local variadic = #parameters > 0
    and parameters[#parameters].type == "VarargParameter"
  self.current_function = { loop_depth = 0, variadic = variadic }

  self:validate_goto_and_label(function_node)
  self:push_scope()

  if
    function_node.identifier ~= nil
    and function_node.identifier.type == "MemberExpression"
    and function_node.identifier.indexer == ":"
  then
    self:declare("self", false)
  end

  for _, parameter in ipairs(function_node.parameters) do
    if parameter.type == "Identifier" then
      self:declare(parameter.name, false)
    elseif parameter.identifier ~= nil then
      self:declare(parameter.identifier.name, self.features.named_varargs)
    end
  end

  self:visit_block(function_node.body)
  self:pop_scope()
  self.current_function = previous_function
end

function checker_methods:visit_expression_list(expressions)
  for i = 1, #expressions do
    self:visit_expression(expressions[i])
  end
end

function checker_methods:visit_expression(expression)
  local expr_type = expression.type
  if expr_type == "Identifier" then
    self:visit_identifier(expression, false)
  elseif expr_type == "VarargLiteral" then
    if not self.current_function.variadic then
      self:add_diagnostic(
        expression,
        "cannot use '...' outside a vararg function near '...'"
      )
    end
  elseif
    expr_type == "BinaryExpression" or expr_type == "LogicalExpression"
  then
    self:visit_expression(expression.left)
    self:visit_expression(expression.right)
  elseif expr_type == "UnaryExpression" then
    self:visit_expression(expression.argument)
  elseif expr_type == "ParenthesizedExpression" then
    self:visit_expression(expression.expression)
  elseif expr_type == "MemberExpression" then
    self:visit_expression(expression.base)
  elseif expr_type == "IndexExpression" then
    self:visit_expression(expression.base)
    self:visit_expression(expression.index)
  elseif expr_type == "CallExpression" then
    self:visit_expression(expression.base)
    self:visit_expression_list(expression.arguments)
  elseif expr_type == "TableConstructorExpression" then
    for _, field in ipairs(expression.fields) do
      if field.type == "TableKey" then self:visit_expression(field.key) end
      self:visit_expression(field.value)
    end
  elseif expr_type == "FunctionDeclaration" then
    self:visit_function(expression)
  end
end

function checker_methods:visit_block_contents(body)
  for i = 1, #body do
    self:visit_statement(body[i])
  end
end

function checker_methods:visit_block(body)
  self:push_scope()
  self:visit_block_contents(body)
  self:pop_scope()
end

function checker_methods:visit_statement(statement)
  local stat_type = statement.type
  if stat_type == "BreakStatement" then
    if self.current_function.loop_depth == 0 then
      self:add_diagnostic(statement, "break outside loop near 'break'")
    end
  elseif stat_type == "GotoStatement" or stat_type == "LabelStatement" then
    self:emit_control_errors(statement)
  elseif stat_type == "ReturnStatement" then
    self:visit_expression_list(statement.arguments)
  elseif stat_type == "DoStatement" then
    self:visit_block(statement.body)
  elseif stat_type == "WhileStatement" then
    self:visit_expression(statement.condition)
    self:adjust_loop_depth(1)
    self:visit_block(statement.body)
    self:adjust_loop_depth(-1)
  elseif stat_type == "RepeatStatement" then
    self:adjust_loop_depth(1)
    self:push_scope()
    self:visit_block_contents(statement.body)
    self:visit_expression(statement.condition)
    self:pop_scope()
    self:adjust_loop_depth(-1)
  elseif stat_type == "IfStatement" then
    for _, clause in ipairs(statement.clauses) do
      if clause.condition ~= nil then
        self:visit_expression(clause.condition)
      end
      self:visit_block(clause.body)
    end
  elseif stat_type == "NumericForStatement" then
    self:visit_expression(statement.start)
    self:visit_expression(statement.limit)
    if statement.step ~= nil then self:visit_expression(statement.step) end
    self:push_scope()
    self:declare(statement.variable.name, self.features.readonly_loop_variables)
    self:adjust_loop_depth(1)
    self:visit_block(statement.body)
    self:adjust_loop_depth(-1)
    self:pop_scope()
  elseif stat_type == "GenericForStatement" then
    self:visit_expression_list(statement.iterators)
    self:push_scope()
    local readonly_loop_variables = self.features.readonly_loop_variables
    for index, variable in ipairs(statement.variables) do
      self:declare(variable.name, readonly_loop_variables and index == 1)
    end
    self:adjust_loop_depth(1)
    self:visit_block(statement.body)
    self:adjust_loop_depth(-1)
    self:pop_scope()
  elseif stat_type == "VariableDeclaration" then
    self:visit_variable_declaration(statement)
  elseif stat_type == "GlobalWildcardDeclaration" then
    self:visit_global_wildcard(statement)
  elseif stat_type == "AssignmentStatement" then
    for _, variable in ipairs(statement.variables) do
      self:visit_assignment_target(variable)
    end
    self:visit_expression_list(statement.init)
  elseif stat_type == "FunctionCallStatement" then
    self:visit_expression(statement.expression)
  elseif stat_type == "FunctionDeclaration" then
    if statement.scope == "local" then
      self:declare(statement.identifier.name, false)
    elseif
      statement.scope == "global" and self.features.global_declarations
    then
      self:declare_global(statement.identifier.name, false)
    else
      self:visit_assignment_target(statement.identifier)
    end
    self:visit_function(statement)
  end
end

local function check(ast, options)
  if type(ast) ~= "table" or ast.type ~= "Chunk" then
    error("ast must be a Chunk node", 2)
  end
  options = options or {}
  local lua_version = options.lua_version or "5.1"
  local features = feature_profiles[lua_version]
  if features == nil then
    error("unsupported Lua version " .. lua_version, 2)
  end

  local checker = setmetatable({
    control_errors = {},
    diagnostics = {},
    features = features,
    scopes = {},
  }, checker_mt)

  checker:push_scope()
  if features.environment then checker:declare("_ENV", false) end
  checker.current_function = { loop_depth = 0, variadic = true }
  checker:validate_goto_and_label(ast)
  checker:visit_block(ast.body)
  checker:pop_scope()
  return checker.diagnostics
end

return { check = check }
