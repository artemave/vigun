local M = {}
M._last = nil
M._poll_timer = nil
-- Cache the pane id so it stays stable when the test pane
-- is moved into/out of the Vim window and back.
local pane_id = nil

local function has_only()
  return require('vigun.treesitter').has_only_tests()
end

local function effective_mode(mode)
  if mode:find('nearest', 1, true) and has_only() then
    return (mode:gsub('nearest', 'all'))
  end
  return mode
end

local function send_to_tmux(command)
  local opts = require('vigun.config').get_options()
  if opts.dry_run then
    -- Print exactly what command function returned; no extra escaping
    vim.api.nvim_echo({{command, ''}}, true, {})
    return
  end

  local tmux_pane_id = M.get_tmux_pane_id()
  local win = opts.tmux_window_name
  vim.fn.system({'tmux', 'select-window', '-t', win})

  if vim.v.shell_error ~= 0 then
    local vim_pane_id = vim.fn.getenv('TMUX_PANE')
    vim.fn.system({'tmux', 'select-pane', '-t', tmux_pane_id})

    -- Send Ctrl-C
    vim.fn.system({'tmux', 'send-keys', 'C-c'})
    vim.fn.system({'tmux', 'send-keys', command, 'Enter'})
    vim.fn.system({'tmux', 'select-pane', '-t', vim_pane_id})

    return
  end

  vim.fn.system({'tmux', 'send-keys', 'C-c'})
  vim.fn.system({'tmux', 'send-keys', command, 'Enter'})
end

-- Helpers -------------------------------------------------------------------

local HISTORY_LINES = 32768
local ANCHOR_LINES = 32
local FALLBACK_TAIL_LINES = 800

local function slice_new_output(before, after)
  -- Build anchor from last K lines of before
  local blines = {}
  for line in (before .. '\n'):gmatch('([^\n]*)\n') do
    table.insert(blines, line)
  end
  local start_idx = math.max(1, #blines - ANCHOR_LINES + 1)
  local anchor = table.concat({ unpack(blines, start_idx, #blines) }, '\n')
  if #anchor > 0 then
    -- find last occurrence of anchor in after
    local p = 0
    local lastp = nil
    while true do
      p = after:find(anchor, p + 1, true)
      if not p then break end
      lastp = p
    end
    if lastp then
      local slice_start = lastp + #anchor
      local out = after:sub(slice_start)
      if out and #out > 0 then return out end
    end
  end
  -- Fallback: last N lines of after
  local alines = {}
  for line in (after .. '\n'):gmatch('([^\n]*)\n') do
    table.insert(alines, line)
  end
  local nstart = math.max(1, #alines - FALLBACK_TAIL_LINES + 1)
  return table.concat({ unpack(alines, nstart, #alines) }, '\n')
end

local function capture_pane_sync()
  local id = M.get_tmux_pane_id()
  local out = vim.fn.system({ 'tmux', 'capture-pane', '-pJ', '-t', id, '-S', '-' .. tostring(HISTORY_LINES) })
  return out
end

local function capture_pane_async(id, cb)
  vim.system({ 'tmux', 'capture-pane', '-pJ', '-t', id, '-S', '-' .. tostring(HISTORY_LINES) }, { text = true }, function(obj)
    cb(obj.stdout or '')
  end)
end

-- Polling helpers: detect completion by watching child processes of the pane shell
local function list_descendants_async(root_pid, cb)
  -- Portable approach using ps; parse pid/ppid and compute descendant set
  vim.system({ 'ps', '-Ao', 'pid,ppid' }, { text = true }, function(obj)
    local out = obj.stdout or ''
    local children = {}
    for line in tostring(out):gmatch('[^\n]+') do
      local pid, ppid = line:match('%s*(%d+)%s+(%d+)')
      if pid and ppid then
        pid = tonumber(pid)
        ppid = tonumber(ppid)
        if not children[ppid] then children[ppid] = {} end
        table.insert(children[ppid], pid)
      end
    end
    local root = tonumber(root_pid)
    local seen = {}
    local frontier = { root }
    seen[root] = true
    local descendants = {}
    while #frontier > 0 do
      local next_frontier = {}
      for _, p in ipairs(frontier) do
        for _, c in ipairs(children[p] or {}) do
          if not seen[c] then
            seen[c] = true
            table.insert(descendants, c)
            table.insert(next_frontier, c)
          end
        end
      end
      frontier = next_frontier
    end
    cb(descendants)
  end)
end

-- Resolve the pane's root shell PID (stable across a run)
local function get_pane_pid(pane_id_arg)
  local out = vim.fn.system({ 'tmux', 'display-message', '-p', '-t', pane_id_arg, '#{pane_pid}' })
  local pid = tonumber((tostring(out):match('(%d+)') or ''))
  if not pid then
    error('Vigun: could not determine tmux pane pid')
  end
  return pid
end

-- Polling helpers: mark done when the pane shell has no descendants for N ticks
local function run_until_processes_done(pane_id_arg, before_snapshot, on_done)
  if M._poll_timer then
    M._poll_timer:stop()
    M._poll_timer:close()
  end

  local timer = vim.loop.new_timer()
  M._poll_timer = timer

  local started = vim.loop.now()
  -- TODO: add timeout to config
  local TIMEOUT_MS = 30000
  local INTERVAL_MS = 100
  -- Finish as soon as we've observed the process tree become non-empty at
  -- least once, and then drop to zero (i.e., the test process ended).
  local seen_busy = false
  local pane_pid = get_pane_pid(pane_id_arg)

  timer:start(0, INTERVAL_MS, function()
    list_descendants_async(pane_pid, function(descendants)
      if timer ~= M._poll_timer then return end

      local now = vim.loop.now()
      local timed_out = (now - started) >= TIMEOUT_MS
      local count = #descendants
      if count > 0 then
        seen_busy = true
      end
      if (seen_busy and count == 0) or timed_out then
        timer:stop()
        timer:close()

        capture_pane_async(pane_id_arg, function(snap)
          if timer ~= M._poll_timer then return end

          on_done(snap)
        end)
      end
    end)
  end)
end

function M.run(mode)
  local emode = effective_mode(mode)
  local cmd = require('vigun.config').get_command(emode)
  local config = require('vigun.config').get_active()

  if not config then
    error('Vigun: no enabled config for ' .. vim.fn.expand('%'))
  end

  if not emode then
    error("Vigun: no command '" .. emode .. "' for current file")
  end

  local opts = require('vigun.config').get_options()

  if not config.on_result or opts.dry_run then
    send_to_tmux(cmd)
    M._last = cmd
  end

  -- Resolve pane id once and use it across async callbacks
  local tmux_pane_id = M.get_tmux_pane_id()
  local before = capture_pane_sync()

  -- Prepare result context
  local file = vim.fn.expand('%')

  local started_at = os.time()

  -- Send original command now that we've captured 'before'
  send_to_tmux(cmd)
  M._last = cmd

  run_until_processes_done(tmux_pane_id, before, function(after)
    local output = slice_new_output(before, after)
    local ended_at = os.time()

    -- Run user callback on main loop to avoid fast-event API restrictions
    vim.schedule(function()
      config.on_result({
        command = cmd,
        mode = mode,
        file = file,
        output = output,
        started_at = started_at,
        ended_at = ended_at,
      })
    end)
  end)
end

-- CLI entry used by :VigunRun <mode>
function M.cli(mode)
  local ok, val = pcall(function() return M.run(mode) end)
  if not ok then
    local opts = require('vigun.config').get_options()
    if opts.remember_last_command and M._last then
      send_to_tmux(M._last)
    else
      error(val)
    end
  end
end

-- Expose last known tmux pane id for helpers (e.g., join/break)
function M.get_tmux_pane_id()
  -- Reuse cached pane id if it still exists
  if pane_id then
    vim.fn.system({'tmux', 'list-panes', '-t', pane_id})
    if vim.v.shell_error == 0 then return pane_id end
  end
  local win = require('vigun.config').get_options().tmux_window_name
  -- Ensure window exists
  vim.fn.system("tmux list-windows -F '#{window_name}' | grep -w " .. win)
  if vim.v.shell_error ~= 0 then
    vim.fn.system({'tmux', 'new-window', '-d', '-n', win})
  end
  -- Cache and return the first pane id in that window
  local out = vim.fn.system("tmux list-panes -F '#{pane_id}' -t " .. win)
  pane_id = (tostring(out):match('([^\n]+)') or tostring(out)):gsub('%s+$','')
  if pane_id == '' then
    error('Vigun: no known tmux pane id')
  end
  return pane_id
end

return M
