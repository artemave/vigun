local Config = require('vigun.config')
local Runner = require('vigun.runner')

local function with_buf(name, fn)
  vim.cmd('enew')
  vim.cmd('file ' .. name)
  local ok, err = pcall(fn)
  vim.cmd('bd!')
  assert(ok, err)
end

describe('vigun.runner on_result with real tmux', function()
  if vim.fn.executable('tmux') ~= 1 or vim.fn.getenv('TMUX') == vim.NIL then
    pending('tmux not available or not running inside tmux')
    return
  end

  local win

  before_each(function()
    Config._reset()
  end)

  after_each(function()
    if win then
      vim.fn.system({'tmux', 'kill-window', '-t', win})
    end
  end)

  it('fires on_result and includes run output', function()
    local received
    -- Use a unique window name so we don't collide with other panes in this session
    win = 'vigun-int-' .. math.floor(vim.loop.now())
    -- Create a temporary window for this test; cleaned up at the end
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
              return [[sh -lc 'printf RUN1\n; sleep 0.2; printf RUN2\n']]
            end,
          },
          on_result = function(info)
            received = info
          end,
        },
      },
    })

    with_buf('tmux_integration.fake', function()
      Runner.run('all')
      local ok = vim.wait(2000, function() return received ~= nil end, 50)

      assert.is_true(ok, 'on_result was not invoked')
      assert.equals([[sh -lc 'printf RUN1\n; sleep 0.2; printf RUN2\n']], received.command)
      assert.equals('all', received.mode)
      assert.equals('tmux_integration.fake', received.file)
      assert.is_true(type(received.started_at) == 'number')
      assert.is_true(type(received.ended_at) == 'number')
      assert.is_true(received.ended_at >= received.started_at)
      -- Output should contain both lines in order; allow extra prompt/noise
      local o = received.output or ''
      assert.is_truthy(o:find('RUN1'))
      assert.is_truthy(o:find('RUN2'))
      assert.is_true((o:find('RUN1') or 0) < (o:find('RUN2') or 0))
    end)
  end)
end)
