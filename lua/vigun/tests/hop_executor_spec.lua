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

local function fake_config(extra)
  local config = {
    executor = 'hop',
    runners = {
      fake = {
        enabled = function()
          return vim.fn.expand('%'):match('hop_exec%.fake$') ~= nil
        end,
        commands = { all = function() return 'run-the-tests' end },
      },
    },
  }
  for k, v in pairs(extra or {}) do
    config.runners.fake[k] = v
  end
  return config
end

describe('vigun hop executor', function()
  before_each(function()
    Config._reset()
  end)

  it('reports a failed `hop run` (runner without on_result)', function()
    Config.setup(fake_config())

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

  it('reports a `hop wait` timeout (runner with on_result)', function()
    Config.setup(fake_config({ on_result = function() end }))

    -- `hop run` succeeds and prints an id; `hop wait` then times out (124).
    local script = '#!/bin/sh\ncase "$1" in\n  run) echo abc123 ;;\n  wait) echo "hop wait timed out" >&2; exit 124 ;;\nesac\n'
    with_fake_hop(script, function()
      with_buf('hop_exec.fake', function()
        vim.cmd('messages clear')
        Runner.run('all')
        assert.is_true(
          wait_for_message('hop wait timed out'),
          'expected hop wait stderr in messages, got: ' .. vim.fn.execute('messages')
        )
      end)
    end)
  end)

  it('delivers output to on_result when `hop wait` exits non-zero for failing tests', function()
    local seen
    Config.setup(fake_config({
      on_result = function(info)
        seen = info.output
      end,
    }))

    -- `hop run` prints an id; `hop wait` prints the failing run's output and
    -- exits 1 — the normal "tests failed" outcome, not a dispatch failure.
    local script = '#!/bin/sh\ncase "$1" in\n  run) echo abc123 ;;\n  wait) echo "1 failing"; exit 1 ;;\nesac\n'
    with_fake_hop(script, function()
      with_buf('hop_exec.fake', function()
        vim.cmd('messages clear')
        Runner.run('all')
        assert.is_true(
          vim.wait(2000, function() return seen ~= nil end, 50),
          'expected on_result to fire'
        )
        assert.equals('1 failing\n', seen)
        assert.is_nil(
          vim.fn.execute('messages'):find('ERROR', 1, true),
          'a failing test run must not raise an error notification'
        )
      end)
    end)
  end)
end)
