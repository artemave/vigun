local M = {}
M._last = nil

local function has_only()
  return require('vigun.treesitter').has_only_tests()
end

local function effective_mode(mode)
  if mode:find('nearest', 1, true) and has_only() then
    return (mode:gsub('nearest', 'all'))
  end
  return mode
end

local function normalize_mode(mode)
  if type(mode) == 'string' and #mode >= 2 then
    local first = mode:sub(1,1)
    local last = mode:sub(-1)
    if (first == last) and (first == '"' or first == "'") then
      mode = mode:sub(2, -2)
    end
  end
  return mode
end

-- Minimal tmux integration (not exercised in tests when dry_run option is set)
local pane_id = nil
local function ensure_tmux_window()
  if pane_id then
    vim.fn.system({'tmux', 'list-panes', '-t', pane_id})
    if vim.v.shell_error == 0 then return end
  end

  local win = require('vigun.config').get_options().tmux_window_name or 'test'
  vim.fn.system("tmux list-windows -F '#{window_name}' | grep -w " .. win)
  if vim.v.shell_error ~= 0 then
    vim.fn.system({'tmux', 'new-window', '-d', '-n', win})
  end
  pane_id = vim.fn.system("tmux list-panes -F '#{pane_id}' -t " .. win)
  pane_id = pane_id:gsub('%s+$','')
end

local function send_to_tmux(command)
  local opts = require('vigun.config').get_options()
  if opts.dry_run then
    -- Print exactly what command function returned; no extra escaping
    vim.api.nvim_echo({{command, ''}}, true, {})
    return
  end

  ensure_tmux_window()

  local win = opts.tmux_window_name or 'test'
  vim.fn.system({'tmux', 'select-window', '-t', win})
  if vim.v.shell_error ~= 0 then
    local vim_pane_id = vim.fn.getenv('TMUX_PANE') or ''
    if pane_id and #pane_id > 0 then
      vim.fn.system({'tmux', 'select-pane', '-t', pane_id})
    end
    -- Send Ctrl-C
    vim.fn.system({'tmux', 'send-keys', 'C-c'})
    vim.fn.system({'tmux', 'send-keys', command, 'Enter'})
    if vim_pane_id ~= '' then
      vim.fn.system({'tmux', 'select-pane', '-t', vim_pane_id})
    end
    return
  end

  vim.fn.system({'tmux', 'send-keys', 'C-c'})
  vim.fn.system({'tmux', 'send-keys', command, 'Enter'})
end

function M.run(mode)
  mode = normalize_mode(mode)
  local emode = effective_mode(mode)
  local cmd = require('vigun.config').get_command(emode)
  if type(cmd) ~= 'string' or cmd == '' then
    local active = require('vigun.config').get_active()
    if active == nil then
      error('Vigun: no enabled config for ' .. vim.fn.expand('%'))
    else
      error("Vigun: no command '" .. emode .. "' for current file")
    end
  end
  send_to_tmux(cmd)
  M._last = cmd
  return cmd
end

function M.safe_run(mode)
  local ok, val = pcall(function() return M.run(mode) end)
  return { ok = ok, val = val }
end

function M.exec(cmd)
  send_to_tmux(cmd)
  M._last = cmd
  return cmd
end

function M.safe_exec(cmd)
  local ok, val = pcall(function() return M.exec(cmd) end)
  return { ok = ok, val = val }
end

-- CLI entry used by :VigunRun <mode>
function M.cli(mode)
  if type(mode) == 'string' and #mode >= 2 then
    local first = mode:sub(1,1)
    local last = mode:sub(-1)
    if (first == last) and (first == '"' or first == "'") then
      mode = mode:sub(2, -2)
    end
  end
  local ok, val = pcall(function() return M.run(mode) end)
  if not ok then
    local opts = require('vigun.config').get_options()
    if opts.remember_last_command and M._last then
      M.exec(M._last)
    else
      error(val)
    end
  end
end

-- Expose last known tmux pane id for helpers (e.g., join/break)
function M.get_tmux_pane_id()
  return pane_id or error('Vigun: no known tmux pane id')
end

return M
