local Config = require('vigun.config')

local function with_buf(name, fn)
  vim.cmd('enew')
  vim.cmd('file ' .. name)
  local ok, err = pcall(fn)
  vim.cmd('bd!')
  assert(ok, err)
end

describe('vigun.config keyed + deep merge', function()
  before_each(function()
    vim.g.vigun_config = nil
  end)

  it('uses default mocha on Spec.js files', function()
    with_buf('testSpec.js', function()
      local active = Config.get_active()
      assert.equals('table', type(active))
      local cmd = Config.get_command('all')
      assert.equals('./node_modules/.bin/mocha testSpec.js', cmd)
    end)
  end)

  it('allows overriding a single command while keeping defaults', function()
    vim.g.vigun_config = {
      mocha = {
        commands = {
          all = function(_)
            return 'custom ' .. vim.fn.expand('%')
          end,
        },
      },
    }
    with_buf('testSpec.js', function()
      local all_cmd = Config.get_command('all')
      assert.equals('custom testSpec.js', all_cmd)
      local dbg_all = Config.get_command('debug-all')
      assert.equals('./node_modules/.bin/mocha --inspect-brk --no-timeouts testSpec.js', dbg_all)
    end)
  end)

  it('respects enabled override to broaden selection', function()
    vim.g.vigun_config = {
      mocha = {
        enabled = function()
          return vim.fn.expand('%'):match('%.js$') ~= nil
        end,
      },
    }
    with_buf('blahStuff.js', function()
      local cmd = Config.get_command('all')
      assert.equals('./node_modules/.bin/mocha blahStuff.js', cmd)
    end)
  end)

  it('keeps known-key priority over unknown keys, but falls back when disabled', function()
    vim.g.vigun_config = {
      custom = {
        enabled = function()
          return vim.fn.expand('%'):match('Spec%.js$') ~= nil
        end,
        commands = {
          all = function(_)
            return 'custom-all ' .. vim.fn.expand('%')
          end,
        },
      },
    }
    with_buf('testSpec.js', function()
      local cmd = Config.get_command('all')
      assert.equals('./node_modules/.bin/mocha testSpec.js', cmd)
    end)

    vim.g.vigun_config = {
      mocha = { enabled = function() return false end },
      custom = {
        enabled = function() return vim.fn.expand('%'):match('Spec%.js$') ~= nil end,
        commands = { all = function(_) return 'custom-all ' .. vim.fn.expand('%') end },
      },
    }
    with_buf('testSpec.js', function()
      local cmd = Config.get_command('all')
      assert.equals('custom-all testSpec.js', cmd)
    end)
  end)
end)
