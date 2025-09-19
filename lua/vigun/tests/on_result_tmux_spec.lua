local Config = require('vigun.config')
local Runner = require('vigun.runner')

local function with_buf(name, fn)
  vim.cmd('enew')
  vim.cmd('file ' .. name)
  local ok, err = pcall(fn)
  vim.cmd('bd!')
  assert(ok, err)
end

local function seed_tmux_history(window)
  local token = 'vigun-seed-' .. tostring(vim.loop.hrtime())
  local script_lines = {
    'xyz1',
    'xyz2',
    'i=0',
    'while [ $i -lt 500 ]; do',
    '  echo FILL',
    '  i=$((i + 1))',
    'done',
    'tmux wait-for -S ' .. token,
  }
  local tmp = vim.fn.tempname()
  local fh = assert(io.open(tmp, 'w'))
  fh:write(table.concat(script_lines, '\n'))
  fh:write('\n')
  fh:close()

  vim.fn.system({'tmux', 'load-buffer', tmp})
  assert.equals(0, vim.v.shell_error, 'failed to load tmux seed buffer')

  vim.fn.system({'tmux', 'paste-buffer', '-d', '-t', window})
  assert.equals(0, vim.v.shell_error, 'failed to paste tmux seed buffer')

  vim.fn.system({'tmux', 'wait-for', token})
  assert.equals(0, vim.v.shell_error, 'tmux seed wait failed')

  vim.fn.delete(tmp)
end

describe('vigun.runner on_result with real tmux', function()
  if vim.fn.executable('tmux') ~= 1 or vim.fn.getenv('TMUX') == vim.NIL then
    pending('tmux not available or not running inside tmux')
    return
  end

  local win
  local received

  before_each(function()
    Config._reset()
    received = nil
    win = 'vigun-int-' .. math.floor(vim.loop.now())
    vim.fn.system({'tmux', 'new-window', '-d', '-n', win})
    Config.setup({
      dry_run = false,
      tmux_window_name = win,
      runners = {
        integ = {
          enabled = function()
            return vim.fn.expand('%'):match('tmux_integration%.fake$') ~= nil
          end,
          commands = {
            all = function()
              -- Print two lines with a short delay to ensure a child process exists
              return [[sh -lc 'xyz1; sleep 0.2; xyz2']]
            end,
          },
          on_result = function(info)
            received = info
          end,
        },
      },
    })
  end)

  after_each(function()
    if win then
      vim.fn.system({'tmux', 'kill-window', '-t', win})
    end
  end)

  it('fires on_result and includes run output', function()
    with_buf('tmux_integration.fake', function()
      Runner.run('all')
      local ok = vim.wait(2000, function() return received ~= nil end, 50)

      assert.is_true(ok, 'on_result was not invoked')
      assert.equals([[sh -lc 'xyz1; sleep 0.2; xyz2']], received.command)
      assert.equals('all', received.mode)
      assert.equals('tmux_integration.fake', received.file)
      assert.is_true(type(received.started_at) == 'number')
      assert.is_true(type(received.ended_at) == 'number')
      assert.is_true(received.ended_at >= received.started_at)
      -- Output should contain both lines in order; allow extra prompt/noise
      assert.is_truthy(received.output:find('xyz1: command not found'))
      assert.is_truthy(received.output:find('xyz2: command not found'))
    end)
  end)

  it('does not include pre-existing matching visible output', function()
    with_buf('tmux_integration.fake', function()
      -- Pre-seed visible area with the same markers
      vim.fn.system({'tmux', 'send-keys', '-t', win, 'xyz1', 'Enter'})
      vim.fn.system({'tmux', 'send-keys', '-t', win, 'xyz2', 'Enter'})

      Runner.run('all')
      local ok = vim.wait(2000, function() return received ~= nil end, 50)
      assert.is_true(ok, 'on_result was not invoked')

      local _, n1 = received.output:gsub('xyz1: command not found', '')
      local _, n2 = received.output:gsub('xyz2: command not found', '')
      assert.equals(1, n1)
      assert.equals(1, n2)
    end)
  end)

  it('does not include pre-existing matching output in history', function()
    with_buf('tmux_integration.fake', function()
      -- Seed matching lines, then fill scrollback to push them into history
      seed_tmux_history(win)

      Runner.run('all')
      local ok = vim.wait(2000, function() return received ~= nil end, 50)
      assert.is_true(ok, 'on_result was not invoked')

      local _, n1 = received.output:gsub('xyz1: command not found', '')
      local _, n2 = received.output:gsub('xyz2: command not found', '')
      assert.equals(1, n1)
      assert.equals(1, n2)
    end)
  end)
end)
