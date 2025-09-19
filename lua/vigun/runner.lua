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

  -- error means the test window has been joined into the nvim window as pane
  -- and so we need to send the command to the pane instead
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

local function count_lines(s)
  local n = 0
  for _ in (s .. '\n'):gmatch('([^\n]*)\n') do n = n + 1 end
  return n
end

-- Remove trailing empty lines from captured tmux output
local function trim_trailing_empty_lines(s)
  local t = {}
  for line in (s .. '\n'):gmatch('([^\n]*)\n') do table.insert(t, line) end
  while #t > 0 and t[#t] == '' do table.remove(t, #t) end
  return table.concat(t, '\n')
end

local function suffix_after(before, after)
  local max_i = math.min(#before, #after)
  local i = 1
  while i <= max_i do
    if before:byte(i) ~= after:byte(i) then break end
    i = i + 1
  end
  return after:sub(i)
end

local function parse_history_count(raw)
  return tonumber((tostring(raw or '')):match('%d+')) or 0
end

local function make_buffer_snapshot(hist, visible_output)
  local trimmed = trim_trailing_empty_lines(visible_output or '')
  local visible = count_lines(trimmed)
  return {
    history = hist,
    visible = visible,
    total = hist + visible,
  }
end

-- Return totals combining tmux history and visible buffer lines
local function get_total_buffer_lines(pane)
  local out_hist = vim.fn.system({ 'tmux', 'display-message', '-p', '-t', pane, '#{history_size}' })
  local hist = parse_history_count(out_hist)

  local visible = vim.fn.system({ 'tmux', 'capture-pane', '-pJ', '-t', pane })
  return make_buffer_snapshot(hist, visible)
end

local function get_total_buffer_lines_async(pane, cb)
  vim.system({ 'tmux', 'display-message', '-p', '-t', pane, '#{history_size}' }, { text = true }, function(obj1)
    local hist = parse_history_count(obj1.stdout)

    vim.system({ 'tmux', 'capture-pane', '-pJ', '-t', pane }, { text = true }, function(obj2)
      cb(make_buffer_snapshot(hist, obj2.stdout))
    end)
  end)
end

local function capture_pane_range_async(id, start_line, end_line, cb)
  vim.system(
    { 'tmux', 'capture-pane', '-pJ', '-t', id, '-S', tostring(start_line), '-E', tostring(end_line) },
    { text = true },
    function(obj)
      cb(trim_trailing_empty_lines(obj.stdout))
    end
  )
end

local function list_descendants_async(root_pid, cb)
  vim.system({ 'ps', '-Ao', 'pid,ppid' }, { text = true }, function(obj)
    local out = obj.stdout
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

local function get_pane_pid(tmux_pane_id)
  local out = vim.fn.system({ 'tmux', 'display-message', '-p', '-t', tmux_pane_id, '#{pane_pid}' })
  local pid = tonumber(tostring(out):match('%d+'))
  if not pid then
    error('Vigun: could not determine tmux pane pid')
  end
  return pid
end

local function run_until_processes_done(tmux_pane_id, before_snapshot, on_done)
  if M._poll_timer then
    M._poll_timer:stop()
    if not M._poll_timer:is_closing() then M._poll_timer:close() end
  end

  local timer = vim.loop.new_timer()
  M._poll_timer = timer

  local started = vim.loop.now()
  local INTERVAL_MS = 100
  local TIMEOUT_MS = 30000
  local seen_busy = false
  local pane_pid = get_pane_pid(tmux_pane_id)

  timer:start(0, INTERVAL_MS, function()
    list_descendants_async(pane_pid, function(descendants)
      if timer ~= M._poll_timer then return end
      local now = vim.loop.now()
      local timed_out = (now - started) >= TIMEOUT_MS
      local count = #descendants
      if count > 0 then seen_busy = true end
      if (seen_busy and count == 0) or timed_out then
        timer:stop()
        if not timer:is_closing() then timer:close() end

        get_total_buffer_lines_async(tmux_pane_id, function(after_snapshot)
          local delta = after_snapshot.total - before_snapshot.total
          local start_index = after_snapshot.total - delta
          local end_index = after_snapshot.total

          local start_offset = start_index - after_snapshot.history
          local end_offset = end_index - after_snapshot.history

          capture_pane_range_async(tmux_pane_id, start_offset, end_offset, function(snap)
            if timer ~= M._poll_timer then return end
            on_done(snap)
          end)
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
  -- Capture buffer size before; we'll later fetch only the added tail
  local before_snapshot = get_total_buffer_lines(tmux_pane_id)

  -- Prepare result context
  local file = vim.fn.expand('%')

  local started_at = os.time()

  -- Send original command now that we've captured 'before'
  send_to_tmux(cmd)
  M._last = cmd

  run_until_processes_done(tmux_pane_id, before_snapshot, function(output)
    local ended_at = os.time()
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
