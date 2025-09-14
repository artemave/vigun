local M = {}

-- Extract test title from a string node
local function extract_string_content(string_node)
  local node_type = string_node:type()

  -- For Ruby constants and identifiers, return as-is
  if node_type == 'constant' or node_type == 'identifier' then
    return vim.treesitter.get_node_text(string_node, 0)
  end

  -- For strings, look for string_fragment child which contains the actual text without quotes
  for child in string_node:iter_children() do
    if child:type() == 'string_fragment' then
      return vim.treesitter.get_node_text(child, 0)
    end
  end
  -- Fallback: return the whole text and remove quotes
  local text = vim.treesitter.get_node_text(string_node, 0)
  return text:gsub('^["\']', ''):gsub('["\']$', '')
end
-- Name and node-type matchers (lists or predicates)
local function make_name_matcher(val)
  if type(val) == 'function' then
    return function(node, name)
      return val(node, name) and true or false
    end
  end
  local list = {}
  if type(val) == 'table' then list = val else list = {} end
  local set = {}
  for _, v in ipairs(list) do set[v] = true end
  return function(_node, name)
    if not name then return false end
    return set[name] == true
  end
end

local ALL_NODE_TYPES = {
  -- call-like
  'call_expression', -- js/ts
  'call', 'command', 'command_call', 'method_call', -- ruby
  'function_call', -- lua
  -- def/context-like
  'function_definition', 'method_definition', -- python/ruby (method_definition present in some grammars)
  'class_definition', 'class', -- ruby uses 'class'
}

local function make_node_type_matcher()
  local set = {}
  for _, t in ipairs(ALL_NODE_TYPES) do set[t] = true end
  return function(node)
    return set[node:type()] == true
  end
end

local CALL_NODE_TYPES = {
  call_expression = true,
  call = true,
  command = true,
  command_call = true,
  method_call = true,
  function_call = true,
}

local function is_call_like(node)
  return CALL_NODE_TYPES[node:type()] == true
end

local function extract_call_generic(node)
  local callee = node:child(0)
  if not callee then return nil end
  local func_name = vim.treesitter.get_node_text(callee, 0)

  local title_node = nil
  local function is_title_candidate(n)
    if not n then return false end
    local t = n:type()
    return t == 'string' or t == 'template_string' or t == 'simple_symbol' or t == 'symbol' or t == 'constant' or t == 'identifier'
  end

  for i = 1, node:child_count() - 1 do
    local ch = node:child(i)
    if not ch then goto continue end
    if is_title_candidate(ch) then title_node = ch; break end
    local ct = ch:type()
    if ct == 'arguments' or ct == 'argument_list' then
      for j = 0, ch:child_count() - 1 do
        local arg = ch:child(j)
        if is_title_candidate(arg) then title_node = arg; break end
      end
      if title_node then break end
    end
    ::continue::
  end

  local title = title_node and extract_string_content(title_node) or nil
  return func_name, title
end

local function extract_function_or_method_name(node)
  local name = nil
  for i = 0, node:child_count() - 1 do
    local ch = node:child(i)
    if ch and (ch:type() == 'identifier' or ch:type() == 'constant') then
      name = vim.treesitter.get_node_text(ch, 0)
      break
    end
  end
  return name
end

-- Get all test and context nodes by walking the AST
local function get_test_nodes_via_query()
  local config = require('vigun.config').get_active()
  local parser = vim.treesitter.get_parser()
  local trees = parser:parse()
  local root = trees[1]:root()

  local test_nodes_val = config.test_nodes or nil
  local context_nodes_val = config.context_nodes or nil

  local node_types_match = make_node_type_matcher()
  local test_match = make_name_matcher(test_nodes_val)
  local context_match = make_name_matcher(context_nodes_val)

  local function base_name(name)
    if not name then return nil end
    return (name:match('^([%w_]+)')) or name
  end

  local nodes = {}

  local function consider_node(node)
    if not node_types_match(node) then return end
    local ntype = node:type()

    if is_call_like(node) then
      local func_name, title = extract_call_generic(node)
      if not func_name or not title then return end
      local b = base_name(func_name)
      local is_ctx = context_match(node, b)
      local is_test = test_match(node, b)
      if not (is_ctx or is_test) then return end
      local srow, _, erow, _ = node:range()
      table.insert(nodes, {
        node = node,
        func_name = func_name,
        title = title,
        start_row = srow,
        end_row = erow,
        is_context = is_ctx,
      })
      return
    end

    if ntype == 'function_definition' or ntype == 'method_definition' then
      local name = extract_function_or_method_name(node)
      if not name then return end
      local is_test = test_match(node, name)
      if not is_test then return end
      local srow, _, erow, _ = node:range()
      table.insert(nodes, {
        node = node,
        func_name = name,
        title = name,
        start_row = srow,
        end_row = erow,
        is_context = false,
      })
      return
    end

    if ntype == 'class_definition' or ntype == 'class' then
      local name = extract_function_or_method_name(node)
      if not name then return end
      local is_ctx = context_match(node, name)
      if not is_ctx then return end
      local srow, _, erow, _ = node:range()
      table.insert(nodes, {
        node = node,
        func_name = name,
        title = name,
        start_row = srow,
        end_row = erow,
        is_context = true,
      })
      return
    end
  end

  local function walk(node)
    consider_node(node)
    for i = 0, node:child_count() - 1 do
      local ch = node:child(i)
      if ch then walk(ch) end
    end
  end
  walk(root)

  table.sort(nodes, function(a, b) return a.start_row < b.start_row end)
  return nodes
end

-- Find the nearest test node from a given line
function M.find_nearest_test(line_number)
  local target_line = (line_number or vim.fn.line('.')) - 1
  local bufnr = vim.api.nvim_get_current_buf()
  local nodes = get_test_nodes_via_query(bufnr)

  -- Find the test node that contains or is closest before the target line
  local best_node = nil
  for _, node_info in ipairs(nodes) do
    if not node_info.is_context and node_info.start_row <= target_line and node_info.end_row >= target_line then
      -- Line is within this test node
      return node_info.start_row + 1 -- Convert back to 1-based
    elseif not node_info.is_context and node_info.start_row <= target_line then
      -- This test is before the target line, keep it as a candidate
      best_node = node_info
    end
  end

  if best_node then
    return best_node.start_row + 1
  end
  return 0
end

-- Get test title at a specific line
function M.get_test_title(line_number)
  local target_line = (line_number or vim.fn.line('.')) - 1
  local nodes = get_test_nodes_via_query(0)

  -- Find the test node that contains the target line
  for _, node_info in ipairs(nodes) do
    if not node_info.is_context and node_info.start_row <= target_line and node_info.end_row >= target_line then
      return node_info.title
    end
  end
end

-- Get test title with context (parent describe/context blocks)
function M.get_test_title_with_context(line_number)
  local target_line = (line_number or vim.fn.line('.')) - 1
  local bufnr = vim.api.nvim_get_current_buf()
  local nodes = get_test_nodes_via_query(bufnr)

  -- Find all nodes that contain the target line
  local containing_nodes = {}
  for _, node_info in ipairs(nodes) do
    if node_info.start_row <= target_line and node_info.end_row >= target_line then
      table.insert(containing_nodes, node_info)
    end
  end

  if #containing_nodes == 0 then
    return ''
  end

  -- Sort by nesting level (innermost first = largest start_row, smallest span)
  table.sort(containing_nodes, function(a, b)
    -- If they have different start rows, prefer the one with larger start_row (more nested)
    if a.start_row ~= b.start_row then
      return a.start_row > b.start_row
    end
    -- If same start row, prefer the one with smaller span (more specific)
    return (a.end_row - a.start_row) < (b.end_row - b.start_row)
  end)

  -- The first non-context node should be our test
  local context_titles = {}
  local test_title = ''

  -- Find the innermost test (first non-context node)
  for _, node_info in ipairs(containing_nodes) do
    if not node_info.is_context then
      test_title = node_info.title
      break
    end
  end

  -- Collect all contexts (in outer-to-inner order)
  local contexts_in_order = {}
  for _, node_info in ipairs(containing_nodes) do
    if node_info.is_context then
      table.insert(contexts_in_order, node_info)
    end
  end
  -- Sort contexts from outermost to innermost
  table.sort(contexts_in_order, function(a, b) return a.start_row < b.start_row end)
  for _, context in ipairs(contexts_in_order) do
    table.insert(context_titles, context.title)
  end

  if test_title == '' then
    -- No actual test found, maybe we're in a context only
    return ''
  end

  if #context_titles > 0 then
    local result = table.concat(context_titles, ' ') .. ' ' .. test_title
    return result
  else
    return test_title
  end
end

-- Get only the context titles (outermost -> innermost) for the given line
function M.get_context_titles(line_number)
  local target_line = (line_number or vim.fn.line('.')) - 1
  local bufnr = vim.api.nvim_get_current_buf()
  local nodes = get_test_nodes_via_query(bufnr)

  local containing_contexts = {}
  for _, node_info in ipairs(nodes) do
    if node_info.is_context and node_info.start_row <= target_line and node_info.end_row >= target_line then
      table.insert(containing_contexts, node_info)
    end
  end

  table.sort(containing_contexts, function(a, b) return a.start_row < b.start_row end)

  local titles = {}
  for _, ctx in ipairs(containing_contexts) do
    table.insert(titles, ctx.title)
  end
  return titles
end

-- Check if there are any .only tests in the file
function M.has_only_tests()
  local bufnr = vim.api.nvim_get_current_buf()
  local nodes = get_test_nodes_via_query(bufnr)

  for _, node_info in ipairs(nodes) do
    if node_info.func_name:match('%.only$') then
      return true
    end
  end

  return false
end

-- Get all test nodes in the file (for spec index)
function M.get_test_nodes()
  local bufnr = vim.api.nvim_get_current_buf()
  local nodes = get_test_nodes_via_query(bufnr)
  local test_nodes = {}

  -- Build a hierarchy to calculate depth
  local function calculate_depth(node_info, all_nodes)
    local depth = 0
    for _, other_node in ipairs(all_nodes) do
      if other_node.is_context and
          other_node.start_row < node_info.start_row and
          other_node.end_row > node_info.end_row then
        depth = depth + 1
      end
    end
    return depth
  end

  for _, node_info in ipairs(nodes) do
    local depth = calculate_depth(node_info, nodes)
    table.insert(test_nodes, {
      line = node_info.start_row + 1, -- Convert to 1-based
      title = node_info.title,
      depth = depth
    })
  end

  return test_nodes
end

-- Compute fold ranges for all tests that are not on the path to the current test
function M.get_fold_ranges_for_line(line_number)
  local target_line = (line_number or vim.fn.line('.')) - 1
  local bufnr = vim.api.nvim_get_current_buf()
  local nodes = get_test_nodes_via_query(bufnr)

  -- Find selected test node (contains or closest before the target line)
  local selected = nil
  for _, node_info in ipairs(nodes) do
    if not node_info.is_context and node_info.start_row <= target_line and node_info.end_row >= target_line then
      selected = node_info
      break
    elseif not node_info.is_context and node_info.start_row <= target_line then
      selected = node_info
    end
  end
  if not selected then
    return {}
  end

  -- Collect ancestor contexts that contain the selected test
  local ancestors = {}
  for _, node_info in ipairs(nodes) do
    if node_info.is_context and node_info.start_row < selected.start_row and node_info.end_row > selected.end_row then
      table.insert(ancestors, node_info)
    end
  end
  table.sort(ancestors, function(a, b) return a.start_row < b.start_row end)

  local ranges = {}
  -- Start with the selected test as the kept child range inside its parent context
  local kept_child = { start_row = selected.start_row, end_row = selected.end_row }

  -- Helper to determine if A is strictly inside B
  local function inside(a, b)
    return a.start_row > b.start_row and a.end_row < b.end_row
  end

  -- Walk from innermost ancestor outwards; fold all other immediate children inside each ancestor
  for i = #ancestors, 1, -1 do
    local ctx = ancestors[i]

    -- Collect immediate children calls (tests or contexts) of this context
    local children = {}
    for _, cand in ipairs(nodes) do
      if cand.start_row > ctx.start_row and cand.end_row < ctx.end_row then
        -- Check if there is an intermediate context that contains cand
        local is_immediate = true
        for _, other in ipairs(nodes) do
          if other.is_context and other ~= ctx and other ~= cand and inside(other, ctx) and cand.start_row >= other.start_row and cand.end_row <= other.end_row then
            is_immediate = false
            break
          end
        end
        if is_immediate then
          table.insert(children, cand)
        end
      end
    end

    for _, child in ipairs(children) do
      local inside_kept = child.start_row >= kept_child.start_row and child.end_row <= kept_child.end_row
      if not inside_kept then
        table.insert(ranges, { start = child.start_row + 1, ["end"] = child.end_row + 1 })
      end
    end

    kept_child = { start_row = ctx.start_row, end_row = ctx.end_row }
  end

  return ranges
end

return M
