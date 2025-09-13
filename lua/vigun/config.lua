local M = {}

-- Accumulated user configuration provided via setup(); merged into defaults
M._user_config = nil
M._user_options = nil

-- Public setup API: merge provided table into accumulated user config.
-- Lists overwrite; tables deep-merge; scalars overwrite.
function M.setup(user_cfg)
  if type(user_cfg) ~= 'table' then
    error('vigun.config.setup: expected table, got ' .. type(user_cfg))
  end
  if M._user_config == nil then
    M._user_config = {}
  end
  if M._user_options == nil then
    M._user_options = {}
  end
  local function is_list(t)
    if type(t) ~= 'table' then return false end
    local count = 0
    for k, _ in pairs(t) do
      if type(k) ~= 'number' then return false end
      count = count + 1
    end
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
  local cfg = vim.deepcopy(user_cfg)

  -- Known top-level options (anything else scalar at top-level will also be treated as option)
  local option_keys = {
    tmux_window_name = true,
    tmux_pane_orientation = true,
    remember_last_command = true,
    dry_run = true,
  }

  -- Extract runners from explicit runners key
  local runners = cfg.runners
  if type(runners) == 'table' then
    cfg.runners = nil
    if type(M._user_config.runners) ~= 'table' then M._user_config.runners = {} end
    deep_merge(M._user_config.runners, runners)
  end

  -- Distribute remaining keys: tables -> runners; scalars -> options
  for k, v in pairs(cfg) do
    if type(v) == 'table' then
      if type(M._user_config.runners) ~= 'table' then M._user_config.runners = {} end
      if type(M._user_config.runners[k]) ~= 'table' then M._user_config.runners[k] = {} end
      deep_merge(M._user_config.runners[k], v)
    else
      -- scalar or function: treat as option
      if option_keys[k] or type(v) ~= 'nil' then
        M._user_options[k] = v
      end
    end
  end
end

-- Test helper: clear accumulated config
function M._reset()
  M._user_config = nil
  M._user_options = nil
end

function M.default_config()
  return {
    runners = {
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
        -- Use Treesitter for spec index: `test "..."` inside a test class
        test_nodes = { 'test' },
        -- Treat Ruby class definitions as contexts
        context_nodes = function(node, _)
          return node and (node:type() == 'class_definition' or node:type() == 'class')
        end,
        commands = {
          all = function(_)
            return 'rails test ' .. vim.fn.expand('%')
          end,
          nearest = function(_)
            return 'rails test ' .. vim.fn.expand('%') .. ':' .. vim.fn.line('.')
          end,
        },
      },
    },
  }
end

-- No fixed activation order; exactly one config must match.

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
  local user = M._user_config
  if type(user) ~= 'table' then return defaults end
  -- Merge user entries into defaults
  local result = vim.deepcopy(defaults)
  deep_merge(result, user)
  return result
end

-- Non-framework options
function M.default_options()
  return {
    tmux_window_name = 'test',
    tmux_pane_orientation = 'vertical', -- or 'horizontal'
    remember_last_command = true,
    dry_run = false,
  }
end

function M.get_options()
  local result = vim.deepcopy(M.default_options())
  if type(M._user_options) == 'table' then
    deep_merge(result, M._user_options)
  end
  return result
end

-- Modes are already trimmed/dequoted in Vimscript; no further normalization needed.

-- Return the first enabled config entry for the current buffer
function M.get_active()
  local cfg = merged_config()
  local matches = {}
  local keys = {}
  local runners = (type(cfg.runners) == 'table') and cfg.runners or {}
  for key, entry in pairs(runners) do
    if type(entry) == 'table' and type(entry.enabled) == 'function' then
      local res = entry.enabled()
      if res then
        table.insert(matches, entry)
        table.insert(keys, key)
      end
    end
  end
  if #matches == 0 then return nil end
  if #matches == 1 then return matches[1] end
  error('Vigun: multiple configs matched: ' .. table.concat(keys, ', '))
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
