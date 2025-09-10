local M = {}

-- Returns true if a user config is present
function M.has_config()
  return type(vim.g.vigun_config) == 'table'
end

function M.default_config()
  return {
    mocha = {
      enabled = function()
        return vim.fn.expand('%'):match('Spec%.js$') ~= nil
      end,
      test_nodes = { 'it', 'xit' },
      context_nodes = { 'context', 'describe' },
      commands = {
        all = function(_)
          return './node_modules/.bin/mocha ' .. vim.fn.expand('%')
        end,
        ['debug-all'] = function(_)
          return './node_modules/.bin/mocha --inspect-brk --no-timeouts ' .. vim.fn.expand('%')
        end,
        nearest = function(info)
          local parts = {}
          for _, c in ipairs(info.context_titles) do table.insert(parts, c) end
          table.insert(parts, info.test_title)
          local title = table.concat(parts, ' ')
          local quoted = vim.fn.shellescape(title)
          return './node_modules/.bin/mocha --fgrep ' .. quoted .. ' ' .. vim.fn.expand('%')
        end,
        ['debug-nearest'] = function(info)
          local parts = {}
          for _, c in ipairs(info.context_titles) do table.insert(parts, c) end
          table.insert(parts, info.test_title)
          local title = table.concat(parts, ' ')
          local quoted = vim.fn.shellescape(title)
          return './node_modules/.bin/mocha --inspect-brk --no-timeouts --fgrep ' .. quoted .. ' ' .. vim.fn.expand('%')
        end,
      },
    },
    pytest = {
      enabled = function()
        return vim.fn.expand('%'):match('_test%.py$') ~= nil
      end,
      -- Predicate: pytest tests are functions starting with test_
      test_nodes = function(node, name)
        return node and node:type() == 'function_definition' and type(name) == 'string' and name:match('^test_') ~= nil
      end,
      -- Predicate: treat classes as context containers for titles
      context_nodes = function(node, name)
        return node and node:type() == 'class_definition'
      end,
      commands = {
        all = function(_)
          return 'pytest -s ' .. vim.fn.expand('%')
        end,
        nearest = function(info)
          local quoted = vim.fn.shellescape(info.test_title)
          return 'pytest -k ' .. quoted .. ' -s ' .. vim.fn.expand('%')
        end,
        ['debug-all'] = function(_)
          return 'pytest -vv -s ' .. vim.fn.expand('%')
        end,
        ['debug-nearest'] = function(info)
          local quoted = vim.fn.shellescape(info.test_title)
          return 'pytest -vv -k ' .. quoted .. ' -s ' .. vim.fn.expand('%')
        end,
      },
    },
    rspec = {
      enabled = function()
        return vim.fn.expand('%'):match('_spec%.rb$') ~= nil
      end,
      test_nodes = { 'it', 'xit' },
      context_nodes = { 'describe', 'context' },
      commands = {
        all = function(_)
          return 'rspec ' .. vim.fn.expand('%')
        end,
        nearest = function(_)
          return 'rspec ' .. vim.fn.expand('%') .. ':' .. vim.fn.line('.')
        end,
      },
    },
    minitest_rails = {
      enabled = function()
        return vim.fn.expand('%'):match('_test%.rb$') ~= nil
      end,
      -- line-number based; Tree-sitter not needed
      test_nodes = {},
      context_nodes = {},
      commands = {
        all = function(_)
          return 'rails test ' .. vim.fn.expand('%')
        end,
        nearest = function(_)
          return 'rails test ' .. vim.fn.expand('%') .. ':' .. vim.fn.line('.')
        end,
      },
    },
  }
end

-- Order used when checking which config is active
M._order = { 'mocha', 'pytest', 'rspec', 'minitest_rails' }

-- Deep merge user config into defaults, merging by top-level keys (mocha, pytest, etc.)
local function is_list(t)
  if type(t) ~= 'table' then return false end
  local count = 0
  for k, _ in pairs(t) do
    if type(k) ~= 'number' then return false end
    count = count + 1
  end
  -- allow sparse but treat numeric-key-only tables as lists
  return count > 0
end

local function deep_merge(dst, src)
  for k, v in pairs(src or {}) do
    if type(v) == 'table' and type(dst[k]) == 'table' then
      if is_list(v) or is_list(dst[k]) then
        dst[k] = vim.deepcopy(v)
      else
        deep_merge(dst[k], v)
      end
    else
      dst[k] = v
    end
  end
  return dst
end

local function merged_config()
  local defaults = M.default_config()
  if not M.has_config() then return defaults end
  local user = vim.g.vigun_config
  if type(user) ~= 'table' then return defaults end
  -- Merge only known keys; also allow new keys but they will be considered later
  local result = {}
  -- Start with defaults clone
  for k, v in pairs(defaults) do
    if type(v) == 'table' then
      result[k] = vim.deepcopy(v)
    else
      result[k] = v
    end
  end
  -- Merge user entries by key
  for k, v in pairs(user) do
    if result[k] ~= nil and type(v) == 'table' then
      deep_merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

-- Modes are already trimmed/dequoted in Vimscript; no further normalization needed.

-- Return the first enabled config entry for the current buffer
function M.get_active()
  local cfg = merged_config()
  -- Check in declared order first
  for _, key in ipairs(M._order) do
    local entry = cfg[key]
    if entry and type(entry.enabled) == 'function' and entry.enabled() then
      return entry
    end
  end
  -- Fallback: check any other keys provided by user
  for key, entry in pairs(cfg) do
    local known = false
    for _, k in ipairs(M._order) do if k == key then known = true break end end
    if not known and type(entry) == 'table' and type(entry.enabled) == 'function' then
      if entry.enabled() then return entry end
    end
  end
end

-- Build the command string for a mode (e.g., 'all', 'nearest', 'debug-nearest')
-- Returns nil if no matching enabled entry or command (caller may throw)
function M.get_command(mode)
  -- mode is expected to be a simple token like 'all' or 'nearest'
  local entry = M.get_active()

  if not entry then
    return nil
  end

  -- Lazily-computed semantic info; avoids requiring Treesitter unless needed
  local function make_info()
    local cache = {}
    return setmetatable({}, {
      __index = function(_, key)
        if cache[key] ~= nil then return cache[key] end
        local ts = require('vigun.treesitter')
        if key == 'test_title' then
          cache[key] = ts.get_test_title()
        elseif key == 'context_titles' then
          cache[key] = ts.get_context_titles()
        else
          return nil
        end
        return cache[key]
      end
    })
  end
  local info = make_info()

  local cmds = entry.commands or {}
  local fn = cmds[mode]
  if type(fn) == 'function' then
    return fn(info)
  end
  return nil
end

-- Safe wrapper used from Vimscript to avoid luaeval quoting issues
return M
