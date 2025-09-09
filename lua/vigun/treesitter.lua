local M = {}

-- Treesitter query for JavaScript/TypeScript test functions - capture ALL call expressions
local js_test_query = vim.treesitter.query.parse("javascript", [[
  (call_expression) @call
]])

-- Treesitter query for Python test functions
local python_test_query = vim.treesitter.query.parse("python", [[
  (function_definition
    name: (identifier) @func
    (#match? @func "^test_")
  ) @call
]])

-- Treesitter query for Ruby test functions - capture ALL call expressions
local ruby_test_query = vim.treesitter.query.parse("ruby", [[
  (call) @call
]])

-- Extract test title from a string node
local function extract_string_content(string_node, bufnr)
  local node_type = string_node:type()

  -- For Ruby constants and identifiers, return as-is
  if node_type == 'constant' or node_type == 'identifier' then
    return vim.treesitter.get_node_text(string_node, bufnr)
  end

  -- For strings, look for string_fragment child which contains the actual text without quotes
  for child in string_node:iter_children() do
    if child:type() == 'string_fragment' then
      return vim.treesitter.get_node_text(child, bufnr)
    end
  end
  -- Fallback: return the whole text and remove quotes
  local text = vim.treesitter.get_node_text(string_node, bufnr)
  return text:gsub('^["\']', ''):gsub('["\']$', '')
end

-- Check if a function name is a test-related function
local function is_test_function(func_name)
  local base_name = func_name:match('^([^.]+)') or func_name

  local cfg = require('vigun.config').get_active()
  if cfg and type(cfg.test_nodes) == 'table' then
    for _, n in ipairs(cfg.test_nodes) do
      if base_name == n then return true end
    end
    return false
  end

  -- Fallback default set
  local defaults = { 'it', 'test', 'xit', 'testWidgets' }
  for _, n in ipairs(defaults) do
    if base_name == n then return true end
  end
  return false
end

-- Check if a function name is a context function (describe, context, etc.)
local function is_context_function(func_name)
  local base_name = func_name:match('^([^.]+)') or func_name

  local cfg = require('vigun.config').get_active()
  if cfg and type(cfg.context_nodes) == 'table' then
    for _, n in ipairs(cfg.context_nodes) do
      if base_name == n then return true end
    end
    return false
  end

  -- Fallback default set
  local defaults = { 'describe', 'context', 'feature', 'scenario', 'group' }
  for _, n in ipairs(defaults) do
    if base_name == n then return true end
  end
  return false
end

-- Get all test and context nodes from the buffer
local function get_test_nodes_via_query(bufnr)
  local parser = vim.treesitter.get_parser(bufnr)
  local trees = parser:parse()
  local root = trees[1]:root()

  local nodes = {}

  -- Use JavaScript query for JavaScript/TypeScript files
  local filetype = vim.bo[bufnr].filetype
  if filetype == 'javascript' or filetype == 'typescript' or filetype == 'javascriptreact' or filetype == 'typescriptreact' then
    for id, node, metadata in js_test_query:iter_captures(root, bufnr, 0, -1) do
      local capture_name = js_test_query.captures[id]
      if capture_name == 'call' then
        -- Manually extract function name and first string argument
        local func_node = node:child(0) -- First child is the function
        local args_node = node:child(1) -- Second child is the arguments

        if func_node and args_node then
          local func_name = vim.treesitter.get_node_text(func_node, bufnr)

          -- Look for the first string argument
          local title_node = nil
          for child in args_node:iter_children() do
            if child:type() == 'string' then
              title_node = child
              break
            end
          end

          if title_node then
            local title = extract_string_content(title_node, bufnr)

            if is_test_function(func_name) or is_context_function(func_name) then
              local start_row, start_col, end_row, end_col = node:range()
              table.insert(nodes, {
                node = node,
                func_name = func_name,
                title = title,
                start_row = start_row,
                end_row = end_row,
                is_context = is_context_function(func_name)
              })
            end
          end
        end
      end
    end
  elseif filetype == 'ruby' then
    -- Use Ruby query for Ruby files
    for id, node, metadata in ruby_test_query:iter_captures(root, bufnr, 0, -1) do
      local capture_name = ruby_test_query.captures[id]
      if capture_name == 'call' then
        -- Ruby call structure: method [arguments]
        local method_node = node:child(0) -- First child is the method name

        if method_node then
          local func_name = vim.treesitter.get_node_text(method_node, bufnr)

          -- Look for string argument (Ruby can have arguments without parentheses)
          local title_node = nil

          -- Look for argument list or direct string/symbol arguments
          for i = 1, node:child_count() - 1 do
            local child = node:child(i)
            if child then
              local child_type = child:type()
              if child_type == 'string' or child_type == 'simple_symbol' or child_type == 'symbol' or child_type == 'constant' or child_type == 'identifier' then
                title_node = child
                break
              elseif child_type == 'argument_list' then
                -- Look inside argument list for string, symbol, constant, or identifier
                for j = 0, child:child_count() - 1 do
                  local arg = child:child(j)
                  if arg and (arg:type() == 'string' or arg:type() == 'simple_symbol' or arg:type() == 'symbol' or arg:type() == 'constant' or arg:type() == 'identifier') then
                    title_node = arg
                    break
                  end
                end
                if title_node then break end
              end
            end
          end

          if title_node then
            local title = extract_string_content(title_node, bufnr)

            if is_test_function(func_name) or is_context_function(func_name) then
              local start_row, start_col, end_row, end_col = node:range()
              table.insert(nodes, {
                node = node,
                func_name = func_name,
                title = title,
                start_row = start_row,
                end_row = end_row,
                is_context = is_context_function(func_name)
              })
            end
          end
        end
      end
    end
  elseif filetype == 'python' then
    -- Use Python query for Python files
    for id, node, metadata in python_test_query:iter_captures(root, bufnr, 0, -1) do
      local capture_name = python_test_query.captures[id]
      if capture_name == 'call' then
        local func_node = nil
        for child_id, child_node, metadata in python_test_query:iter_captures(node, bufnr) do
          local child_capture = python_test_query.captures[child_id]
          if child_capture == 'func' then
            func_node = child_node
            break
          end
        end

        if func_node then
          local func_name = vim.treesitter.get_node_text(func_node, bufnr)
          local start_row, start_col, end_row, end_col = node:range()
          table.insert(nodes, {
            node = node,
            func_name = func_name,
            title = func_name,
            start_row = start_row,
            end_row = end_row,
            is_context = false -- Python test functions aren't context
          })
        end
      end
    end
  end

  -- Sort by start position
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
  local bufnr = vim.api.nvim_get_current_buf()
  local nodes = get_test_nodes_via_query(bufnr)

  -- Find the test node that contains the target line
  for _, node_info in ipairs(nodes) do
    if not node_info.is_context and node_info.start_row <= target_line and node_info.end_row >= target_line then
      return node_info.title
    end
  end

  return ''
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

-- Return a CLI-quoted test title with context, matching historical escaping
function M.get_cli_quoted_test_title_with_context()
  local title = M.get_test_title_with_context()
  title = title:gsub("([%(%)%?])", "\\%1")
  title = title:gsub('"', '\\"')
  title = title:gsub('`', '\\`')
  return '\\"' .. title .. '\\"'
end

return M
