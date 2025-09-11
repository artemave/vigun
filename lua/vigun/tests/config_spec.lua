local Config = require('vigun.config')

local function with_buf(name, fn)
  vim.cmd('enew')
  vim.cmd('file ' .. name)
  local ok, err = pcall(fn)
  vim.cmd('bd!')
  assert(ok, err)
end

describe('vigun.config setup() + deep merge', function()
  before_each(function()
    Config._reset()
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
    Config.setup({
      mocha = {
        commands = {
          all = function(_)
            return 'custom ' .. vim.fn.expand('%')
          end,
        },
      },
    })
    with_buf('testSpec.js', function()
      local all_cmd = Config.get_command('all')
      assert.equals('custom testSpec.js', all_cmd)
      local dbg_all = Config.get_command('debug-all')
      assert.equals('./node_modules/.bin/mocha --inspect-brk --no-timeouts testSpec.js', dbg_all)
    end)
  end)

  it('respects enabled override to broaden selection', function()
    Config.setup({
      mocha = {
        enabled = function()
          return vim.fn.expand('%'):match('%.js$') ~= nil
        end,
      },
    })
    with_buf('blahStuff.js', function()
      local cmd = Config.get_command('all')
      assert.equals('./node_modules/.bin/mocha blahStuff.js', cmd)
    end)
  end)

  it('errors on multiple enabled configs; works when one is disabled', function()
    Config.setup({
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
    })
    with_buf('testSpec.js', function()
      local ok, err = pcall(function()
        Config.get_command('all')
      end)
      assert.is_false(ok)
      assert.truthy(tostring(err):match('multiple configs'))
    end)

    Config._reset()
    Config.setup({
      mocha = { enabled = function() return false end },
      custom = {
        enabled = function() return vim.fn.expand('%'):match('Spec%.js$') ~= nil end,
        commands = { all = function(_) return 'custom-all ' .. vim.fn.expand('%') end },
      },
    })
    with_buf('testSpec.js', function()
      local cmd = Config.get_command('all')
      assert.equals('custom-all testSpec.js', cmd)
    end)
  end)

  it('merges nested tables without clobbering siblings (commands)', function()
    Config.setup({
      mocha = {
        commands = {
          nearest = function(_)
            return 'custom-nearest ' .. vim.fn.expand('%')
          end,
        },
      },
    })
    with_buf('testSpec.js', function()
      local nearest = Config.get_command('nearest')
      assert.equals('custom-nearest testSpec.js', nearest)
      local all_cmd = Config.get_command('all')
      assert.equals('./node_modules/.bin/mocha testSpec.js', all_cmd)
      local dbg_all = Config.get_command('debug-all')
      assert.equals('./node_modules/.bin/mocha --inspect-brk --no-timeouts testSpec.js', dbg_all)
    end)
  end)

  it('overrides list fields entirely (test_nodes)', function()
    Config.setup({
      mocha = {
        test_nodes = { 'fit' },
      },
    })
    with_buf('testSpec.js', function()
      local active = Config.get_active()
      assert.same({ 'fit' }, active.test_nodes)
      assert.same({ 'context', 'describe' }, active.context_nodes)
    end)
  end)

  it('preserves function predicates in merge (pytest)', function()
    local fn = function() return true end
    Config.setup({
      pytest = {
        test_nodes = fn,
      },
    })
    with_buf('foo_test.py', function()
      local active = Config.get_active()
      assert.equals('function', type(active.test_nodes))
      assert.is_true(active.test_nodes == fn)
      -- Commands remain intact
      local all_cmd = Config.get_command('all')
      assert.equals('pytest -s foo_test.py', all_cmd)
    end)
  end)

  it('merges across multiple setup() calls', function()
    Config.setup({
      mocha = {
        commands = {
          all = function(_)
            return 'A ' .. vim.fn.expand('%')
          end,
        },
      },
    })
    Config.setup({
      mocha = {
        commands = {
          nearest = function(_)
            return 'B ' .. vim.fn.expand('%')
          end,
        },
      },
    })
    with_buf('testSpec.js', function()
      assert.equals('A testSpec.js', Config.get_command('all'))
      assert.equals('B testSpec.js', Config.get_command('nearest'))
      -- Unchanged default still present
      assert.equals('./node_modules/.bin/mocha --inspect-brk --no-timeouts testSpec.js', Config.get_command('debug-all'))
    end)
  end)
end)
