local M = {}

-- Cache the pane id so it stays stable when the test pane
-- is moved into/out of the Vim window and back.
local pane_id = nil
local poll_timer = nil
local pane_id_to_break_out = nil

local function get_options()
  return require('vigun.config').get_options()
end

function M.get_pane_id()
  if pane_id then
    vim.fn.system({'tmux', 'list-panes', '-t', pane_id})
    if vim.v.shell_error == 0 then return pane_id end
  end
  local win = get_options().tmux_window_name
  vim.fn.system("tmux list-windows -F '#{window_name}' | grep -w " .. win)
  if vim.v.shell_error ~= 0 then
    vim.fn.system({'tmux', 'new-window', '-d', '-n', win})
  end
  local out = vim.fn.system("tmux list-panes -F '#{pane_id}' -t " .. win)
  pane_id = (tostring(out):match('([^\n]+)') or tostring(out)):gsub('%s+$','')
  if pane_id == '' then
    error('Vigun: no known tmux pane id')
  end
  return pane_id
end

local function send(command)
  local opts = get_options()
  local tmux_pane_id = M.get_pane_id()
  local win = opts.tmux_window_name
  vim.fn.system({'tmux', 'select-window', '-t', win})

  -- error means the test window has been joined into the nvim window as pane
  -- and so we need to send the command to the pane instead
  if vim.v.shell_error ~= 0 then
    local vim_pane_id = vim.fn.getenv('TMUX_PANE')
    vim.fn.system({'tmux', 'select-pane', '-t', tmux_pane_id})
    vim.fn.system({'tmux', 'send-keys', 'C-c'})
    vim.fn.system({'tmux', 'send-keys', command, 'Enter'})
    vim.fn.system({'tmux', 'select-pane', '-t', vim_pane_id})
    return
  end

  vim.fn.system({'tmux', 'send-keys', 'C-c'})
  vim.fn.system({'tmux', 'send-keys', command, 'Enter'})
end

local function count_lines(s)
  local n = 0
  for _ in (s .. '\n'):gmatch('([^\n]*)\n') do n = n + 1 end
  return n
end

local function trim_trailing_empty_lines(s)
  local t = {}
  for line in (s .. '\n'):gmatch('([^\n]*)\n') do table.insert(t, line) end
  while #t > 0 and t[#t] == '' do table.remove(t, #t) end
  return table.concat(t, '\n')
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
  if poll_timer then
    poll_timer:stop()
    if not poll_timer:is_closing() then poll_timer:close() end
  end

  local timer = vim.loop.new_timer()
  poll_timer = timer

  local started = vim.loop.now()
  local INTERVAL_MS = 100
  local TIMEOUT_MS = 30000
  local seen_busy = false
  local pane_pid = get_pane_pid(tmux_pane_id)

  timer:start(0, INTERVAL_MS, function()
    list_descendants_async(pane_pid, function(descendants)
      if timer ~= poll_timer then return end
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
            if timer ~= poll_timer then return end
            on_done(snap)
          end)
        end)
      end
    end)
  end)
end

function M.run(cmd, on_done)
  local opts = get_options()
  if opts.dry_run then
    vim.api.nvim_echo({{cmd, ''}}, true, {})
    return
  end

  if not on_done then
    send(cmd)
    return
  end

  local tmux_pane_id = M.get_pane_id()
  local before_snapshot = get_total_buffer_lines(tmux_pane_id)
  send(cmd)
  run_until_processes_done(tmux_pane_id, before_snapshot, on_done)
end

function M.toggle_layout()
  local opts = get_options()
  local orientation = (opts.tmux_pane_orientation == 'horizontal') and '-v' or '-h'
  local win = opts.tmux_window_name

  local current_pane_id = M.get_pane_id()

  -- Determine size as one-third of available dimension
  local dim_query = (orientation == '-h') and '#{window_width}' or '#{window_height}'
  local dim_out = vim.fn.system({ 'tmux', 'display-message', '-p', dim_query })
  local total = tonumber(tostring(dim_out):match('%d+'))
  local size = math.floor(total / 3)
  if size < 20 then size = 20 end

  vim.fn.system({ 'tmux', 'join-pane', '-d', orientation, '-l', tostring(size), '-s', win })

  -- error means there was no pane, and then can only mean that it's already inside nvim window,
  -- so we are at the "break pane back into window" part of the toggle
  if vim.v.shell_error ~= 0 then
    vim.fn.system('tmux break-pane -d -n ' .. win .. ' -s ' .. pane_id_to_break_out)
  else
    pane_id_to_break_out = current_pane_id
  end
end

return M
