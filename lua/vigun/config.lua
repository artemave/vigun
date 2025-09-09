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
    {
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
    {
      enabled = function()
        return vim.fn.expand('%'):match('_test%.py$') ~= nil
      end,
      test_nodes = { 'test' },
      context_nodes = {},
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
    {
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

local function iter_entries(cfg)
  if type(cfg) ~= 'table' then return function() end end
  if cfg[1] ~= nil then
    local i = 0
    return function()
      i = i + 1
      if cfg[i] then return i, cfg[i] end
    end
  else
    return pairs(cfg)
  end
end

-- Return the first enabled config entry for the current buffer
function M.get_active()
  local cfg = M.has_config() and vim.g.vigun_config or M.default_config()
  for _, entry in iter_entries(cfg) do
    if type(entry.enabled) == 'function' then
      if entry.enabled() then
        return entry
      end
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

  -- Only pass semantic info that requires Treesitter; callsites may use vim.fn for file/line
  local info = {
    test_title = require('vigun.treesitter').get_test_title(),
    context_titles = require('vigun.treesitter').get_context_titles(),
  }

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
