local M = {}

-- Returns true if a user config is present
function M.has_config()
  return type(vim.g.vigun_config) == 'table'
end

-- Internal default configuration used when no user config is provided
-- Use shellescape to return safe single-quoted shell arguments
local function shell_q(s)
  return vim.fn.shellescape(s)
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
          local quoted = shell_q(title)
          return './node_modules/.bin/mocha --fgrep ' .. quoted .. ' ' .. vim.fn.expand('%')
        end,
        ['debug-nearest'] = function(info)
          local parts = {}
          for _, c in ipairs(info.context_titles) do table.insert(parts, c) end
          table.insert(parts, info.test_title)
          local title = table.concat(parts, ' ')
          local quoted = shell_q(title)
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
          local quoted = shell_q(info.test_title)
          return 'pytest -k ' .. quoted .. ' -s ' .. vim.fn.expand('%')
        end,
        ['debug-all'] = function(_)
          return 'pytest -vv -s ' .. vim.fn.expand('%')
        end,
        ['debug-nearest'] = function(info)
          local quoted = shell_q(info.test_title)
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
  }
end

-- Order used when checking which config is active
M._order = { 'mocha', 'pytest', 'rspec' }

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

local function normalize_mode(mode)
  if type(mode) ~= 'string' then return mode end
  mode = mode:gsub('^%s+', ''):gsub('%s+$', '')
  if #mode >= 2 then
    local first = mode:sub(1,1)
    local last = mode:sub(-1)
    if (first == last) and (first == '"' or first == "'") then
      mode = mode:sub(2, -2)
    end
  end
  return mode
end

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
  mode = normalize_mode(mode)
  local entry = M.get_active()
  if not entry then
    error('Vigun: no enabled config for ' .. vim.fn.expand('%'))
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
    local ok_cmd, result = pcall(fn, info)
    if ok_cmd and type(result) == 'string' and #result > 0 then
      return result
    end
  end

  error("Vigun: no command '" .. tostring(mode) .. "' for current file")
end

-- Safe wrapper used from Vimscript to avoid luaeval quoting issues
function M.safe_get(mode)
  local ok, val = pcall(function()
    return M.get_command(mode)
  end)
  return { ok = ok, val = val }
end

return M
