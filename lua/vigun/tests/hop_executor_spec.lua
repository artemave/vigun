local Config = require('vigun.config')
local Runner = require('vigun.runner')

local function with_buf(name, fn)
  vim.cmd('enew')
  vim.cmd('file ' .. name)
  local ok, err = pcall(fn)
  vim.cmd('bd!')
  assert(ok, err)
end

-- Put a real, executable `hop` ahead of the system one on PATH so vim.system
-- runs it for the duration of `fn`. A genuine subprocess at the process
-- boundary, in the spirit of on_result_tmux_spec's real-tmux integration.
local function with_fake_hop(script, fn)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  local path = dir .. '/hop'
  local fh = assert(io.open(path, 'w'))
  fh:write(script)
  fh:close()
  vim.fn.setfperm(path, 'rwxr-xr-x')

  local saved = vim.env.PATH
  vim.env.PATH = dir .. ':' .. saved
  local ok, err = pcall(fn)
  vim.env.PATH = saved
  vim.fn.delete(dir, 'rf')
  assert(ok, err)
end

local function wait_for_message(needle)
  return vim.wait(2000, function()
    return vim.fn.execute('messages'):find(needle, 1, true) ~= nil
  end, 50)
end

describe('vigun hop executor surfaces failures', function()
  before_each(function()
    Config._reset()
  end)

  it('reports a failed `hop run` (runner without on_result)', function()
    Config.setup({
      executor = 'hop',
      runners = {
        fake = {
          enabled = function()
            return vim.fn.expand('%'):match('hop_exec%.fake$') ~= nil
          end,
          commands = { all = function() return 'run-the-tests' end },
        },
      },
    })

    local script = '#!/bin/sh\necho "no focused hop editor" >&2\nexit 1\n'
    with_fake_hop(script, function()
      with_buf('hop_exec.fake', function()
        vim.cmd('messages clear')
        Runner.run('all')
        assert.is_true(
          wait_for_message('no focused hop editor'),
          'expected hop stderr in messages, got: ' .. vim.fn.execute('messages')
        )
      end)
    end)
  end)

  it('reports a failed `hop tail` (runner with on_result)', function()
    Config.setup({
      executor = 'hop',
      runners = {
        fake = {
          enabled = function()
            return vim.fn.expand('%'):match('hop_exec%.fake$') ~= nil
          end,
          commands = { all = function() return 'run-the-tests' end },
          on_result = function() end,
        },
      },
    })

    -- `hop run` succeeds and prints an id; `hop tail` then fails.
    local script = '#!/bin/sh\ncase "$1" in\n  run) echo abc123 ;;\n  tail) echo "tail stream broke" >&2; exit 1 ;;\nesac\n'
    with_fake_hop(script, function()
      with_buf('hop_exec.fake', function()
        vim.cmd('messages clear')
        Runner.run('all')
        assert.is_true(
          wait_for_message('tail stream broke'),
          'expected hop tail stderr in messages, got: ' .. vim.fn.execute('messages')
        )
      end)
    end)
  end)
end)
